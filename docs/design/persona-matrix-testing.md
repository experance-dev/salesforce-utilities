# PersonaMatrix — Persona-Matrix Testing for Apex

**Status:** Draft v2 — three-lens adversarial review folded (platform facts · consumer ergonomics · standards conformance)
**Module:** `utilities/testing/persona/`
**Target release:** v1.1.0
**Author:** David Wood

---

## 1. Problem

On an org with a closed security model (OWD Private, permission-set ladders per feature), every
story has a security dimension: each persona the feature touches must be tested for what it **can**
do and what it **must not** do. Today that coverage is hand-rolled — nested `System.runAs` blocks,
one-off user fabrication, ad-hoc asserts — and it is the first thing dropped under schedule
pressure. The result is the most common gap in Salesforce test suites: green happy-path coverage
that says nothing about whether the sharing and permission model actually holds.

No open-source project fills this gap. The ecosystem has data factories that can build users
([Apex Test Kit](https://github.com/apexfarm/ApexTestKit)), mocking frameworks
([fflib-apex-mocks](https://github.com/apex-enterprise-patterns/fflib-apex-mocks)), runtime
CRUD/FLS predicates ([CanTheUser](https://github.com/trailheadapps/apex-recipes)), and permission
toggling helpers ([TestCustomPermissions](https://github.com/flexchecks/TestCustomPermissions)) —
but no runner that executes one scenario as each persona with per-persona expected outcomes. The
community's state of the art is a PMD lint rule that checks a test class contains *at least one*
`runAs` call. Commercial tools (Provar, Copado Robotic Testing) sell persona-based execution at
the UI level, closed-source.

PersonaMatrix is that runner: declare the scenario once, declare the personas and what each one
should experience, and let the framework execute, collect, and report.

## 2. Why this only works on a user-mode codebase

`System.runAs` switches the context user and enforces **record sharing**. Object CRUD and
field-level security bite only on code paths that enforce them — `WITH USER_MODE` SOQL,
`AccessLevel.USER_MODE` DML, `Security.stripInaccessible`. On a codebase that runs in system mode,
a persona matrix would pass for every persona and prove nothing.¹

This library's stack is user-mode throughout: `DMLManager` pre-checks CRUD/FLS and executes DML at
`AccessLevel.USER_MODE`; [security-sharing §2](../standards/security-sharing.md) requires
`WITH USER_MODE` on queries and §3 routes DML through `DMLManager`. PersonaMatrix is therefore
honest here: a denied persona actually gets denied, with a typed exception the test can assert on.

**Prerequisite (measurable):** code under a PersonaMatrix test must perform its SOQL with
`WITH USER_MODE` and its DML through `DMLManager` (or equivalent `USER_MODE` access level). A
scenario exercising system-mode code paths is out of scope for persona asserts and the test class
must not claim persona coverage for it.

> ¹ The current [runAs doc](https://developer.salesforce.com/docs/atlas.en-us.apexcode.meta/apexcode/apex_testing_tools_runas.htm)
> reads "The runAs method enforces record sharing. User permissions and field-level permissions
> are applied for the new context user as described in Enforcing Object and Field Permissions" —
> i.e., applied *where the code enforces them*, which is exactly why this prerequisite exists.
> Older doc wording ("doesn't enforce user permissions or field-level permissions") described the
> same behavior less precisely.

## 3. Design constraints the platform imposes

These four constraints dictate the shape of the API. They are not preferences.

1. **No parameterized tests.** Apex test methods take no arguments and cannot be generated at
   runtime. A persona matrix must therefore be either N hand-written methods or a loop inside one
   method. The framework supports both (see §6.5) but the primary API is the loop.
2. **A failed assert aborts the whole method.** A naive `for (persona : personas) { runAs …
   Assert … }` loop stops at the first failing persona and silences every persona after it. The
   runner therefore never asserts mid-loop: it collects every persona's actual outcome into a
   **failure ledger** and raises one aggregate failure at the end that names every mismatch.
3. **Governor limits are shared across `runAs` blocks in one method.** `System.runAs` does not
   reset limits — a five-persona matrix shares one 100-SOQL budget. Additionally,
   [every call to `runAs` counts as a DML statement](https://developer.salesforce.com/docs/atlas.en-us.apexcode.meta/apexcode/apex_testing_tools_runas.htm)
   against the 150-statement cap. The runner records per-persona limit consumption in its report
   (taking its pre-snapshot *inside* the `runAs` block, so the `runAs` call itself is not
   attributed to the scenario), and §6.5 defines the fallback for heavy scenarios.
4. **Mixed-DML.** `User` and `PermissionSetAssignment` are
   [setup objects](https://developer.salesforce.com/docs/atlas.en-us.apexcode.meta/apexcode/apex_dml_mixed_dml_operations.htm):
   their DML cannot share a transaction with DML on non-setup (standard/custom) objects. All
   persona-user fabrication therefore runs under `System.runAs(adminUser)` via `TestFactory`'s
   existing `getAdminUser()` seam, per
   [testing-discipline §1.3](../standards/testing-discipline.md) — setup-object DML under an
   explicit admin context, separated from record DML.

## 4. Components

All classes live in `utilities/testing/persona/`. Interfaces use bare names — no `I` prefix —
per [naming.md §1](../standards/naming.md), which reserves the prefix for interface+`Impl` DI
pairs; the custom-assert interface is named `Check`, not `Assert`, so it can never shadow
`System.Assert` inside the class that hosts it.

| Class | Kind | Role |
| --- | --- | --- |
| `PersonaMatrix` | `@IsTest` class | Fluent builder + runner. Entry point: `PersonaMatrix.of(scenario)`. Inner `PersonaStep` stage makes the grammar compile-safe (§6.1). |
| `Persona` | `@IsTest` class | **Immutable** value object: a persona's name (its identity key), profile, role, permission-set ladder, parameters. Produced by `PersonaBuilder.build()`; registry constants hold these. |
| `PersonaBuilder` | `@IsTest` class | Mutable recipe, frozen by `build()`. `provision()` and `.persona()` accept `Persona` only — a builder is never a handle. |
| `PersonaScenario` | interface | The story action under test. One method: `Object run(PersonaContext ctx)`. |
| `PersonaContext` | `@IsTest` class | Handed to the scenario. Accessors: `getUser()`, `getPersonaName()`, `getParameter(String key)`. |
| `PersonaOutcome` | `@IsTest` class | The per-persona expectation model (§5). Hosts the `Check` interface for custom asserts. |
| `PersonaMatrixResult` | `@IsTest` class | Per-persona actual outcome: pass/fail, detail, returned value, caught exception, limits delta. Returned by `run()`/`runQuietly()` (§6.3). |
| `PersonaDefaults` | `@IsTest` class | Portable sample personas used by the framework's own tests (§7, §8). |

## 5. Expectation model

`PersonaOutcome` is deliberately small in v1 — measurable outcome kinds plus one extension point.
Anything not expressible here belongs in a conventional test.

```apex
PersonaOutcome.allowed()                          // scenario completes without exception
PersonaOutcome.allowed().returnedRows(3)          // …and returned exactly N rows
PersonaOutcome.allowed().returnedRowIds(expectedIds)  // …and returned exactly these records
PersonaOutcome.allowed().returnedNonNull()        // …and returned something
PersonaOutcome.seesNoRows()                       // sharing-denial idiom ≡ allowed().returnedRows(0)
PersonaOutcome.denied(DMLManager.CRUDException.class)             // scenario throws this exact type
PersonaOutcome.denied(QueryException.class).messageContains('inaccessible')  // …case-insensitive fragment
PersonaOutcome.custom(new MyCheck())              // PersonaOutcome.Check — full access to PersonaMatrixResult
```

Semantics, precisely:

- **`allowed()`** — the scenario returns without throwing. Any exception is a mismatch and the
  ledger records its type and message.
- **`returnedRows(Integer n)`** — the row-visibility assert for OWD-Private reads. The scenario's
  return value is compared as: a `List` → its size; an `Integer` → compared directly (the
  `SELECT COUNT()` idiom); **`null` → mismatch** ("expected n rows, scenario returned null");
  anything else → mismatch. The same query returning 3 rows for one persona and 0 for another is
  the whole point.
- **`returnedRowIds(Set<Id> expected)`** — order-insensitive Id-set equality over a returned
  `List<SObject>`. Distinguishes "manager sees the rep's record" from "manager sees *some*
  record" — a sharing-rule bug that leaks the wrong row must not pass a row-count assert.
- **`returnedNonNull()`** — the scenario returned any non-null value. For service calls whose
  return shape doesn't fit rows.
- **`seesNoRows()`** — alias for `allowed().returnedRows(0)`, because the correct Private-OWD
  negative assert *completes successfully with nothing visible*, and a reviewer scanning for
  negative coverage should be able to read it as a denial.
- **`denied(Type exceptionType)`** — the scenario must throw, and the thrown exception's
  `getTypeName()` must equal the expected type's name — **exact type-name equality, not
  instance-of** (Apex `Type` has no `isInstance`; callers name the concrete type; subclass
  matching is out of scope for v1, see §9). Completing without an exception is a mismatch — the
  security bug this framework exists to catch. A thrown exception of a different type is also a
  mismatch — a `NullPointerException` is not a denial.
- **`messageContains(String fragment)`** — optional refinement on `denied`, **case-insensitive**
  (`containsIgnoreCase`). Platform denial messages are org/version-observable strings, not
  documented API: every fragment used in a shipped test must be captured from a §8 self-test run,
  never assumed. For SOQL denials prefer the structured alternative — a `custom()` check reading
  `QueryException.getInaccessibleFields()`.
- **`custom(PersonaOutcome.Check)`** — receives the `PersonaMatrixResult`; returns a `String`
  describing the mismatch, or `null` for pass. Escape hatch for `stripInaccessible` redaction
  checks, `getInaccessibleFields` inspection, and anything else v1 does not model.

The denial surface on this stack is typed and predictable — that is a direct payoff of routing all
DML through `DMLManager`:

| Code path | Denial surface |
| --- | --- |
| `DMLManager` CRUD pre-check | `DMLManager.CRUDException` |
| `DMLManager` FLS pre-check | `DMLManager.FLSException` |
| `WITH USER_MODE` SOQL, object or field inaccessible | `System.QueryException` (+ `getInaccessibleFields()`) |
| Direct `USER_MODE` DML — object CRUD denied | `System.SecurityException` (message names the object) |
| Direct `USER_MODE` DML — field FLS denied | `System.DmlException` — "Operation failed due to fields being inaccessible…" (+ `getDmlFieldNames`) |
| Record not shared — **read** | no exception — 0 rows. Use `seesNoRows()`. |
| Record not shared — **write** (object CRUD passes; sharing bites at DML) | `System.DmlException`, `INSUFFICIENT_ACCESS_OR_READONLY` (verify §10) |

Sources for the two direct-DML rows: the
[Enforce User Mode doc](https://developer.salesforce.com/docs/atlas.en-us.apexcode.meta/apexcode/apex_classes_enforce_usermode.htm)
shows both behaviors verbatim; the Summer '23 (API 58.0+)
[versioned change](https://help.salesforce.com/s/articleView?id=release-notes.rn_apex_dml_exception_usermode.htm&release=244&type=5)
settled non-security user-mode DML failures on `DmlException` — satisfied at this library's
API 66.0.

The read row is the one hand-rolled tests get wrong most often: under Private OWD a read denial is
an *empty result*, not an exception. `seesNoRows()` is the correct negative assert for sharing;
`denied(...)` is the correct negative assert for CRUD/FLS. **Corollary (§6.4): one scenario = one
denial mode** — never write a scenario whose read result gates its write, or the two modes blur.

## 6. Runner semantics

### 6.1 Consumer shape

```apex
@IsTest
private class QuoteAccessPersonaTest {

    // Read scenario — sharing assert (row visibility). One scenario = one denial mode.
    private class ReadQuotes implements PersonaScenario {
        public Object run(PersonaContext ctx) {
            return [SELECT Id FROM Quote__c WITH USER_MODE];
        }
    }

    // Action scenario — CRUD assert (typed denial). Setup-data Ids ride scenario
    // constructor state — the first-class way to inject them (§6.4).
    private class SubmitQuote implements PersonaScenario {
        private final Id quoteId;
        public SubmitQuote(Id quoteId) { this.quoteId = quoteId; }
        public Object run(PersonaContext ctx) {
            QuoteService.submit(this.quoteId);
            return null;
        }
    }

    @TestSetup
    static void setup() {
        // provision() returns the fabricated users so the test can own/share records to them.
        Map<String, User> users = PersonaMatrix.provision(new List<Persona>{
            MyOrgPersonas.SALES_REP, MyOrgPersonas.SALES_MANAGER, MyOrgPersonas.SUPPORT_AGENT
        });
        TestFactory.createSObject(
            new Quote__c(OwnerId = users.get('Sales Rep').Id), true);
    }

    @IsTest
    static void readQuotes_personaMatrix() {
        PersonaMatrix.of(new ReadQuotes())
            .persona(MyOrgPersonas.SALES_REP)     .expect(PersonaOutcome.allowed().returnedRows(1))
            .persona(MyOrgPersonas.SALES_MANAGER) .expect(PersonaOutcome.allowed().returnedRows(1)) // role hierarchy
            .persona(MyOrgPersonas.SUPPORT_AGENT) .expect(PersonaOutcome.seesNoRows())
            .run();
    }

    @IsTest
    static void submitQuote_personaMatrix() {
        Id quoteId = [SELECT Id FROM Quote__c LIMIT 1].Id;  // test context, pre-runAs
        PersonaMatrix.of(new SubmitQuote(quoteId))
            .persona(MyOrgPersonas.SALES_REP)     .expect(PersonaOutcome.allowed())
            .persona(MyOrgPersonas.SUPPORT_AGENT) .expect(PersonaOutcome.denied(DMLManager.CRUDException.class))
            .run();
    }
}
```

**Compile-safe grammar.** `.persona(Persona)` returns an inner `PersonaStep` exposing only
`.expect(PersonaOutcome)`, which returns the `PersonaMatrix`. A persona without an expectation, an
expectation without a persona, or a double `.expect()` does not compile. `run()` on an empty
matrix throws a configuration error before any `runAs` executes.

**Provisioning contract.** `PersonaMatrix.provision(List<Persona>)` returns
`Map<String, User>` (persona name → fabricated user) and is the documented home for it:
`@TestSetup`, so every test method reuses the users (user + permset DML is the slow part).
`PersonaMatrix.userFor(Persona)` / `userFor(String name)` is the canonical lookup afterward —
usable in `@TestSetup` and in test methods. Persona **name is a unique key**: re-provisioning an
already-provisioned name is an idempotent no-op; `.persona()` with an unprovisioned name fails at
`run()` start with a named configuration error ("Persona 'Sales Rep' not provisioned — call
PersonaMatrix.provision in @TestSetup"). There is no lazy provisioning in v1.

### 6.2 Execution order

`run()` executes personas **in declaration order**, each inside its own `System.runAs(personaUser)`
block. For each persona it:

1. Enters `runAs`, then snapshots `Limits` (queries, DML statements, DML rows, CPU) — inside the
   block, so the `runAs` call's own DML-statement charge (§3.3) is not attributed to the scenario.
2. Invokes `scenario.run(ctx)`, catching any exception.
3. Snapshots `Limits` again; computes the delta.
4. Evaluates the declared `PersonaOutcome` against the actual result into a `PersonaMatrixResult`.

No assert fires until every persona has run.

### 6.3 The failure ledger

After the loop, if any persona mismatched, the runner raises **one** `Assert.fail` whose message
is the full ledger — every persona, pass or fail, one line each:

```text
PersonaMatrix: 2 of 3 personas failed — scenario ReadQuotes
  [PASS] Sales Rep       allowed, 1 row(s), 4 SOQL / 1 DML / ~80ms CPU
  [FAIL] Sales Manager   expected allowed with 1 row(s); got 0 row(s)  (sharing gap?)
  [FAIL] Support Agent   expected denied(DMLManager.CRUDException); scenario COMPLETED — security gap
  limits: 14/100 SOQL, 6/150 DML statements (excl. 3 runAs charges), total
```

Design intent: a single red test tells the whole story; nobody re-runs the suite three times to
discover the failures one persona at a time. Mechanics:

- CPU is reported **approximate** (`~Nms`) — `Limits.getCpuTime()` deltas are structurally valid
  across `runAs` but exclude database time and include runner overhead. SOQL/DML counts are the
  authoritative budget signals.
- The ledger message is capped at ~3,500 characters with a `(+N more lines — see debug log)` tail;
  the full ledger always goes to `System.debug`. (`ApexTestResult.Message` persists ~4,000 chars;
  no first-party citation, so §8 keeps an empirical cap test.)
- On an all-pass matrix, `run()` returns `List<PersonaMatrixResult>` for further inspection.
  `runQuietly()` collects and returns results **without ever asserting** — for consumers building
  their own reporting.

### 6.4 Run-state rules

- **The runner does not call `Test.startTest()`/`stopTest()`.** That budget belongs to the
  consumer (async scenarios need it around `run()`). Documented, not enforced.
- **The runner does not create data.** Records come from the test class (`@TestSetup` +
  `TestFactory`). The scenario reads what the running persona can see — that is the point.
  Setup-data Ids reach the scenario as **constructor state** (the blessed pattern, §6.1);
  persona-trait parameters ride `Persona` definitions and surface via
  `PersonaContext.getParameter()`.
- **The runner reuses the scenario instance and does not roll back data between personas —
  declaration order is semantic.** A field the scenario mutates in persona A's run is visible in
  persona B's; a record persona A submits stays submitted for persona B. For write scenarios,
  prefer per-persona target records; `.rollbackBetweenPersonas()` (savepoint before each persona,
  rollback after — savepoint/`runAs` interaction on the §10 verify list) is the opt-in
  alternative.
- **One scenario = one denial mode.** A scenario asserted with `denied(...)` acts
  unconditionally on known Ids; a scenario asserted with row counts only reads. A read-guarded
  write (`if (!visible.isEmpty()) submit(...)`) silently converts a CRUD denial into a
  false "COMPLETED" and must not appear in a matrix.
- **The runner does not mutate personas between runs.** One persona = one fabricated user with a
  fixed ladder. A "same user, more permissions" comparison is two personas.

### 6.5 Heavy scenarios: the per-method fallback

When a matrix approaches shared-limit ceilings (the ledger's limit line makes this visible), the
same API decomposes into one method per persona — restoring per-method limit isolation and
per-method pass/fail granularity in the test results UI, at the cost of boilerplate:

```apex
static void submitQuoteAs(Persona persona, PersonaOutcome expected) {
    Id quoteId = [SELECT Id FROM Quote__c LIMIT 1].Id;
    PersonaMatrix.of(new SubmitQuote(quoteId)).persona(persona).expect(expected).run();
}
@IsTest static void submitQuote_asSalesRep()     { submitQuoteAs(MyOrgPersonas.SALES_REP, PersonaOutcome.allowed()); }
@IsTest static void submitQuote_asSupportAgent() { submitQuoteAs(MyOrgPersonas.SUPPORT_AGENT, PersonaOutcome.denied(DMLManager.CRUDException.class)); }
```

**Guidance (measurable):** matrix-in-one-method up to the point any single test method exceeds 50%
of a governor limit; per-method beyond that.

## 7. Persona definition — the portable split

Same split as `TestFactory` / `TestFactoryDefaults`: the framework owns the machinery, the
consuming org owns the personas.

```apex
// Consumer-owned registry (one class per org/feature). Constants hold FROZEN Persona
// values — build() returns an immutable object, so no test can mutate a shared persona.
@IsTest
public class MyOrgPersonas {
    public static final Persona SALES_REP = PersonaBuilder.named('Sales Rep')
        .permissionSet('Quotes_View')
        .permissionSet('Quotes_Submit')
        .build();
    public static final Persona SALES_MANAGER = PersonaBuilder.named('Sales Manager')
        .role('Sales_Manager')                       // role hierarchy is how managers see under Private OWD
        .permissionSet('Quotes_View')
        .permissionSet('Quotes_Approve')
        .build();
    public static final Persona SUPPORT_AGENT = PersonaBuilder.named('Support Agent')
        .permissionSet('Cases_Standard')
        .build();
}
```

Builder surface: `PersonaBuilder.named(String)` → `.profile(String)` (default
`Minimum Access - Salesforce`) → `.role(String roleDeveloperName)` → `.permissionSet(String)`
(chainable, one ladder entry per call — Apex has no varargs) → `.parameter(String, Object)` →
`.build()`.

Rules:

- **Profiles and roles are referenced, never created.** `Profile` is on the
  [no-DML-from-Apex list](https://developer.salesforce.com/docs/atlas.en-us.apexcode.meta/apexcode/apex_dml_non_dml_objects.htm);
  roles follow the same rule by policy. Default profile is `Minimum Access - Salesforce` — a
  Salesforce-shipped [standard profile](https://help.salesforce.com/s/articleView?id=platform.standard_profiles.htm&type=5)
  present in Developer-Edition-based scratch orgs — so a persona's capability is exactly its
  permission-set ladder, which is the permission model the standards mandate anyway. Provisioning
  **fails fast** with a named error if the exact profile name resolves to zero rows ("profile X
  not found — override .profile(...)"); `Standard User` is the documented manual fallback, never
  an automatic one (and loose queries must not match `Minimum Access - API Only Integrations`).
- **`PersonaBuilder` composes existing `TestFactory` machinery — no `TestFactory` changes
  needed:** `createMinAccessUser(true)` (or `createTestUser(true, profileName)` for a non-default
  profile) plus `assignPermSetToUser(user, name)` per ladder entry. It never touches the shared
  `@TestVisible` `testUserPermissionSets` static (cross-test bleed). Usernames are uniquified on
  the reserved `test.example.com` domain per
  [testing-discipline §1.4](../standards/testing-discipline.md). Setup-object DML runs under
  `System.runAs(adminUser)` via `TestFactory.getAdminUser()`, per §3 item 4.
- **For orgs without a role hierarchy**, manager-style visibility is granted by inserting `Share`
  records to `userFor(persona).Id` in `@TestSetup` — which is exactly why `provision()` returns
  the user map.
- The library ships `PersonaDefaults` with three working personas used by the framework's own
  tests and serving as the copy-me example:
  - `Library User` — ladder `{'BasePermissionsApex', 'Utilities_Test_User'}`, mirroring
    `TestFactory`'s own `testUserPermissionSets`. `BasePermissionsApex` carries the `Debug_Log__c`
    capability; `Utilities_Test_User` is the grant-nothing marker/lookup identity.
  - `Library Peer` — same ladder, distinct user. Exists so sharing tests can compare owner vs
    non-owner on `Debug_Log__c` (OWD Private) with permissions held constant.
  - `No Access User` — no permission sets. The CRUD/FLS denial persona.

## 8. Framework self-test plan

The framework must catch a rigged security gap, not merely pass clean code. Meta-tests run against
the library's own `Debug_Log__c` object (OWD Private) in a clean scratch org — no org-specific
schema:

| Test | Persona(s) | Scenario | Expected |
| --- | --- | --- | --- |
| Positive path | Library User | insert `Debug_Log__c` via `DMLManager` | `allowed()` passes |
| CRUD denial (write) | No Access User | same | `denied(DMLManager.CRUDException)` passes |
| Read denial (no object perm) | No Access User | `SELECT … WITH USER_MODE` | `denied(System.QueryException)` passes |
| Row visibility (sharing, permissions constant) | Library User (record owner) vs Library Peer | `SELECT … WITH USER_MODE` | owner `returnedRows(n)`; peer `seesNoRows()` |
| Row identity | Library User | read returning known records | `returnedRowIds(expected)` passes; wrong-Id set recorded as mismatch |
| **False-green detection** | No Access User | insert, expectation rigged `allowed()` | matrix FAILS with ledger naming the persona |
| **Missed-denial detection** | Library User | expectation rigged `denied(...)` | matrix FAILS — completing is a mismatch |
| Wrong exception type | No Access User | scenario throws `NullPointerException` deliberately | `denied(CRUDException)` records type mismatch, not pass |
| Unprovisioned persona | any | `.persona()` never provisioned | configuration error before any `runAs` |
| Ledger completeness | 3 personas, 2 rigged to fail | any | aggregate message contains all three lines |
| Ledger cap | many personas, long details | any | message capped with `(+N more…)` tail; full ledger in debug log |
| Limits accounting | any | scenario with known SOQL count | exact delta; `runAs` DML charges excluded |

Denial-message fragments observed in these runs are the **only** sanctioned source for
`messageContains` strings (§5).

Acceptance (measurable): all self-tests green in a scratch org from
`config/project-scratch-def.json`; full suite still ≤ 20 seconds; analyzer at zero gating
violations (with the §11 naming-canon amendment landed); library coverage stays ≥ 85%.

## 9. Out of scope for v1

- **Subclass exception matching.** `denied()` is exact type-name equality. An umbrella match
  (e.g., `DMLManager.DMLManagerException` catching both CRUD and FLS) waits for a proven need and
  the §10 type-name groundwork.
- **CMDT-driven persona registry** (`Test_Persona__mdt`). Attractive for admin-maintained ladders;
  deferred until a second consuming org proves the code-registry shape wrong.
- **Lazy / mid-method provisioning.** Provision-in-`@TestSetup` is the only v1 path.
- **UI-level persona testing** (Provar's territory). This is an Apex-context framework.
- **LWC/Jest side.** Jest has real parameterized tests; a thin per-persona wire-mock convention
  may become a standards entry, not library code.
- **Automatic persona discovery** from permission-set metadata. Personas are declared, not
  inferred — inference would couple tests to incidental org state.

## 10. Platform facts — resolved and remaining

Resolved by the review pass (sources inline above): direct user-mode DML denial surfaces (§5 —
`SecurityException` for object CRUD, `DmlException` for FLS, versioned API 58.0+);
`@TestSetup`-provisioned users/permset assignments are visible to every test method and reset
between methods ([Using Test Setup Methods](https://developer.salesforce.com/docs/atlas.en-us.apexcode.meta/apexcode/apex_testing_testsetup_using.htm));
`Minimum Access - Salesforce` is a standard profile safe to default to with a fail-fast guard
(§7); CPU deltas are reportable as approximate (§6.3); `runAs` counts as a DML statement (§3.3).

Remaining — each changes code if wrong, all closable during implementation:

1. Exact surface of an unshared-record **write** under this stack: `DmlException` with
   `INSUFFICIENT_ACCESS_OR_READONLY` expected — capture type + status code empirically.
2. Type-token comparison mechanics: `String.valueOf(Type)` / `Type.getName()` formatting for
   inner classes (`DMLManager.CRUDException`) vs `Exception.getTypeName()`, including namespace
   prefix behavior in managed contexts.
3. `Database.setSavepoint()` / `rollback` interaction with `runAs` boundaries (gates
   `.rollbackBetweenPersonas()`).
4. `ApexTestResult.Message` effective length (~4,000 chars per third-party describes; no
   first-party citation) — the §8 ledger-cap test is the empirical check.

## 11. Naming, placement, versioning

- Folder: `utilities/testing/persona/`; all classes prefixed `Persona*`; API version 66.0.
- Only classes containing test methods take the `*Test` suffix (`PersonaMatrixTest`); `@IsTest`
  infrastructure uses descriptive names.
- **Required same-PR canon amendment:** [naming.md §10](../standards/naming.md)'s compiled PMD
  `testClassPattern` keys off the `@IsTest` annotation and today admits only
  `(Test|Factory|FactoryDefaults|Stub|Double)`-suffixed (or `Mock`-prefixed) names — every
  Persona-module class would fail the analyzer gate. Amend the pattern with
  `|Persona([A-Z][a-zA-Z0-9]*)?` and record the rationale in naming.md the way the
  `FieldNamingConventions` constants note is recorded. Without this amendment the §8 acceptance
  criterion is unachievable.
- Headers: `@author David Wood`; the full [testing-discipline §1.1](../standards/testing-discipline.md)
  header set including `@see` on every `@IsTest` class (`PersonaMatrixTest` `@see PersonaMatrix`,
  `PersonaOutcome`, …); change-log discipline per
  [documentation §2.1](../standards/documentation.md) (one entry per day, one line preferred).
- Ships as **v1.1.0** — additive, no breaking changes; one CHANGELOG entry.
- Standards impact: [testing-discipline](../standards/testing-discipline.md) gains a §
  "Persona coverage" making the matrix (or its per-method decomposition) the required form for
  any story touching more than one persona — positive and negative expectations both declared.
