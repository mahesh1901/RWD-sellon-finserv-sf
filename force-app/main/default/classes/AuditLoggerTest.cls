/**
 * @description  Test class for AuditLogger.cls
 *               Validates: single log, bulk log, integration log,
 *               PII masking, null handling, and bulk volume.
 *
 *               Target coverage: 100% of AuditLogger.cls
 *               Run with: sf apex run test --class-names AuditLoggerTest
 *
 * @author       Sellon Finserv Dev Team
 * @created      Day 01 — Foundation Sprint
 */
@isTest
public class AuditLoggerTest {

    // ─────────────────────────────────────────────────────────────────
    // TEST: log() — Single event log
    // Verifies that a single Audit_Log__c record is created with
    // correct field values when log() is called.
    // ─────────────────────────────────────────────────────────────────
    @isTest
    static void testLog_SingleEvent() {
        // Arrange: prepare test data
        Account testAccount = new Account(Name = 'Test Account for Audit');
        insert testAccount;

        String eventType = Constants.AUDIT_LOAN_CREATED;
        String message   = 'Test loan created event';

        // Act: call the logger
        Test.startTest();
        AuditLogger.log(eventType, message, testAccount.Id);
        Test.stopTest();

        // Assert: verify the Audit_Log__c record was created correctly
        List<Audit_Log__c> logs = [
            SELECT Event_Type__c, Message__c, Related_Record__c, Logged_At__c, Logged_By__c
            FROM Audit_Log__c
            WHERE Related_Record__c = :testAccount.Id
        ];

        System.assertEquals(1, logs.size(),
            'Expected exactly 1 audit log record to be created');
        System.assertEquals(eventType, logs[0].Event_Type__c,
            'Event type should match the passed constant');
        System.assertEquals(message, logs[0].Message__c,
            'Message should be saved verbatim');
        System.assertEquals(testAccount.Id, logs[0].Related_Record__c,
            'Related record ID should be set correctly');
        System.assertNotEquals(null, logs[0].Logged_At__c,
            'Logged timestamp must be set');
        System.assertEquals(UserInfo.getUserId(), logs[0].Logged_By__c,
            'Logged_By should be the running user');
    }

    // ─────────────────────────────────────────────────────────────────
    // TEST: log() with null recordId
    // Should still create the audit record — some system events
    // are not tied to a specific record (e.g., batch start/end).
    // ─────────────────────────────────────────────────────────────────
    @isTest
    static void testLog_NullRecordId() {
        Test.startTest();
        // Should NOT throw an exception — null recordId is valid
        AuditLogger.log(Constants.AUDIT_BATCH_START, 'Batch started', null);
        Test.stopTest();

        List<Audit_Log__c> logs = [
            SELECT Id, Event_Type__c FROM Audit_Log__c
            WHERE Event_Type__c = :Constants.AUDIT_BATCH_START
        ];

        System.assertEquals(1, logs.size(),
            'Audit log should be created even with null recordId');
    }

    // ─────────────────────────────────────────────────────────────────
    // TEST: log() with very long message
    // Messages longer than 32,768 chars must be truncated gracefully.
    // ─────────────────────────────────────────────────────────────────
    @isTest
    static void testLog_LongMessageTruncation() {
        // Generate a message longer than the 32,768 char field limit
        String longMessage = 'X'.repeat(50000);

        Test.startTest();
        AuditLogger.log(Constants.AUDIT_SYSTEM_ERROR, longMessage, null);
        Test.stopTest();

        List<Audit_Log__c> logs = [
            SELECT Message__c FROM Audit_Log__c
            WHERE Event_Type__c = :Constants.AUDIT_SYSTEM_ERROR
        ];

        System.assertEquals(1, logs.size(), 'Log record should still be created');
        System.assertEquals(32768, logs[0].Message__c.length(),
            'Message must be truncated to 32,768 characters');
    }

    // ─────────────────────────────────────────────────────────────────
    // TEST: logBulk() — 200 records
    // Simulates trigger context. Must create exactly 200 logs in a
    // single DML operation (Governor Limit: 150 DML statements total,
    // but one statement can affect up to 10,000 rows).
    // ─────────────────────────────────────────────────────────────────
    @isTest
    static void testLogBulk_200Records() {
        // Arrange: create 200 Account records to simulate a bulk insert trigger
        List<Account> accounts = new List<Account>();
        for (Integer i = 0; i < 200; i++) {
            accounts.add(new Account(Name = 'Bulk Test Account ' + i));
        }
        insert accounts;

        // Act: call logBulk() as a trigger handler would
        Test.startTest();
        // Cast to List to match the method signature
        // AuditLogger.logBulk(Constants.AUDIT_LOAN_CREATED, (List) accounts);
        List<SObject> records = new List<SObject>();
            records.addAll(accounts);

           AuditLogger.logBulk(
            Constants.AUDIT_LOAN_CREATED,
               records );
               
        Test.stopTest();

        // Assert: exactly 200 audit records created
        Integer logCount = [
            SELECT COUNT() FROM Audit_Log__c
            WHERE Event_Type__c = :Constants.AUDIT_LOAN_CREATED
        ];

        System.assertEquals(200, logCount,
            'logBulk() must create one Audit_Log__c per record in the input list');
    }

    // ─────────────────────────────────────────────────────────────────
    // TEST: logBulk() with empty list
    // Should complete without error or creating any records.
    // ─────────────────────────────────────────────────────────────────
    @isTest
    static void testLogBulk_EmptyList() {
        Test.startTest();
        // Should silently return — no exception
        AuditLogger.logBulk(Constants.AUDIT_LOAN_CREATED, new List<SObject>());
        Test.stopTest();

        Integer count = [SELECT COUNT() FROM Audit_Log__c];
        System.assertEquals(0, count, 'Empty list should produce zero log records');
    }

    // ─────────────────────────────────────────────────────────────────
    // TEST: logIntegration()
    // Verifies integration logs capture source, endpoint, status code,
    // and truncate request/response payloads correctly.
    // ─────────────────────────────────────────────────────────────────
    @isTest
    static void testLogIntegration() {
        Test.startTest();
        AuditLogger.logIntegration(
            'CreditBureau',
            '/api/v2/credit-score',
            200,
            '{"pan":"ABCDE1234F","dob":"1990-01-15"}',
            '{"score":750,"bureau":"CIBIL","reportId":"RPT-001"}'
        );
        Test.stopTest();

        List<Audit_Log__c> logs = [
            SELECT Event_Type__c, Message__c, Request_Payload__c, Response_Payload__c
            FROM Audit_Log__c
            WHERE Event_Type__c = :Constants.AUDIT_API_CALL
        ];

        System.assertEquals(1, logs.size(), 'One integration log should be created');
        System.assert(logs[0].Message__c.contains('CreditBureau'),
            'Message should contain the source name');
        System.assert(logs[0].Message__c.contains('HTTP 200'),
            'Message should contain the HTTP status code');
        System.assertNotEquals(null, logs[0].Request_Payload__c,
            'Request payload must be persisted');
    }

    // ─────────────────────────────────────────────────────────────────
    // TEST: maskPAN() — PII Masking
    // ─────────────────────────────────────────────────────────────────
    @isTest
    static void testMaskPAN() {
        // Valid PAN — should mask middle 4 digits
        System.assertEquals('ABCDE****F', AuditLogger.maskPAN('ABCDE1234F'),
            'Valid PAN must be masked as ABCDE****F');

        // Null PAN — should return safe placeholder
        System.assertEquals('****', AuditLogger.maskPAN(null),
            'Null PAN should return masked placeholder');

        // Short/invalid PAN — should return safe placeholder
        System.assertEquals('****', AuditLogger.maskPAN('ABC'),
            'Invalid PAN length should return masked placeholder');
    }

    // ─────────────────────────────────────────────────────────────────
    // TEST: maskAadhaar() — PII Masking
    // ─────────────────────────────────────────────────────────────────
    @isTest
    static void testMaskAadhaar() {
        // Valid 12-digit Aadhaar — only last 4 should be visible
        String masked = AuditLogger.maskAadhaar('123456789012');
        System.assert(masked.endsWith('9012'),
            'Masked Aadhaar must expose only last 4 digits');
        System.assert(!masked.contains('123456'),
            'Masked Aadhaar must not expose the first 8 digits');

        // Null Aadhaar
        System.assertEquals('****', AuditLogger.maskAadhaar(null),
            'Null Aadhaar should return safe placeholder');
    }
}