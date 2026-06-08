/**
 * @description  Interface contract that all trigger handler classes must implement.
 *               Every handler method receives bulkified lists — methods must
 *               never assume they will be called with a single record.
 *
 *               Implementing classes: LoanApplicationTriggerHandler (Day 02)
 *               Future: ApplicantTriggerHandler, DocumentTriggerHandler, etc.
 *
 * @author       Sellon Finserv Dev Team
 * @created      Day 02 — Apex Framework Sprint
 */
public interface ITriggerHandler {

    /**
     * Fires BEFORE records are inserted into the database.
     * Use for: setting defaults, validation that needs no Id, duplicate checks.
     * @param newList  The incoming records (not yet committed — no Id)
     */
    void beforeInsert(List<SObject> newList);

    /**
     * Fires BEFORE records are updated in the database.
     * Use for: field validation, stage transition checks, computed field updates.
     * @param newList  Updated record values (not yet committed)
     * @param oldMap   Previous record values (keyed by Id)
     */
    void beforeUpdate(List<SObject> newList, Map<Id, SObject> oldMap);

    /**
     * Fires BEFORE records are deleted from the database.
     * Use for: cascading cleanup of records not covered by Master-Detail.
     * @param oldList  Records about to be deleted
     */
    void beforeDelete(List<SObject> oldList);

    /**
     * Fires AFTER records have been successfully inserted.
     * Use for: related record creation (Tasks, Logs), notifications.
     * Records now have Ids — safe to create child records.
     * @param newList  Newly inserted records with populated Ids
     */
    void afterInsert(List<SObject> newList);

    /**
     * Fires AFTER records have been successfully updated.
     * Use for: audit logging, async job enqueuing, cross-object updates.
     * @param newList  Updated records (committed values)
     * @param oldMap   Previous values before the update
     */
    void afterUpdate(List<SObject> newList, Map<Id, SObject> oldMap);

    /**
     * Fires AFTER records have been deleted.
     * @param oldList  Deleted records (Id is still accessible)
     */
    void afterDelete(List<SObject> oldList);

    /**
     * Fires AFTER records have been undeleted (restored from Recycle Bin).
     * @param newList  Undeleted records
     */
    void afterUndelete(List<SObject> newList);
}