# Data Retention and Subject Erasure

This file governs two related but distinct problems: **retention** (deleting records once they've outlived the business or legal reason to keep them) and **erasure** (deleting *everything* tied to a data subject on request, to the standard a privacy regulation demands). Read this before writing a scheduled cleanup job, adding a new retention rule to an existing purge framework, or building a delete cascade for a subject-erasure / right-to-be-forgotten request.

## Retention

### 1.1 Drive retention from configuration, not a schedulable class per object

**Rule.** A retention job reads its scope — which object, what age cutoff, what exclusion flag — from Custom Metadata, not from values hardcoded in Apex. Adding a new object to retention should be a CMDT record, not a deploy.

**Why.** Retention windows are a business/compliance decision, not an engineering one, and they change: legal shortens a window, a new object needs purging, an exception gets carved out for one record type. If that logic lives in Apex, every change is a deploy with a review cycle attached. If it lives in CMDT, an admin (or a change set) ships the new window without touching code.

**Evidence.** [`LogCleanupBatch`](../utilities/logging/LogCleanUp/LogCleanupBatch.cls) reads retention days per log object from `Log_Clean_Up__mdt` via [`LogCleanupContext`](../utilities/logging/LogCleanUp/LogCleanupContext.cls), builds one dynamic query per configured object, and deletes whatever's older than its configured cutoff — adding a new log type to the purge is a CMDT record, not a code change.

```apex
Map<String, Integer> logRetentionDays = context.getLogRetentionDays();
for (String logName : logRetentionDays.keySet()) {
    Integer daysToKeep = logRetentionDays.get(logName);
    Date cutoffDate = Date.today().addDays(-daysToKeep);
    // one dynamic query per configured object — see 1.4 for why this is safe
}
```

**Recommended pattern: generalize to an SObject-agnostic rule engine.** `LogCleanupBatch` above is scoped to log objects. The same shape generalizes cleanly to *any* object — audit records, business records, anything with an age-based or condition-based expiry: one retention-rule CMDT (`sobjectApiName`, `soqlWhereClause`, `retentionDays`, `active`) and one batch that iterates active rules, builds the candidate query per rule, and deletes what qualifies. Build it as one engine that all retention needs share, not a new schedulable class per object — the moment you have two purge batches that differ only in which object and which cutoff they hardcode, that's the signal to collapse them into one CMDT-driven runner.

### 1.2 A retention batch's elevated privilege is deliberate, documented, and never reachable from a UI

**Rule.** A scheduled purge must remove records regardless of who owns them or what FLS the running user has — that's the whole point of a background retention job. Declare the class `without sharing`, route the delete through the DML layer's system-elevated path, and say why in the class header. The elevation must never be reachable from an `@AuraEnabled` method; retention runs on a schedule, not on a click.

**Why.** `without sharing` plus a system-mode delete is real privilege elevation — worth a second look from anyone reading the class. Stating the reason inline (records must be purged independent of ownership) turns that second look into a five-second confirmation instead of an investigation. Keeping it out of the `@AuraEnabled` surface means the elevation can never be triggered by a user action, only by the trusted scheduler.

**Evidence.** [`LogCleanupBatch`](../utilities/logging/LogCleanUp/LogCleanupBatch.cls) declares `without sharing`, documents the elevation in its class header and again at the call site, and deletes via `Database.delete(scope, AccessLevel.SYSTEM_MODE)` — the one place in the codebase a [`DMLManager`](../utilities/dml/DMLManager.cls) bypass is warranted, because `DMLManager`'s default path enforces `USER_MODE`. Route the same elevation through [`DMLManager.deleteAsSystem`](../utilities/dml/DMLManager.cls) where the manager's system-mode surface covers your case. The class has no `@AuraEnabled` methods.

### 1.3 Recommended pattern: predicate-driven retention, positive framing, fail closed on error

Age-based cutoffs (1.1) cover most retention needs, but some records need a *conditional* hold — don't delete this record even though it's old, because some related condition still applies (an open case references it, an open opportunity is still active). Model that as a predicate the retention engine calls per candidate record, not as an ever-growing `WHERE` clause on the purge query:

- Define a single-method interface — `shouldKeep(SObject candidate)` — and let each hold condition be one small implementation.
- Name it for what it does when true, not what it does when false. `KeepIfOpportunityOpen` reads correctly at the call site; `RejectIfOpportunityOpenPredicate` makes every reader negate twice to understand the outcome.
- **Fail closed on any predicate error** — class not found, exception thrown mid-evaluation. The engine must treat an error as "keep." Deleting a record because its hold-check broke is unrecoverable. Keeping a record because its hold-check broke is a missed cleanup that runs again tomorrow, once whatever broke is fixed.

```apex
public interface IRetentionHoldPredicate {
    Boolean shouldKeep(SObject candidate);
}

// In the engine, per candidate:
Boolean keep;
try {
    keep = predicate.shouldKeep(candidate);
} catch (Exception ex) {
    Logger.logException(ex, 'RetentionEngine', 'applyPredicate');
    keep = true; // fail closed — an error is never grounds to delete
}
```

### 1.4 Dynamic SOQL sourced from Custom Metadata field values does not need `escapeSingleQuotes` — but document why

**Rule.** When a retention batch (or any batch) builds dynamic SOQL from a CMDT field value — an object API name, a `WHERE` clause fragment — that value does not need `String.escapeSingleQuotes()`. CMDT rows are authored by admins deploying trusted configuration, not submitted by end users. Bind everything that *is* user- or record-derived (a cutoff date, an ID) as a bind variable; the CMDT-sourced string itself is the trusted part of the query and can compose directly. Document the trust boundary at the point of composition so a future reader doesn't "fix" it into a bind variable that doesn't apply, or worse, treat it as an injection risk that needs sanitizing.

**Why.** `escapeSingleQuotes()` exists to neutralize single quotes in *untrusted* string input before it lands inside a query literal. A CMDT object-API-name or where-clause fragment isn't user input — it's admin-authored configuration that ships the same way a permission set or a validation rule does. Escaping it doesn't add safety; it just obscures that the trust boundary is "who can edit CMDT," not "what characters are in this string."

**Evidence.** [`LogCleanupBatch.start()`](../utilities/logging/LogCleanUp/LogCleanupBatch.cls) composes `'SELECT Id FROM ' + logName + ' WHERE CreatedDate < :cutoffDate ...'` from a CMDT-sourced object name with an inline comment stating the trust boundary explicitly, while binding the actual variable data (`cutoffDate`) rather than concatenating it.

---

## Erasure

### 2.1 Subject erasure pairs every delete with `Database.emptyRecycleBin` in the same transaction

**Rule.** When a data-subject erasure request (GDPR Article 17, CCPA deletion) reaches Apex, a plain `delete` is not enough. Salesforce's standard delete is a soft delete — the record sits in the Recycle Bin, recoverable, for up to 15 days. A regulation that requires data to become irrecoverable on request is not satisfied by a recoverable delete. Every erasure DML call is immediately followed, in the same method, by `Database.emptyRecycleBin(records)` against the same records.

**Why.** "Irrecoverable" is the operative word in subject-erasure law — a soft-deleted row that any admin can restore from the Recycle Bin for two weeks does not meet that bar. Pairing the delete with an immediate recycle-bin purge closes the gap in the same transaction that performed the delete, so there is no window where the "erased" data is still sitting in a bin waiting to be undeleted.

```apex
List<Contact> subjectContacts = /* records identified for this subject */;
Database.DeleteResult[] results = DMLManager.deleteAsUser(subjectContacts);
Database.emptyRecycleBin(subjectContacts);
```

### 2.2 Cascade erasure from a `before delete` trigger; rethrow on cascade failure to abort the parent delete

**Rule.** When erasing a subject's primary record must also erase dependent records, run the cascade from a `before delete` handler on the parent object — before the platform clears the foreign-key references the cascade needs to find the dependents. If the cascade fails partway through, rethrow the exception so the parent delete aborts too. Do not swallow a cascade failure and let the parent delete succeed anyway.

**Why.** `before delete` still has the parent's relationships intact, so the handler can reliably query "everything that points at this record" before that graph disappears. Rethrowing on failure matters because a partial cascade is worse than no cascade: the subject's primary record is gone, but some dependent record — still holding the subject's data — survives, invisible, with no parent left to reveal it exists. A silent partial cascade is exactly the compliance gap the erasure requirement exists to prevent; aborting the whole delete on cascade failure keeps the data intact and the failure visible instead of hiding it.

```apex
trigger ContactTrigger on Contact (before delete) {
    if (Trigger.isBefore && Trigger.isDelete) {
        try {
            new ContactErasureCascadeHandler().eraseDependents(Trigger.old);
        } catch (Exception ex) {
            Logger.logException(ex, 'ContactErasureCascadeHandler', 'eraseDependents');
            // Rethrow to abort the parent delete — a partial cascade would leave
            // dependent records holding the subject's data with no parent left
            // to reveal they exist. Losing the delete is safer than losing the trail.
            throw ex;
        }
    }
}
```

---

**Summary of the boundary between the two halves.** Retention is routine and scheduled — it runs on a timer, elevates deliberately, and is driven by configuration so the business can change its mind without a deploy. Erasure is triggered and transactional — it runs on request, must reach every dependent record in one atomic unit of work, and must leave no recoverable trace. Both end in a delete; what precedes the delete, and what happens if something goes wrong mid-cascade, is where the two patterns diverge.
