# Naming

This file governs how things are named: Apex classes, methods, and variables; custom object and field API names; custom metadata types and their records; permission sets and custom permissions; flows and subflows; Lightning web components; and platform events. It closes with how to compile the grammar into the static-analysis gate so naming is machine-enforced rather than doc-only. Read it before creating any new metadata component — an API name is the one decision that outlives every refactor, because renaming a shipped API name breaks every consumer that ever referenced it. One meta-rule up front: the grammar is *per metadata type*. Apex identifiers (classes, methods, variables) ban internal underscores; SObject, field, CMDT, and platform-event API names use underscores as word separators; flow API names use underscores as token separators. Neither is inconsistent — what matters is one grammar per type, applied without exception, so a reviewer can check any name against exactly one rule.

## 1. Apex class names carry their archetype as a suffix

**Rule.** Every Apex class whose role matches a layering archetype ends with that archetype's suffix: `*Service`, `*Selector`, `*TriggerHandler`, `*Batch`, `*Queueable`, `*Scheduler`, `*Controller`, `*Test`. Test classes — classes containing test methods — are named `<ClassUnderTest>Test`, no exceptions. The `*Test` suffix is scoped to test *methods*, not to the `@IsTest` annotation: `@IsTest`-annotated test **infrastructure** — factories, stubs, mocks that ship no test methods, like [`TestFactory.cls`](../../utilities/testing/TestFactory.cls), [`TestDouble.cls`](../../utilities/testing/TestDouble.cls), or [`DMLManagerErrorStub.cls`](../../utilities/dml/DMLManagerErrorStub.cls) — carries a descriptive suffix instead (`*Factory`, `*Stub`, `*Double`, `Mock*`), because a stub wearing `*Test` promises test methods it doesn't have, to readers and to test-discovery tooling alike. A class with no archetype — a shared utility like [`Utilities.cls`](../../utilities/general/Utilities.cls) or [`Logger.cls`](../../utilities/logging/Logger.cls) — carries no suffix rather than a misleading one.

**Why.** The suffix is the architecture, read off the name: a reviewer knows the class's allowed dependencies before opening it, because [architecture-layering.md](./architecture-layering.md) binds each archetype to a dependency contract (selectors never call services; services never inline SOQL). fflib prescribes exactly this for the Service and Selector layers, and it makes the codebase enumerable — `grep -rl "class \w*Selector"` is a complete inventory of every class allowed to own SOQL. The cron-entry archetype is named for what it is on this platform — `*Scheduler`, not `*Schedulable` — matching the shipped [`LogCleanupScheduler.cls`](../../utilities/logging/LogCleanUp/LogCleanupScheduler.cls): `Schedulable` is the interface it implements, not the noun a reviewer is looking for in a file listing.

**Selectors are `<SObject>Selector`, dropping `__c` and any namespace prefix:** `Order__c` → `OrderSelector`. One selector per SObject keeps the query surface one grep away from complete.

**Domain classes, if you introduce them, are `<SObject>Domain` — this library deliberately does not use fflib's plural convention** (`Accounts.cls`, `Orders.cls`). State your choice either way, because half the community expects the plural: fflib uses it to signal that a domain class always operates on a list. Here the domain layer lives in [`TriggerHandler`](../../utilities/triggers/TriggerHandler.cls) subclasses plus services (see [architecture-layering.md](./architecture-layering.md)), and a bare plural like `Orders` reads as a collection variable, not a class, to anyone picking the code up cold.

**Interfaces carry an `I` prefix; their default implementation carries the archetype suffix plus `Impl`.** A service interfaced for dependency injection is `IOrderService`; its concrete implementation is `OrderServiceImpl`, wired once at class-load time and swapped for a test double through a `@TestVisible` setter. This is [architecture-layering.md §2–3](./architecture-layering.md)'s controller/service DI seam, restated here so the two files can't drift apart: any class that follows that pattern — service or otherwise — is named `I<Name>` for the interface and `<Name>Impl` for the implementation, no other prefix or suffix scheme.

## 2. One word per concept; names must read cold

**Rule.** Pick one verb per concept and use it codebase-wide: `get` *or* `fetch` *or* `retrieve` — never a mixture. Methods are camelCase verb phrases. Constants are `SCREAMING_SNAKE_CASE`. Collection names encode their shape: `accountsById` for a `Map<Id, Account>`, `orderIds` for a `Set<Id>`, `resolvedOrders` for a filtered `List<Order__c>`. When a readable name and a short name conflict, the readable name wins: `collectOrderIdsForAccounts` beats `getOrdIds`, every time.

**Why.** Synonym drift is the top source of duplicate helpers — when half the codebase says `fetch` and half says `retrieve`, "does this method already exist?" stops being answerable by search, and the second copy gets written. Shape-encoding collection names make bulkification bugs visible at the call site: a method iterating `accountsById.values()` inside a loop that already holds `account` reads wrong on sight. And verbosity has a budget, but readability wins it — the person picking this code up cold is the audience, not the person who wrote it.

## 3. Custom object and field API names: underscore-separated Pascal words, whole words, no abbreviations

**Rule.** Custom object and field API names are underscore-separated Pascal words — whole English words, no abbreviations: `Annual_Contract_Value__c`, not `AnnualContractValue__c` or `ACV__c`; `Opportunity_Competitor__c`, not `OpportunityCompetitor__c`. Boolean fields are prefixed `Is`/`Has`/`Can` (`Is_Primary__c`, `Has_Open_Dispute__c`). Lookup fields are named so the reference reads as the relationship: `Primary_Contact__c`, not `Contact2__c`.

**Why.** API names outlive labels. They leak into SOQL, formulas, reports, flow references, integrations, and every metadata-consuming tool — a label rename is free, an API-name rename is a breaking change across all of them. This is the grammar the shipped library already uses — `Log_Setting__mdt`, `Print_Debug_Logs__c`, `Log_Clean_Up__mdt` — and it holds up somewhere camelCase doesn't: word boundaries survive contexts that strip case entirely. Formula and validation-rule error messages render field references in ALL CAPS (`ANNUAL_CONTRACT_VALUE__C`), which erases every camelCase boundary but leaves the underscores intact, and the same is true wherever a rendering surface (a log line, a report column key) uppercases or otherwise flattens the API name. Whole words with no abbreviations keep it readable to a human, and to schema-consuming tooling, with no tribal glossary either way.

**This matches the platform default mechanism, not a deviation from it.** Salesforce auto-generates the API name by copying the label's spaces into underscores, so accepting the generated name is fine *provided the label itself is well-formed* — whole words, no abbreviations, describing what the field holds rather than encoding it. The discipline this rule still requires is in the label, not the casing: `ACV` or `Comp1` as a label produces a lazy API name whether or not Salesforce auto-generated it. It applies to *new* metadata only — never rename a shipped API name to comply, because API-name stability is the entire point of the rule.

**Validation rules on an object are numbered** (`01_`, `02_`, …) **and the object name plus rule number goes inside the error message.** Users report the message they saw, not the metadata name; the embedded number turns a support ticket into a one-grep fix.

## 4. Automation-plumbing fields are prefixed `TECH_`

**Rule.** A field that exists for automation rather than humans — a dedupe key, a rollup staging value, an integration correlation id, flow scratch state — gets the `TECH_` prefix ahead of the §3 grammar: `TECH_Last_Sync_Hash__c`, `TECH_Dedupe_Key__c`.

**Why.** The prefix instantly separates "safe to expose on layouts and reports" from "touch this and automation breaks" — for the admin building a page layout, the analyst building a report, and the reviewer reading a field list. It is also auditable with a single metadata grep, which is what makes it a rule instead of a hope.

## 5. Custom metadata types name the config domain; record DeveloperNames read as lookup keys

**Rule.** A custom metadata type is named for the configuration domain it holds, using the §3 grammar plus the platform's `__mdt` suffix: `Retention_Policy__mdt`, `Integration_Config__mdt` — never for the one feature that happens to consume it first. Records within a type follow one grammar per type, normally the thing each row configures: the `Retention_Policy__mdt` rows for orders and invoices are `Order` and `Invoice`, not `Policy1` and `NewPolicy_Final`.

**Why.** CMDT records are addressed from code by DeveloperName — `Retention_Policy__mdt.getInstance('Order')` — so a record's name is a string contract, not a label. A rename silently breaks every `getInstance` call that references it, and the compiler won't tell you. Before renaming any CMDT record, grep the codebase for its DeveloperName; a reviewer can hold the line the same way.

## 6. Permission set atoms are capability-named; personas live only in permission set groups

**Rule.** A permission set is an atom named for *what it grants*, on the ladder grammar `Additional Permissions - <Feature> <Tier>`: `Additional Permissions - Order Tracking View`, `Additional Permissions - Order Tracking Admin`. Every feature ships the full three-tier ladder — View / Power User / Admin — and [permissions.md §3](./permissions.md) owns that ladder grammar and its tier semantics; this section cross-links it rather than restating a second version. Personas — job roles — never appear in an atom's name; they belong to permission set groups, which compose atoms into a role's full grant.

Custom permissions follow the `Can_<Action>` grammar owned by [permissions.md §7](./permissions.md) — `Can_View_Order_Tracking`, not `Order_Tracking_Access` — and, once shipped, are frozen: a custom permission's API name is referenced as a raw string from FlexiPage visibility formulas, `@salesforce/customPermission/` imports in LWC, and `FeatureManagement.checkPermission()` calls in Apex — all three layers of the feature gate in [security-sharing.md §6](./security-sharing.md).

**Why.** A persona-named atom rots the moment a second persona needs the same capability — you either duplicate the atom or grant "Sales Manager Permissions" to support agents and let the name lie. Capability-named atoms compose; the persona mapping lives in exactly one place (the group), which is what keeps least-privilege auditable instead of archaeological.

## 7. Flows: object first, type token second, behavior last

**Rule.** Flow API names are Snake_Case with three ordered tokens — triggering object, flow type, behavior: `Account_BeforeSave_SetRegion`, `Case_Screen_CloseWizard`, `Order_Scheduled_ExpireQuotes`. Subflows use `Subflow` as the type token, led by the domain they serve: `Order_Subflow_ApplyDiscounts`. Every flow carries a description, every non-obvious element carries a description, and element labels start with a verb.

**Why.** Flows have no package structure — the name *is* the folder. Setup lists every flow in the org flat, hundreds at a time, and object-first naming is the only findability mechanism: sort by name and each object's automation clusters together, with the type token telling you what fires when. The description requirement exists because the flow canvas is the one place where "self-documenting code" is not available as an excuse.

## 8. LWC component folders are camelCase and must survive the kebab-case conversion

**Rule.** Component folder names begin with a lowercase letter and are camelCase: `orderTimeline`, not `order_timeline` or `OrderTimeline`. The platform enforces the hard constraints (alphanumeric plus underscore only, no hyphens, no consecutive underscores, can't end in an underscore); the convention here adds: no underscores at all, and child components extend the parent's name — `orderTimeline`, `orderTimelineItem`, `orderTimelineFilterBar`.

**Why.** camelCase converts mechanically to the kebab-case tag in markup — `orderTimeline` renders as `<c-order-timeline>` — so anyone reading a template can find the folder by reversing the conversion. Underscores don't convert: `my_component` becomes `<c-my_component>`, an off-standard tag that survives forever. And because the `lwc/` directory is as flat as the flow list, feature-first names are what group a feature's components together.

## 9. Platform events are named for the fact that occurred

**Rule.** A platform event is named as a past-tense business fact, using the §3 grammar plus the platform's `__e` suffix: `Order_Shipped__e`, `Payment_Failed__e`. Never name an event for one consumer's intended reaction — `Send_Order_Email__e` is a command wearing an event's suffix. Fields on the event follow §3.

**Why.** An event has any number of subscribers, present and future; a name that encodes one subscriber's action becomes a lie the day the second subscriber arrives. Past-tense fact naming also states what a platform event actually is — an immutable record that something happened, published to a bus — and keeps the publisher honestly decoupled from whatever anyone does about it.

## 10. Machine enforcement: compile the grammar into PMD Code Style rules

**Rule.** Every naming rule a regex can check is enforced by the analyzer gate, not by reviewer stamina. PMD's Apex Code Style category ships naming rules whose patterns are configurable properties — `ClassNamingConventions` (`classPattern`, `testClassPattern`, `abstractClassPattern`, `interfacePattern`, `enumPattern`, inner-class variants), `MethodNamingConventions` (`instancePattern`, `staticPattern`, `testPattern`), `FieldNamingConventions`, `PropertyNamingConventions`, `FormalParameterNamingConventions`, and `LocalVariableNamingConventions`. Tighten the defaults to this file's grammar in the shared ruleset:

```xml
<rule ref="category/apex/codestyle.xml/ClassNamingConventions">
    <properties>
        <!-- §1 compiled: Apex class names are PascalCase, underscores banned
             (PMD's default [A-Z][a-zA-Z0-9_]* permits them). This governs
             Apex identifiers only — it does not reach §3/§5's custom
             object, field, and CMDT API names, which live in metadata XML
             PMD's Apex ruleset never parses, and which use the opposite
             grammar (underscore-separated) by design. -->
        <property name="classPattern" value="[A-Z][a-zA-Z0-9]*" />
        <!-- §1 compiled: every class containing test methods ends in Test.
             PMD keys "test class" off the @IsTest annotation, which also
             catches §1's test infrastructure (factories, stubs, mocks,
             doubles) that ships no test methods — so the pattern admits
             those descriptive suffixes alongside *Test. Whether a class
             actually contains test methods stays a review check. -->
        <property name="testClassPattern" value="[A-Z][a-zA-Z0-9]*(Test|Factory|FactoryDefaults|Stub|Double)|Mock[A-Z][a-zA-Z0-9]*" />
    </properties>
</rule>
<rule ref="category/apex/codestyle.xml/MethodNamingConventions" />
<rule ref="category/apex/codestyle.xml/FormalParameterNamingConventions" />
<rule ref="category/apex/codestyle.xml/LocalVariableNamingConventions" />
```

**Why.** A naming standard that lives only in a document is a suggestion; wiring it into the analyzer makes §1–§2 compilable, enforced at the same SPOTLESS gate as every other finding (see [static-analysis.md](./static-analysis.md) for the gate sites, severity thresholds, and waiver discipline — including the scoped `FieldNamingConventions` waiver for `SCREAMING_SNAKE_CASE` constants in §3.3 there).

**Know the boundary.** Regex checks *shape*, not *role*: the analyzer can prove every test class ends in `Test` and no class name contains an underscore, but it cannot know that a class issuing SOQL should have been named `*Selector`. Archetype-fit stays a code-review check, which is why every rule in this file is written to be checkable by a reviewer holding nothing but the diff.

---

**Summary of the naming principle:** the name is the cheapest permanent documentation a component will ever get. Apex names encode the architecture (archetype suffixes, one verb per concept); API names are whole readable words because they outlive every label and refactor; config-shaped metadata (CMDT records, custom permissions) is a string contract frozen by its consumers; flows and LWCs get object-first / feature-first names because their flat listings have no other structure; events are named for facts, not reactions. Then compile whatever a regex can see into the PMD gate, and spend review attention only on what it can't.

## Sources

- <https://fflib.dev/docs/service-layer/overview> · <https://fflib.dev/docs/selector-layer/overview> · <https://fflib.dev/docs/domain-layer/overview> — archetype suffixes, selector and domain naming
- <https://www.campfiresolutions.io/blog/salesforce-object-and-field-api-naming-conventions> and <https://github.com/cfpb/salesforce-docs/blob/master/_pages/Salesforce-Naming-Conventions.md> — whole-word, no-abbreviation API names, controller suffixes
- <https://sfxd.github.io/article-convfields.html> — `TECH_` prefix, boolean prefixes, underscore-separated field grammar
- <https://blog.beyondthecloud.dev/blog/salesforce-naming-convention> — one word per concept, constants, collection-shape names
- <https://automationchampion.com/2021/11/09/naming-conventions-for-salesforce-flow/> and <https://admin.salesforce.com/blog/2021/the-ultimate-guide-to-flow-best-practices-and-standards> — flow naming grammar and description discipline
- <https://www.salesforceben.com/salesforce-naming-conventions-how-to-enforce-them/> — validation-rule numbering
- <https://www.cloudkettle.com/blog/optimizing-profiles-and-permission-sets-in-your-salesforce-org/> and <https://admin.salesforce.com/blog/2024/use-permission-sets-overcome-access-dilemmas> — capability-named permission sets, persona groups
- <https://developer.salesforce.com/docs/platform/lwc/guide/create-components-folder.html> — LWC folder constraints and kebab-case conversion
- <https://trailhead.salesforce.com/content/learn/modules/platform_events_basics/platform_events_define_publish> — `__e` suffix mechanics
- <https://pmd.github.io/pmd/pmd_rules_apex_codestyle.html> — naming-rule regex properties and defaults
