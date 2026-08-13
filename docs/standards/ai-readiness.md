# AI Readiness — Data & Metadata Standards for Agent Consumption

This file governs the org-level standards that make Salesforce data and metadata consumable by AI agents (Agentforce), Einstein features, and Data Cloud without a human translating in between: descriptions as machine-readable semantics, enumerated vocabularies, stable keys, explicit business timestamps, read models for retrieval, permission-set provisioning for agent users, and describable entry points. Read it before enabling any agent surface against an org, and before designing schema or automation in an org that will host one. The through-line: AI readiness is overwhelmingly data and metadata hygiene, not model configuration — and every rule here pays for itself in reporting, maintenance, and onboarding even if no agent ever ships.

## 1. Treat metadata as the agent's ground truth

**Rule.** Before enabling any agent against an object, audit that object's labels, API names, descriptions, and help text for accuracy. A field whose label, description, and actual usage disagree is a defect and must be fixed before rollout, not after.

**Why.** Agents reason over metadata, not just rows. A human user routes around a mislabeled field by asking a colleague; an agent reads `Discount__c` described as "percentage discount" that actually stores a currency amount and produces a confidently wrong answer, at scale, with no colleague in the loop. The audit is cheap; the hallucinated invoice explanation is not.

## 2. Describe every object and field as machine-readable semantics

**Rule.** Every custom object and field carries a Description written at creation time, stating what the value *means* — not restating the label. Say who or what writes it, what unit or timezone it carries, and what an empty value signifies. Add Help Text wherever usage isn't self-evident from the label.

**Why.** Descriptions are the org's only inline schema documentation, and they are consumed verbatim: by the next admin, by metadata-scanning tools, and by agents as reasoning input. An undescribed field is an undeletable mystery to a human and an invitation to invent semantics for an LLM.

```text
Bad:  Renewal_Date__c — "The renewal date."
Good: Renewal_Date__c — "Date the current contract term ends. Set by the
      renewal batch job nightly; blank means the account has no active
      contract. Date only, org timezone."
```

Schema-design rules for the fields themselves live in [data-model.md](./data-model.md); this section governs the words attached to them.

## 3. Enumerate categorical values — restricted picklists, never free text

**Rule.** Every categorical field is a restricted picklist with a standardized value set. Free-text fields carrying category-shaped data ("status", "type", "tier", "region") are a build-breaking review finding on any object an agent will read.

**Why.** An enumerated value set is a vocabulary an agent can ground on: `Active`, `Lapsed`, `Churned` are answers. Free text is noise the model will hallucinate structure into — `"active"`, `"ACTIVE - renewed"`, and `"still a customer I think"` are three strings, zero categories. The same enumeration is also what reports, validation rules, and flow entry conditions consume, so the rule costs nothing extra.

Apex that consumes categorical values reads the enumeration from describe rather than hardcoding it — see [`UtilPickLists.cls`](../../utilities/picklists/UtilPickLists.cls) for the shipped helpers.

## 4. Put a stable external key on every object that feeds grounding

**Rule.** Every object that feeds Data Cloud, agent grounding, or any cross-system retrieval carries a unique External ID field holding the source system's stable key. Restrict its editability to the integration principal via FLS. Do not repurpose record IDs, names, or email addresses as cross-system identity.

**Why.** Identity resolution and retrieval both join on keys. Unstable or duplicated identifiers fragment one customer into several partial records — and the agent answers about the wrong one, which reads to the user as the model being wrong rather than the data. A locked external ID also makes integration upserts idempotent, so the same field serves both masters. Budget note: the platform allows 25 external-ID/unique fields per object, so spend them deliberately.

## 5. Timestamp business events explicitly; leave audit fields to the platform

**Rule.** When *when something happened* matters to the business — a status change, an approval, a customer touch — model an explicit `Datetime` field written at the moment of the event. Never use `CreatedDate` or `LastModifiedDate` as a proxy for business timing.

**Why.** The system audit fields (`CreatedDate`, `CreatedById`, `LastModifiedDate`, `LastModifiedById`, `SystemModstamp`) record row mechanics, not business events: `LastModifiedDate` moves on every data fix, backfill, and automation touch, so as a business signal it lies. It gets worse after a migration — audit fields can be set at insert under the *Set Audit Fields upon Record Creation* permission, and `SystemModstamp` never can, so no combination of them reliably reconstructs business timing. An agent asked "when did this order ship?" needs `Shipped_At__c`, whose semantics survive both automation and migration.

```apex
// In the before-update path, stamp the event when the transition happens —
// not derived later from audit fields.
if (order.Status__c == 'Shipped' && oldOrder.Status__c != 'Shipped') {
    order.Shipped_At__c = System.now();
}
```

## 6. Pre-compute the answer shape for retrieval-heavy surfaces

**Rule.** For the questions an agent (or report, or dashboard) will be asked repeatedly, provide a denormalized read model — a rollup/reporting object or a Data Cloud calculated view — rather than forcing multi-hop relationship traversal at answer time.

**Why.** Retrieval quality degrades with join depth: a question that needs Account → Contract → Order → Line resolution at answer time gives the retrieval layer four chances to pick the wrong hop. A flat, query-cheap read shape gives agents, reports, and humans one consistent answer surface. This is a recommended practice synthesized from AI-readiness field experience, not platform doctrine — weigh the freshness pipeline it requires against the traversal it removes, and see [data-model.md](./data-model.md) for when denormalization is justified in general.

## 7. Subtract before you enable — archive stale data, retire dead automation

**Rule.** Before agent rollout on an object: archive or close out stale records (per the retention rules in [data-retention-erasure.md](./data-retention-erasure.md)) and deactivate automation that no longer runs for a reason anyone can name.

**Why.** A retrieval system cannot tell ten years of abandoned open cases from live signal — it will cite them. Orphaned flows are worse: they still *fire*, so the agent inherits behavior nobody remembers designing. Readiness is as much subtraction as addition; the enable-the-agent ticket is the forcing function to finally do the cleanup.

## 8. Permission-set-first access is an agent prerequisite

**Rule.** Complete the profile-to-permission-set migration for any org that will host agents. Agent users are provisioned through permission sets; scope each agent's access with the same feature-scoped permset atoms used for humans, at the same least-privilege bar.

**Why.** Salesforce's own admin guidance frames the profile→permset migration as Agentforce preparation: profile-locked orgs cannot scope a non-human principal's access cleanly, and an agent is the last user that should inherit a kitchen-sink profile. An agent with admin-shaped access doesn't just leak data — it *acts* on it. The full permission architecture (atoms, groups, naming ladder) lives in [permissions.md](./permissions.md).

## 9. Name and describe every entry point an agent can target

**Rule.** Every flow or invocable Apex method exposed (or exposable) as an agent action carries a deliberate label and description — on the action itself and on every input and output. Descriptions state when the action applies and what each parameter means, in the same semantic register as §2. Flow naming and type-code conventions are governed by [naming.md](./naming.md); the Description field on every flow and flow element is mandatory.

**Why.** The action and parameter descriptions are the reasoning input the agent's planner uses to decide *whether* to invoke an action and *how* to fill its inputs — Salesforce's own guidance on agent actions is explicit that these descriptions drive the agent's understanding of the operation. An undescribed input is a parameter the model guesses at.

```apex
@InvocableMethod(
    label='Look Up Open Invoices'
    description='Returns unpaid invoices for one account. Use when the user asks about outstanding balances or unpaid invoices.')
public static List<InvoiceResult> lookUpOpenInvoices(List<InvoiceRequest> requests) { ... }

public class InvoiceRequest {
    @InvocableVariable(
        required=true
        description='Record ID of the Account whose unpaid invoices to return.')
    public Id accountId;
}
```

## 10. Keep agent-invocable automation change-governed

**Rule.** Any flow or Apex an agent can invoke changes only through the tracked pipeline — reviewed, versioned, and owned. Ad-hoc in-org edits to agent-reachable automation are a build-breaking violation.

**Why.** Agents inherit whatever the org's automation does. A flow that three teams edit ad hoc produces agent behavior that cannot be reproduced, tested, or explained to the user it just confused. Lineage visibility and governed change are readiness criteria, not process garnish.

## Sources

- <https://www.sweep.io/blog/the-agentforce-metadata-readiness-checklist>
- <https://www.sweep.io/blog/the-ultimate-guide-to-ai-readiness-in-salesforce-from-metadata-to-agents>
- <https://technologyblog.rsmus.com/uncategorized/the-hidden-power-of-metadata-how-clean-data-structure-supercharges-your-salesforce-agentforce/>
- <https://admin.salesforce.com/blog/2025/get-agentforce-ready-move-from-profiles-to-permission-sets-how-i-solved-it>
- <https://www.dataarchiva.com/how-to-build-ai-ready-salesforce-data-infrastructure/>
- <https://www.clearconciseconsulting.com/blog/salesforce-ai-data-readiness-checklist>
- <https://www.getgenerative.ai/salesforce-data-model-design-best-practices/>
- <https://cloud4good.com/announcements/best-practices-salesforce-fields/>
- <https://s2-labs.com/admin-tutorials/external-id-record-id-security-token/>
- <https://developer.salesforce.com/docs/atlas.en-us.object_reference.meta/object_reference/system_fields.htm>
- <https://developer.salesforce.com/blogs/2025/05/call-third-party-apis-from-an-agent-with-external-service-actions>
