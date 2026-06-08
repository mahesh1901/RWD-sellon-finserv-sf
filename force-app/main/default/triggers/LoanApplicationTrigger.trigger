/**
 * @description  The ONLY trigger for Loan_Application__c.
 *               All business logic lives in LoanApplicationTriggerHandler
 *               and LoanApplicationService — never in this file.
 *
 *               If you find yourself adding an if-statement here, STOP.
 *               Put the logic in the handler or service class.
 *
 * @author       Sellon Finserv Dev Team
 * @created      Day 02 — Apex Framework Sprint
 */

trigger LoanApplicationTrigger on Loan_Application__c (
    before insert, before update, before delete,
    after insert,  after update,  after delete,  after undelete
) {
    // One line. That's it. The dispatcher handles all routing.
    TriggerDispatcher.run(new LoanApplicationTriggerHandler());
}