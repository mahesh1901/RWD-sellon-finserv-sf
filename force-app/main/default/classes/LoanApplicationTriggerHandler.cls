/**
 * @description  Trigger handler for Loan_Application__c.
 *               Extends TriggerHandlerBase — only overrides the 4 events
 *               this object actually needs to act on.
 *
 *               RULE: This class is a router only. No business logic here.
 *               All logic lives in LoanApplicationService.
 *               This class is responsible for:
 *                 1. Casting SObject lists to typed lists
 *                 2. Filtering records (e.g., "only stage-changed records")
 *                 3. Delegating to the correct service method
 *
 * @author       Sellon Finserv Dev Team
 * @created      Day 02 — Apex Framework Sprint
 * @see          LoanApplicationService
 * @see          AuditLogger
 */
public class LoanApplicationTriggerHandler extends TriggerHandlerBase {

    // ── BEFORE INSERT ─────────────────────────────────────────────────
    // Fires before new Loan_Application__c records are committed.
    // Good time for: defaults, eligibility checks, duplicate prevention.
    // Records do NOT have an Id yet at this point.
  
    public override void beforeInsert(List<SObject> newList) {
        // Cast once — reuse the typed list
        List<Loan_Application__c> apps =
            (List<Loan_Application__c>) newList;

        // Step 1: Populate default field values (Stage, Submission Date, etc.)
        LoanApplicationService.setDefaults(apps);

        // Step 2: Check if this account already has an active loan application.
        //         Adds a field-level addError() — blocks the insert if true.
        LoanApplicationService.preventDuplicates(apps);

        // Step 3: Validate loan amount against applicant's income eligibility.
        //         Adds a field-level addError() on Loan_Amount__c if exceeded.
        LoanApplicationService.validateEligibility(apps);
    }

    // ── BEFORE UPDATE ─────────────────────────────────────────────────
    // Fires before existing records are updated.
    // Good time for: stage transition validation, computed field recalculation.
 
    public override void beforeUpdate(List<SObject> newList, Map<Id,SObject> oldMap) {
        List<Loan_Application__c> apps =
            (List<Loan_Application__c>) newList;
        Map<Id,Loan_Application__c> oldApps =
            (Map<Id,Loan_Application__c>) oldMap;

        // Validate that stage transitions follow the allowed state machine.
        // Invalid transitions get a field-level addError() on Stage__c.
        LoanApplicationService.validateStageTransition(apps, oldApps);

        // Recalculate EMI if any of the three inputs changed (amount, rate, tenure).
        // Formula field handles display, but we also store it in a currency field
        // for use in SOQL, reports, and batch comparisons.
        LoanApplicationService.calculateEMI(apps);
    }

    // ── AFTER INSERT ──────────────────────────────────────────────────
    // Records are now committed — Ids are populated.
    // Good time for: creating related records (Tasks), audit logging,
    // sending notifications.
  
    public override void afterInsert(List<SObject> newList) {
        List<Loan_Application__c> apps =
            (List<Loan_Application__c>) newList;

        // Create the initial follow-up task for the assigned RM
        LoanApplicationService.createInitialTasks(apps);

        // Log bulk audit entry: one Audit_Log__c per new loan application
        AuditLogger.logBulk(Constants.AUDIT_LOAN_CREATED, (List<SObject>) apps);

        // Queue async notification to RM — not in-line to avoid callout/limit issues
        NotificationService.notifyOnNewApplication(apps);
    }

    // ── AFTER UPDATE ──────────────────────────────────────────────────
    // Fires after records are committed with updated values.
    // KEY PATTERN: filter for only the records that actually changed the
    // relevant field — don't process every updated record unnecessarily.
    
    public override void afterUpdate(List<SObject> newList, Map<Id,SObject> oldMap) {
        List<Loan_Application__c> apps =
            (List<Loan_Application__c>) newList;
        Map<Id,Loan_Application__c> oldApps =
            (Map<Id,Loan_Application__c>) oldMap;

        // ── FILTER: Only records where Stage actually changed ──────────
        // Processing every updated record when only stage changes matter
        // wastes CPU time and risks hitting governor limits on bulk updates.
        List<Loan_Application__c> stageChanged = new List<Loan_Application__c>();
        for (Loan_Application__c app : apps) {
            Loan_Application__c oldApp = oldApps.get(app.Id);
            if (app.Stage__c != oldApp.Stage__c) {
                stageChanged.add(app);
            }
        }

        // Only proceed if at least one record had a stage change
        if (!stageChanged.isEmpty()) {
            // Handle downstream actions for the new stage (tasks, notifications)
            LoanApplicationService.onStageChange(stageChanged, oldApps);

            // Log the stage change for each affected record
            AuditLogger.logBulk(Constants.AUDIT_STAGE_CHANGED, (List<SObject>) stageChanged);

            // Send stage update notifications (email + in-app)
            NotificationService.notifyOnStageChange(stageChanged, oldApps);
        }
    }

    // beforeDelete, afterDelete, afterUndelete use base class no-ops.
    // Loan applications should not be hard-deleted — use Withdrawn stage instead.
}