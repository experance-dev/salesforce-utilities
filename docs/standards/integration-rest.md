# REST & Inbound Integration

This file governs Apex `@RestResource` endpoints that receive data from external systems, and the perimeter controls needed when a managed-package connector — not code you own — decides what leaves the org. Read this before building or reviewing an inbound webhook receiver, before granting an integration user access to a REST class, or before wiring a new managed-package sync (ticketing, HRIS, chat-ops, or similar) that pulls Salesforce field values on its own schedule.

## 1. Inbound REST endpoints declare `with sharing` and document the caller identity

**Rule.** `@RestResource` classes declare `global with sharing`. The session belongs to whichever user authenticated the inbound call — typically a dedicated integration user, never an interactive human session — and `with sharing` scopes that user's *record* visibility: which rows the endpoint can see. It does nothing for CRUD/FLS — that's enforced separately, at each SOQL/DML site the endpoint touches, via `WITH USER_MODE` (queries) and the `DMLManager` `xxxAsUser` wrapper (writes). Document the assumed caller identity in the class header, and grant Apex Class Access to the endpoint through that integration user's own permission set, not through a profile.

**Why.** A REST endpoint is a network-reachable entry point with no UI in front of it to hide a permission gap. If the endpoint runs `without sharing` "to keep things simple," any caller who can forge or replay a valid session token inherits system-level access. Keeping the endpoint on `with sharing` and a narrowly-scoped integration user means a compromised or misconfigured caller is contained to exactly what that one user can see — nothing else in the org.

```apex
/**
 * @description Inbound REST endpoint for order-event ingestion from the
 *              order-sync integration user. Runs `with sharing` — the
 *              integration user's permission set is the actual access
 *              boundary for every record this endpoint touches.
 * @group REST
 * @author Jane Developer
 * @since August 2026
 */
@RestResource(urlMapping='/orders/v1/*')
global with sharing class OrderInboundRest {
    @HttpPost
    global static void upsertOrders() {
        // ...
    }
}
```

Grant Apex Class Access to `OrderInboundRest` on the integration user's permission set only — not on any human-assigned permission set group, and not via profile. If the integration user's credentials leak, the blast radius is bounded by what that one permission set exposes.

## 2. Batched inbound events: idempotent upsert, then tell the truth about what happened

### 2.1 Upsert on an external ID, so redelivery is a no-op

**Rule.** REST endpoints that accept batched events upsert on an `External_Id__c`-style field supplied by the sender, never on a Salesforce-generated `Id`. The sender's own event ID is the identity the upstream system understands, and it's the only key that makes redelivery safe.

**Why.** Webhook and event-stream providers retry on ambiguous outcomes — timeout, 5xx, a dropped connection after they sent the request but before they saw the response. If the endpoint can't tell "this event already landed" from "this is new," a redelivered event either duplicates the record or throws on a duplicate-detection rule, and either way the retry that was supposed to make the integration reliable makes it worse. Upserting on the sender's external ID makes redelivery idempotent by construction: the second delivery of the same event updates the same row instead of creating a second one.

```apex
List<Order__c> orders = new List<Order__c>();
for (OrderEventDto evt : payload.events) {
    orders.add(new Order__c(
        External_Id__c = evt.eventId,
        Status__c = evt.status
    ));
}
```

### 2.2 HTTP 200 means "batch accepted" — report per-record failures in the response body, not the status code

**Rule.** When some records in a batch fail validation but the batch as a whole was processed, return HTTP 200 with a per-record `errors[]` array in the response body identifying which events failed and why. A 200 status means "we received and attempted this batch"; it does not mean "every record in it succeeded."

**Why.** Collapsing "3 of 200 events failed validation" into an HTTP error code forces the sender into an all-or-nothing choice: either it retries the whole batch (re-processing 197 events that already succeeded) or it silently drops the 3 that failed. A structured `errors[]` array lets the sender retry exactly the failed events, or route them to its own dead-letter handling, without touching what already worked.

```apex
List<Object> errors = new List<Object>();
for (Order__c ord : orders) {
    if (String.isBlank(ord.External_Id__c)) {
        errors.add(new Map<String, Object>{
            'record' => ord,
            'reason' => 'Missing External_Id__c'
        });
    }
}
// ... upsert the valid records, then return 200 with `errors` populated
// for whatever didn't make it in.
```

Build the batch's valid records with [`TestFactory.cls`](../../utilities/testing/TestFactory.cls) in the corresponding test — assert both the happy-path upsert and that a deliberately malformed record shows up in `errors[]` instead of aborting the batch.

## 3. Catastrophic upsert failure returns 5xx — 200 is reserved for partial validation failure

**Rule.** When the upsert operation itself throws — a `DmlException` from a validation rule misfire, a governor limit, a locked row — the catch block sets `RestContext.response.statusCode = 500` (or the more specific 4xx/5xx the failure warrants) so the caller's own retry logic kicks in. Returning HTTP 200 with a populated `errors[]` array is correct *only* for §2.2's case — some records rejected, most processed. It is never correct for "the whole batch failed to write."

**Why.** Webhook and event-stream providers treat any 2xx response as an acknowledgment and stop retrying. If a total upsert failure is reported as 200 — even with an apologetic `errors[]` body — the sender has no way to know the data never landed, and nothing retries it. The distinction in this file matters precisely because both failure modes can produce a response body that looks similar; the status code is what tells the caller whether to move on or try again.

```apex
List<Database.UpsertResult> results;
try {
    // DMLManager.upsertAsUser does not currently expose an external-ID-keyed,
    // partial-tolerant upsert — its wrapped path is Id-based and all-or-none.
    // TODO: extend the DML manager with an upsertAsUser(records, externalIdField,
    // allOrNone) overload; until then this is a documented, sanctioned direct
    // Database call rather than a routed one.
    results = Database.upsert(orders, Order__c.External_Id__c, false, AccessLevel.USER_MODE);
} catch (DmlException e) {
    Logger.logException(e, 'OrderInboundRest', 'upsertOrders');
    RestContext.response.statusCode = 500;
    RestContext.response.responseBody = Blob.valueOf(
        '{"error":"Batch upsert failed entirely; retry the full batch."}'
    );
    return;
}
```

See [`Logger.cls`](../../utilities/logging/Logger.cls) for the exception-logging call used above, and [`DMLManager.cls`](../../utilities/dml/DMLManager.cls) for the routed insert/update/upsert/delete surface this endpoint should use for every write that *isn't* the external-ID partial-upsert gap called out above. For the outbound half of an integration — calls this org makes to an external system rather than receives — see [`RestClient.cls`](../../utilities/rest/RestClient.cls).

## 4. A managed-package connector's field mapping is a regulated-data perimeter control

**Rule.** When a managed-package connector configured *outside* your Apex — a ticketing sync, an HRIS connector, a chat-ops bridge, or similar — pulls Salesforce field values into an external system through its own field-mapping configuration, that mapping is a load-bearing perimeter control. Treat it with the same rigor as a trigger filter or a Platform Event payload shape you author directly: every such integration ships a field-mapping inventory, committed to the repo, reviewed on a fixed cadence (quarterly minimum, or immediately on any mapping change).

**Why.** It's common to design the Apex-owned half of an integration carefully — a Platform Event that carries only `Id`, `Change_Type__c`, and a timestamp, deliberately excluding field content — and consider the perimeter handled. But if a managed package then pulls the actual field values server-side through its own mapping UI, that mapping is the thing that actually determines what leaves the org, and it isn't reviewed by the same code-review process your Apex goes through. A mapping that gets quietly widened — someone adds an Account healthcare-context field or a Contact's personal details to "make the ticket more useful" — leaks regulated data on every synced record, and nothing in your code review catches it, because the leak never happens in your code. The inventory makes an otherwise invisible boundary explicit and auditable.

**Inventory shape (minimum one row per source-field-to-target-field mapping):**

| Column | Purpose |
| --- | --- |
| Source SObject + field (API name) | What's being read out of Salesforce |
| Target system + field | Where it lands |
| Direction | Outbound / inbound / bidirectional |
| Sensitivity classification | `none` / `low` / `medium` / `high` / `regulated (PHI/PII)` |
| Last reviewed | Date + reviewer |

```
Order__c.Account__r.Health_Plan_Type__c → Ticketing.CustomField_1042
  Direction: outbound
  Sensitivity: regulated (PHI/PII)
  Last reviewed: 2026-08-01, data architect
```

**Ownership.** Assign inventory authorship to whoever owns data architecture for the org, with an out-of-team reviewer signing off at the fixed cadence — the same separation of duties you'd want on any other perimeter control. Any mapping change that adds a `medium` classification or higher triggers an off-cycle review rather than waiting for the quarterly pass.
