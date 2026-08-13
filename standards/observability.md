# Observability — Exception Handling and Logger Discipline

This file governs what happens after a `catch` block fires: what the user (or the calling system) is allowed to see, what gets written server-side for an operator to find later, and how privileged actions leave an audit trail. Read it before writing any try/catch that rethrows, any `@AuraEnabled` or `@RestResource` method that surfaces an error to a caller, or any controller action an admin or moderator uses to mutate state.

## 1 Exception messages

### 1.1 Never leak a stack trace into a rethrown exception message

A rethrown exception's message MUST contain only three things:

- A sanitized, human-readable sentence.
- `e.getTypeName()` — the exception class name, an operator hint with no internal detail.
- The transaction request ID, via `System.Request.getCurrent().getRequestId()`.

Never concatenate `e.getStackTraceString()` — or `e.getMessage()` — into the message a user, an admin, or an API caller can see. The stack trace's home is your logging sink, reached by correlation ID; it does not belong in a Lightning toast, a Setup "Delete failed" page, or a REST response body.

Salesforce surfaces uncaught or rethrown exception messages directly at whatever surface the operation ran on. A user attempting to delete a record can read class names, line numbers, and method signatures straight off a failure toast — that's a reconnaissance surface, not a cosmetic one.

```apex
// Bad — leaks internal topology to whoever reads the toast
throw new OrderServiceException(
    'Order close failed: ' + e.getMessage() + ' - ' + e.getStackTraceString());

// Good — operator hint + correlation ID, nothing else
throw new OrderServiceException(
    'Order close failed. Contact your administrator. ' +
    e.getTypeName() + ' [txn:' + System.Request.getCurrent().getRequestId() + ']');
```

### 1.2 Route every catch through the logger's exception method, never a raw message log

Every catch boundary that needs server-side observability logs the full exception before rethrowing a sanitized one:

```apex
try {
    // ...
} catch (Exception e) {
    Logger.logException(e, 'OrderService', 'closeOrder');
    throw new OrderServiceException(
        'Order close failed. Contact your administrator. ' +
        e.getTypeName() + ' [txn:' + System.Request.getCurrent().getRequestId() + ']');
}
```

Use the logger's dedicated exception method — [`Logger.logException`](../utilities/logging/Logger.cls) — not a generic `Logger.error(e.getMessage(), ...)` call. `logException` captures the exception's type, message, and stack trace together; a bare `error(e.getMessage())` call drops the stack trace and leaves you diagnostically blind on exactly the record you need most.

The user-facing message (rule 1.1) and the server-side log (this rule) are two different audiences with two different disclosure budgets — never let the two collapse into one string. Never leak into the rethrown message:

- `e.getMessage()` — may contain field names, record IDs, or query text.
- `e.getStackTraceString()` — leaks class names and line numbers.
- Any internal SOQL or business-rule detail.

### 1.3 AuraHandledException carries a correlation ID, never raw exception text

LWC-facing exceptions follow the same shape as rule 1.2, but the rethrow type is `AuraHandledException`:

```apex
try {
    // ...
} catch (Exception e) {
    Logger.logException(e, 'OrderController', 'loadOrderSummary');
    throw new AuraHandledException('Unable to load order data. Error ID: ' +
        System.Request.getCurrent().getRequestId());
}
```

The toast or inline error the end user sees should be operator-actionable: "give me Error ID X" lets an admin find the logged exception and get a full diagnostic, without the component ever needing to render internal detail. A message like `'Unable to load order data for this account.'` with no correlation ID gives the operator no thread to pull — it looks tidy but it's a dead end.

## 2 Audit trail on privileged actions

### 2.1 Admin and moderation actions emit an audit-trail log entry on success

When an admin- or moderator-tier user mutates state through a controller — approve, retry, override, force-process, manually close — the success path (not just the failure path) emits a log entry capturing **actor, action, target record ID, and reason or payload**, with a timestamp.

```apex
DMLManager.updateAsUser(orders);
Logger.info(
    UserInfo.getUserName() + ' overrode order ' + orderId + ' reason=' + reason,
    'OrderAdminController', 'overrideOrder');
```

Treat the audit trail as an artifact you build regardless of whether a regulator or auditor is asking today — not a side effect you'll add once compliance asks for it. When an admin overrides a stuck record, retries a failed job, or force-processes a test case, the system must be able to answer "who did that, and when" without someone doing git-archaeology or interviewing the team. This is the same discipline GDPR/CCPA subject-erasure logging already forces on you for delete paths; apply it to every privileged mutation, not just erasure.

## 3 Recommended pattern: persist trigger-originated exceptions to a dedicated log object

Rule 1.2 gets you server-side capture for any exception your own code explicitly catches. Trigger-context exceptions are a harder case: the whole point of a trigger handler's catch-and-swallow boundary is that one bad record in a batch of 200 shouldn't fail the other 199, so the exception gets logged and the transaction moves on. If "logged" means "written to the debug log," that record of what went wrong survives only as long as the debug log does — typically hours — and it isn't queryable by transaction ID or record ID. The first time that trigger misbehaves in production without someone tailing debug logs live, the failure is gone before anyone notices the record that silently didn't process.

The durable version of the same pattern:

1. A dedicated SObject (e.g. `Trigger_Exception_Log__c`) that persists trigger exceptions with full context — originating class, method, transaction ID, the record ID(s) involved, the exception type/message/stack trace, and a recoverable-or-not flag.
2. A logging helper — `Logger.logTriggerException(e, className, methodName, sObjectType, recordIds)` — that writes the row. Bulkify it the same way the trigger handler batches recovery: one row per failing record, or one row per failing chunk, not one row per exception thrown inside a loop.
3. A retention rule so the log object doesn't grow unbounded. If your org already runs a CMDT-driven retention framework, this object is just another consumer of it — no special-casing needed.
4. A narrowly scoped viewer permission set for ops/support triage, so reading the log doesn't require a full System Administrator grant.

This mirrors how [`Logger.cls`](../utilities/logging/Logger.cls) already persists exceptions for outbound-integration failures — the trigger-context version is the same idea applied to the inbound/DML side, where the current default (debug-log-only) is the diagnostic gap most teams don't notice until the record they needed is already gone. Build it as an extension of `Logger`, not a fork of it — the catch-and-persist shape belongs in one place. Wire the handler side through [`TriggerHandler.cls`](../utilities/triggers/TriggerHandler.cls) so every trigger's catch boundary calls the same helper instead of each handler inventing its own.

```apex
// Inside a trigger handler's catch boundary
} catch (Exception e) {
    Logger.logTriggerException(e, 'OrderTriggerHandler', 'handleAfterUpdate',
        Order__c.SObjectType, failedIds);
    // TODO: decide per-handler whether a partial-batch failure should also
    // rethrow to abort the transaction, or swallow and let the log entry
    // be the record of what needs manual follow-up.
}
```
