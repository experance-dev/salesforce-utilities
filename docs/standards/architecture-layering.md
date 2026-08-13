# Architecture — Layering (Selector / Service / Domain)

This file governs how Apex is organized into layers on top of this library: Selector, Service, Domain, and the LWC-facing controller that fronts them. Read it before structuring a new feature or reviewing one, when the question is "where does this logic belong." Pair with [architecture.md](../best-practices/architecture.md) for trigger framework and async guidance, and [apex.md](../best-practices/apex.md) for class-level conventions.

## 1. Align with Apex Enterprise Patterns (fflib) — without importing the framework

**Rule.** Structure Apex around the [Apex Enterprise Patterns](https://github.com/apex-enterprise-patterns/fflib-apex-common) (fflib) layering — Selector / Service / Domain — using this library's hand-rolled equivalents instead of pulling in the fflib base classes.

**Why.** fflib solves the same problems this library solves, differently: explicit `WITH USER_MODE` per query instead of a dynamic-SOQL builder with automatic FLS enforcement, an interface-based DI seam per service instead of a `Type`-keyed factory, and a single audited DML chokepoint instead of a unit-of-work that batches commits. Same shape, smaller framework footprint. Introducing fflib base classes piecemeal into a codebase already using these equivalents creates two parallel framework surfaces solving the same problem — don't do it a class at a time. Adopting fflib outright is a legitimate choice; adopting it accidentally, one file at a time, is not.

| Layer | fflib base | This library's equivalent | Why it diverges |
| --- | --- | --- | --- |
| Selector | `fflib_SObjectSelector` | Hand-rolled static selectors (`OrderSelector`) | fflib adds dynamic-SOQL-building and automatic FLS enforcement; explicit `WITH USER_MODE` per method is less framework and more readable per query. |
| Service | `fflib_Application.Service` factory + interface | `IOrderService` + a `@TestVisible` setter for test injection | fflib's factory maps `Type` to instance application-wide; per-controller injection is a smaller surface with the same DI seam. |
| Domain | `fflib_SObjectDomain` | [`TriggerHandler`](../../utilities/triggers/TriggerHandler.cls) subclasses + service calls | fflib's Domain base auto-wires trigger context and bulk-method invariants; the Kevin O'Hara `TriggerHandler` this library extends already supplies trigger context, loop-count guarding, and bypass machinery. |
| DML chokepoint | `fflib_SObjectUnitOfWork` | [`DMLManager`](../../utilities/dml/DMLManager.cls) | UnitOfWork batches DML at transaction-commit time; `DMLManager` wraps each call with `xxxAsUser` / `xxxAsSystem` CRUD/FLS enforcement. Different mechanism, same goal: one auditable chokepoint. |
| Mocking | `fflib_ApexMocks` (Mockito-style) | [`TestDouble`](../../utilities/testing/TestDouble.cls) + interface mocks | ApexMocks is more capable than most codebases exercise; `TestDouble` is smaller and pairs directly with the `@TestVisible`-setter DI pattern in §3 below. |

**Citation discipline.** When someone asks "is this fflib?", the accurate answer is: *"This follows the Apex Enterprise Patterns layering with hand-rolled equivalents. The pattern is the same; the framework footprint is smaller."*

## 2. One controller-facade per LWC entry point — thin wrapper, zero business logic

**Rule.** The `@AuraEnabled` class delegates every call to a service through an interface. It contains nothing beyond input pass-through and exception-shaping — no query construction, no branching business logic, no DML.

**Why.** Tests inject a mock through a `@TestVisible` setter instead of exercising real DML through the controller. The controller is also the only `with sharing` surface the LWC binds to, so the security boundary stays exactly one class wide — auditing it means reading one file, not tracing a call graph.

```apex
public with sharing class OrderController {
    @TestVisible
    private static IOrderService service = new OrderServiceImpl();

    @AuraEnabled
    public static List<OrderSummary> getOpenOrders(Id accountId) {
        try {
            return service.getOpenOrders(accountId);
        } catch (Exception e) {
            Logger.logException(e, 'OrderController', 'getOpenOrders');
            throw new AuraHandledException('Unable to load open orders.');
        }
    }

    @TestVisible
    private static void setServiceForTest(IOrderService stub) {
        service = stub;
    }
}
```

## 3. Interface every non-trivial service for dependency injection

**Rule.** A service with more than trivial logic exposes an interface (`IOrderService`); the controller depends on the interface, never the concrete implementation directly; the implementation is swapped in through a `@TestVisible` setter, as shown in §2 above.

**Why.** Tests stub the interface and run without touching the database. Production wires once, at class-load time — `private static IOrderService service = new OrderServiceImpl();` — so there's no runtime factory lookup or registration step to reason about.

```apex
public interface IOrderService {
    List<OrderSummary> getOpenOrders(Id accountId);
}
```

## 4. Never query Custom Metadata Types with SOQL — use `Type.getInstance()` / `Type.getAll()`

**Rule.** Custom Metadata Type access always goes through the platform `Type` methods — `MyType__mdt.getInstance(devName)` for a single row, `MyType__mdt.getAll()` for the full keyed map — then filter and sort in memory. There is exactly one sanctioned exception, covered at the end of this section. Filtering cost and `ORDER BY` convenience don't justify a query: a `getAll().values()` collection is small enough that an in-memory pass beats a query every time.

**Why.** The platform `Type` methods are cache-served — `getInstance()` / `getAll()` reads come from the platform's CMDT cache, not a fresh query, so repeated calls in the same transaction (or across transactions) cost nothing extra. A CMDT SOQL query bypasses that cache for data the platform is already holding for you. It also trips static analyzers' CRUD-violation rule for nothing in return: `WITH USER_MODE` on a `__mdt` object is theater — CMDT bypasses CRUD/FLS by platform rule, and on some API versions a `USER_MODE` query against `__mdt` raises a `QueryException` outright — while `WITH SYSTEM_MODE` spends a security-relevant keyword on a query that shouldn't exist. Remove the query and the whole access-level debate, plus the analyzer noise, disappears with it.

Treat this as absolute apart from that one documented exception below — not "prefer, with exceptions" as a general license. A soft version of this rule produces exactly what soft rules always produce: every author is convinced their case is the exception, and the list of violations never gets shorter.

```apex
// The only pattern — zero SOQL, platform-cached.
Map<String, Routing_Rule__mdt> rulesByName = Routing_Rule__mdt.getAll();
List<Routing_Rule__mdt> active = new List<Routing_Rule__mdt>();
for (Routing_Rule__mdt rule : rulesByName.values()) {
    if (rule.Active__c == true) {
        active.add(rule);
    }
}
// In-memory sort by Priority__c ascending — CMDT row counts are small; this is fast.
```

Single-row lookups follow the same rule:

```apex
Integration_Config__mdt config = Integration_Config__mdt.getInstance('Default_Endpoint');
```

**Known limit — and the one sanctioned exception.** Every static CMDT method — `getAll()`, `getInstance()`, and the rest — truncates every field at 255 characters. `getInstance(devName)` is not a workaround for a long-text-area field; it truncates the same way `getAll()` does. The no-SOQL rule above stands for every normal CMDT read. The one carve-out: a field that must actually exceed 255 characters — a long-text-area value the design genuinely depends on in full — may be read via SOQL, because SOQL is the platform's documented escape hatch for the untruncated value. Document that carve-out inline at the query, with the reason, so it reads as a deliberate, narrow exception rather than a habit.

## 5. Selector classes own all SOQL for an SObject — zero business logic, zero DML

**Rule.** Selectors are stateless, use bind variables only, apply `WITH USER_MODE` on every query, and return lists in a canonical, documented shape. Every method short-circuits defensively on null/empty input at entry, and every query carries a `LIMIT` sized to what the downstream consumer can actually use.

**Why.** Every SOQL statement for a given SObject lives in exactly one place. That makes `WITH USER_MODE` coverage trivial to audit, turns adding a field to the canonical projection into a one-file change, and gives tests a single seam to mock instead of query results stubbed out across several services.

```apex
public inherited sharing class OrderSelector {
    public static List<Order__c> selectByAccountIds(Set<Id> accountIds) {
        if (accountIds == null || accountIds.isEmpty()) {
            return new List<Order__c>();
        }
        return [
            SELECT Id, Name, Status__c, Amount__c
            FROM Order__c
            WHERE Account__c IN :accountIds
            WITH USER_MODE
            LIMIT 2000
        ];
    }
}
```

When two selector methods differ only in their `WHERE` clause — a topic-filtered variant and an unfiltered one, say — prefer a dynamic-SOQL string builder with bind variables over duplicating a wide field projection across both methods. Keep the shared `SELECT` / `FROM` fragment in one place and compose the filter separately, rather than letting a 30-field projection drift out of sync between two near-identical methods.
