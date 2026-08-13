# Sharing & Permission Enforcement

This file governs how Apex and Lightning components enforce record-level sharing and field/object-level security (FLS): the `with sharing` family of class modifiers, `WITH USER_MODE` / `AccessLevel.USER_MODE` on SOQL and DML, guard patterns for feature-gated fields, org-wide default (OWD) selection for per-user data, and layered permission gating for feature-restricted UI. Read this before writing any class that queries or writes user data, and before adding a new OWD-Private SObject or a permission-gated LWC panel.

## 1. Every class declares a sharing modifier explicitly

**Rule.** Every Apex class that touches user data declares `with sharing`, `without sharing`, or `inherited sharing`. Never rely on the implicit default (which is `without sharing` for a class with no modifier at all).

**Why.** An implicit default is invisible at the call site — a reviewer has to know the rule and go check, rather than read it off the class declaration. An explicit modifier also documents intent: `with sharing` says "this respects the running user's record access," `without sharing` says "this deliberately elevates, read the header for why," and `inherited sharing` says "this takes on whatever context calls it, by design."

**`without sharing` requires a documented reason in the class header.** A batch, scheduler, or service that must see records outside the running user's sharing rules — most commonly retention/cleanup jobs that need to purge records regardless of who owns them — is a legitimate use of `without sharing`, but the elevation is not free. State the reason inline.

```apex
/**
 * @description Purges old log SObject records whose age exceeds the retention
 *              threshold defined in `Log_Clean_Up__mdt` custom metadata.
 * @last May 2026 — conformance refactor: explicit sharing, option-c SYSTEM_MODE delete.
 */
public without sharing class LogCleanupBatch
  implements Database.Batchable<SObject>, Database.Stateful {
```

See [`LogCleanupBatch.cls`](../utilities/logging/LogCleanUp/LogCleanupBatch.cls) for the complete pattern, including the method-level comment justifying the elevation at the point it's used (§3 below).

`inherited sharing` is the right default for a shared utility class that is called from many contexts and should not impose its own sharing model — see [`DMLManager.cls`](../utilities/dml/DMLManager.cls) and [`DMLHelper.cls`](../utilities/dml/DMLHelper.cls), both `inherited sharing` so the caller's context is respected without the utility re-deciding it.

## 2. Every SOQL query enforces access at the query site with `WITH USER_MODE`

**Rule.** SOQL against standard or custom SObjects uses the `WITH USER_MODE` clause, enforcing CRUD and FLS at the query itself rather than relying on the class's sharing modifier alone. Any elevation to `WITH SYSTEM_MODE` is a documented, deliberate carve-out with the reason stated inline at the query — never a default.

**Why.** `with sharing` controls *record visibility* (which rows the query can see). It says nothing about *field* or *object* access — a `with sharing` class can still return a field the running user has no FLS on unless the query itself enforces it. `WITH USER_MODE` closes that gap by making CRUD/FLS a property of the query, not an assumption about the caller.

```apex
List<Order__c> orders = [
    SELECT Id, Name, Status__c
    FROM Order__c
    WHERE AccountId = :accountId
    WITH USER_MODE
];
```

**Custom Metadata Types are the one carve-out that isn't a carve-out.** CMDT reads bypass CRUD/FLS by platform rule — there is no access mode to choose. Don't query CMDT with SOQL at all; use `Type.getInstance()` / `<Type>.getAll()` and skip the access-mode question entirely. If you find yourself debating `USER_MODE` vs. `SYSTEM_MODE` on a `__mdt` SOQL, the query itself is the defect.

## 3. All DML routes through `AccessLevel.USER_MODE`, wrapped by a DML manager

**Rule.** Never issue bare `insert` / `update` / `delete` / `upsert`. Route every write through a DML utility whose default path enforces `AccessLevel.USER_MODE` — CRUD/FLS at the DML site, mirroring the SOQL rule above. Reserve the `AsSystem` / `SYSTEM_MODE` path for audited, deliberate elevations, documented at the call site, never chosen as a convenience.

```apex
DMLManager.insertAsUser(newOrder);
DMLManager.updateAsUser(orders);
```

An elevation looks like this — note the comment carries the *why*, not just the *what*:

```apex
/**
 * Uses `Database.delete` with `AccessLevel.SYSTEM_MODE` directly, bypassing
 * the DML manager, because the manager's default path enforces USER_MODE on
 * every write and this batch must purge records regardless of who owns them.
 */
Database.delete(scope, AccessLevel.SYSTEM_MODE); //NOPMD
```

See [`DMLManager.cls`](../utilities/dml/DMLManager.cls) for the full `insertAsUser` / `updateAsUser` / `upsertAsUser` / `deleteAsUser` / `mergeAsUser` surface and its `AsSystem` counterparts, and [`LogCleanupBatch.cls`](../utilities/logging/LogCleanUp/LogCleanupBatch.cls) for a real, documented `SYSTEM_MODE` bypass.

If a platform API forces a one-off exception — e.g. `Database.upsert(records, externalIdField, false, AccessLevel.USER_MODE)` for external-ID upsert, which has no manager-wrapped overload — document it inline with a `TODO:` noting the gap, so the manager's surface can be extended later.

## 4. Feature-gated fields under `USER_MODE` need an `isAccessible()` guard everywhere they're queried

**Rule.** When any code path issues `WITH USER_MODE` SOQL referencing a field that isn't in every user's FLS — typically a custom lookup or field gated behind a feature permission set — that SOQL raises `QueryException: No such column` for a user who lacks FLS on the field. `USER_MODE` doesn't just filter the result; it hides the field from the schema the query sees. If that code path can fire from a trigger, a cascade service, or an inbound REST call that any persona might trigger — not just the feature's own users — an ungated user causes it to throw.

**"We used `WITH USER_MODE`, so we're covered" is the wrong mental model.** `USER_MODE` protects against *unauthorized reads*. It does nothing to protect an *unauthorized user's unrelated transaction* from breaking because the query it incidentally triggers can't resolve a column it has no business needing. That's a separate failure mode, and it needs a separate guard.

**Guard pattern:** check `isAccessible()` on the gated field before the query runs, and short-circuit to a safe no-op (empty collection, early return) if it isn't accessible.

```apex
public static Set<Id> collectOrderIdsForAccounts(Set<Id> accountIds) {
    if (!Schema.sObjectType.Order__c.fields.Feature_Flagged_Lookup__c.isAccessible()) {
        return new Set<Id>(); // Running user has no FLS on the gated field — nothing to process.
    }

    Set<Id> orderIds = new Set<Id>();
    for (Order__c ord : [
        SELECT Id
        FROM Order__c
        WHERE Feature_Flagged_Lookup__c IN :accountIds
        WITH USER_MODE
    ]) {
        orderIds.add(ord.Id);
    }
    return orderIds;
}
```

**Applies to:** trigger handlers, cascade services called from triggers (delete cascades, reparent-on-convert logic), batches that re-process records at scale, and any inbound REST endpoint a non-feature-permissioned caller might reach. The rule of thumb: if the class can run inside *any* persona's transaction — not just the feature's own users — and it issues `WITH USER_MODE` SOQL against a feature-gated field, the guard is required, not optional.

**When canonizing a new feature-gated field**, grep the codebase for its API name; every `WITH USER_MODE` site that references it needs the guard, including sites that are safe today only because the current caller happens to be permission-restricted at the UI layer. A future caller — a new batch, a new REST endpoint, a foreign trigger — won't carry that restriction, and the guard is what keeps the field's absence a clean no-op instead of an unhandled exception.

## 5. Per-user state requires OWD `Private`, never `ReadWrite` plus an application-layer filter

**Rule.** When an SObject stores per-user state — per-user dismissals, per-user saved views, per-user UI preferences — its organization-wide default sharing setting must be `Private`. Widen access deliberately through sharing rules or role hierarchy where the business genuinely requires it. Never use a `ReadWrite` OWD with a `WHERE CreatedById = :UserInfo.getUserId()` filter in the selector as the only thing standing between one user's rows and another's.

**Why.** An application-layer filter is one selector method away from being dropped — in a refactor, by a new caller who queries the object directly, by a future feature that reuses the SObject for a different purpose. If the boundary lives in the platform's sharing model, Salesforce enforces it for every query against that object, forever, regardless of who wrote the query. If the boundary lives in application code, the application is a single point of failure for cross-user data disclosure.

**Admin visibility survives the tightening.** Setting OWD to `Private` doesn't block legitimate cross-user visibility for moderation or support use cases — grant `View All Records` / `Modify All Records` on the object to the admin permission set. That's an explicit, auditable grant instead of an accidental one.

| OWD choice | Boundary enforced by | Survives a selector refactor? |
| --- | --- | --- |
| `Private` | Platform sharing engine | Yes |
| `ReadWrite` + app-layer filter | Whichever selector method remembers to filter | No |

## 6. Feature-gated UI needs three independent permission layers, not one

**Rule.** A feature-restricted Lightning component and its Apex controller are protected by three layers, each of which must fail closed independently:

1. **FlexiPage Component Visibility** — a filter condition on the component's placement (e.g. `{!$Permission.FeatureAccess} = true`) hides the panel for non-permissioned users at the App Builder layer, before the component even loads.
2. **LWC custom-permission check** — the component imports `@salesforce/customPermission/<name>` and gates its own rendering with a strict `=== true` check. Even if the FlexiPage visibility rule is misconfigured or bypassed (a different page includes the component without the same filter), the component self-gates.
3. **Apex Class Access on the permission set** — the `@AuraEnabled` controller class is only invokable by permission sets that grant it Apex Class Access. Even if both UI-layer checks are bypassed — a crafted request calling the Apex method directly — the platform rejects the call before any code runs.

**Why layer it.** Each layer protects against a different failure: a misconfigured page, a component reused somewhere its guard doesn't apply, or a client-side bypass entirely. No single layer is sufficient on its own — FlexiPage visibility is cosmetic (it hides, it doesn't secure), the LWC check is client-side (trivially bypassed by anyone driving the API directly), and Apex Class Access is the only layer that's actually enforced server-side. Ship all three on every feature-gated component; treat any single missing layer as an incomplete implementation, not an acceptable partial.

```js
// featurePanel.js
import hasFeatureAccess from '@salesforce/customPermission/Feature_Access';

get isVisible() {
    return hasFeatureAccess === true; // strict equality — jest-mocked undefined must not pass
}
```

```xml
<!-- Additional_Permissions_Feature_View.permissionset-meta.xml -->
<classAccesses>
    <apexClass>FeatureController</apexClass>
    <enabled>true</enabled>
</classAccesses>
```

---

**Summary of the layering principle:** `with sharing` controls record visibility. `WITH USER_MODE` / `AccessLevel.USER_MODE` controls field and object access at the query/DML site. `isAccessible()` guards protect *other* personas' transactions from a feature's FLS footprint. OWD `Private` puts per-user boundaries in the platform instead of application code. The three-layer UI gate assumes every individual layer can fail and builds redundancy in anyway. None of these substitute for each other — a complete feature uses all of them together.
