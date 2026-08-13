# Static Analysis — Code Analyzer Gate and Waiver Discipline

This file governs how automated static analysis enforces code quality on every change: the merge-gate severity threshold, where the analyzer runs, how a finding earns a narrow signed waiver instead of being silently tolerated, why baseline files are rejected outright, and the shell-scripting discipline that keeps a gate script from silently passing when it should fail. Read this before wiring an analyzer step into CI, before suppressing any finding, and before writing any script whose exit code decides whether a merge is allowed.

## 1 Run the analyzer at every gate; the severity threshold is SPOTLESS

**Rule.** [Salesforce Code Analyzer v5](https://developer.salesforce.com/docs/platform/salesforce-code-analyzer/overview) runs on every pull request. Its bundled rule engines — PMD, ESLint, RetireJS, CPD, and the Salesforce Graph Engine's data-flow analysis (DFA) — catch a class of defect that human review systematically misses: CRUD/FLS gaps, SOQL injection surfaces, dead code, complexity blowups, vulnerable third-party JS dependencies. The bar is SPOTLESS: zero findings at the gate's configured severity threshold, at every gate site, every time — not "no new findings since the last run."

| Severity | Pre-commit | CI | Owner action |
| --- | --- | --- | --- |
| **sev1 (Critical)** | BLOCKS | BLOCKS | Author fixes before commit / before re-requesting review |
| **sev2 (High)** | BLOCKS | BLOCKS | Author fixes; pre-commit catches it locally |
| **sev3 (Medium)** | BLOCKS | BLOCKS | Author fixes; pre-commit catches it locally |
| **sev4 (Low)** | passes (speed) | BLOCKS | Author fixes before merge; CI is the gate |
| **sev5 (Info)** | passes | passes (logged) | Surfaced if a pattern recurs — enough instances earn a standards-doc entry or a scoped waiver |

Pre-commit trades a little rigor for speed — it blocks sev1–sev3 and lets sev4 through so a local commit doesn't stall on a slow full-severity scan. CI closes that gap and blocks sev1–sev4; sev5 is logged, never gating. If your code ships into a downstream deployment pipeline that runs its own analyzer pass on top of yours, a spotless local gate is what keeps you from bouncing at theirs — you don't control their threshold, so leave yourself zero margin to violate at your own.

## 2 Run it at three sites: local, CI, and a periodic full sweep

1. **Developer pre-PR (local).** The author runs the analyzer before opening a PR; sev1–sev3 must be clean before the PR opens at all.
2. **CI gate on push (load-bearing).** A CI workflow — conventionally `.github/workflows/code-analyzer.yml` — runs on every push to protected branches (feature branches, the integration branch, a staging/UAT branch, and the production branch). Its report posts back to the PR as a comment so reviewers see findings without leaving the PR page.
3. **Periodic full-repo sweep (drift).** Independent of any single PR, a designated reviewer runs the analyzer across the whole codebase on a cadence — weekly is a reasonable default. New MEDIUM+ findings, growth in LOW-severity patterns, and any DFA findings get triaged from this sweep. The sweep exists because PR-scoped runs only ever see the diff; a class that was clean when it merged can still accumulate findings as the rules or the surrounding code evolve.

Raw scan output (`reports/scanner-<context>.{html,json}`) is regenerable and gitignored — don't commit it. The sweep's triage summary is different: it's a decision record, so it gets committed (for example, under `docs/standards/code-reviews/<date>-analyzer-sweep.md`).

## 3 Waivers are narrow and signed; the default is "fix, not waive"

**Rule.** A waiver is not a way to make a real finding go away quietly. When a finding is a genuine false positive for your codebase's architecture, the standards owner signs the waiver, and the canonical reason lands in this document — not in a Slack thread, not in a commit message. Suppression scope is narrow: file-level or rule-level, never a blanket class- or project-wide suppression. If the standards owner won't sign it, the finding is real — fix the code.

Each waiver below follows the same shape: rule name, scope, why, and how to apply it. New waivers land here before the PR that needs them merges — see [§4](#4-a-new-waiver-lands-in-this-document-before-its-pr-merges).

### 3.1 `ApexDoc` — waive only on private, self-documenting helpers

**Rule.** Every public method — and every `global` or `@AuraEnabled` method — carries ApexDoc. A project-wide suppression of the `ApexDoc` rule is not a valid shortcut; it hides a real documentation gap on every method visibility tier that actually needs one.

**Scope of the narrow waiver.** `private static` helpers and trivially named accessors only, where the method-level ApexDoc would add nothing the signature doesn't already say. A method like `private static String collectContactIds(List<Order__c> orders)` doesn't need a comment restating "collects contact IDs from a list of orders" — the name already says it.

**How to apply.** Inline `@SuppressWarnings('PMD.ApexDoc')` on the specific `private static` method. Never suppress at the class level.

### 3.2 `EagerlyLoadedDescribeSObjectResult` — waive for the schema-describe-guard pattern

**Why.** PMD flags `Schema.SObjectType.X.getDescribe().fields.getMap()`-style calls as eagerly loading describe metadata. A cross-permission-set `isAccessible()` guard — checking field-level access before issuing a `WITH USER_MODE` query on a feature-gated field a caller might lack FLS for — requires exactly this describe call. There's no lighter-weight way to ask "can the running user see this field" before the query runs.

```apex
public static Set<Id> collectFeatureFlaggedIds(Set<Id> accountIds) {
    if (!Schema.sObjectType.Order__c.fields.Feature_Flagged_Lookup__c.isAccessible()) {
        return new Set<Id>(); // No FLS on the gated field — nothing to process.
    }
    // ... WITH USER_MODE query against Feature_Flagged_Lookup__c
}
```

**Scope.** Methods that follow the canonical shape: describe call → `isAccessible()` short-circuit → `WITH USER_MODE` SOQL. See the guard pattern itself in [security-sharing.md](security-sharing.md).

**How to apply.** Inline `@SuppressWarnings('PMD.EagerlyLoadedDescribeSObjectResult')` at the method, with a one-line comment pointing back to this section.

### 3.3 `FieldNamingConventions` — waive for `SCREAMING_SNAKE_CASE` constants

**Why.** PMD's `FieldNamingConventions` rule expects camelCase on every field. `private static final` compile-time constants (`MAX_VISIBLE_TOPICS`, `STATUS_RESOLVED`, `PATH_INTEGRATION_LOG`) conventionally use `SCREAMING_SNAKE_CASE` — that's the standard Apex idiom for a constant, and it's what every reference codebase ships.

**Scope.** `private static final` constants only. Instance fields and method parameters still follow camelCase; this waiver doesn't extend to them.

**How to apply.** Rule-level `@SuppressWarnings('PMD.FieldNamingConventions')`, scoped to the constant declaration or the class if every constant in it follows the convention.

### 3.4 A revoked waiver stays documented, not deleted

**Rule.** When a waiver's underlying finding becomes a real violation instead — because the code pattern it excused is now itself prohibited — revoke the waiver but keep its heading in this document, with the revocation explained in place of the old rationale. Existing code comments and PR history that cite the old section number should resolve to the revocation, not to a broken reference.

**Example shape.** A waiver that suppressed a CRUD-violation finding on Custom Metadata Type SOQL (justified at the time as "filtering server-side is cheaper than filtering in Apex") gets revoked once the canon prohibits CMDT SOQL outright — see the CMDT carve-out in [security-sharing.md](security-sharing.md). Once that canon lands, any remaining SOQL against a `__mdt` object isn't a finding to suppress anymore; it's a violation to fix. The heading for the old waiver stays, its body now says so.

### 3.5 Waivers on vendored test-infrastructure findings stay narrow and point upstream

**Why.** Shared test-infrastructure classes — a fixture factory, its per-org defaults layer, an HTTP callout mock factory — sometimes carry analyzer findings that are intentional for `@IsTest`-only infrastructure: bare DML to seed fixtures, non-`USER_MODE` SOQL against standard objects (`Profile`, `User`) while resolving `@TestSetup` identity, or an eagerly loaded describe inside a dynamic-dispatch helper. If that infrastructure ships from a shared library you consume rather than own, patching it locally to satisfy your analyzer creates local drift from the upstream source and has to be redone on every update. The fix belongs upstream, in the library itself.

**Scope.** Findings inside vendored test-infrastructure classes only — for example [`TestFactory.cls`](../utilities/testing/TestFactory.cls), [`TestFactoryDefaults.cls`](../utilities/testing/TestFactoryDefaults.cls), and [`HttpCalloutMockFactory.cls`](../utilities/testing/HttpCalloutMockFactory.cls) — never on test classes you own and author yourself. Your own test classes follow the project's ordinary USER_MODE/DML-manager discipline; this waiver doesn't extend to them.

**How to apply.** Inline `@SuppressWarnings('PMD.<RuleName>')` on the specific method, with a one-line comment: `// PMD waiver per §3.5: vendored @IsTest infrastructure; fix belongs upstream`. File the upstream issue rather than letting the suppression stand in for it indefinitely.

### 3.6 Class-level complexity waivers for legitimate facade classes

**Why.** Per-method complexity budgets (see the complexity budget table in [apex.md](../best-practices/apex.md)) are the real shape signal for depth-of-logic. A facade class — an `@AuraEnabled` LWC controller exposing many narrow operations, a `@RestResource` endpoint routing several HTTP verbs, a service implementation aggregating per-operation delegation to selectors and DTO assemblers — can legitimately accumulate class-level cyclomatic or cognitive complexity above budget while every individual method stays under it. The class total reflects breadth of public surface, not depth of logic in any one method. Extracting `*Helper` classes purely to satisfy the class-level number fragments a facade's natural surface and hides where the actual public contract lives.

**Scope.** A class qualifies only if it satisfies all three:

1. **The public surface is many narrow operations** — `@AuraEnabled`, `@HttpPost`/`@HttpGet`/etc., or service-interface methods, each individually under the per-method budget.
2. **No single method violates the per-method budget** — the class total is the only finding; every method is clean on its own.
3. **Decomposition would create a parallel-class pattern with no architectural justification** — the alternative is N `*OperationHandler` classes standing in for a facade that's already the right shape.

**A waiver can be temporary and conditional.** If a facade class has accumulated complexity because it's aggregating several distinct concerns that genuinely belong in separate sub-controllers, the waiver can cover it until the decomposition ships, then get revoked once the sub-controllers exist and each fits its own budget without help. Name that condition explicitly in the waiver entry so it doesn't quietly become permanent.

**How to apply.** Class-level `@SuppressWarnings('PMD.CyclomaticComplexity,PMD.CognitiveComplexity')` with a one-line comment: `// PMD waiver per §3.6: facade aggregates N narrow operations; per-method budgets satisfied`. The comment makes the suppression auditable at the class header without sending a reader back to this document.

### 3.7 Class-level complexity waivers for framework lifecycle-hook classes

**Why.** A framework class whose job is lifecycle-hook orchestration — priming a bulk cache, applying defaults, dispatching to predicates, decorating records pre- or post-DML — accumulates class-level complexity as it grows hooks. Each hook is a small, single-purpose method; the class total reflects breadth of extension points, not depth of logic. Splitting hooks into separate classes would break the framework's contract, since consumers expect one class to dispatch every lifecycle phase — the same reason a `Database.Batchable` implementation legitimately groups `start`/`execute`/`finish` in one class, as in [`LogCleanupBatch.cls`](../utilities/logging/LogCleanUp/LogCleanupBatch.cls), rather than splitting each phase into its own class.

**Scope.** A framework class in a clearly framework-shaped directory (retention, triggers, batch orchestration) qualifies if:

1. **Each public method is a lifecycle hook** (`primeBulkCache`, `applyDefaults`, `validate`, `decorate`, `dispatch`, and similarly-shaped methods).
2. **Per-method complexity is under budget** — the class total is the only finding.
3. **The dispatch shape is the framework's contract** — splitting hooks across classes would break how consumers extend it.

**New framework classes default to no waiver.** This waiver covers an *existing* framework class that grows past budget as it picks up legitimate new extension points. It is not a starting allowance for a brand-new framework class — design hook dispatch to stay under budget from day one, typically by splitting per-phase concerns across multiple interfaces a consumer composes.

**How to apply.** Class-level `@SuppressWarnings('PMD.CyclomaticComplexity')` with: `// PMD waiver per §3.7: framework dispatches N lifecycle hooks; per-method budgets satisfied`.

### 3.8 No baseline files — ever

**Rule.** No baseline artifact (`scanner-baseline.json`, `.code-analyzer-baseline.yml`, or any file that records "these findings are pre-accepted; only *new* findings block") is permitted. The SPOTLESS bar from [§1](#1-run-the-analyzer-at-every-gate-the-severity-threshold-is-spotless) means zero findings at the configured severity threshold at every gate site — every time, not just on the delta since a snapshot. The analyzer's `--severity-threshold` flag and the inline `@SuppressWarnings` waivers in [§3.1–3.7](#3-waivers-are-narrow-and-signed-the-default-is-fix-not-waive) are the only sanctioned suppression mechanisms.

**Why a baseline is rejected, not just deferred:**

1. **A baseline is retroactive ratification.** There is no fuckup-forgiveness mechanism in this canon. A baseline file is exactly that: an opaque snapshot of "findings we're willing to accept today because we already shipped them." The inline-waiver path is the only sanctioned exception, and it's pre-emptive — named scope, signed entry, cited at the call site — not a bulk grandfather clause.
2. **A baseline is invisible to the next author.** `@SuppressWarnings('PMD.<Rule>') // §3.N: <reason>` is greppable, visible in code review, and forces the author to name the rule and the rationale at the point of use. A baseline file is a JSON blob nobody writing new code ever opens. Drift is silent.
3. **A baseline weakens the gate it's attached to.** Once a baseline exists, the operative threshold quietly becomes "no *new* findings" — strictly weaker than SPOTLESS. If your code also passes through a downstream deployment pipeline that runs the analyzer fresh against its own threshold, your baseline buys you nothing there — it lets you pass your own CI and then bounce at theirs.
4. **A large pre-existing finding count is sweep work, not baseline material.** If a rule change (like revoking a broad `ApexDoc` suppression) suddenly surfaces hundreds of findings, that's a scheduled, owned sweep-toward-spotless effort with a tracked completion state — not a permanent acceptance wearing a baseline file's clothes.

**What this rules out concretely:**

- `sf code-analyzer run --baseline-file <path>` or any equivalent flag.
- A checked-in `reports/scanner-baseline.{json,yml}` artifact that CI reads.
- A workflow step that diffs current findings against a prior run and only blocks on the delta.
- Any configuration record — CMDT, Custom Setting, or otherwise — that toggles "ignore pre-existing findings."

**What's still allowed:**

- Inline `@SuppressWarnings('PMD.<RuleName>')` with a one-line comment citing the waiver section that justifies it.
- `--severity-threshold` tuning per gate site (looser at pre-commit for speed, strictest at CI) — that's gate shape, not a baseline.
- New waiver sections for genuinely canonical exceptions, surfaced pre-emptively per [§4](#4-a-new-waiver-lands-in-this-document-before-its-pr-merges), never retroactively.

## 4 A new waiver lands in this document before its PR merges

**Rule.** A waiver isn't valid until it's documented with a rule name, scope, why, and how to apply it — following the shape in [§3](#3-waivers-are-narrow-and-signed-the-default-is-fix-not-waive). The PR that needs the waiver points at the new section in its description. The standards owner signs by approving that standards-doc edit alongside the code change, not after the fact.

If the standards owner won't sign it, the finding is real — fix the code.

## 5 Shell scripts that drive a merge gate must preserve the real exit code

**Rule.** Every shell script that invokes `sf code-analyzer run` — or any command whose exit code decides a merge — starts with `set -o pipefail` (or `set -eo pipefail` for the stricter version). When analyzer output is piped through a display command (`| tail`, `| grep`, `| jq`), a POSIX shell's `$?` captures the *last* command's exit code in that pipeline, not the analyzer's. The analyzer's real exit code is silently discarded, and any downstream `[ $STATUS -ne 0 ] && exit $STATUS` block becomes dead code. The gate fires but never actually gates.

**Why this is load-bearing.** Without `pipefail`, every severity threshold from [§1](#1-run-the-analyzer-at-every-gate-the-severity-threshold-is-spotless) is theater. You can tune the threshold, canonize waivers, and run a weekly sweep — none of it matters if the shell wrapper returns `0` on every run because the display pipe exits `0`.

**Companion rule — `--target` takes repeatable flags, not a comma-joined value.** `sf code-analyzer run --target` (`-t`) expects the flag repeated once per path, not a single comma-joined string. A comma-joined value produces a literal filename containing commas that matches nothing on disk — the analyzer silently scans zero files and exits `0`. Paired with a missing `pipefail`, the gate fails silently twice over: once because it scanned nothing, and again because the wrapper couldn't have surfaced that failure even if it had one.

**Pattern:**

```bash
#!/usr/bin/env sh
set -o pipefail   # critical — pipeline exit codes propagate

# Build repeatable --target flags; one -t per file
TARGET_ARGS=""
for f in $STAGED_APEX; do
    TARGET_ARGS="$TARGET_ARGS --target $f"
done

sf code-analyzer run \
    --workspace force-app/main/default \
    $TARGET_ARGS \
    --severity-threshold 3 \
    --output-file "reports/scanner-pre-commit-$(git rev-parse --short HEAD).json"
STATUS=$?

# Display only — never use the display pipe's exit code as the gate signal
sf code-analyzer run ... | tail -12 || true

[ $STATUS -ne 0 ] && exit $STATUS
```

**Applies to every gate script** — a pre-commit hook, a CI workflow step, or any future shell-shaped gate. The defect class is shell-portable; canonize the rule once and it catches the bug everywhere a pipe touches a gating exit code.

**Prove the gate gates.** Any PR that introduces or changes a gate script includes a test plan in its description: stage one violation at each severity the script claims to block, confirm the script exits non-zero before the fix and zero after. "I think it works" without a demonstrated red case is exactly how a gate silently stops gating — a documented test plan at review time is what catches it before the gate ships broken.
