# Async Patterns

This file governs when to reach for Queueable, Batchable, Schedulable, or Platform Events; how batch jobs stay idempotent and safe against mixed-SObject scope; and when it's acceptable to stay synchronous instead of reaching for async at all. Read this before adding any job that runs outside a request-response transaction, and before deciding whether a trigger-time operation needs to move off the synchronous path.

## 1. Pick the async tool by shape, not habit

**Rule.** Match the tool to the job's shape. Reaching for the familiar tool instead of the right one is the most common async mistake in this list.

| Tool | When | Notes |
| --- | --- | --- |
| **Queueable** | Default async choice. Chainable, carries state via class fields. | Use for anything that doesn't clearly need `Batchable`'s scope iteration. |
| **Batchable** | Scope exceeds ~50,000 records, or the job needs governor-scoped iteration over a large query. | Use `Database.Stateful` only when you need a cross-execute counter or accumulator — it costs a small amount of overhead per execute and isn't free by default. |
| **Schedulable** | Cron entry point only. | Wraps a Queueable or Batchable. Zero business logic in the schedulable class itself — it exists to satisfy the cron interface and hand off. |
| **Platform Events** | Fire-and-forget cross-system signals. | Consumer subscribes via `lightning/empApi` in an LWC, or an after-insert trigger in Apex. Use when the sender shouldn't block on, or know about, what the receiver does with the signal. |

```apex
public class OrderSyncScheduler implements Schedulable {
    public void execute(SchedulableContext sc) {
        // No business logic here — just hand off to the Queueable/Batchable
        // that actually does the work.
        Database.executeBatch(new OrderSyncBatch(), 200);
    }
}
```

## 2. Batches that recompute state must filter out already-converged records in `start()`

**Rule.** A batch that recomputes a value over time — a decay score, an archival flag, a retention sweep — must filter its `start()` query to exclude records that have already reached their terminal state. Re-running over a dataset where most rows are already converged should do close to no work.

**Why.** These jobs typically run on a recurring schedule (nightly, weekly) against a growing dataset. Once a record reaches its floor, ceiling, or terminal state, re-processing it every run is wasted query rows, wasted DML, and wasted governor budget for zero behavioral change. Idempotency here means "running again against an unchanged record is a no-op" — and that has to be enforced at the query, not discovered inside the loop after the row is already pulled into scope.

```apex
public Database.QueryLocator start(Database.BatchableContext bc) {
    // Skip records already at the terminal state — re-running this job
    // weekly should do no work against rows that already converged.
    return Database.getQueryLocator([
        SELECT Id, Confidence_Score__c, Is_Dismissed__c
        FROM Signal__c
        WHERE Is_Dismissed__c = FALSE
        AND Confidence_Score__c > 0
    ]);
}
```

A companion archival batch follows the same shape from the other direction — filter out rows that are *already* archived so the job only touches the ones still eligible:

```apex
WHERE Is_Active__c = TRUE AND CreatedDate < :cutoffDate
```

## 3. Mixed-SObject batch scope groups by `SObjectType` before DML, with a try/catch per type

**Rule.** A generic batch or framework that can process more than one SObject type in a single execute chunk must call `record.getSObjectType()`, group the scope into a `Map<SObjectType, List<SObject>>`, and issue one DML statement per type — each wrapped in its own try/catch.

**Why.** If the chunk issues a single DML call across mixed types, or a single try/catch around all of them, one type's failure (a validation rule, a trigger exception, a lock contention row) rolls back or swallows every other type in the same chunk. Grouping by type isolates the blast radius: a bad record of one type doesn't starve unrelated types that were otherwise clean.

```apex
public void execute(Database.BatchableContext bc, List<SObject> scope) {
    if (scope == null || scope.isEmpty()) {
        return;
    }

    Map<SObjectType, List<SObject>> byType = groupBySObjectType(scope);

    for (SObjectType type : byType.keySet()) {
        List<SObject> recordsOfType = byType.get(type);
        try {
            DMLManager.deleteAsSystem(recordsOfType);
        } catch (Exception ex) {
            // Log and continue per type — throwing here would roll back
            // the entire chunk and starve other SObject types in scope.
            Logger.logException(ex, 'CleanupBatch', 'execute');
        }
    }
}

private Map<SObjectType, List<SObject>> groupBySObjectType(List<SObject> scope) {
    Map<SObjectType, List<SObject>> byType = new Map<SObjectType, List<SObject>>();
    for (SObject record : scope) {
        SObjectType type = record.getSObjectType();
        if (!byType.containsKey(type)) {
            byType.put(type, new List<SObject>());
        }
        byType.get(type).add(record);
    }
    return byType;
}
```

See [`DMLManager.cls`](../utilities/dml/DMLManager.cls) for the `deleteAsSystem` / `deleteAsUser` surface used per type above, and [`Logger.cls`](../utilities/logging/Logger.cls) for the per-type exception logging.

## 4. Bounded, bulkified trigger-time SOQL fan-out doesn't automatically need to go async

**Rule.** A trigger handler is allowed to call a service that issues several — five, six, seven — SOQL queries against bind-variable sets in the same transaction, provided every query is a pure function of the trigger's input records, the total stays comfortably inside governor headroom, and nothing in the path makes a callout. Moving that work to async (Queueable, Platform Event) is the right call only when the synchronous path would actually breach governor limits, hold an external resource open, or make the UI wait on work the user doesn't need to wait on.

**Why.** "It's async" is not a code-quality signal on its own — async adds a hop, a delay, and a place for eventual-consistency bugs to hide (the UI reads stale data because the async job hasn't run yet). If the synchronous path is bulk-safe and within budget, staying synchronous is simpler to reason about, test, and debug. Reach for async because the synchronous path genuinely can't do the job, not by default.

```apex
// Acceptable synchronous fan-out: every query below is bind-variable-bound,
// pure over the trigger's new/old maps, and there are no callouts in the
// path. If SOQL count or row volume grows past governor headroom, THAT'S
// the signal to move this to a Queueable — not the query count itself.
public class SignalRoutingService {
    public static void routeForRecords(List<Signal__c> newRecords) {
        Set<Id> parentIds = collectParentIds(newRecords);
        Map<Id, Account> accounts = new Map<Id, Account>(
            [SELECT Id, OwnerId FROM Account WHERE Id IN :parentIds WITH USER_MODE]
        );
        // ...additional bounded, bind-variable queries against the same input set...
    }
}
```

Document the decision to stay synchronous inline (or in the class header) when the query count is non-trivial, so a future reviewer doesn't "fix" it into async without checking whether the synchronous path was actually a documented, deliberate choice.

---

**Summary of the tool-selection principle:** Queueable is the default; Batchable is for scale, not preference; Schedulable is a cron trigger with no logic of its own; Platform Events decouple sender from receiver entirely. Idempotency belongs in the batch's `start()` query, not in application-layer "already processed" checks discovered mid-loop. Mixed-type scope isolates failure by grouping before DML. And synchronous trigger-time SOQL fan-out is a legitimate choice — not a code smell — as long as it's bulk-safe, bounded, and callout-free; async is a response to a genuine governor, latency, or resource constraint, not a default posture.
