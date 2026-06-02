/**
 * @description  Project-wide constant registry for Sellon Finserv.
 *               All picklist values, stage names, thresholds, and
 *               named credential identifiers live here.
 *               NEVER use string literals in business logic classes —
 *               always reference a constant from this file.
 *
 * @author       Sellon Finserv Dev Team
 * @created      Day 01 — Foundation Sprint
 * @version      1.0
 *
 * USAGE EXAMPLE:
 *   if (app.Stage__c == Constants.STAGE_NEW_APPLICATION) { ... }
 *   if (creditScore < Constants.CREDIT_SCORE_MINIMUM) { ... }
 */
public class Constants {

    // ─────────────────────────────────────────────────────────────────
    // LOAN APPLICATION STAGES
    // Order matches the business lifecycle — do not reorder.
    // These values MUST match the picklist values on Stage__c exactly.
    // ─────────────────────────────────────────────────────────────────
    public static final String STAGE_NEW_APPLICATION     = 'New Application';
    public static final String STAGE_DOCUMENT_COLLECTION  = 'Document Collection';
    public static final String STAGE_CREDIT_CHECK          = 'Credit Check';
    public static final String STAGE_UNDERWRITING_REVIEW   = 'Underwriting Review';
    public static final String STAGE_CREDIT_COMMITTEE       = 'Credit Committee';
    public static final String STAGE_APPROVED               = 'Approved';
    public static final String STAGE_SANCTIONED              = 'Sanctioned';
    public static final String STAGE_DISBURSED               = 'Disbursed';
    public static final String STAGE_REJECTED                = 'Rejected';
    public static final String STAGE_WITHDRAWN               = 'Withdrawn';

    // Terminal stages — no further transitions allowed.
    // Used by LoanApplicationService.validateStageTransition()
    public static final Set<String> TERMINAL_STAGES = new Set<String>{
        STAGE_DISBURSED, STAGE_REJECTED, STAGE_WITHDRAWN
    };

    // ─────────────────────────────────────────────────────────────────
    // LOAN TYPES
    // ─────────────────────────────────────────────────────────────────
    public static final String LOAN_TYPE_HOME       = 'Home Loan';
    public static final String LOAN_TYPE_PERSONAL    = 'Personal Loan';
    public static final String LOAN_TYPE_AUTO        = 'Auto Loan';
    public static final String LOAN_TYPE_BUSINESS    = 'Business Loan';

    // ─────────────────────────────────────────────────────────────────
    // DOCUMENT TYPES
    // Used in DocumentVerificationService to enforce required docs per loan type.
    // ─────────────────────────────────────────────────────────────────
    public static final String DOC_PAN              = 'PAN';
    public static final String DOC_AADHAAR          = 'Aadhaar';
    public static final String DOC_SALARY_SLIP      = 'Salary Slip';
    public static final String DOC_BANK_STATEMENT   = 'Bank Statement';
    public static final String DOC_IT_RETURNS        = 'IT Returns';
    public static final String DOC_PROPERTY_DOCS     = 'Property Documents';
    public static final String DOC_STATUS_PENDING    = 'Pending';
    public static final String DOC_STATUS_UPLOADED   = 'Uploaded';
    public static final String DOC_STATUS_VERIFIED   = 'Verified';
    public static final String DOC_STATUS_REJECTED   = 'Rejected';

    // Required document types by loan type.
    // DocumentVerificationService.checkAllDocumentsUploaded() iterates this map.
    public static final Map<String, List<String>> REQUIRED_DOCS_BY_LOAN_TYPE =
        new Map<String, List<String>>{
            LOAN_TYPE_HOME     => new List<String>{ DOC_PAN, DOC_AADHAAR, DOC_SALARY_SLIP, DOC_BANK_STATEMENT, DOC_PROPERTY_DOCS },
            LOAN_TYPE_PERSONAL => new List<String>{ DOC_PAN, DOC_AADHAAR, DOC_SALARY_SLIP, DOC_BANK_STATEMENT },
            LOAN_TYPE_AUTO     => new List<String>{ DOC_PAN, DOC_AADHAAR, DOC_SALARY_SLIP },
            LOAN_TYPE_BUSINESS => new List<String>{ DOC_PAN, DOC_AADHAAR, DOC_IT_RETURNS, DOC_BANK_STATEMENT }
        };

    // ─────────────────────────────────────────────────────────────────
    // CREDIT SCORE THRESHOLDS
    // Used in LoanEligibilityService and BatchLoanReconciliation.
    // ─────────────────────────────────────────────────────────────────
    public static final Integer CREDIT_SCORE_MINIMUM         = 650;   // Below this = auto-flag for rejection
    public static final Integer CREDIT_SCORE_STANDARD         = 700;   // 650-749 = standard underwriting
    public static final Integer CREDIT_SCORE_FAST_TRACK       = 750;   // 750+ = fast-track approval

    // ─────────────────────────────────────────────────────────────────
    // LOAN AMOUNT LIMITS (in INR)
    // ─────────────────────────────────────────────────────────────────
    public static final Decimal LOAN_AMOUNT_MIN              = 50000;        // ₹50,000
    public static final Decimal LOAN_AMOUNT_MAX              = 50000000;     // ₹5 Crore
    public static final Decimal APPROVAL_THRESHOLD_L1        = 2500000;      // ₹25L — Credit Manager can approve
    public static final Decimal APPROVAL_THRESHOLD_L2        = 10000000;     // ₹1Cr — National Credit Head required

    // Maximum loan eligibility multiplier
    // Loan amount <= Monthly_Income * 60 (5 years of income)
    public static final Integer ELIGIBILITY_INCOME_MULTIPLIER = 60;

    // ─────────────────────────────────────────────────────────────────
    // TENURE LIMITS (in months)
    // ─────────────────────────────────────────────────────────────────
    public static final Integer TENURE_MIN                   = 12;   // 1 year
    public static final Integer TENURE_MAX                   = 360;  // 30 years

    // ─────────────────────────────────────────────────────────────────
    // SLA THRESHOLDS (in days)
    // Used by BatchLoanReconciliation and SLA escalation flows.
    // ─────────────────────────────────────────────────────────────────
    public static final Integer SLA_DOCUMENT_COLLECTION_WARN  = 3;   // Warn RM after 3 days
    public static final Integer SLA_DOCUMENT_COLLECTION_CRIT  = 5;   // Escalate after 5 days
    public static final Integer SLA_CREDIT_CHECK_DAYS         = 2;   // Credit check must complete in 2 days
    public static final Integer SLA_APPROVAL_DAYS             = 48;  // 48-hour approval SLA (hours, not days)

    // ─────────────────────────────────────────────────────────────────
    // NAMED CREDENTIAL IDENTIFIERS
    // Used in callout classes — NEVER hardcode endpoint URLs in Apex.
    // ─────────────────────────────────────────────────────────────────
    public static final String NC_CREDIT_BUREAU              = 'callout:NC_CreditBureau';
    public static final String NC_SMS_GATEWAY                = 'callout:NC_SMSGateway';
    public static final String NC_DOC_VERIFY                 = 'callout:NC_DocVerify';

    // ─────────────────────────────────────────────────────────────────
    // AUDIT LOG EVENT TYPES
    // Used by AuditLogger.log() — standardizes the Event_Type__c picklist.
    // ─────────────────────────────────────────────────────────────────
    public static final String AUDIT_LOAN_CREATED            = 'LOAN_CREATED';
    public static final String AUDIT_STAGE_CHANGED            = 'STAGE_CHANGED';
    public static final String AUDIT_LOAN_APPROVED            = 'LOAN_APPROVED';
    public static final String AUDIT_LOAN_REJECTED            = 'LOAN_REJECTED';
    public static final String AUDIT_LOAN_DISBURSED           = 'LOAN_DISBURSED';
    public static final String AUDIT_API_CALL                = 'API_CALL';
    public static final String AUDIT_BATCH_START              = 'BATCH_START';
    public static final String AUDIT_BATCH_END                = 'BATCH_END';
    public static final String AUDIT_BATCH_ERROR              = 'BATCH_ROW_ERROR';
    public static final String AUDIT_SYSTEM_ERROR             = 'SYSTEM_ERROR';
    public static final String AUDIT_VALIDATION_FAIL          = 'VALIDATION_FAIL';

    // ─────────────────────────────────────────────────────────────────
    // INTEGRATION — API RETRY SETTINGS
    // ─────────────────────────────────────────────────────────────────
    public static final Integer API_MAX_RETRIES               = 3;     // Max retry attempts on 5xx errors
    public static final Integer API_TIMEOUT_MS                = 10000; // 10 second callout timeout

    // ─────────────────────────────────────────────────────────────────
    // PRIORITY VALUES (Loan_Application__c.Priority__c)
    // ─────────────────────────────────────────────────────────────────
    public static final String PRIORITY_NORMAL               = 'Normal';
    public static final String PRIORITY_HIGH                 = 'High';
    public static final String PRIORITY_CRITICAL              = 'Critical';

    // ─────────────────────────────────────────────────────────────────
    // ERROR MESSAGES
    // Surfaced to users via AuraHandledException — no stack traces, no field API names.
    // ─────────────────────────────────────────────────────────────────
    public static final String ERR_ACTIVE_LOAN_EXISTS         = 'An active loan application already exists for this account. Cannot create a duplicate.';
    public static final String ERR_INVALID_STAGE_TRANSITION   = 'Invalid stage transition: {0} → {1}. This move is not permitted.';
    public static final String ERR_LOAN_AMOUNT_EXCEEDS_LIMIT  = 'Loan amount exceeds maximum eligibility of ₹{0} based on applicant income.';
    public static final String ERR_PROCESSING_FAILED          = 'Processing failed. Please try again or contact support. Reference: {0}';
    public static final String ERR_API_UNAVAILABLE            = 'External service unavailable. The operation has been queued for retry.';

    // ─────────────────────────────────────────────────────────────────
    // BATCH SETTINGS
    // ─────────────────────────────────────────────────────────────────
    public static final Integer BATCH_SIZE_DEFAULT            = 200;  // Standard batch scope size
    public static final Integer BATCH_SIZE_CALLOUT            = 5;    // Callout batches must be small due to limits

    // Private constructor — this class should never be instantiated.
    // All members are static.
    private Constants() {}
}