# Integration Architecture

This file governs how an org chooses its integration mechanisms — platform events, Change Data Capture, REST callouts, External Services — and how outbound callouts and event publishing are hardened once the choice is made. It is the outbound and architecture-choice companion to [REST & Inbound Integration](./integration-rest.md), which owns `@RestResource` endpoints and the managed-package perimeter. Read this before wiring any new connection between the org and an external system, and before reviewing a design that adds one.

## 1. Choose the mechanism by interaction shape, not familiarity

### 1.1 Match the mechanism to the conversation the two systems are having

**Rule.** Pick the integration mechanism from the shape of the interaction — who initiates, who consumes, and what happens when a consumer is down — never from what the team built last time.

| Shape | Mechanism | What you're buying |
| --- | --- | --- |
| Fire-and-forget business signal, one or more independent consumers | Platform event | Durable, replayable pub/sub; the sender doesn't know or block on receivers |
| Broadcast record-data changes with a standard payload | Change Data Capture | Platform-authored change payloads (field deltas, change headers) with no publish code to write |
| Genuine request/response — the caller needs the answer to continue | Synchronous REST callout via [`RestClient.cls`](../../utilities/rest/RestClient.cls) | An immediate answer, paid for in blocking, timeout handling, and retry design (§3) |
| The target API has (or can be given) an OpenAPI spec | External Services registration | Generated invocable actions and typed Apex from the spec — no hand-rolled HTTP parsing to write or unit-test |

**Why.** Each mechanism buys a different failure mode — replay vs. simplicity vs. blocking. A consumer being down is a non-event for a platform-event subscriber (it resumes from where it left off), a data-loss incident for a fire-and-forget callout, and a user-facing error for a blocking one. Choosing by shape makes the failure mode a decision instead of a production discovery.

Two boundary calls that come up repeatedly:

- **CDC vs. platform event.** CDC answers "this record changed, here is what changed" — use it when the downstream system mirrors record state, because the payload and change semantics come free. Define a platform event when the meaningful unit is a business event you name ("order shipped"), which rarely maps 1:1 to field writes.
- **Flow HTTP Callout vs. Apex.** Flow HTTP Callout actions are acceptable for simple, admin-owned, un-spec'd endpoints. The moment the interaction needs retry logic, response mapping, or error triage, it graduates to an External Service (if a spec exists or is cheap to write) or an Apex service extending `RestClient`.

### 1.2 Outbound messages are legacy — never use them in new designs

**Rule.** Do not use workflow outbound messages in any new design; plan a migration wherever an audit finds one.

**Why.** They are SOAP-only, point-to-point, and cannot replay missed deliveries — each of those gaps is something platform events were built to close. Outbound messages also ship today as a Flow core action, not only as a workflow-rule artifact, so "the workflow engine is retired" isn't the argument against them; the transport-level limitations are, on their own, reason enough.

## 2. Every callout goes through a named credential

**Rule.** Every callout resolves its endpoint and authentication through a named credential (external credential + principal). A hardcoded endpoint or secret — in Apex, in a custom setting, in custom metadata — is a build-breaking violation. No exceptions, including "it's just the sandbox URL."

**Why.** Named credentials externalize both the endpoint and the auth handshake from code: secrets never enter version control, rotation is an org-config change instead of a deployment, and per-environment endpoints stop being merge hazards. Every other storage location — a token in a custom setting, a URL constant added "temporarily" — eventually leaks into a repo, a debug log, or a metadata retrieve.

[`RestClient.cls`](../../utilities/rest/RestClient.cls) enforces this by construction: it takes a named credential name and builds every endpoint as `callout:` + that name. There is no constructor path that accepts a raw URL — extend it rather than hand-rolling `HttpRequest` plumbing.

```apex
public with sharing class BillingApiService extends RestClient {
    public BillingApiService() {
        super('Billing_API'); // named credential — endpoint + auth live in org config
    }

    public HttpResponse fetchInvoice(String invoiceNumber) {
        return this.get('/invoices/' + invoiceNumber);
    }
}
```

## 3. Callout resilience

### 3.1 Set an explicit timeout on every callout

**Rule.** Every callout sets an explicit timeout sized to the caller's latency budget — never the platform default. Synchronous contexts holding a user or a trigger get low single-digit seconds; only a detached async job can justify anything near the ceiling.

**Why.** The default 10 seconds (maximum 120) is arbitrary relative to your transaction, and the cumulative 120-second callout budget per transaction is a shared resource: one slow upstream riding the default can consume the time three other callouts in the same transaction needed.

[`RestClient.cls`](../../utilities/rest/RestClient.cls) sets a 120-second default and exposes `withTimeout` for per-call budgets — override the default in any synchronous context.

### 3.2 Retry only recoverable failures, with backoff and jitter — off the synchronous path

**Rule.** Retry timeouts, HTTP 429, and 5xx responses; never retry other 4xx. Use exponential backoff plus jitter, cap the attempt count, and when attempts run out, persist the failed request to a retry queue — a custom object row re-driven by a Queueable or Scheduled job — instead of looping inline.

**Why.** Salesforce never auto-retries HTTP for you; if you don't design the retry, the failure is silent loss. But naive uniform retries synchronize into a thundering herd against an upstream that is already struggling, and retrying a 400 just re-fails faster. The queue converts loss into a visible, re-drivable backlog with its own audit trail — and keeps the retries out of the transaction a user is waiting on.

### 3.3 Design every outbound write to be idempotent

**Rule.** Every outbound write carries an idempotency key — the Salesforce record Id, a UUID stamped on the source record, or the upstream's dedupe header — so that the retry designed in §3.2 is safe to fire.

**Why.** Retry and idempotency are one design, not two. Any retry path can deliver a request twice; the classic case is a timeout that fires after the upstream already processed the write. The key makes the duplicate a no-op instead of a duplicate invoice. [integration-rest.md §2.1](./integration-rest.md) is the same rule facing inbound: external-ID upserts make redelivery to *us* a no-op.

### 3.4 Wrap flaky upstreams in a circuit breaker

**Rule.** For an upstream with a history of outages, track consecutive failures; past a threshold, open the circuit — fail fast without calling out — and probe with a single half-open request after a cooldown, instead of letting every transaction rediscover the outage at full timeout price.

**Why.** Without a breaker, a downstream outage costs every caller a full timeout plus a retry cycle, burning callout budget and user patience to learn the same fact hundreds of times. The breaker converts the outage into one clean, fast-failing signal. A Platform Cache entry or custom object holding the failure count and an open-until timestamp is sufficient — this is a pattern, not a framework purchase.

## 4. Platform-event publish failures are checked, not hoped away

### 4.1 Check the `SaveResult` from every `EventBus.publish` call

**Rule.** `EventBus.publish()` returns `Database.SaveResult` (or a list of them) and does not throw on a failed publish — its behavior mirrors partial-success `Database.insert`. Every publish call checks `isSuccess()` per result and logs failures through [`Logger.cls`](../../utilities/logging/Logger.cls); an unchecked publish result is a review-blocking defect.

**Why.** Publishing can fail per event — while sibling events in the same call succeed — and the method raises nothing. The only evidence is the `SaveResult` nobody read. Note the asymmetry: `isSuccess() == true` means the publish request was *queued*; actual delivery happens asynchronously (§4.3).

```apex
List<Database.SaveResult> results = EventBus.publish(orderEvents);
for (Integer i = 0; i < results.size(); i++) {
    if (!results[i].isSuccess()) {
        for (Database.Error err : results[i].getErrors()) {
            Logger.error(
                'Order event failed to publish: ' + err.getMessage(),
                'OrderEventPublisher',
                'publishShippedEvents'
            );
        }
        // TODO: route the failed event to the §3.2-style retry queue —
        // logging alone records the loss; it doesn't recover it.
    }
}
```

### 4.2 Set publish behavior deliberately: after commit vs. immediately

**Rule.** Choose the publish behavior on every event definition, explicitly. **Publish After Commit** ties the event to the transaction — it rolls back with it and counts as a DML statement. **Publish Immediately** escapes the transaction — it survives rollback and draws on a separate limit of 150 `EventBus.publish()` calls. Use *immediately* only for telemetry that must outlive a rollback (error logging is the canonical case); use *after commit* for anything a downstream system will treat as fact.

**Why.** Publishing "order shipped" immediately from a transaction that then rolls back announces an order that never existed, and no compensating logic downstream will fully unring that bell.

### 4.3 Register a publish callback where losing an event has business cost

**Rule.** For events whose loss costs money or trust, publish with an `EventBus.EventPublishFailureCallback` (and `EventPublishSuccessCallback` where confirmation matters). The callback receives the *final* result of the asynchronous publish — the verdict the immediate `SaveResult` cannot give you.

**Why.** A successful `SaveResult` only proves the event was queued; the asynchronous publish can still fail afterward. The failure callback is the one hook that sees that final outcome, which makes it the right home for the dead-letter write or retry enqueue.

## 5. Each external system gets its own identity

### 5.1 One dedicated integration user per system

**Rule.** Provision one dedicated user per external integration on the Salesforce Integration license with the `Minimum Access - API Only Integrations` profile, and extend access only through permission sets carrying the Salesforce API Integration permission set license. Never run an integration as a System Administrator, and never share one integration user across systems or with a human.

**Why.** Per-integration users deliver least privilege plus per-system traceability: every record's audit trail names which integration touched it, and one system's compromise or misbehavior is contained — and revoked — without taking the others down. The API-only license is inexpensive and cannot log in to the UI, which removes an entire class of credential-misuse risk. Build the permission sets themselves — feature-scoped atoms, naming, tiers — per [permissions.md](./permissions.md).

### 5.2 One connected app per integration, OAuth client-credentials flow

**Rule.** Authenticate each server-to-server caller with its own connected app using the OAuth client-credentials flow, executing as that integration's dedicated user (§5.1). Do not share a connected app between systems, and do not hand an external system a username/password or a long-lived refresh token.

**Why.** Client credentials removes password and refresh-token custody from the external system entirely, and the per-app split means cutting off one vendor is a single connected-app toggle — not a credential rotation shared by three others.

## 6. Any sync touching regulated data ships a field-mapping inventory

**Rule.** Every managed-package connector or outbound sync that carries regulated data (PHI/PII) ships the field-mapping inventory defined in [integration-rest.md §4](./integration-rest.md): one row per source-field-to-target-field mapping, committed to the repo, reviewed on a fixed cadence. This applies with equal force to the mechanisms in this file — a platform event's payload shape, a CDC channel's entity selection, and a callout DTO are all field mappings, whether or not a mapping UI was involved.

**Why.** The mapping — not the transport — is what actually determines what leaves the org. The inventory shape, ownership, and review cadence are specified once in integration-rest.md; reference it rather than forking a second format here.

## Sources

- https://architect.salesforce.com/decision-guides/event-driven
- https://www.salesforceben.com/integration-using-change-data-capture-and-platform-events/
- https://salesforcecodex.com/salesforce/salesforce-outbound-message-vs-platform-event-a-complete-architects-guide/
- https://architect.salesforce.com/docs/architect/well-architected/guide/secure.html
- https://sfdcprep.com/salesforce-apex-callouts-named-credentials-oauth-continuation-retry/
- https://medium.com/@hgupta5746/10-core-strategies-for-safe-rest-api-callouts-in-apex-3e9f2636141e
- https://www.c-sharpcorner.com/article/retry-backoff-and-circuit-breaker-patterns-for-salesforce-api-integrations/
- https://developer.salesforce.com/docs/atlas.en-us.apexref.meta/apexref/apex_class_System_eventbus.htm (EventBus.publish return/limits/behavior, verified via the doc mirror at https://github.com/damecek/salesforce-documentation-context)
- https://developer.salesforce.com/docs/atlas.en-us.platform_events.meta/platform_events/platform_events_publish_callbacks.htm
- https://gearset.com/blog/what-are-salesforce-integration-user-licenses/
- https://admin.salesforce.com/blog/2023/best-practices-for-configuring-your-integration-user
- https://help.salesforce.com/s/articleView?id=release-notes.rn_api_new_user_profile.htm&release=248
- https://developer.salesforce.com/blogs/2024/02/invoke-rest-apis-with-the-salesforce-integration-user-and-oauth-client-credentials
- https://developer.salesforce.com/blogs/2025/05/call-third-party-apis-from-an-agent-with-external-service-actions
- https://admin.salesforce.com/blog/2023/integrations-are-easier-than-ever-with-flow-http-callouts
