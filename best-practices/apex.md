# Apex — Class authoring

## Header

Every class header carries:

| Tag            | Value                                                         |
| -------------- | ------------------------------------------------------------- |
| `@description` | One-line purpose statement.                                   |
| `@group`       | Type / category (e.g. `Service`, `Domain`, `Selector`).       |
| `@author`      | Author name.                                                  |
| `@since`       | Existing date, or current month/year (e.g. `May 2026`).       |
| `@last`        | Current date + brief change note; append to existing entries. |

Comment groupings/sections, not lines.

**Method-level ApexDoc is not header-only.** Every `public`, `global`, `@AuraEnabled`, `virtual`, and `abstract` method carries its own ApexDoc — the public surface is the contract other engineers code against. `private` methods stay undocumented by default, documented only when one of four criteria fires (business-rule predicate, cached state, non-obvious side effects, ordering/idempotency contract). Full shape and the private-method criteria are canonized in [documentation.md §3](../standards/documentation.md#3-apexdoc-and-jsdoc-coverage-on-the-public-surface) — this file doesn't restate them.

## Naming

- **CamelCase** for methods and variables. No underscores except where required (field API names like `Unique_Key__c`).
- Normalize property/variable/method names unless the name is fixed by an interface, `@TestVisible`, or external reference.

## Documentation

- Inline comments only where logic isn't self-evident to a competent Salesforce engineer.
- Document the _why_, not the _what_ — well-named identifiers describe themselves.

## Complexity budget

| Limit                 | Per method | Per class |
| --------------------- | ---------- | --------- |
| Apex complexity       | < 8        | < 45      |
| Cyclomatic complexity | < 8        | < 36      |

Decompose anything over budget. Prefer `Map` lookups over nested loops. Single responsibility per method.

## DML

- All DML routes through [`DMLManager`](../utilities/dml/DMLManager.cls) using its **`xxxAsUser` methods** (`insertAsUser`, `updateAsUser`, etc.). Never bare `insert`/`update`/`delete` outside `DMLManager`.

## Method visibility

- Default to `private`. Use `@TestVisible` only when a test legitimately needs internal access.

## Error handling

- Use [`Logger`](../utilities/logging/Logger.cls) for logging — never `System.debug` in production paths.
- Processing classes wrap in try/catch and rethrow with a custom exception that carries context. **Never concatenate `e.getMessage()` + `e.getStackTraceString()` into the rethrown message** — that's the exact anti-pattern [observability.md](../standards/observability.md) bans: internal exception detail leaking into a message a caller (or an end user, several layers up) can see. `Logger.logException` captures the full detail server-side; the rethrown message carries only a correlation ID and the exception's type name:

```apex
try {
    // ...
} catch (Exception e) {
    String correlationId = Utilities.generateUUID();
    Logger.logException(e, 'OrderProcessor', 'processOrders');
    throw new OrderProcessorException(
        'Order processing failed [' + correlationId + ']: ' + e.getTypeName());
}
```

- Each processor declares its own exception extending the module-level base:

```apex
/** @description Custom exception class for OrderProcessor errors. */
public class OrderProcessorException extends OrderModuleException {
}
```

## Caching

- Use **session platform cache** for state that genuinely needs to survive past the current transaction (e.g. a value computed once and reused by a later, separate transaction). Static class variables reset at the end of every transaction, so they're the wrong tool for that job — but they're the *right* tool for state scoped to a single transaction (a trigger recursion guard, a bypass flag checked only within the transaction that set it). Don't reach for platform cache just because a variable is `static`; reach for it when the state has to outlive the transaction.

## Scheduling

- Use **headless LWC actions** for scheduling work from the UI tier.

---

## Proposed additions

### Sharing modifier is mandatory

Every Apex class declares `with sharing`, `without sharing`, or `inherited sharing` explicitly. No implicit defaults. Static analysis should flag missing modifiers.

### USER_MODE / SYSTEM_MODE on SOQL and DML

For new Apex on API 60+, use `WITH USER_MODE` / `WITH SYSTEM_MODE` on SOQL and the `AccessLevel` enum on `Database` DML in addition to `with sharing`. They enforce CRUD/FLS at the query/DML site, not just record visibility.

```apex
List<Account> accs = [SELECT Id, Name FROM Account WITH USER_MODE LIMIT 50];
Database.insert(accs, AccessLevel.USER_MODE);
```

`DMLManager.xxxAsUser` is verified to route through `AccessLevel.USER_MODE` internally on every path (see [`DMLManager.cls`](../utilities/dml/DMLManager.cls)) — there's nothing left to audit here.

**CMDT reads — not routine SOQL.** Custom Metadata Type access goes through `Type.getInstance()` / `<Type>.getAll()`, never a SOQL query — see [architecture-layering.md](../standards/architecture-layering.md) for the full rule and why. The one sanctioned exception is narrow: a Custom Metadata field is a long-text area whose value exceeds the 255-character truncation the `getInstance()` / `getAll()` static methods impose. That's the only case where SOQL against a `__mdt` object is the right call, and when it fires, the query uses `WITH SYSTEM_MODE` with the reason documented inline — not `WITH USER_MODE`, which is policy theater here: CMDT reads bypass CRUD/FLS by platform rule, so there's no user-mode access decision to make.

```apex
// Long_Description__c exceeds the 255-char limit Type.getInstance() truncates to;
// SOQL is the only way to retrieve the full value. WITH SYSTEM_MODE — CMDT reads
// bypass CRUD/FLS by platform rule, so WITH USER_MODE here would be policy theater.
List<Integration_Config__mdt> cfg = [
    SELECT Id, Long_Description__c
    FROM Integration_Config__mdt
    WITH SYSTEM_MODE
];
```

### Logging discipline

- `Logger.logException(e, className, methodName)` for caught exceptions.
- `Logger.info` / `Logger.warn` / `Logger.debug` sparingly — log decision points, not every step.
- Schedule [`LogCleanupScheduler`](../utilities/logging/LogCleanUp/LogCleanupScheduler.cls) so log records don't accumulate.

### Custom labels for user-facing strings

All user-visible text (toast messages, page labels, exception messages displayed to end users) → Custom Labels. No hardcoded strings in Apex or LWC templates.
