# Trigger Framework

This file governs how Apex triggers are structured on top of the shared dispatcher: one trigger per SObject, how a handler subclass is shaped, when a second concern on the same object earns a second handler instead of a branch, and the idempotency and bulkification rules that keep trigger-time logic safe under bulk DML. Read this before writing any Apex trigger or `TriggerHandler` subclass.

## 1. One trigger per SObject; the trigger body does nothing but hand off

**Rule.** Every SObject gets exactly one trigger, covering every event it needs (`before insert`, `before update`, `before delete`, `after insert`, `after update`, `after delete`, `after undelete`). The trigger body contains no business logic, no SOQL, no DML — it instantiates a handler and calls `.run()`.

**Why.** [`TriggerHandler.cls`](../../utilities/triggers/TriggerHandler.cls) centralizes three things that only work if every trigger dispatches through the same door: a recursion guard (`setMaxLoopCount` / `addToLoopCount`, throwing once a handler's run count exceeds its ceiling), a bypass registry (`bypass` / `clearBypass` / `isBypassed`) for suspending a handler mid-transaction, and context detection that maps `Trigger.operationType` onto the right hook method. Splitting logic across multiple triggers on the same object, or putting logic directly in the trigger body, routes around all three.

```apex
trigger OrderTrigger on Order__c (
    before insert, before update, before delete,
    after insert, after update, after delete, after undelete
) {
    new OrderTriggerHandler().run();
}
```

The handler extends `TriggerHandler` and overrides only the hook methods it actually needs. Every hook the base class exposes — `beforeInsert`, `beforeUpdate`, `beforeDelete`, `afterInsert`, `afterUpdate`, `afterDelete`, `afterUndelete` — is a no-op by default, so a handler that only cares about one event overrides exactly that one method and nothing else runs for the rest.

```apex
public class OrderTriggerHandler extends TriggerHandler {
    protected override void beforeInsert() {
        OrderValidationService.validateNewOrders((List<Order__c>) Trigger.new);
    }

    protected override void afterUpdate() {
        OrderFulfillmentService.processStatusChanges(
            (List<Order__c>) Trigger.new, (Map<Id, Order__c>) Trigger.oldMap);
    }
}
```

See [`TriggerHandler.cls`](../../utilities/triggers/TriggerHandler.cls) for the full dispatch / loop-count / bypass implementation, and [`TriggerHandlerTest.cls`](../../utilities/triggers/TriggerHandlerTest.cls) for how to exercise a handler's hooks directly against a test-mode context instead of firing DML through a real trigger.

## 2. Multiple concerns on the same SObject register as separate handler instances, not branches inside one

**Rule.** When an SObject needs more than one independent behavior — say, a status-change notification and an unrelated cascade cleanup on delete — write two separate `TriggerHandler` subclasses and instantiate both from the trigger body. Don't fold unrelated concerns into one handler's hook methods behind internal `if` branches.

**Why.** Because the base class already dispatches by context and no-ops on any hook a handler doesn't override, there's no manual self-gating to write — a handler that only overrides `beforeDelete()` simply does nothing on every other event, for free. Splitting concerns into separate handler classes keeps loop-count ceilings, bypass toggles, and unit tests scoped to one concern at a time; a bug or a deliberate bypass in the cleanup handler can't accidentally suppress the notification handler.

```apex
trigger ContactTrigger on Contact (
    before delete, after update
) {
    new ContactCascadeCleanupTriggerHandler().run();
    new ContactStatusNotificationTriggerHandler().run();
}
```

`ContactCascadeCleanupTriggerHandler` overrides only `beforeDelete()`; `ContactStatusNotificationTriggerHandler` overrides only `afterUpdate()`. Both are safe to instantiate on every trigger fire — whichever one's hook doesn't match the current context runs its inherited no-op and returns immediately.

## 3. Idempotency belongs at two layers: the handler filters for performance, the service enforces it for correctness

**Rule.** A trigger handler should narrow down to the records that plausibly need work — for example, only rows whose status actually transitioned to a terminal value — before calling into a service. The service itself must independently guard against doing that work twice, because the handler's filter is a performance optimization, not a correctness boundary.

**Why.** Triggers refire on every DML against the object, including unrelated field updates, workflow/flow-driven updates, and legitimate recursion once a bypassed handler is cleared. If duplicate downstream work is prevented only by the handler's pre-filter, any refire that happens to match the filter condition produces duplicate work. The service-level check — deduping against existing records, checking a state flag before writing — is what makes replaying the same trigger event, or the same inbound event, a safe no-op.

```apex
// Handler: cheap pre-filter, not the correctness boundary.
protected override void afterUpdate() {
    List<Order__c> resolvedOrders = new List<Order__c>();
    for (Order__c order : (List<Order__c>) Trigger.new) {
        Order__c oldOrder = ((Map<Id, Order__c>) Trigger.oldMap).get(order.Id);
        if (order.Status__c == 'Resolved' && oldOrder.Status__c != 'Resolved') {
            resolvedOrders.add(order);
        }
    }
    if (!resolvedOrders.isEmpty()) {
        OrderFulfillmentService.processResolvedOrders(resolvedOrders);
    }
}
```

```apex
// Service: the actual correctness boundary — safe even if called twice
// for the same order.
public static void processResolvedOrders(List<Order__c> orders) {
    Set<Id> orderIds = collectIds(orders);
    Set<Id> alreadyProcessed = queryExistingFulfillmentIds(orderIds);

    List<Order__c> toProcess = new List<Order__c>();
    for (Order__c order : orders) {
        if (!alreadyProcessed.contains(order.Id)) {
            toProcess.add(order);
        }
    }
    // ...
}
```

## 4. Bulkified by default: collections in, SOQL hoisted out of loops, `Map` lookups for O(1) access

**Rule.** Every method a trigger handler calls into takes a collection — `Set<Id>` or `List<SObject>` — never a single record. Every SOQL query the handler or its downstream service issues runs once, before any loop, with results indexed into a `Map` keyed by `Id` (or another natural key) so per-record lookups are O(1). No SOQL inside a `for` loop, no exceptions.

**Why.** A trigger can fire with up to 200 records in a single execution context. A method that only accepts a single record either gets invoked once per record — turning any SOQL inside it into a query-per-record that blows the 100-query governor limit on a bulk operation — or forces the caller to loop and call it one record at a time, which is the same defect one layer up. Bulk-shaped code that happens to run against a single record costs nothing extra; single-record-shaped code that receives bulk input breaks.

```apex
public static void routeOrders(List<Order__c> orders) {
    Set<Id> accountIds = collectAccountIds(orders);

    // One query, hoisted above any loop, indexed for O(1) lookup below.
    Map<Id, Account> accountsById = new Map<Id, Account>(
        [SELECT Id, Owner_Region__c FROM Account WHERE Id IN :accountIds WITH USER_MODE]
    );

    for (Order__c order : orders) {
        Account account = accountsById.get(order.AccountId);
        if (account != null) {
            // per-record logic against the pre-fetched map — no query here
        }
    }
}
```

---

**Summary of the trigger-framework principle:** one trigger per SObject, delegating in a single line to a handler that extends the shared dispatcher; split unrelated concerns into separate handler instances rather than branching inside one; treat the handler's pre-filter as a performance optimization and put the actual idempotency guarantee in the service layer; and never let a method or a query assume it only ever handles one record.
