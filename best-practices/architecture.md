# Architecture & patterns

> Ratified by David Wood 2026-05-12. The conventions below are canon for all Apex work in this codebase.

## Canonical guidance from existing standards

- Single-responsibility per method/class. Decompose anything over the complexity budget (see [apex.md](apex.md)).
- All DML through [`DMLManager`](../utilities/dml/DMLManager.cls) using `xxxAsUser` methods.
- State that must outlive the current transaction belongs in session platform cache, never static class variables. State scoped to the current transaction (a trigger recursion guard, a bypass flag) is exactly what static class variables are for — see [apex.md](apex.md#caching).

---

## Proposed additions

### Trigger framework

- **One trigger per object.** The trigger body is one line: delegate to [`TriggerHandler`](../utilities/triggers/TriggerHandler.cls).
- Handlers route events to services; they don't contain business logic. A `BeforeInsert` handler method either calls service methods or does cheap validation — nothing else.
- Services and domain logic are independently testable without firing a trigger.

```apex
trigger AccountTrigger on Account (
    before insert, before update, before delete,
    after insert, after update, after delete, after undelete
) {
    new AccountTriggerHandler().run();
}
```

### Selector / Service / Domain layering

Adopt a simplified [Apex Enterprise Patterns](https://github.com/apex-enterprise-patterns/fflib-apex-common) layering:

| Layer | Owns | Example |
| --- | --- | --- |
| **Selector** | All SOQL for an SObject. No business logic. | `AccountSelector.selectByIds(Set<Id>)`. |
| **Service** | Transactional business logic, bulk-safe, stateless. | `AccountService.recalculateRollups(List<Account>)`. |
| **Domain** | Per-record / per-list invariants and behavior. | `Accounts.applyDefaultsBeforeInsert()`. |
| **Controller / Trigger Handler** | Glue. Translates inbound events to service calls. | `AccountTriggerHandler.onAfterInsert()`. |

Use the `@group` ApexDoc tag to identify the layer (`@group Selector`, `@group Service`, `@group Domain`).

### Bulkification — non-negotiable

- **No SOQL or DML inside `for` loops.** Period.
- Every method that takes a single record should also accept a `List<>` of records. Single-record methods delegate to bulk:

```apex
public static void apply(SObject record) { apply(new List<SObject>{ record }); }
public static void apply(List<SObject> records) { /* … */ }
```

- Guard early: `if (records == null || records.isEmpty()) return;`

### SOQL safety

- **Static SOQL with bind variables** by default: `WHERE Name LIKE :queryName`. No string concatenation of user input.
- Dynamic SOQL only when the shape is genuinely dynamic. When required, sanitize every user-supplied value with `String.escapeSingleQuotes()` before composition.
- Always enforce CRUD/FLS at the query site (`WITH USER_MODE` clause — see [apex.md](apex.md#user_mode--system_mode-on-soql-and-dml)).

### Async patterns

- **Queueable** for chainable async work with state. Default async tool.
- **Batchable** only when processing > 50,000 records or needing scope iteration.
- **Schedulable** wraps a Queueable/Batchable; the schedulable class itself contains no business logic.
- Platform Events for fire-and-forget cross-system signals.

### Custom metadata over custom settings

Configuration that ships with the package or is environment-specific lives in **Custom Metadata Types**. Custom Settings only when the value must be writable by Apex at runtime (rare).

### Code review expectations

- PR titles start with a ticket reference from the team's issue tracker: `PROJ-1234: short description`.
- PR description: 1–2 sentence summary plus a test plan (bulleted checklist).
- No merging without passing CI (lint, Jest, Apex tests).
- Touched Apex classes ≥ 75 % coverage in the PR's tests (see [apex-tests.md](apex-tests.md#coverage-threshold)).
