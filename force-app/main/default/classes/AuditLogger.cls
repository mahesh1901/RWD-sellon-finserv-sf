/**
 * @description  Centralized audit logging utility for Sellon Finserv.
 *               Creates Audit_Log__c records for all significant system
 *               events: loan lifecycle changes, API calls, batch jobs,
 *               and security-relevant operations.
 *
 *               Declared WITHOUT SHARING — audit records must be created
 *               regardless of the running user's record-level permissions.
 *               Compensating control: Audit_Log__c OWD = Private, no
 *               profile has Edit/Delete on the object.
 *
 *               PII masking: PAN and Aadhaar are never written in
 *               plaintext — use maskPAN() and maskAadhaar() before
 *               including in log messages.
 *
 * @author       Sellon Finserv Dev Team
 * @created      Day 01 — Foundation Sprint
 * @version      1.0
 * @see          Constants (for event type strings)
 * @see          AuditLoggerTest (test class)
 */
public without sharing class AuditLogger {

    // ─────────────────────────────────────────────────────────────────
    // SINGLE EVENT LOG
    // Use for one-off events: errors, stage changes on a single record,
    // manual admin actions.
    //
    // @param eventType   One of Constants.AUDIT_* values
    // @param message     Human-readable description of the event
    // @param recordId    The Salesforce ID of the related record (nullable)
    // ─────────────────────────────────────────────────────────────────
    public static void log(String eventType, String message, Id recordId) {
        try {
            // Truncate message to field limit — Long Text Area is 32,768 chars
            String safeMessage = message != null ? message.left(32768) : '(null message)';

            Audit_Log__c auditRecord = new Audit_Log__c(
                Event_Type__c      = eventType,
                Message__c         = safeMessage,
                Related_Record__c  = recordId,
                Logged_At__c       = System.now(),
                Logged_By__c       = UserInfo.getUserId(),
                // Session ID is null in batch/async context — handle gracefully
                Session_Id__c      = UserInfo.getSessionId() != null
                                       ? UserInfo.getSessionId().left(36)
                                       : 'ASYNC'
            );
            insert auditRecord;

        } catch (Exception e) {
            // Log failure must NOT bubble up — it would mask the original error.
            // Write to debug log as last resort. In production, set up a
            // Platform Event or email alert as an alternative channel.
            System.debug(LoggingLevel.ERROR,
                '[AuditLogger] CRITICAL: Failed to write audit log. EventType='
                + eventType + ' Error=' + e.getMessage());
        }
    }

    // ─────────────────────────────────────────────────────────────────
    // BULK EVENT LOG
    // Use in trigger contexts where multiple records are being processed.
    // Single insert of all log records — avoids DML limit violations.
    //
    // Uses Database.insert with allOrNothing=false so a failure on one
    // audit record does not roll back the parent business transaction.
    //
    // @param eventType   One of Constants.AUDIT_* values
    // @param records     List of SObjects (e.g., Loan_Application__c list from trigger)
    // ─────────────────────────────────────────────────────────────────
    public static void logBulk(String eventType, List<SObject> records) {
        if (records == null || records.isEmpty()) {
            return; // Nothing to log
        }

        List<Audit_Log__c> auditRecords = new List<Audit_Log__c>();
        String userId    = UserInfo.getUserId();
        Datetime now     = System.now();
        String nowFormat = now.format();

        for (SObject rec : records) {
            auditRecords.add(new Audit_Log__c(
                Event_Type__c      = eventType,
                Related_Record__c  = rec.Id,
                // Standard message format: EVENT_TYPE at DATETIME
                Message__c         = eventType + ' processed at ' + nowFormat,
                Logged_At__c       = now,
                Logged_By__c       = userId
            ));
        }

        if (!auditRecords.isEmpty()) {
            // allOrNothing = false: partial success allowed.
            // An audit log failure must not break the main transaction.
            Database.SaveResult[] results = Database.insert(auditRecords, false);

            // Log any failed audit inserts to debug — visibility without impact
            for (Database.SaveResult sr : results) {
                if (!sr.isSuccess()) {
                    System.debug(LoggingLevel.WARN,
                        '[AuditLogger] Bulk audit log insert failed: '
                        + sr.getErrors()[0].getMessage());
                }
            }
        }
    }

    // ─────────────────────────────────────────────────────────────────
    // INTEGRATION EVENT LOG
    // Use when calling external APIs (Credit Bureau, SMS, DocVerify).
    // Logs HTTP method, endpoint, status code, and request/response payloads.
    // Payloads are truncated to field limit (32,768 chars).
    //
    // IMPORTANT: Never log PAN, Aadhaar, or bank account numbers in
    // request/response payloads. Mask before passing to this method.
    //
    // @param source      Human-readable source name (e.g., 'CreditBureau')
    // @param endpoint    The endpoint path (e.g., '/api/v2/credit-score')
    // @param statusCode  HTTP response status code (200, 400, 500, etc.)
    // @param request     Serialized request payload string
    // @param response    Serialized response body string
    // ─────────────────────────────────────────────────────────────────
    public static void logIntegration(
        String source,
        String endpoint,
        Integer statusCode,
        String request,
        String response
    ) {
        try {
            insert new Audit_Log__c(
                Event_Type__c        = Constants.AUDIT_API_CALL,
                // Message format: SOURCE | ENDPOINT | HTTP STATUS
                Message__c           = source + ' | ' + endpoint + ' | HTTP ' + statusCode,
                Request_Payload__c   = request?.left(32768),
                Response_Payload__c  = response?.left(32768),
                Logged_At__c         = System.now(),
                Logged_By__c         = UserInfo.getUserId()
            );
        } catch (Exception e) {
            System.debug(LoggingLevel.ERROR,
                '[AuditLogger] Integration log failed: ' + e.getMessage());
        }
    }

    // ─────────────────────────────────────────────────────────────────
    // PII MASKING UTILITIES
    // Always call these before including sensitive data in log messages.
    // ─────────────────────────────────────────────────────────────────

    /**
     * Masks a PAN number for safe logging.
     * Input: ABCDE1234F → Output: ABCDE****F
     */
    public static String maskPAN(String pan) {
        if (String.isBlank(pan) || pan.length() != 10) {
            return '****'; // Invalid PAN — mask entirely
        }
        // Keep first 5 chars + last 1 char. Mask positions 6-9.
        return pan.left(5) + '****' + pan.right(1);
    }

    /**
     * Masks an Aadhaar number for safe logging.
     * Input: 123456789012 → Output: ****89012 (last 4 digits only)
     * RBI guideline: Never log or display full Aadhaar number.
     */
    public static String maskAadhaar(String aadhaar) {
        if (String.isBlank(aadhaar) || aadhaar.length() < 4) {
            return '****';
        }
        // Only expose last 4 digits — consistent with RBI compliance guidance
        return 'XXXX XXXX ' + aadhaar.right(4);
    }
}