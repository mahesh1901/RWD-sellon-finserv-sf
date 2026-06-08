/**
 * @description  Centralized notification service for Sellon Finserv.
 *               Handles Salesforce Custom Notifications (bell/push),
 *               transactional email alerts, and batch summaries.
 *
 *               CRITICAL DESIGN RULE:
 *               ALL methods in this class swallow exceptions and log
 *               them to AuditLogger. A notification failure must NEVER
 *               cause a loan application DML transaction to roll back.
 *               Notifications are best-effort, not transactional.
 *
 * @author       Sellon Finserv Dev Team
 * @created      Day 02 — Apex Framework Sprint
 * @see          AuditLogger
 */
public with sharing class NotificationService {

    // Custom Notification Type developer name — must match Setup → Custom Notifications
    private static final String NOTIFICATION_TYPE_NAME = 'Loan_Alert';

    // ── NOTIFY: NEW APPLICATION ───────────────────────────────────────
    // Sends a Salesforce bell notification to the assigned RM when
    // a new loan application is created.
    // public static void notifyOnNewApplication(List<Loan_Application__c> apps) {
    //     try {
    //         // Look up the Custom Notification Type Id once
    //         CustomNotificationType notifType = getNotificationType();
    //         if (notifType == null) return;

    //         List<Messaging.CustomNotification> notifications =
    //             new List<Messaging.CustomNotification>();

    //         for (Loan_Application__c app : apps) {
    //             if (app.Assigned_RM__c == null) continue;

    //            // Messaging.CustomNotification notif =
    //             //     new Messaging.CustomNotification();

    //             // notif.setNotificationTypeId(notifType.Id);
    //             // notif.setTitle('New Loan Application Assigned');
    //             // notif.setBody('A new loan application has been assigned to you. Please review.');
    //             // notif.setTargetId(app.Id); // Opens the record when tapped
    //             // notif.setRecipientIds(new Set<String>{ app.Assigned_RM__c });

    //             // notifications.add(notif);
    //           Messaging.CustomNotification notification = new Messaging.CustomNotification();

    //          notification.setTitle('New Loan Application Assigned');
    //          notification.setBody('A new loan application has been assigned to you.');
    //          notification.setNotificationTypeId(notifType.Id);
    //          notification.setTargetId(app.Id);

    //               Set<Id> recipientIds = new Set<Id>{app.Assigned_RM__c};

    //            notification.send(recipientIds);

    //          } catch (Exception e) {
    //         // Log but never re-throw — notification failure must not break the transaction
    //         AuditLogger.log(Constants.AUDIT_SYSTEM_ERROR,
    //             'NotificationService.notifyOnNewApplication failed: ' + e.getMessage(), null);
    //     }
    // }

public static void notifyOnNewApplication(
    List<Loan_Application__c> apps
) {
    System.debug(
        'New Loan Applications Created: ' + apps.size()
    );
}

    // ── NOTIFY: STAGE CHANGE ─────────────────────────────────────────
    // Sends email to the applicant's Account primary contact when
    // the loan stage changes.
    public static void notifyOnStageChange(
        List<Loan_Application__c> apps,
        Map<Id, Loan_Application__c> oldMap
    ) {
        try {
            // Collect account IDs to look up contact emails in one query
            Set<Id> accountIds = new Set<Id>();
            for (Loan_Application__c app : apps) {
                if (app.Account__c != null) accountIds.add(app.Account__c);
            }

            // Get primary contact email per account — single SOQL
            Map<Id, String> emailByAccount = new Map<Id, String>();
            for (Contact c : [
                SELECT AccountId, Email
                FROM Contact
                WHERE AccountId IN :accountIds
                AND Email != null
                ORDER BY CreatedDate ASC
            ]) {
                // Take first contact found per account
                if (!emailByAccount.containsKey(c.AccountId)) {
                    emailByAccount.put(c.AccountId, c.Email);
                }
            }

            List<Messaging.SingleEmailMessage> emails =
                new List<Messaging.SingleEmailMessage>();

            for (Loan_Application__c app : apps) {
                String email = emailByAccount.get(app.Account__c);
                if (email == null) continue;

                Messaging.SingleEmailMessage msg = new Messaging.SingleEmailMessage();
                msg.setToAddresses(new List<String>{ email });
                msg.setSubject('Loan Application Update — Stage: ' + app.Stage__c);
                msg.setPlainTextBody(buildStageUpdateBody(app));
                msg.setSaveAsActivity(false); // Don't clutter the timeline
                emails.add(msg);
            }

            if (!emails.isEmpty()) {
                Messaging.sendEmail(emails, false); // allOrNothing=false
            }

        } catch (Exception e) {
            AuditLogger.log(Constants.AUDIT_SYSTEM_ERROR,
                'NotificationService.notifyOnStageChange failed: ' + e.getMessage(), null);
        }
    }

    // ── BATCH SUMMARY EMAIL ───────────────────────────────────────────
    // Called by BatchLoanReconciliation.finish() to send a completion
    // summary to the System Administrator email.
    public static void sendBatchSummary(
        String batchName,
        Integer processedCount,
        Integer errorCount
    ) {
        try {
            Messaging.SingleEmailMessage msg = new Messaging.SingleEmailMessage();
            msg.setToAddresses(new List<String>{ UserInfo.getUserEmail() });
            msg.setSubject('[Sellon Finserv] Batch Complete: ' + batchName);
            msg.setPlainTextBody(
                'Batch Job: '   + batchName       + '\n' +
                'Processed: '  + processedCount  + '\n' +
                'Errors: '     + errorCount      + '\n' +
                'Completed at: ' + System.now().format()
            );
            Messaging.sendEmail(new List<Messaging.SingleEmailMessage>{ msg }, false);
        } catch (Exception e) {
            AuditLogger.log(Constants.AUDIT_SYSTEM_ERROR,
                'NotificationService.sendBatchSummary failed: ' + e.getMessage(), null);
        }
    }

    // ── PRIVATE HELPERS ───────────────────────────────────────────────

    /** Fetch the Custom Notification Type by developer name */
    private static CustomNotificationType getNotificationType() {
        List<CustomNotificationType> types = [
            SELECT Id FROM CustomNotificationType
            WHERE DeveloperName = :NOTIFICATION_TYPE_NAME
            LIMIT 1
        ];
        return types.isEmpty() ? null : types[0];
    }

    /** Build the plain-text body for a stage update email */
    private static String buildStageUpdateBody(Loan_Application__c app) {
        return
            'Dear Applicant,\n\n' +
            'Your loan application status has been updated.\n\n' +
            'New Status: '     + app.Stage__c                 + '\n' +
            'Loan Amount: ₹'   + app.Loan_Amount__c?.format()  + '\n' +
            'Updated On: '     + System.now().format()         + '\n\n' +
            'For queries, please contact your Relationship Manager.\n\n' +
            'Regards,\nSellon Finserv Team';
    }
}
