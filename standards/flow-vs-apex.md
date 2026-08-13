# Flow vs. Apex — the Automation Boundary

This file governs the decision boundary between declarative automation (record-triggered flows) and Apex on any SObject: how to pick the owning mechanism, when to escalate to code, the performance rules that keep flows safe under bulk DML, and the naming and documentation standards that keep an object's automation inventory auditable. Read it before adding any record-triggered automation — flow or trigger — to an object. Pair with [triggers.md](./triggers.md) for the Apex side of the line and [architecture-layering.md](./architecture-layering.md) for where escalated logic lands.

## 1. Decide by automation density, not by builder preference

**Rule.** Before adding automation to an SObject, count what already fires on it. The owning mechanism is a function of the object's cumulative automation load per save — not of whether the person holding the requirement is an admin or a developer.

| Automation density on the object | Owning mechanism |
| --- | --- |
| Low — a handful of simple field rules | Record-triggered flows, before-save first |
| Medium — several interacting automations, some heavy steps | Flow as the orchestrator; invocable Apex for the heavy steps |
| High — many automations, cross-object cascades, integrations | Apex trigger framework owns the object; flows stay out of the trigger path |

**Why.** Salesforce's record-triggered automation decision guide frames the choice around total automation impact on the object per save, because that is what determines limit consumption and debuggability. The tenth automation on an object is a different decision from the first; per-requirement choices made in isolation are how objects accumulate interleaved flow/trigger stacks nobody can order or reason about.

## 2. One entry-point mechanism per object per save context

**Rule.** For a given object, pick one mechanism — record-triggered flows or the Apex trigger framework — as the entry point for record-triggered automation. Never run both as peers on the same object in the same phase. On an Apex-owned object, new automation enters through the object's single trigger handler ([triggers.md §1](./triggers.md)); requirements that arrive shaped as flows get implemented in the handler, or exposed to declarative callers as invocable Apex.

**Why.** Relative ordering between record-triggered flows and Apex triggers within the same phase is only partially controllable. A mixed stack turns "what runs before what" into something you discover in production rather than read off the metadata — and "just one small flow" on a trigger-owned object is how that discovery starts.

When flow and Apex contributions genuinely must share one ordered pipeline — a large multi-team org with both declarative and code owners on the same object — the strongest community answer is the [Trigger Actions Framework](https://github.com/mitchspano/trigger-actions-framework): one class or flow per action, sequenced and toggled by custom metadata rows in a single pipeline. This library ships handler-based dispatch instead ([TriggerHandler.cls](../utilities/triggers/TriggerHandler.cls)) because the CMDT indirection costs readability most orgs don't need to spend. If your org has the multi-team problem, adopt that framework deliberately — don't drift into mixed peers.

## 3. "One flow per object" is retired — entry conditions and Trigger Order are the real controls

**Rule.** On a flow-owned object, multiple record-triggered flows per save context are acceptable when all three controls are present: each flow is scoped to one domain concern, each flow declares entry conditions, and each flow carries an explicit Trigger Order value. "One giant flow per object" is not the standard here, and its absence is not a review finding.

**Why.** The single-flow absolutism was imported from Apex trigger frameworks and was never official platform guidance — Salesforce's own architect guidance says record-triggered automation does not need to live in a single mega-flow per object. In a multi-team org the mega-flow collapses under ownership contention: every team edits one artifact, every change risks every other team's logic, and flow XML merges are effectively unresolvable (§12). What the platform actually sanctions is partitioning with controls:

- **Entry conditions on every record-triggered flow, no exceptions.** Entry conditions stop the flow interview from starting at all; a Decision element as the first node still pays an interview per record at bulk scale. Gate at the door, not in the hallway.
- **Explicit Trigger Order on every record-triggered flow** — values 1–2,000, assigned in gaps (10, 20, 30 …) so a new flow slots in without renumbering the set. An unset order leaves sequencing to a default nobody chose.

## 4. Trigger Order works within a phase — never design across phases with it

**Rule.** Trigger Order sequences flows relative to other flows in the same phase: before-save against before-save, after-save against after-save. No order value makes an after-save flow run before a before-save flow, or before an Apex `before` trigger. Use Trigger Order to arrange siblings; design phase placement against the platform's order of execution.

**Why.** The save order of execution always wins. A design that needs an after-save flow's result inside a before-save computation isn't mis-ordered — it's impossible, and the fix is moving the logic across the phase line, not tuning numbers.

## 5. Escalate to Apex when the logic needs what flows cannot express

**Rule.** Cross the line to code when the requirement needs any of the following. This is the checklist — reviewable item by item, not a matter of taste:

- Map/Set/wrapper-type data structures, or branching complex enough to become canvas spaghetti
- Aggregate or subquery SOQL
- Savepoints or partial-rollback transaction control
- `addError()` on specific records
- Callout orchestration — retries, backoff, response handling
- Guaranteed bulk behavior at data-migration volume (flows hit row-limit errors and unbatchable loops where bulkified Apex does not)
- Reuse of the same logic across surfaces — trigger, REST endpoint, LWC controller, batch
- Unit-testability with mocked seams and asserted behavior, not a debug-run in a sandbox
- Anything that must route through this library's security and DML wrappers — [DMLManager](../utilities/dml/DMLManager.cls) `USER_MODE` enforcement, [Logger](../utilities/logging/Logger.cls) error handling

**Why.** Each item is something a flow either cannot express or can only fake at a cost that resurfaces later as a limit error or an untestable canvas. Escalated logic lands in the service layer per [architecture-layering.md](./architecture-layering.md); the flow-facing surface — if one is still needed — shrinks to a thin invocable wrapper around the service call. The wrapper stays one call deep — validation, queries, and DML all live in the service, where they're testable with mocked seams:

```apex
public with sharing class OrderDiscountFloorInvocable {
    @InvocableMethod(
        label='Apply Discount Floor'
        description='Clamps order discounts to the approved floor. Bulk-safe.')
    public static void applyDiscountFloor(List<Id> orderIds) {
        OrderDiscountService.applyDiscountFloor(new Set<Id>(orderIds));
    }
}
```

## 6. Bypass switches are custom permissions, honored on both sides of the boundary

**Rule.** Feature toggles and automation bypasses are Custom Permissions — named on a fixed grammar such as `Bypass_<Object>_<Automation>` — and every mechanism automating the object checks them: Apex handlers via `FeatureManagement.checkPermission()`, record-triggered flows via `$Permission` in their entry conditions, validation rules via `$Permission` in the formula. Scope bypasses per object, never as one global kill switch, and house them in dedicated permission sets so granting a bypass is an assignment, not a deploy.

**Why.** A data migration or integration backfill has to silence automation on both sides of the boundary at once; a bypass only the Apex handler honors leaves the flows firing, and vice versa. One custom permission read by all three surfaces makes "turn off this object's automation for the migration user" a permission-set assignment that takes seconds and reverses cleanly — and per-object scoping keeps that switch from silencing the rest of the org. The [TriggerHandler](../utilities/triggers/TriggerHandler.cls) bypass registry (`bypass` / `clearBypass`) covers the in-transaction Apex case; the custom permission is the cross-mechanism, cross-session control.

## 7. Same-record field defaulting is a before-save flow — full stop

**Rule.** Every same-record field default, stamp, or recalculation runs as a before-save ("fast field update") record-triggered flow. Not Apex; not an after-save flow; never an after-save update to the record that just saved.

**Why.** A before-save flow mutates the record already in memory: no extra DML, no second trip through the save order of execution. Benchmarks place before-save flows just behind Apex triggers and far ahead of after-save paths. Apex for a field default spends a code review and a deploy on admin-shaped work; doing the same-record update after-save buys a full wasted recursion of every automation on the object.

## 8. No data elements inside flow loops

**Rule.** Get / Create / Update / Delete elements never appear inside a Loop. Accumulate changes into collection variables and commit once after the loop closes; where a Transform element replaces the loop entirely, prefer it.

**Why.** This is the flow-side twin of the no-SOQL-in-loops rule in [triggers.md §4](./triggers.md). Every in-loop data element is a separate query or DML statement against the shared per-transaction limits (100 SOQL queries, 150 DML statements) — one loop over 150 records exhausts the DML budget by itself. The violation is visible in review: a data element nested under a loop connector in the flow XML diff.

## 9. Every data-touching flow has a fault path, and the fault path logs

**Rule.** Every data element and callout action in a flow carries a fault connector, and the fault path records the failure through an invocable log action writing to the same persistent store as [Logger](../utilities/logging/Logger.cls) — not a screen message, not an admin email.

**Why.** An unhandled flow fault emails an admin and vanishes; nothing persists that correlates the failure with the transaction that caused it. Wiring flow faults into the same log store as Apex gives one observability pane across both halves of the automation estate — the flow failure and the Apex failure for the same save show up side by side.

TODO: this library does not yet ship an invocable wrapper around `Logger`; until it lands, adopting this rule means adding a thin `@InvocableMethod` class in your org that delegates to `Logger`.

## 10. Flow naming lives in naming.md §7; this file adds only subflow-extraction discipline

**Rule.** Flow API names, description requirements, and element-label discipline follow [naming.md §7](./naming.md) — object first, flow type second, behavior last, spelled out rather than coded (`Case_Screen_CloseWizard`, not `Case_SCR_CloseWizard`). What this file adds on top of that grammar: logic used by more than one flow is extracted into a subflow, never copied.

**Why.** Naming and description discipline are governed once, in naming.md §7, so an author checks a single file instead of reconciling two versions of the same rule. Duplicated canvas logic drifts exactly the way duplicated code does, except no diff tool shows it; the subflow is the flow analog of the shared service method.

## 11. The object's automation inventory is documented — hard rule

**Rule.** Every object carrying more than one automation has a documented inventory: what fires, in which phase, in what order, owned by whom. The inventory lives in the repo alongside the object's metadata (or in the docs tree), and the PR that adds, reorders, or retires an automation updates it in the same change. A PR touching flow or trigger metadata with a stale inventory is incomplete.

| Phase | Automation | Trigger Order | Owner | Purpose |
| --- | --- | --- | --- | --- |
| Before-save | `Order_BeforeSave_SetRegionDefaults` | 10 | Sales ops team | Default region and currency stamps |
| Before-save | `Order_BeforeSave_ApplyDiscountFloor` | 20 | Pricing team | Clamp discount to the approved floor |
| After-save | `OrderTrigger` → `OrderTriggerHandler` | — | Platform team | Fulfillment cascade, integration events |

**Why.** Entry conditions, Trigger Order values, and handler hooks are each readable individually, but the platform offers no single view of "everything that fires when this record saves" that includes ownership. The inventory is that view. It is also what makes §1's density decision repeatable — the next person deciding where a requirement lands starts by reading the table, not by archaeology in Setup.

## 12. Flows ride the same PR gate as code — and flow XML never gets hand-merged

**Rule.** Flows deploy from version control through the same review gate as Apex: one logical flow change per PR, kept small. When a flow's XML conflicts on merge, resolve by re-applying the change in Flow Builder on the current branch head — never by hand-editing conflict markers in the XML.

**Why.** A flow is business logic and gets business-logic review — entry conditions, ordering, and fault paths are all reviewable in the XML diff (§3, §8, §9). But flow XML is a serialization, not a source format: a hand-merged file can deploy cleanly and still corrupt at runtime. Re-doing the change costs minutes; debugging a corrupted flow in production does not.

---

**Summary of the boundary principle:** the object's automation density picks the owning mechanism; one mechanism owns the entry point per object per save context; multiple flows are fine under entry conditions plus explicit Trigger Order, within — never across — a phase; escalate to Apex on the checklist, not on taste; before-save for same-record work, collection variables instead of in-loop data elements, fault paths that log; and every object's automation inventory stays written down and current.

## Sources

- https://architect.salesforce.com/docs/architect/decision-guides/guide/record-triggered — automation-density axis, flow-first default, single entry point per object
- https://www.salesforce.com/blog/record-triggered-automation-apex-or-flow/ — official corroboration of the decision guide's Apex/flow split
- https://www.salesforceben.com/salesforces-new-decision-guide-format-makes-architecture-decisions-easier/ — density as the updated decision axis
- https://help.salesforce.com/s/articleView?id=platform.flow_concepts_trigger_guidelines.htm — Trigger Order range (1–2,000) and evenly distributed values
- https://developer.salesforce.com/docs/atlas.en-us.apexcode.meta/apexcode/apex_triggers_order_of_execution.htm — save order of execution across phases
- https://www.salesforceben.com/before-save-flow-vs-after-save-flow-in-salesforce/ — before-save vs after-save characteristics
- https://metillium.com/2020/10/salesforce-record-automation-benchmarking/ — automation performance benchmarks
- https://www.salesforceben.com/complete-guide-to-salesforce-flow-limits-and-how-to-avoid-them/ — flow consumption of transaction limits
- https://blog.beyondthecloud.dev/blog/bulkification-in-flows — collection-variable accumulation and Transform
- https://www.salesforceben.com/record-triggered-flow-strategy/ — entry conditions vs in-flow Decision gating
- https://www.apexhours.com/one-record-triggered-flow-per-object-per-type/ — origin of the single-flow rule in trigger frameworks
- https://www.salesforceben.com/how-many-flows-should-you-have-per-object/ — multi-flow partitioning, per-context flow split
- https://automationchampion.com/2021/11/09/naming-conventions-for-salesforce-flow/ — flow naming grammar and type codes
- https://admin.salesforce.com/blog/2021/the-ultimate-guide-to-flow-best-practices-and-standards — descriptions, subflows, flow standards
- https://blog.beyondthecloud.dev/blog/salesforce-flow-considerations — Apex-escalation triggers, fault paths, flow XML merge hazard
- https://www.salesforceben.com/an-admins-guide-to-bypass-logic-for-flows-apex-and-validation-rules/ — custom-permission bypass across flows, Apex, and validation rules
- https://admin.salesforce.com/blog/2021/allow-certain-users-to-edit-data-using-custom-permissions-in-validation-rules — `$Permission` checks in validation rules
- https://github.com/mitchspano/trigger-actions-framework — mixed flow/Apex pipeline framework
- https://github.com/jongpie/NebulaLogger — flow-fault-to-persistent-logger invocable pattern
