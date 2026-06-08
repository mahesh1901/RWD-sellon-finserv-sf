/**
 * @description  Selector layer for Loan_Application__c queries.
 *               All SOQL for this object lives here — never in service
 *               classes, controllers, or batch jobs directly.
 *
 *               Benefits:
 *                 - One place to add/remove queried fields
 *                 - WITH SECURITY_ENFORCED on every query
 *                 - Easy to mock in tests by subclassing
 *                 - Field sets are reusable across Day 03-10 classes
 *
 * @author       Sellon Finserv Dev Team
 * @created      Day 02 — Apex Framework Sprint
 */
public with sharing class LoanApplicationSelector {

    // ── QUERY BY IDs ──────────────────────────────────────────────────
    // Standard lookup by a set of record IDs.
    // Includes all fields needed for service layer decisions.
    public static List<Loan_Application__c> getByIds(Set<Id> ids) {
        return [
            SELECT Id, Application_Number__c, Stage__c, Loan_Type__c,
                   Loan_Amount__c, Interest_Rate__c, Tenure_Months__c,
                   EMI_Amount__c, Submission_Date__c, Approval_Date__c,
                   Rejection_Reason__c, Credit_Score__c, Priority__c,
                   Compliance_Cleared__c, Branch__c, Days_In_Current_Stage__c,
                   Assigned_RM__c, Credit_Analyst__c,
                   Account__c, Account__r.Name,
                   OwnerId
            FROM Loan_Application__c
            WHERE Id IN :ids
            WITH SECURITY_ENFORCED
        ];
    }

    // ── QUERY ACTIVE LOANS BY ACCOUNT ─────────────────────────────────
    // Returns non-terminal loans for a set of Account IDs.
    // Used by preventDuplicates() and eligibility checks.
    public static List<Loan_Application__c> getActiveByAccountIds(Set<Id> accountIds) {
        return [
            SELECT Id, Account__c, Stage__c, Loan_Amount__c, Loan_Type__c
            FROM Loan_Application__c
            WHERE Account__c IN :accountIds
            AND Stage__c NOT IN :Constants.TERMINAL_STAGES
            WITH SECURITY_ENFORCED
            LIMIT 10000
        ];
    }

    // ── QUERY FOR BATCH RECONCILIATION ────────────────────────────────
    // Returns all non-terminal loans for nightly batch processing.
    // Called from BatchLoanReconciliation (Day 04).
    public static Database.QueryLocator getActiveForBatch() {
        return Database.getQueryLocator([
            SELECT Id, Stage__c, Submission_Date__c, Loan_Amount__c,
                   EMI_Amount__c, Days_In_Current_Stage__c,
                   Priority__c, Assigned_RM__c
            FROM Loan_Application__c
            WHERE Stage__c NOT IN :Constants.TERMINAL_STAGES
        ]);
    }

    // ── QUERY LOANS IN A SPECIFIC STAGE ───────────────────────────────
    // Used by SLA flows and reports.
    public static List<Loan_Application__c> getByStage(String stage) {
        return [
            SELECT Id, Stage__c, Submission_Date__c, Days_In_Current_Stage__c,
                   Assigned_RM__c, Account__c, Account__r.Name
            FROM Loan_Application__c
            WHERE Stage__c = :stage
            WITH SECURITY_ENFORCED
            LIMIT 10000
        ];
    }
}