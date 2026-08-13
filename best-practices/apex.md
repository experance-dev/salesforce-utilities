# Apex — Class authoring

## Header

ApexDoc annotations live **only in the class header** (not on every method):

| Tag            | Value                                                         |
| -------------- | ------------------------------------------------------------- |
| `@description` | One-line purpose statement.                                   |
| `@group`       | Type / category (e.g. `Service`, `Domain`, `Selector`).       |
| `@author`      | Author name.                                                  |
| `@since`       | Existing date, or current month/year (e.g. `May 2026`).       |
| `@last`        | Current date + brief change note; append to existing entries. |

Comment groupings/sections, not lines. Method-level ApexDoc only when params/returns warrant `@param` / `@return`.

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
- Processing classes wrap in try/catch and rethrow with a custom exception that carries context:

```apex
try {
    // ...
} catch (Exception e) {
    Logger.logException(e, 'OrderProcessor', 'processOrders');
    throw new OrderProcessorException(
        'An error occurred while processing orders: '
        + e.getMessage() + ' - ' + e.getStackTraceString());
}
```

- Each processor declares its own exception extending the module-level base:

```apex
/** @description Custom exception class for OrderProcessor errors. */
public class OrderProcessorException extends OrderModuleException {
}
```

## Caching

- Use **session platform cache** for cross-transaction state (e.g. trigger helper flags). Don't use static class variables as a substitute.

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

Audit `DMLManager.xxxAsUser` to confirm it uses `AccessLevel.USER_MODE` internally.

**CMDT carve-out.** `WITH SYSTEM_MODE` is acceptable on Custom Metadata Type queries since CMDT reads bypass CRUD/FLS by platform rule. `WITH USER_MODE` on a CMDT SOQL is semantically policy-theater and has historically raised `QueryException` on older API versions. Prefer `WITH SYSTEM_MODE` (or no clause — CMDT reads ignore both) when the query targets a `__mdt` object; document the choice in the method ApexDoc.

```apex
List<Integration_Config__mdt> cfg = [SELECT Id, SObject_Name__c FROM Integration_Config__mdt WITH SYSTEM_MODE];
```

### Logging discipline

- `Logger.logException(e, className, methodName)` for caught exceptions.
- `Logger.info` / `Logger.warn` / `Logger.debug` sparingly — log decision points, not every step.
- Schedule [`LogCleanupScheduler`](../utilities/logging/LogCleanUp/LogCleanupScheduler.cls) so log records don't accumulate.

### Custom labels for user-facing strings

All user-visible text (toast messages, page labels, exception messages displayed to end users) → Custom Labels. No hardcoded strings in Apex or LWC templates.
