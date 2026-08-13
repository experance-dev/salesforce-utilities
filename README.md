# salesforce-utilities

Reusable Apex utility classes for the Salesforce platform — DML, logging, triggers, REST callouts, email, test infrastructure — shipped together with the full [engineering standards](docs/standards/README.md) they enforce. The standards cite these classes as their enforcement mechanism, and the classes pass the standards' own gates: the whole library deploys and runs green in a clean scratch org (135 tests, ~13 seconds, 87% coverage) and holds the Salesforce Code Analyzer at zero gating violations.

## Layout

| Folder | Contents |
| --- | --- |
| [docs/standards/](docs/standards/) | The full standards set — 18 domains from layering and security to naming, DevOps, and AI-readiness. |
| [docs/best-practices/](docs/best-practices/) | The quick-reference conventions layer (Apex, tests, LWC, architecture). |
| [utilities/dml/](utilities/dml/) | `DMLManager`, `DMLHelper`, `DMLManagerInert` — one audited DML chokepoint with USER_MODE/SYSTEM_MODE enforcement on every verb, merge included; `DMLManagerErrorStub` — error-injecting test stub. |
| [utilities/triggers/](utilities/triggers/) | `TriggerHandler` — one-trigger-per-object framework. `QuiddityGuard` / `QuiddityGuardInvocable` — execution-context gating. |
| [utilities/logging/](utilities/logging/) | `Logger` — error-severity entries persist to the shipped `Debug_Log__c` object; [`LogCleanUp/`](utilities/logging/LogCleanUp/) — CMDT-driven, batchable log retention that survives a stuck record. |
| [utilities/testing/](utilities/testing/) | `TestFactory` + `TestFactoryDefaults` — portable test-data factory (standard objects only; extend per org); `TestDouble` — stub framework; `HttpCalloutMockFactory` — request-capturing callout mock. |
| [utilities/rest/](utilities/rest/) | `RestClient` — named-credential-only HTTP client: per-instance headers, native PATCH, explicit timeouts, sanitized errors. |
| [utilities/email/](utilities/email/) | `SingleEmail` — build/dispatch split with a mockable result seam; `GroupMemberEmailRetriever`. |
| [utilities/strings/](utilities/strings/) | `StringBuilder` — string, field-list, and CSV assembly with real escaping. |
| [utilities/picklists/](utilities/picklists/) | `UtilPickLists` — describe-based picklist value access. |
| [utilities/pricing/](utilities/pricing/) | `PricebookUtil`. |
| [utilities/general/](utilities/general/) | `Utilities`, `UtilitiesHelper` — fake IDs, describe helpers, collection utilities. |
| [utilities/objects/](utilities/objects/), [utilities/permissionsets/](utilities/permissionsets/), [utilities/customMetadata/](utilities/customMetadata/) | The metadata the classes read: `Debug_Log__c`, the Logger/retention configuration types and records, and the permission sets the test factory assigns. |

Test classes live alongside the class they cover (suffix `*Test.cls`); API version 66.0.

## Using this in your own org

This is a deployable SFDX project — the fastest proof is a scratch org:

```bash
sf org create scratch -f config/project-scratch-def.json -a utils -v <your-devhub>
sf project deploy start -o utils
sf apex run test -o utils --test-level RunLocalTests --code-coverage
```

Cherry-picking is still fine, with two notes: the logging set (`Logger`, `LogCleanUp/*`) expects its objects and CMDT from `utilities/objects/` and `utilities/customMetadata/`, and `TestFactory` expects the two permission sets from `utilities/permissionsets/`. Everything else is close to standalone.

## Versioning

The library versions as a whole — semver git tags, one [CHANGELOG.md](CHANGELOG.md) entry per release. Individual classes carry their own `@since` / `@last` narrative in their headers. Current release: **v1.0.0**.

## License

[MIT](LICENSE) — use it freely, keep the copyright notice. The `DMLManager` family retains its original PatronManager BSD header under that code's own terms.
