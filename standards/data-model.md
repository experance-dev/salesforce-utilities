# Data Model & Schema Design

This file governs SObject and field design: picklist discipline, relationship typing, external IDs, metadata descriptions, record-type restraint, audit and lifecycle fields, compound-field handling, field-history policy, data-volume planning, and formula-field depth. The through-line is a single test — can the schema be read cold by a new admin in Setup, a new developer in SOQL, *and* a machine consuming the metadata as ground truth? A field that fails any one of the three readers is a defect. Read this before creating any custom object or field.

## 1. Every enumerable value is a restricted picklist, never free text

**Rule.** Any field whose values come from a finite, nameable set — statuses, categories, tiers, reasons — is a restricted picklist with standardized values. Free text for categorical data is a build-breaking defect, not a style choice.

**Why.** Free-text categories are unreportable, unvalidatable, and unreadable to machine consumers. The enumerated value set is the contract that reports, validation rules, flow entry conditions, and AI agents all consume; `"Active"`, `"active"`, and `"ACTIVE "` in a text field are three different values to every one of them.

**Shared enumerations live in a Global Value Set.** When two or more fields — on the same object or across objects — carry the same enumeration, define it once as a Global Value Set and reference it from each field. One source of truth: update the set, every referencing field inherits the change. A global value set holds up to 1,000 values including inactive ones.

```xml
<!-- Order_Status__c and Invoice_Status__c both reference the same enumeration -->
<type>Picklist</type>
<valueSet>
    <valueSetName>Document_Status</valueSetName>
</valueSet>
```

## 2. References to other records are lookups, never text-typed foreign keys

**Rule.** A field that identifies another record is a lookup (or master-detail where the child's lifecycle genuinely depends on the parent). Never store a record's Name — or its Id — in a text field as a homemade foreign key.

**Why.** Text references rot on rename, enforce no referential integrity, and hide the relationship from everything that could otherwise use it: SOQL relationship traversal, report joins, sharing calculations, and cascade behavior all key off real relationship fields. A text-typed foreign key is a join the platform can never see.

## 3. Every integration-touched object carries a unique external ID

**Rule.** Every object that any integration reads or writes gets a unique, external-ID-flagged field carrying the source system's key. Restrict its editability to the integration user via FLS — humans never edit the join key.

**Why.** An external ID makes upsert idempotent and de-duplicating: the integration can replay a payload without creating doubles or needing to query for the Salesforce Id first. FLS-locking the field to the integration principal keeps a well-meaning user from corrupting the key that two systems join on. Spend the budget deliberately — the platform allows 25 external-ID/unique fields per object.

```xml
<fullName>Source_System_Key__c</fullName>
<type>Text</type>
<length>64</length>
<externalId>true</externalId>
<unique>true</unique>
<description>Primary key of this invoice in the billing system of record.
    Written only by the integration user (FLS-restricted); humans never edit it.</description>
```

External-ID upsert from Apex has no manager-wrapped overload — use `Database.upsert(records, Invoice__c.Source_System_Key__c, false, AccessLevel.USER_MODE)` directly, documented inline, per the carve-out noted in [`DMLManager.cls`](../utilities/dml/DMLManager.cls) and [security-sharing.md](security-sharing.md) §3.

## 4. Description is mandatory on every custom object and every custom field

**Rule.** No custom object or field ships without its Description populated at creation time. Add Help Text wherever the field's use isn't self-evident from its label. "I'll document it later" is a review-blocking finding.

**Why.** The metadata *is* the documentation — the Description is the only schema documentation that lives where the schema lives, and it is read by all three audiences this file exists for: the next admin deciding whether a field is safe to delete, the next developer deciding whether to reuse or duplicate it, and every metadata-scanning tool or AI agent that consumes descriptions verbatim as reasoning input. An undescribed field becomes an undeletable mystery within one team rotation — nobody remembers why it exists, so nobody dares remove it.

A description answers three questions the API name can't: what populates this field, who consumes it, and what happens if it's blank. The `Source_System_Key__c` example in §3 is the shape to copy.

## 5. Record types only for genuinely divergent processes — never as a picklist substitute

**Rule.** Create a record type only when the same object genuinely carries divergent business processes: different picklist value sets, different sales/case processes, different persona defaults. Never create one for layout variation alone — Dynamic Forms covers conditional UI without a record type. When a picklist value on the record can carry the distinction, use the picklist.

**Why.** Every record type multiplies maintenance across page layouts, permission sets, and automation branching — each new one is a standing tax on every future change to the object. "Record type as glorified layout switch" is the most common proliferation pattern, and a picklist-driven state branches flows and validation rules at a fraction of the admin surface. A record type answers "which *process* is this record in?"; a picklist answers "which *state* is this record in?" — conflating the two costs you the difference in maintenance forever.

**Audit and prune.** Record types that no longer earn their cost don't get grandfathered; retire them.

## 6. Use the platform's audit fields — and standardize lifecycle stamps

**Rule.** Never recreate what the platform already maintains: `CreatedDate`, `CreatedById`, `LastModifiedDate`, `LastModifiedById`, and `SystemModstamp` are read-only system fields on every record. When the business lifecycle needs its own timestamps — submitted, activated, closed — pair each with the status picklist that drives it, stamp it by automation at the moment of transition, and name the pair consistently (`Submitted_On__c` + `Submitted_By__c`), never as a hand-entered field.

**Why.** System audit fields are free, trustworthy, and maintained by the platform regardless of which code path wrote the record. Custom duplicates of them drift the first time an automation path forgets to stamp. Two nuances worth knowing cold:

- `SystemModstamp` differs from `LastModifiedDate`: it also advances when an automated process modifies the record, which is why replication and sync tools key off it.
- Data migrations can set audit fields at insert via the "Set Audit Fields upon Record Creation" permission — except `SystemModstamp`, which is always platform-managed. Plan migrations around that; don't add shadow date fields to compensate.

Lifecycle stamps set by automation are the queryable, reportable record of *when the state changed* — the thing field history (§7) only partially covers and the status picklist alone can't tell you.

## 7. Write a field-history-tracking policy per object — history is neither complete nor permanent

**Rule.** Decide per object, at design time, which fields are tracked and whether standard tracking suffices. Standard field history tracks up to 20 fields per object with 18–24 months of retention. Objects under a regulatory or audit obligation need Field Audit Trail: up to 200 tracked fields per object, retention you define via `HistoryRetentionPolicy`, with archived history stored in the `FieldHistoryArchive` big object.

**Why.** Teams routinely assume field history is complete and permanent; it is neither, and discovering that during an audit is the expensive way. Salesforce archives standard history data after 18 months in production by default — if the retention question hasn't been answered on purpose, it has been answered by default, and the default is not what your auditor assumed.

## 8. Never build logic against compound fields — always the components

**Rule.** Read, write, and filter the component fields of every compound field (`Address` → `Street`/`City`/`State`/`PostalCode`/`Country`, `Name` → `FirstName`/`LastName`, `Geolocation` → latitude/longitude). Never bind logic to the compound itself.

**Why.** Compound fields carry a set of documented sharp edges that only surface at runtime:

- Compound address fields are not filterable in SOQL `WHERE` clauses — and `DescribeFieldResult.isFilterable()` erroneously reports `true` for them, so a describe-driven query builder will happily generate a query that fails.
- Bulk API won't export custom compound fields.
- Search indexes only the Street component of custom Address fields.

```apex
// Wrong: BillingAddress is a compound — not filterable, despite isFilterable() = true.
// Right: filter the component.
List<Account> accounts = [
    SELECT Id, BillingStreet, BillingCity
    FROM Account
    WHERE BillingCity = :city
    WITH USER_MODE
];
```

## 9. Decide the archive strategy for every high-volume object at design time

**Rule.** Any object projected to accumulate high volume — logs, touches, events, line items — gets an explicit retention rule and an archive destination (big object, Data Cloud, or off-platform) written down when the object is designed, not when it hurts.

**Why.** Large data volumes degrade query, report, and sharing performance long before storage limits bite, and retrofitting archival onto an object that already holds tens of millions of rows is a project, not a task. The retention rule belongs in configuration, not in a comment: [`LogCleanupBatch.cls`](../utilities/logging/LogCleanUp/LogCleanupBatch.cls) is the shipped pattern — a batch whose age thresholds live in custom metadata (`Log_Clean_Up__mdt`), so the retention policy is declarative, per-object, and changeable without a deploy.

"High-volume" is a design-time judgment: estimate rows/year at creation. An object growing by millions of rows a year without a retention answer is a §-violation even while it's still small.

## 10. No formula-field chains — compile size and query cost both break

**Rule.** A formula field must not reference other formula fields as a habit, and never in chains (formula → formula → formula). When a computed value needs to be filtered on, reported at scale, or referenced by other formulas, stamp it into a regular field with automation and reference the stamped field.

**Why.** Two independent failure modes, both invisible until they fire:

- **Compile size.** A formula's compiled size is capped at 5,000 bytes, and referencing another formula field adds *that field's entire compiled size* to yours — on every reference. Chains therefore grow multiplicatively, and the "compiled formula is too big to execute" error fires when someone edits a formula three links upstream of the one that breaks.
- **Query cost.** Formula fields are not indexed by default; filtering on one in SOQL forces a full table scan unless it has been. Only *deterministic* formulas are even index-eligible, and getting one indexed still means filing a Salesforce Support request — it is not a Setup checkbox available at design time. On a §9-scale object, that gap between "not indexed" and "not self-service indexable" is the difference between a selective query and a timeout, discovered the expensive way if nobody planned for it.

A stamped field contains the resulting value, not the formula — it costs one automation to maintain and is indexed, filterable, and inert to upstream formula edits. That trade is almost always correct past the first level of nesting.

---

**Summary of the readable-cold principle:** picklists and global value sets make values enumerable to machines and reports (§1). Lookups make relationships visible to the platform (§2). External IDs make integration joins idempotent (§3). Descriptions make intent survive team rotation (§4). Record-type restraint (§5) and platform audit fields (§6) keep the maintenance surface honest. History policy (§7), component-field discipline (§8), design-time archival (§9), and formula restraint (§10) are all the same bet placed four ways: the schema decisions that are cheap at creation time are ruinous to retrofit. Make them on purpose, at creation, in the metadata — where all three readers can see them.

## Sources

Official documentation (verified during authoring):

- <https://developer.salesforce.com/docs/atlas.en-us.api_meta.meta/api_meta/meta_globalvalueset.htm> — Global Value Set metadata (shared value sets, 1,000-value cap)
- <https://developer.salesforce.com/docs/atlas.en-us.object_reference.meta/object_reference/system_fields.htm> — system audit fields, SystemModstamp behavior, Set Audit Fields upon Record Creation
- <https://developer.salesforce.com/docs/atlas.en-us.object_reference.meta/object_reference/compound_fields_limitations.htm> — compound-field limitations (filterability)
- <https://developer.salesforce.com/docs/atlas.en-us.caf_dev_guide.meta/caf_dev_guide/caf_dev_limitations.htm> — Custom Address Fields requirements and limitations (Bulk API export, street-only search indexing — §8's claims live here, not on the general compound-fields page)
- <https://developer.salesforce.com/docs/atlas.en-us.field_history_retention.meta/field_history_retention/field_history_retention_intro.htm> — standard tracking (20 fields, 18–24 months) vs. Field Audit Trail (200 fields, `HistoryRetentionPolicy`, `FieldHistoryArchive`)
- <https://developer.salesforce.com/docs/atlas.en-us.salesforce_formula_size_tipsheet.meta/salesforce_formula_size_tipsheet/reducing_formula_compile_size.htm> — 5,000-byte compile limit, referenced-formula expansion
- <https://github.com/forcedotcom/sf-skills> — SOQL anti-patterns (formula fields unindexed; filter on base or stamped fields)

Secondary sources (research corroboration):

- <https://www.sweep.io/blog/the-agentforce-metadata-readiness-checklist> and <https://www.getgenerative.ai/salesforce-data-model-design-best-practices/> — picklists over free text; lookups over text references
- <https://s2-labs.com/admin-tutorials/external-id-record-id-security-token/> and <https://www.mytutorialrack.com/external-id-in-salesforce/> — external-ID practice, 25-field budget
- <https://www.salesforceben.com/salesforce-record-type-best-practices-tutorial/>, <https://www.museoperations.com/blog/record-types-vs-picklists-how-to-choose-tips-and-best-practices>, and <https://sfdcprep.com/salesforce-record-types-page-layouts-dynamic-forms-picklist-strategy/> — record-type restraint, picklist-driven state
- <https://nebulaconsulting.co.uk/insights/overcoming-salesforce-field-history-limits-using-data-cloud/> and <https://www.dataarchiva.com/how-to-build-ai-ready-salesforce-data-infrastructure/> — design-time archival for high-volume objects
- <https://cloud4good.com/announcements/best-practices-salesforce-fields/> and <https://technologyblog.rsmus.com/uncategorized/the-hidden-power-of-metadata-how-clean-data-structure-supercharges-your-salesforce-agentforce/> — descriptions as schema documentation, machine consumption
