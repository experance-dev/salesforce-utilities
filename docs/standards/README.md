# Salesforce Engineering Standards

A full, opinionated standards set for building on the Salesforce platform. Each file governs one domain, states its rules imperatively (**Rule** first, then **Why**, then a worked example where it earns its place), and is written to be enforceable — in code review, by the [static analyzer gate](static-analysis.md), or by CI. The companion [best-practices/](../best-practices/README.md) folder is the quick-reference conventions layer; these files are the deep standards behind it. Code examples reference the shipped [utilities](../../utilities/) classes, which exist precisely to make these rules cheap to follow.

## Core code standards

| Domain | File |
| --- | --- |
| Layering — Selector / Service / Domain | [architecture-layering.md](architecture-layering.md) |
| Sharing & permission enforcement in code | [security-sharing.md](security-sharing.md) |
| Exception handling & logging | [observability.md](observability.md) |
| Trigger framework | [triggers.md](triggers.md) |
| Async patterns — future / queueable / batch / schedulable | [async.md](async.md) |
| Lightning Web Component patterns | [lwc-patterns.md](lwc-patterns.md) |

## Platform boundaries

| Domain | File |
| --- | --- |
| Flow vs. Apex — the decision boundary | [flow-vs-apex.md](flow-vs-apex.md) |
| Permission-set-first security architecture | [permissions.md](permissions.md) |
| SObject & field design | [data-model.md](data-model.md) |
| Naming — objects, fields, classes, permsets, flows | [naming.md](naming.md) |

## Integration

| Domain | File |
| --- | --- |
| Inbound REST endpoints | [integration-rest.md](integration-rest.md) |
| Integration architecture — events, CDC, callouts | [integration-architecture.md](integration-architecture.md) |

## Quality gates

| Domain | File |
| --- | --- |
| Test infrastructure & CI test discipline | [testing-discipline.md](testing-discipline.md) |
| Static analysis as a merge gate | [static-analysis.md](static-analysis.md) |
| Headers, ApexDoc & change-log discipline | [documentation.md](documentation.md) |

## Lifecycle

| Domain | File |
| --- | --- |
| Data retention & subject erasure | [data-retention-erasure.md](data-retention-erasure.md) |
| Environments, version control & release flow | [devops-cicd.md](devops-cicd.md) |
| AI-era readiness — Agentforce / Einstein / Data Cloud | [ai-readiness.md](ai-readiness.md) |

## How to adopt

Adopt the quality gates first — [static-analysis.md](static-analysis.md) and [testing-discipline.md](testing-discipline.md) make every other standard enforceable rather than aspirational. Then take the core code standards as a unit (they assume each other: layering assumes the trigger framework, security assumes the DML wrapper). The platform-boundary and lifecycle files stand alone and can be adopted per-team.

Deviations are handled the way [static-analysis.md](static-analysis.md) handles waivers: narrow, written, signed by the standards owner — the default is fix, not waive.
