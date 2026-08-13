# DevOps & CI/CD — Environments, Version Control, and Release Flow

This file governs how a change travels from a developer's keyboard to production: the branch model, the org ladder each branch deploys to, what belongs in version control, the CI gates every pull request clears (in order), how lower environments get their data, and the cadence and rollback discipline around releases. Read it before creating a sandbox, cutting a branch, or wiring a pipeline stage. Two of the gates it sequences have their own files — [static-analysis.md](./static-analysis.md) and [testing-discipline.md](./testing-discipline.md) — this file defines where those gates sit in the flow, not what they contain.

## 1 Branch model — Gitflow with three permanent boxes

### 1.1 Exactly three permanent branches, each backed by exactly one org

**Rule.** The repository carries three permanent branches, and each maps to one long-lived org. No fourth permanent branch, no branch without an org, no org-backed branch shared by two orgs.

| Branch | Org | What it is |
| --- | --- | --- |
| `main` | Production | What users run. Merges here are releases. |
| `UAT` | Pre-prod sandbox | Business sign-off against production-shaped metadata. |
| `develop` | Integration sandbox | Where parallel workstreams first collide. |

Feature branches cut from `develop`. Story branches cut from their feature branch. Promotion runs one direction only — **story → feature → develop → UAT → main** — and nothing skips a rung. A hotfix is the lone sanctioned short circuit, and it has its own lane (see [§7.1](#71-publish-a-release-calendar-around-the-platforms-seasonal-releases)); it still back-merges to `UAT` and `develop` immediately so the permanent branches never diverge from production.

**Why.** The branch↔org mapping is what makes "where is this change?" answerable by looking at git instead of interrogating orgs. Promotion becomes a merge, not an archaeology dig.

### 1.2 Only the pipeline deploys to a shared org

**Rule.** All three permanent branches are protected: no direct pushes, PR-only, and every merge auto-deploys to the branch's org. No human runs `sf project deploy start` against a shared org — the pipeline is the only principal with deploy credentials there. Personal developer sandboxes and scratch orgs are the only orgs a developer deploys to by hand.

**Why.** A hand deploy to a shared org is how orgs and repos diverge. Once one component in the integration sandbox didn't come from `develop`, git has stopped being the source of truth and every subsequent deploy is a guess.

### 1.3 Feature-level PRs may validate delta; promotions between permanent branches deploy full

**Rule.** A story→feature or feature→develop PR may validate only the changed metadata (delta) for speed. A promotion between permanent branches — develop→UAT, UAT→main — always deploys the full branch contents, never a delta.

**Why.** The asymmetry is deliberate. Delta keeps the feature loop fast; a full promotion deploy is what catches drift — config someone clicked directly into a shared org — because the full deploy reasserts the repo's version of every component. Delta everywhere means drift rides along silently until production.

## 2 The org ladder mirrors the branch ladder

### 2.1 Each tier exists for one job — don't borrow tiers

**Rule.** Run a fixed ladder, and use each tier for the job it exists for:

| Tier | Backing | Job |
| --- | --- | --- |
| Developer sandbox / scratch org | story or feature branch | Build and unit-test in isolation |
| Integration sandbox | `develop` | Cross-stream collision; first full CI gate |
| UAT sandbox (Partial Copy, or seeded) | `UAT` | Business acceptance against realistic data shapes |
| Staging (Full Copy) | refreshed before each major release | Performance testing and final release rehearsal at production scale |
| Production | `main` | Users |

Staging is optional as a permanent fixture but not as a rehearsal step: if you keep only one Full Copy sandbox, reserve it for performance testing and pre-release rehearsal. Burning the org's one Full sandbox on day-to-day development is the classic waste — it takes weeks to earn a refresh and nothing about building features needs production-scale data.

### 2.2 Scratch orgs for disposable source-driven work; developer sandboxes for org-shaped work

**Rule.** Use a scratch org when the work is source-driven and disposable: CI runs, package builds, spikes, and any job where "can this be stood up from the repo alone?" is itself the test. Use a developer sandbox when the work needs the production org's real shape — installed managed packages, org features, integration config — that a scratch definition file deliberately lacks.

**Why.** A scratch org is built from source in minutes and guarantees a clean, reproducible definition — which is exactly why it's the honest test of repo completeness: if the repo can't stand up a working scratch org, the repo is missing something. A sandbox carries everything production carries, including the things nobody remembered to write down. They are complements; treating either as a replacement for the other loses one of the two guarantees.

## 3 The repository is the source of truth

### 3.1 A click below production counts only once retrieved and committed

**Rule.** The source-format repo (`force-app/`, `sfdx-project.json`) is the single source of truth. Any declarative change made in any org below production — a field, a flow, a permission set edit — exists only once it has been retrieved (`sf project retrieve start`), committed, and merged through the normal promotion path. Until then it is a pending change at best and refresh-fodder at worst: the next full promotion deploy ([§1.3](#13-feature-level-prs-may-validate-delta-promotions-between-permanent-branches-deploy-full)) or sandbox refresh erases it.

Commit small and single-purpose — one logical change per commit. Single-purpose commits are what make review, revert, and cherry-pick possible; a 40-component "sandbox sync" commit is unreviewable and unrevertable.

### 3.2 Declare the org-owned metadata boundary as pipeline config

**Rule.** Some metadata is legitimately org-managed, not repo-managed: queues with per-org membership and emails, dashboards admins tune in place, admin-owned list views. Name that boundary explicitly in pipeline configuration — a no-overwrite list the deploy step respects — rather than leaving it as tribal knowledge.

**Why.** Without a declared boundary, either the pipeline clobbers the admins' work on every promotion or developers start hand-tending "just this one component" in shared orgs, and [§1.2](#12-only-the-pipeline-deploys-to-a-shared-org) dies by exception. A written list makes the code-owns/org-owns line reviewable like any other config.

### 3.3 Monitor production for drift on a schedule

**Rule.** Run a scheduled (daily) monitoring job against production: retrieve the metadata, diff it against `main`, and flag any delta; sweep the setup audit trail for unexpected changes; track org limits; and detect callers still on legacy API versions. This is a standing job, not an ad hoc forensic exercise.

**Why.** Production changes made outside the pipeline — an emergency admin edit, a managed-package upgrade — are inevitable. A daily diff answers "who changed what, when" from a git log. Discovering drift during a failed release deploy is the expensive way.

## 4 What belongs in version control — and what never does

### 4.1 Never commit secrets; externalize org-specific values

**Rule.** The following never enter version control, in any branch, ever: credentials, certificates and private keys, connected-app consumer secrets, API tokens. A secret in git is a breach with a timestamp — history survives deletion.

Org-specific *values* (non-secret) don't get committed as constants either; they externalize by kind:

- **Endpoints and outbound auth** — Named Credentials. The repo commits the named credential's shape; each org carries its own endpoint and principal. Code never assembles a URL or auth header from a hardcoded string.
- **Non-secret environment config** — Custom Metadata Types (for example `Integration_Config__mdt`) or hierarchy custom settings, with per-environment values loaded per org rather than committed as one org's truth.
- **Secrets, even "just for the sandbox"** — never in CMDT or custom settings either. Both deploy, export, and diff like any other metadata; a secret stored there is a secret in the repo with extra steps. Named credentials (external credential + principal) are the platform's sanctioned store for integration secrets.

### 4.2 Curate `.forceignore` deliberately and review it like code

**Rule.** `.forceignore` is the membrane between the org and the repo — it decides what retrieval brings in and what deploys push out. Every entry carries a one-line comment saying why it's excluded, and changes to the file get the same review scrutiny as an Apex change.

**Why.** An overgrown ignore file silently excludes metadata someone later assumes is tracked — the repo looks like the source of truth while quietly not being one for whole metadata types. That failure mode is invisible until a new org stands up incomplete.

### 4.3 Track permission sets, not profiles

**Rule.** Permission sets and permission set groups are the tracked, promoted security surface. Profiles stay out of version control except for the minimal surface only a profile can carry (login policy, defaults) — and if a profile must be tracked, trim its XML to that surface so diffs stay reviewable. See [permissions.md](./permissions.md) for the permission-set-first architecture itself.

**Why.** Full profile XML churns on every org change — thousand-line diffs no reviewer reads are worse than no tracking, because they train reviewers to approve without reading. The permset-first security model is also the version-control-friendly one; that alignment is not a coincidence, it's the reason to prefer it here too.

## 5 CI gates, in order

Every PR clears the same three gates, in the same order — cheapest and fastest first, so a violation fails in seconds instead of after a 40-minute test run.

### 5.1 Gate one — static analysis, SPOTLESS

**Rule.** The Code Analyzer gate from [static-analysis.md](./static-analysis.md) runs first on every PR: zero findings at the configured severity threshold, no baseline files, waivers only by the signed inline mechanism defined there. A PR that can't pass the analyzer never gets to spend org time running tests.

### 5.2 Gate two — full test suite, diffed against the known-failures ledger

**Rule.** The full Apex and Jest suite runs on every PR — `RunLocalTests`, never a scoped selection — and CI diffs actual failures against the known-failures ledger exactly as [testing-discipline.md](./testing-discipline.md) defines: a failure not in the ledger blocks; a ledgered failure passes as acknowledged drift; a ledgered test that now passes flags the ledger for pruning.

### 5.3 Gate three — check-only validation against the promotion target

**Rule.** Before any promotion merge (feature→develop, develop→UAT, UAT→main), the pipeline runs a check-only deploy against the target org and posts the result back to the PR:

```bash
sf project deploy validate \
  --target-org <promotion-target> \
  --manifest manifest/package.xml \
  --test-level RunLocalTests
```

No promotion merge happens without a green validation against the org that merge will deploy to. Three specifics that earn their place:

1. **The test level is explicit.** `sf project deploy validate` already defaults to `RunLocalTests`, so the flag isn't rescuing a silent skip on this command specifically — where it matters is consistency across the pipeline: `sf project deploy start` and quick-deploy runs don't carry that same default, and leaving the level implicit on validate is one accident away from an org-config change silently narrowing it. Spelling out `--test-level RunLocalTests` here is belt-and-braces — it makes the gate mean the same thing at every rung regardless of what any single command's default happens to be today.
2. **The result posts to the PR as a comment.** A reviewer who can't see "this validates against the target org" is approving hope, not deployability. Evidence in the PR is part of the gate.
3. **For production, the validation is also the deploy.** A successful validation's job ID stays quick-deployable for 10 days via `sf project deploy quick` — validate during the day, quick-deploy in the release window without re-running the suite.

## 6 Sandbox seeding

### 6.1 Synthetic data only below Full Copy; no production PII below staging

**Rule.** Developer sandboxes, scratch orgs, and the integration org are seeded with purpose-built synthetic datasets — never cloned production data. Production-derived data appears only in Partial and Full Copy tiers, and anything production-derived below the production tier is masked or anonymized on refresh, without exception for regulated data (PHI/PII), which must never exist below the staging tier at all.

**Why.** Synthetic data is small, deterministic, and relationship-complete — which is what tests actually need. An un-anonymized production copy in a lower sandbox is a compliance incident waiting for a refresh: lower tiers have wider access lists, weaker audit posture, and email deliverability accidents ([testing-discipline.md §1.4](./testing-discipline.md) exists because of exactly this class of leak).

### 6.2 Seeding is automated, relational, and deterministic

**Rule.** Seeding runs as a pipeline step, not a manual ritual — SFDMU for relationship-preserving data movement, Snowfakery (or equivalent) for generated volume — so a refreshed or newly created org reaches a known data state from a committed plan file. Hand-seeded orgs drift the same way hand-deployed orgs do; if the seed plan isn't in the repo, the environment isn't reproducible.

## 7 Release cadence and rollback

### 7.1 Publish a release calendar around the platform's seasonal releases

**Rule.** Releases run on a published calendar: a fixed minor-release train (sprint-aligned), scheduled majors, and a defined hotfix lane — all scheduled around Salesforce's three seasonal releases and their sandbox preview windows. The seasonal constraint is real (API version bumps, preview-window sandbox behavior) and belongs in the calendar, not in a surprise.

**Why.** Cadence converts releases from events into routine. A team that releases on a train stops negotiating each release's timing and starts improving each release's mechanics.

### 7.2 Route every change through a tracked work item

**Rule.** Every promotion traces to a work item — a ticket that names the change, its owner, and its acceptance criteria. Ad hoc change sets are not a deployment path. Whether the mechanism is DevOps Center, your git host's issue linkage, or pipeline convention, the invariant is the same: no anonymous metadata in a promotion merge.

### 7.3 Stage destructive changes separately — deletes don't roll back

**Rule.** A release deploy is additive. Component deletions ship in their own follow-up deploy — a `destructiveChangesPre.xml`/`destructiveChangesPost.xml` manifest, generated per delta tooling — after the additive release has soaked in production. Never bundle deletions into the release deploy itself.

**Why.** Rollback for additive changes is cheap: redeploy the prior commit, or quick-deploy the previously validated package. Deletions are not symmetrical — redeploying old source does not restore everything a destructive deploy removed (a deleted roll-up summary field, for one, skips the Recycle Bin entirely, and `purgeOnDelete` bypasses it for everything). Staging deletions behind the soak window means the release itself stays reversible; the irreversible step happens only once the release has proven it no longer needs what it left behind. Use the pre/post split deliberately: pre-destructive for components the additive payload replaces, post-destructive for components whose dependents must deploy first.

TODO: publish a reference GitHub Actions workflow wiring §5's three gates in order, once the repo ships one worth copying.

## Sources

- https://sfdx-hardis.cloudity.com/salesforce-ci-cd-setup-git/ — org-backed protected branches, pipeline-only deploys
- https://sfdx-hardis.cloudity.com/salesforce-ci-cd-config-delta-deployment/ — delta for feature PRs, full for promotions
- https://sfdx-hardis.cloudity.com/salesforce-ci-cd-home/ — no-overwrite list, PR evidence comments, production monitoring
- https://github.com/scolladon/sfdx-git-delta — delta and destructive-manifest generation
- https://gearset.com/blog/salesforce-version-control-best-practices/ — repo as source of truth, never-commit list, `.forceignore`, profile trimming
- https://gearset.com/blog/choosing-the-right-git-branching-strategy-for-your-team/ — branch↔environment mapping
- https://dgt27.com/blog/salesforce-sandbox-strategy/ — environment ladder
- https://www.itransition.com/crm/salesforce/deployment/best-practices — sandbox type per job
- https://developer.salesforce.com/blogs/2024/05/choose-the-right-salesforce-org-for-the-right-job — scratch orgs vs sandboxes
- https://admin.salesforce.com/blog/2023/sandboxes-vs-scratch-orgs-and-how-to-use-them — scratch orgs as complements
- https://architect.salesforce.com/docs/architect/well-architected/guide/secure.html — named credentials as the sanctioned secret store
- https://trailhead.salesforce.com/content/learn/modules/seeding-basics/apply-seeding-best-practices — seeding best practices
- https://jmcloudservices.com/blog/integrate-snowfakery-with-sfdx-data-move-utility-sfdmu-and-automate-salesforce-scratch-org-data-seeding-using-generated-data — SFDMU + Snowfakery pipeline seeding
- https://gearset.com/blog/salesforce-release-management-best-practices/ — release calendar and seasonal-release scheduling
- https://help.salesforce.com/s/articleView?id=platform.devops_center_overview.htm — work-item-driven promotion
- https://developer.salesforce.com/docs/platform/salesforce-cli-reference/guide/cli_reference_project_deploy_validate.html — check-only validation, RunLocalTests default, 10-day quick-deploy window (verified via fetch)
- https://developer.salesforce.com/docs/atlas.en-us.api_meta.meta/api_meta/meta_deploy_deleting_files.htm — destructive-changes manifests, pre/post ordering, Recycle Bin behavior (verified via fetch)
