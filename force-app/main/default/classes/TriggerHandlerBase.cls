/**
 * @description  Abstract base class implementing ITriggerHandler with
 *               empty default methods. Concrete handler classes extend
 *               this and only override the events they need to act on.
 *
 *               WITHOUT this base: every handler must implement all 7
 *               methods even when only 2 are needed — pure boilerplate.
 *
 *               WITH this base: LoanApplicationTriggerHandler only
 *               overrides beforeInsert, beforeUpdate, afterInsert,
 *               afterUpdate — the other 3 are silently no-ops.
 *
 * @author       Sellon Finserv Dev Team
 * @created      Day 02 — Apex Framework Sprint
 */
public abstract class TriggerHandlerBase implements ITriggerHandler {

    // Default no-op implementations — override only what you need
    public virtual void beforeInsert  (List<SObject> newList)                              {}
    public virtual void beforeUpdate  (List<SObject> newList, Map<Id,SObject> oldMap) {}
    public virtual void beforeDelete  (List<SObject> oldList)                              {}
    public virtual void afterInsert   (List<SObject> newList)                              {}
    public virtual void afterUpdate   (List<SObject> newList, Map<Id,SObject> oldMap)  {}
    public virtual void afterDelete   (List<SObject> oldList)                              {}
    public virtual void afterUndelete (List<SObject> newList)                              {}
}