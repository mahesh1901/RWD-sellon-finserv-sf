/**
 * @description  Central trigger dispatcher for all Sellon Finserv triggers.
 *               Every trigger in this org calls TriggerDispatcher.run(handler)
 *               with one line. This class handles all routing based on
 *               Trigger context variables.
 *
 *               BYPASS MECHANISM:
 *               Tests or admin utilities can call TriggerDispatcher.bypass('HandlerName')
 *               to skip that handler for the current transaction. Always call
 *               clearBypass() in test teardown.
 *
 *               RECURSION GUARD:
 *               Tracks trigger execution depth. After-update triggers that
 *               perform DML can re-fire the trigger — the depth counter
 *               prevents infinite recursion.
 *
 * @author       Sellon Finserv Dev Team
 * @created      Day 02 — Apex Framework Sprint
 */
public class TriggerDispatcher {

    // ── BYPASS REGISTRY ───────────────────────────────────────────────
    // Add a handler class name here to skip it for the current transaction.
    // Example in test class:
    //   TriggerDispatcher.bypass('LoanApplicationTriggerHandler');
    //   // ... do setup DML ...
    //   TriggerDispatcher.clearBypass('LoanApplicationTriggerHandler');
    private static Set<String> bypassedHandlers = new Set<String>();

    // Execution depth guard — prevents recursive trigger loops
    private static Integer executionDepth = 0;
    private static final Integer MAX_DEPTH = 5;

    // ── MAIN DISPATCH METHOD ──────────────────────────────────────────
    // Called from every trigger. Reads Trigger context and routes to
    // the appropriate handler method.
    //
    // @param handler  An instance of a class that implements ITriggerHandler
    //                 e.g.: new LoanApplicationTriggerHandler()
    public static void run(ITriggerHandler handler) {

        // Get the simple class name for bypass check (e.g., 'LoanApplicationTriggerHandler')
        String handlerName = handler.toString().split(':')[0];

        // Skip this handler if bypassed (test setup or admin utility)
        if (bypassedHandlers.contains(handlerName)) {
            System.debug(LoggingLevel.INFO,
                '[TriggerDispatcher] Handler bypassed: ' + handlerName);
            return;
        }

        // Recursion guard — bail out if we are called too deep
        executionDepth++;
        if (executionDepth > MAX_DEPTH) {
            executionDepth--;
            System.debug(LoggingLevel.WARN,
                '[TriggerDispatcher] Max recursion depth reached for: ' + handlerName);
            return;
        }

        try {
            // BEFORE context — record values are NOT yet committed
            if (Trigger.isBefore) {
                if (Trigger.isInsert) handler.beforeInsert(Trigger.new);
                if (Trigger.isUpdate) handler.beforeUpdate(Trigger.new, Trigger.oldMap);
                if (Trigger.isDelete) handler.beforeDelete(Trigger.old);
            }
            // AFTER context — records are committed; Ids are available
            if (Trigger.isAfter) {
                if (Trigger.isInsert)   handler.afterInsert(Trigger.new);
                if (Trigger.isUpdate)   handler.afterUpdate(Trigger.new, Trigger.oldMap);
                if (Trigger.isDelete)   handler.afterDelete(Trigger.old);
                if (Trigger.isUndelete) handler.afterUndelete(Trigger.new);
            }
        } finally {
            // Always decrement depth — even if handler throws an exception
            executionDepth--;
        }
    }

    // ── BYPASS HELPERS ────────────────────────────────────────────────

    /** Add a handler to the bypass set for this transaction */
    public static void bypass(String handlerName) {
        bypassedHandlers.add(handlerName);
    }

    /** Remove a handler from the bypass set */
    public static void clearBypass(String handlerName) {
        bypassedHandlers.remove(handlerName);
    }

    /** Remove all bypasses — call this in @TestSetup teardown */
    public static void clearAllBypasses() {
        bypassedHandlers.clear();
    }

    /** Check if a handler is currently bypassed */
    public static Boolean isBypassed(String handlerName) {
        return bypassedHandlers.contains(handlerName);
    }
}