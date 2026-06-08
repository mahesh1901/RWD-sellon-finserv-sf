/**
 * @description  Core business logic for Loan_Application__c.
 *               All methods are static and bulkified — they accept lists,
 *               never assume a single record, and never perform SOQL or
 *               DML inside a loop.
 *
 *               Declared WITH SHARING: respects record-level access.
 *               Called by: LoanApplicationTriggerHandler (trigger context)
 *               Called by: LoanApplicationController (LWC context — Day 05)
 *
 * @author       Sellon Finserv Dev Team
 * @created      Day 02 — Apex Framework Sprint
 * @see          Constants   (for all picklist values and thresholds)
 * @see          AuditLogger (for event logging)
 */
public with sharing class LoanApplicationService {

    // ─────────────────────────────────────────────────────────────────
    // 1. SET DEFAULTS
    // Called in: beforeInsert
    // Sets Stage and Submission Date if not already provided.
    // ─────────────────────────────────────────────────────────────────
    public static void setDefaults(List<Loan_Application__c> apps) {
        for (Loan_Application__c app : apps) {

            // Default stage to 'New Application' if not explicitly set
            if (app.Stage__c == null) {
                app.Stage__c = Constants.STAGE_NEW_APPLICATION;
            }

            // Default submission date to today if not provided
            if (app.Submission_Date__c == null) {
                app.Submission_Date__c = Date.today();
            }

            // Default priority to Normal
            if (app.Priority__c == null) {
                app.Priority__c = Constants.PRIORITY_NORMAL;
            }
        }
    }

    // ─────────────────────────────────────────────────────────────────
    // 2. PREVENT DUPLICATE ACTIVE LOANS
    // Called in: beforeInsert
    // Blocks creation if the Account already has an active loan
    // application (not Rejected / Withdrawn / Disbursed).
    //
    // BULKIFICATION NOTE: one SOQL query for ALL account IDs,
    // then an in-memory map lookup per record. Never: SOQL inside loop.
    // ─────────────────────────────────────────────────────────────────
    public static void preventDuplicates(List<Loan_Application__c> apps) {

        // Collect all Account IDs from the incoming records
        Set<Id> accountIds = new Set<Id>();
        for (Loan_Application__c app : apps) {
            if (app.Account__c != null) {
                accountIds.add(app.Account__c);
            }
        }

        if (accountIds.isEmpty()) return; // Nothing to check

        // Single SOQL: find all active loan applications for these accounts.
        // Active = not in a terminal stage.
        Map<Id, Loan_Application__c> activeLoanByAccount =
            new Map<Id, Loan_Application__c>();

        for (Loan_Application__c existing : [
            SELECT Id, Account__c, Stage__c
            FROM Loan_Application__c
            WHERE Account__c IN :accountIds
            AND Stage__c NOT IN :Constants.TERMINAL_STAGES
            LIMIT 10000
        ]) {
            // One active loan per account is enough to block
            activeLoanByAccount.put(existing.Account__c, existing);
        }

        // Check each incoming record against the active loan map
        for (Loan_Application__c app : apps) {
            if (activeLoanByAccount.containsKey(app.Account__c)) {
                // addError() on the record blocks the DML and shows the message in UI
                app.addError(Constants.ERR_ACTIVE_LOAN_EXISTS);
            }
        }
    }

    // ─────────────────────────────────────────────────────────────────
    // 3. ELIGIBILITY VALIDATION
    // Called in: beforeInsert
    // Validates that loan amount does not exceed 60x monthly income.
    // (Constants.ELIGIBILITY_INCOME_MULTIPLIER = 60)
    // ─────────────────────────────────────────────────────────────────
    public static void validateEligibility(List<Loan_Application__c> apps) {

        // Collect account IDs to look up applicant income in one query
        Set<Id> accountIds = new Set<Id>();
        for (Loan_Application__c app : apps) {
            if (app.Account__c != null && app.Loan_Amount__c != null) {
                accountIds.add(app.Account__c);
            }
        }

        if (accountIds.isEmpty()) return;

        // Single SOQL: get primary applicant's monthly income per account
        Map<Id, Decimal> incomeByAccount = new Map<Id, Decimal>();
        for (Applicant__c applicant : [
            SELECT Account__c, Monthly_Income__c
            FROM Applicant__c
            WHERE Account__c IN :accountIds
            AND Monthly_Income__c != null
        ]) {
            incomeByAccount.put(applicant.Account__c, applicant.Monthly_Income__c);
        }

        // Validate each application against the eligibility formula
        for (Loan_Application__c app : apps) {
            if (!incomeByAccount.containsKey(app.Account__c)) continue;

            Decimal monthlyIncome  = incomeByAccount.get(app.Account__c);
            Decimal maxEligible    = monthlyIncome * Constants.ELIGIBILITY_INCOME_MULTIPLIER;

            if (app.Loan_Amount__c > maxEligible) {
                // Format: "Loan amount exceeds maximum eligibility of ₹X,XX,XXX"
                String errorMsg = String.format(
                    Constants.ERR_LOAN_AMOUNT_EXCEEDS_LIMIT,
                    new List<String>{ maxEligible.format() }
                );
                app.Loan_Amount__c.addError(errorMsg);
            }
        }
    }

    // ─────────────────────────────────────────────────────────────────
    // 4. EMI CALCULATION
    // Called in: beforeUpdate (when amount, rate, or tenure changes)
    // Standard loan amortization: P * r * (1+r)^n / ((1+r)^n - 1)
    // ─────────────────────────────────────────────────────────────────
    public static void calculateEMI(List<Loan_Application__c> apps) {
        for (Loan_Application__c app : apps) {

            // Only calculate if all required inputs are present and valid
            if (app.Loan_Amount__c == null
                || app.Interest_Rate__c == null
                || app.Tenure_Months__c == null
                || app.Tenure_Months__c <= 0
                || app.Interest_Rate__c <= 0) {
                continue;
            }

            Double principal   = app.Loan_Amount__c;
            Double monthlyRate = app.Interest_Rate__c / 1200; // Annual% → monthly decimal
            Integer months     = (Integer) app.Tenure_Months__c;

            // Standard amortization formula
            // EMI = P × r × (1 + r)^n ÷ ((1 + r)^n − 1)
            Double factor = Math.pow(1 + monthlyRate, months);
            Double emi    = (principal * monthlyRate * factor) / (factor - 1);

            // Store with 2 decimal precision — Decimal.setScale rounds correctly
            app.EMI_Amount__c = Decimal.valueOf(emi).setScale(2,
                System.RoundingMode.HALF_UP);
        }
    }

    // ─────────────────────────────────────────────────────────────────
    // 5. STAGE TRANSITION VALIDATION
    // Called in: beforeUpdate
    // Enforces a strict state machine — only certain stage moves are legal.
    // Uses the VALID_TRANSITIONS map defined below.
    // ─────────────────────────────────────────────────────────────────

    // The allowed transition map.
    // Key: current stage. Value: set of stages you can move TO.
    // Any move not in the allowed set gets blocked with addError().
    private static final Map<String, Set<String>> VALID_TRANSITIONS =
        new Map<String, Set<String>> {
            Constants.STAGE_NEW_APPLICATION     => new Set<String> {
                Constants.STAGE_DOCUMENT_COLLECTION, Constants.STAGE_WITHDRAWN },

            Constants.STAGE_DOCUMENT_COLLECTION => new Set<String> {
                Constants.STAGE_CREDIT_CHECK, Constants.STAGE_NEW_APPLICATION, Constants.STAGE_WITHDRAWN },

            Constants.STAGE_CREDIT_CHECK        => new Set<String> {
                Constants.STAGE_UNDERWRITING_REVIEW, Constants.STAGE_REJECTED, Constants.STAGE_WITHDRAWN },

            Constants.STAGE_UNDERWRITING_REVIEW => new Set<String> {
                Constants.STAGE_CREDIT_COMMITTEE, Constants.STAGE_REJECTED, Constants.STAGE_WITHDRAWN },

            Constants.STAGE_CREDIT_COMMITTEE    => new Set<String> {
                Constants.STAGE_APPROVED, Constants.STAGE_REJECTED },

            Constants.STAGE_APPROVED            => new Set<String> {
                Constants.STAGE_SANCTIONED },

            Constants.STAGE_SANCTIONED          => new Set<String> {
                Constants.STAGE_DISBURSED },

            // Terminal stages — no further transitions allowed
            Constants.STAGE_DISBURSED           => new Set<String>(),
            Constants.STAGE_REJECTED            => new Set<String>(),
            Constants.STAGE_WITHDRAWN           => new Set<String>()
        };

    public static void validateStageTransition(
        List<Loan_Application__c> newList,
        Map<Id, Loan_Application__c> oldMap
    ) {
        for (Loan_Application__c app : newList) {
            String oldStage = oldMap.get(app.Id).Stage__c;
            String newStage = app.Stage__c;

            // Only validate when stage actually changed
            if (oldStage == newStage) continue;

            Set<String> allowed = VALID_TRANSITIONS.get(oldStage);

            // If old stage is not in our map, or new stage is not in allowed set
            if (allowed == null || !allowed.contains(newStage)) {
                String allowedStr = allowed != null && !allowed.isEmpty()
                    ? 'Allowed: ' + String.join(new List<String>(allowed), ', ')
                    : 'No further transitions allowed from this stage.';

                app.Stage__c.addError(
                    String.format(
                        Constants.ERR_INVALID_STAGE_TRANSITION,
                        new List<String>{ oldStage, newStage }
                    ) + ' ' + allowedStr
                );
            }
        }
    }

    // ─────────────────────────────────────────────────────────────────
    // 6. ON STAGE CHANGE — Post-Transition Actions
    // Called in: afterUpdate (stage-changed records only)
    // Creates tasks appropriate to the new stage, updates Approval Date
    // for Approved stage.
    // ─────────────────────────────────────────────────────────────────
    public static void onStageChange(
        List<Loan_Application__c> apps,
        Map<Id, Loan_Application__c> oldMap
    ) {
        List<Task> tasksToInsert = new List<Task>();
        List<Loan_Application__c> toUpdate = new List<Loan_Application__c>();

        for (Loan_Application__c app : apps) {
            String stage = app.Stage__c;

            Task t = new Task(
                WhatId       = app.Id,
                OwnerId      = app.Assigned_RM__c != null
                                 ? app.Assigned_RM__c
                                 : UserInfo.getUserId(),
                Status       = 'Not Started',
                Priority     = 'Normal'
            );

            if (stage == Constants.STAGE_DOCUMENT_COLLECTION) {
                t.Subject       = 'Collect KYC Documents from Applicant';
                t.ActivityDate  = Date.today().addDays(2);

            } else if (stage == Constants.STAGE_CREDIT_CHECK) {
                t.Subject       = 'Initiate Credit Bureau Check';
                t.ActivityDate  = Date.today().addDays(1);
                // Reassign to Credit Analyst if populated
                if (app.Credit_Analyst__c != null) {
                    t.OwnerId = app.Credit_Analyst__c;
                }

            } else if (stage == Constants.STAGE_APPROVED) {
                t.Subject       = 'Prepare and Issue Sanction Letter to Applicant';
                t.Priority      = 'High';
                t.ActivityDate  = Date.today().addDays(1);

                // Stamp approval date when moving to Approved
                toUpdate.add(new Loan_Application__c(
                    Id                = app.Id,
                    Approval_Date__c  = Date.today()
                ));

            } else if (stage == Constants.STAGE_DISBURSED) {
                t.Subject       = 'Post-Disbursement Welcome Call to Customer';
                t.Priority      = 'Normal';
                t.ActivityDate  = Date.today().addDays(3);

            } else if (stage == Constants.STAGE_REJECTED) {
                t.Subject       = 'Follow Up with Rejected Applicant (30 Days)';
                t.ActivityDate  = Date.today().addDays(30);
            }

            // Only add task if subject was populated (i.e., stage matched a case)
            if (t.Subject != null) {
                tasksToInsert.add(t);
            }
        }

        // Bulk DML — never DML inside the loop above
        if (!tasksToInsert.isEmpty()) insert tasksToInsert;

        // Update Approval Date for Approved records
        // Using Database.update with partial success so a single failure
        // doesn't roll back all the other updates.
        if (!toUpdate.isEmpty()) {
            Database.update(toUpdate, false);
        }
    }

    // ─────────────────────────────────────────────────────────────────
    // 7. CREATE INITIAL TASKS
    // Called in: afterInsert
    // Creates a Day 1 follow-up task for the RM when a new loan is created.
    // ─────────────────────────────────────────────────────────────────
    public static void createInitialTasks(List<Loan_Application__c> apps) {
        List<Task> tasks = new List<Task>();

        for (Loan_Application__c app : apps) {
            tasks.add(new Task(
                Subject       = 'New Loan Application Received — Initial Contact',
                WhatId        = app.Id,
                OwnerId       = app.Assigned_RM__c != null
                                  ? app.Assigned_RM__c
                                  : UserInfo.getUserId(),
                Status        = 'Not Started',
                Priority      = 'Normal',
                ActivityDate  = Date.today().addDays(1),
                Description   = 'Review application details and contact applicant to confirm receipt.'
            ));
        }

        if (!tasks.isEmpty()) insert tasks;
    }
}