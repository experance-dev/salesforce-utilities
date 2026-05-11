# salesforce-utilities

A grab-bag of reusable Apex utility classes for the Salesforce platform — DML, logging, triggers, REST callouts, email, test data, and more.

Released into the **public domain** under [The Unlicense](LICENSE) — copy, modify, ship, and sell freely. No attribution required.

## Layout

Everything lives under [utilities/](utilities/), grouped by purpose:

| Folder | Contents |
| --- | --- |
| [utilities/dml/](utilities/dml/) | `DMLManager`, `DMLHelper`, `DMLManagerError`, `DMLManagerInert`, `ConversionFactory` — wrap DML with partial-success / error-collection semantics. |
| [utilities/triggers/](utilities/triggers/) | `TriggerHandler` — standard trigger framework. `QuiddityGuard` / `QuiddityGuardInvocable` — execution-context gating. |
| [utilities/logging/](utilities/logging/) | `Logger` plus [`LogCleanUp/`](utilities/logging/LogCleanUp/) — batchable + schedulable log retention. |
| [utilities/testing/](utilities/testing/) | `TestFactory`, `TestFactoryDefaults`, `TestFactoryRig`, `TestDouble`, `HttpCalloutMockFactory`, `LiveTest`. |
| [utilities/rest/](utilities/rest/) | `RestClient` — outbound HTTP callout helper. |
| [utilities/email/](utilities/email/) | `SingleEmail`, `GroupMemberEmailRetriever`. |
| [utilities/strings/](utilities/strings/) | `StringBuilder`. |
| [utilities/picklists/](utilities/picklists/) | `UtilPickLists` — describe-based picklist value access. |
| [utilities/pricing/](utilities/pricing/) | `PricebookUtil`. |
| [utilities/general/](utilities/general/) | `Utilities`, `UtilitiesHelper` — miscellaneous helpers. |

Test classes live alongside the class they cover (suffix `*Test.cls`).

## Using these in your own org

These are standalone Apex source files (`.cls` + `.cls-meta.xml`), API version 61.0 (60.0 for a few). Pick what you want, drop it into your `force-app/main/default/classes/` directory, deploy. Most files have no inter-dependencies; the `LogCleanUp/*` set depends on `Logger`.

## License

[The Unlicense](LICENSE). Public domain. Do whatever.
