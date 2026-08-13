# Testing Discipline — Test Infrastructure and CI Enforcement

This file governs the infrastructure a test class is built on and the process that runs it in CI: what every `@isTest` class's header must carry, how to keep org-specific test data out of shared test source, the `System.runAs` boundaries required inside `@TestSetup`, safe synthetic test data, and the discipline that keeps a growing suite honest — full-suite runs on every PR, and a known-failures ledger for pre-existing breakage instead of quiet tolerance. Read this alongside [../best-practices/apex-tests.md](../best-practices/apex-tests.md), which covers test-method conventions, the `Assert` class, and fixture patterns; this file covers the infrastructure and process wrapped around those tests.

## 1 Test infrastructure

### 1.1 Every test class header carries a `@see` back to the class under test

**Rule.** Every `@isTest` class carries an ApexDoc header with `@description`, `@group`, **`@see`** (the class or classes under test), `@author`, `@since`, and `@last`. The `@see` tag is non-negotiable — it is what lets a reader, human or AI, scan headers and map test to production code without grepping.

```apex
/**
 * @description Tests for `OrderRouter` — covers per-record rule matching,
 *              idempotency, and bulk routing under USER_MODE.
 * @group Order Management
 * @see OrderRouter
 * @author Jane Developer
 * @since May 2026
 * @last 2026-05-16 — initial coverage for v1 routing rules.
 */
@isTest
private class OrderRouterTest { ... }
```

When a test class covers more than one production class, list each on its own `@see` line. The rendered ApexDoc table then shows the full test-to-code map at a glance, instead of requiring a reader to open the class body to find out what it's testing.

### 1.2 Keep org-specific test data out of shared test source — inject it through a defaults layer

**Rule.** A test class that ships in a shared library — a DML wrapper's test, a logging utility's test, a general-helper's test — constructs its records through a factory (`TestFactory.createSObject(record, doInsert)`), never with inline field assignments that only satisfy one org's validation rules. Org-specific field defaults (the values needed to clear a particular org's validation rules, required fields, or record-type dependencies) live in that org's own defaults implementation, layered on top of the shared factory rather than hardcoded into the shared test. The same test source then compiles and passes in the library's own scratch org and in any consuming org, because neither one had org-specific assumptions baked into the test body.

**Why.** A test that hardcodes `Order__c.Region__c = 'Northeast'` to satisfy one org's validation rule breaks the moment that test class ships into an org without a `Region__c` field, or with a validation rule that rejects `'Northeast'`. Push the org-specific values down into a per-object defaults class instead — the shared test only ever asks the factory for "a valid record of this type," and the factory's registered defaults decide what "valid" means for the org it's running in.

```apex
// Shared test source — no org-specific field values
Order__c ord = (Order__c) TestFactory.createSObject(new Order__c(), true);

// Org-specific defaults, layered on top of the shared factory —
// this is where a given org's validation-rule requirements get satisfied
public class OrderDefaults implements TestFactory.FieldDefaults {
    public Map<Schema.SObjectField, Object> getFieldDefaults() {
        return new Map<Schema.SObjectField, Object>{
            Order__c.Status__c => 'Draft',
            Order__c.Region__c => 'Northeast' // satisfies this org's VR, nowhere else
        };
    }
}
```

See [`TestFactory.cls`](../utilities/testing/TestFactory.cls) for the `createSObject` auto-discovery mechanism, and [`TestFactoryDefaults.cls`](../utilities/testing/TestFactoryDefaults.cls) for the per-SObject `FieldDefaults` implementation pattern. A single, well-documented defaults class that neutralizes dozens of org-specific validation rules through registered field defaults — with an inline comment explaining any rule that genuinely can't be satisfied that way — beats scattering ad hoc field assignments across every test that happens to touch the object.

### 1.3 `@TestSetup` DML on setup objects runs under an explicit admin context

**Rule.** `User`, `PermissionSet`, `PermissionSetAssignment`, and `ObjectPermissions` are Salesforce "setup objects" — DML on them inside `@TestSetup` (or anywhere in a test) must run under `System.runAs(adminUser)`. Non-setup DML inside the same `@TestSetup` method runs under `System.runAs(runningUser)` — a separate, explicit test user, not the setup-object admin. Keeping the two DML boundaries separate is what satisfies Salesforce's `MIXED_DML_OPERATION` rule regardless of what triggers or platform automation the org runs.

```apex
@TestSetup
static void setup() {
    // Setup-object DML: must run under an explicit admin context.
    User adminUser = TestFactory.createTestUser(true, 'System Administrator');

    // Non-setup DML: runs under the test's own running user, not the admin.
    System.runAs(TestFactory.getTestUser('Standard User')) {
        TestFactory.createSObject(new Order__c(), true);
    }
}
```

See [`TestFactory.cls`](../utilities/testing/TestFactory.cls)'s `createTestUser` implementation — it wraps its own `User` insert in `System.runAs(getAdminUser())` internally, so callers get the MIXED_DML boundary for free instead of having to remember it at every call site.

### 1.4 Synthetic test-data emails use the `.invalid` reserved TLD

**Rule.** Every email address generated in an `@isTest` factory, fixture, or `@TestSetup` method uses the `.invalid` TLD reserved by [RFC 2606](https://datatracker.ietf.org/doc/html/rfc2606#section-2) — typically `<prefix>-<unique>@example.invalid`. Never `@gmail.com`, never your own company's real domain, and never `@example.com` — that domain is reserved but it does resolve.

**Why.** `.invalid` is the one TLD that cannot resolve to a real mailbox by DNS construction. If a production code path ever escapes its mock seam during a test run — directly via `Messaging.sendEmail`, or indirectly through a workflow, flow, or trigger that sends email — the address fails delivery at the resolver, never at a real inbox. Combined with a rule that test code must never actually dispatch email, this is the belt-and-suspenders boundary: the test shouldn't send, and if it somehow did, the address can't reach anyone.

```apex
// Good
String email = 'order-test-' + String.valueOf(Crypto.getRandomInteger()) + '@example.invalid';

// Bad — these CAN resolve to real mailboxes
String email = 'test@example.com';        // reserved, but DOES resolve
String email = 'test@gmail.com';          // real domain
String email = 'test@yourcompany.com';    // confused-real-domain — never seed a real company domain in test data
```

Seed this pattern once in your org's [`TestFactoryDefaults.cls`](../utilities/testing/TestFactoryDefaults.cls) per-SObject defaults, so every generated record gets a safe email without each test author having to remember the rule.

---

## 2 CI test discipline

### 2.1 Every CI run executes the full suite — never a scoped run

**Rule.** CI runs the entire Apex and Jest suite on every PR:

```bash
sf apex run test --target-org <ci-target> \
  --test-level RunLocalTests --wait 60 --result-format human
npx sfdx-lwc-jest
```

Always the full suite. Never a scoped "run only the tests I touched" mode. A PR that only runs its own tests hides regressions it introduced in code it didn't directly change — a shared utility, a trigger side effect, a cross-object dependency.

### 2.2 Track pre-existing failures in a known-failures ledger, not silence

**Rule.** A living suite inherited from years of prior work will have some failures that predate the current PR and aren't fixable in it. Don't let those failures either block every unrelated PR or get silently ignored — track them explicitly in a known-failures ledger, and have CI diff actual failures against it.

**Ledger columns:**

| Column | Required | Notes |
| --- | --- | --- |
| Test class | always | |
| Method | always | |
| Severity | always | one of the categories below |
| Reason | always | one-sentence root cause |
| Owner | always | who's accountable for the eventual fix |
| Tracker ref | always | ticket ID, or `none` |
| Expected fix | always | sprint/milestone reference, or `indefinite` with a stated rationale |

**Severity categories** (Apex-test-shaped, not exhaustive — extend as your suite's real failure modes emerge):

| Severity | Typical cause |
| --- | --- |
| `UNABLE_TO_LOCK_ROW` | Row-lock contention from parallel test execution |
| `MIXED_DML` | Setup-object DML not isolated per §1.3 |
| `NO_SINGLE_MAIL_PERMISSION` | Test user lacks the Single Email permission a code path requires |
| `FIELD_NOT_FOUND` | Test assumes a field the target org doesn't have |
| `ASSERTION_FAILED` | Genuine behavioral drift between test expectation and code |
| `OTHER` | Anything not covered above — the reason column carries the real detail |

**CI comparison logic:**

| Outcome | Gate |
| --- | --- |
| Fail not in ledger | BLOCK — new regression |
| Fail in ledger | passes — acknowledged drift |
| Ledgered test now PASSES | flag — ledger needs pruning; the PR description must note the removal |
| All pass, ledger empty | release-ready — the goal state |

A ledger entry is a deliberate, visible concession, not a way to make CI quiet. The comparison logic is what keeps it honest in both directions: a new failure still blocks, and a fixed failure gets noticed instead of just quietly staying in the ledger forever.

### 2.3 Adding a ledger entry requires sign-off, not just categorization

**Rule.** A failure becoming "known" is a deliberate decision, not a default. Three steps, in order:

1. Categorize the root cause (see §2.4 for how to do this at scale).
2. Open a ticket in your tracker for the underlying fix — a ledger entry with no tracker ref is a fix nobody's actually committed to making.
3. A designated owner — the standards owner, tech lead, or whoever holds the quality bar for the codebase — signs off, verifying the failure is legitimate drift and not a real bug being quietly papered over.

Only then does the row land, with every column filled. No half-entries — a row missing owner, tracker, or expected-fix is not yet a ledger entry, it's an unreviewed failure someone forgot to finish tracking.

### 2.4 Pareto-categorize before canonizing a wall of failures

**Rule.** When a dependency bump, a schema change, or a baseline reload drops dozens of failing tests into a suite at once, don't triage them one at a time. Categorize first:

1. Read one or two failure messages per failing class.
2. Group the failures into a handful of buckets by apparent cause.
3. Identify the two or three patterns that account for most of the volume.
4. Write one ticket per pattern — not one ticket per failing test.
5. Canonize each individual failure in the ledger, pointing its "reason" and "tracker ref" at the pattern ticket that covers it.

Genuine long-tail failures — one-off per class, sharing no pattern with anything else — get individual ledger entries with their own tracker refs.

**Why.** Handing a developer sixty individually-listed failing tests produces a developer who fixes six of them and gives up. Handing them three pattern tickets and a ledger entry per failure that traces back to one of those three tickets produces a developer who can see the actual shape of the problem and close it in three focused changes instead of sixty scattered ones.

---

**Summary of the layering:** §1 is about what a test *is* — a header that tells a reader what it covers, org-independent construction so the same test source travels between environments, DML boundaries that satisfy platform rules, and test data that can never reach a real inbox. §2 is about what CI *does* with the suite those tests form — run all of it, every time, and treat any failure that isn't fixed in the PR that introduced it as a tracked, owned, sign-off-gated concession rather than either a hard block or a silent pass.
