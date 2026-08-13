# Third-Party Notices

This library is licensed under the MIT License (see [LICENSE](LICENSE)). A small number of
components derive from third-party open-source projects. This file lists each derived component,
its upstream project and license, and where the required in-file notice or attribution lives.
Original code in this repository carries no per-file license text — the repository
[LICENSE](LICENSE) governs it.

## DMLManager family — PatronManager LLC (BSD 3-Clause)

| File | Relationship |
| --- | --- |
| [utilities/dml/DMLManager.cls](utilities/dml/DMLManager.cls) | Derived from PatronManager LLC's `DMLManager` utility. The upstream BSD 3-Clause notice is retained in full at the top of the file, as the license requires. |
| [utilities/dml/DMLManagerTest.cls](utilities/dml/DMLManagerTest.cls) | Derived from the upstream test class. BSD 3-Clause notice retained in full at the top of the file. |
| [utilities/dml/DMLHelper.cls](utilities/dml/DMLHelper.cls) | Contains FLS-inspection and field-caching logic refactored out of `DMLManager.cls`; covered by the same BSD 3-Clause attribution, which remains in `DMLManager.cls`. |
| [utilities/dml/DMLManagerInert.cls](utilities/dml/DMLManagerInert.cls) | Original extension of the `DMLManager.SimpleDML` seam (no upstream code). |
| [utilities/dml/DMLManagerErrorStub.cls](utilities/dml/DMLManagerErrorStub.cls) | Original extension of the `DMLManager.SimpleDML` seam (no upstream code). |

- **Upstream:** `DMLManager` by PatronManager LLC (Patron Holdings)
- **License:** BSD 3-Clause — redistribution requires retaining the copyright notice, the
  condition list, and the disclaimer; the full text lives in the headers of `DMLManager.cls` and
  `DMLManagerTest.cls` and must not be removed.

## TriggerHandler — Kevin O'Hara (MIT)

| File | Relationship |
| --- | --- |
| [utilities/triggers/TriggerHandler.cls](utilities/triggers/TriggerHandler.cls) | Fork of Kevin O'Hara's trigger-dispatcher framework, extended with this library's exception hierarchy, hook ApexDoc, and cache stubs. Attribution is carried in the class header (`@author Kevin O'Hara / David Wood`). |

- **Upstream:** <https://github.com/kevinohara80/sfdc-trigger-framework>
- **License:** MIT

## QuiddityGuard — Salesforce Apex Recipes (CC0 1.0 Universal)

| File | Relationship |
| --- | --- |
| [utilities/triggers/QuiddityGuard.cls](utilities/triggers/QuiddityGuard.cls) | Derived from the `QuiddityGuard` recipe in Salesforce's Apex Recipes sample app. Attribution is carried in the class-header description ("Adapted from the Apex Recipes quiddity sample"). |

- **Upstream:** <https://github.com/trailheadapps/apex-recipes>
- **License:** CC0 1.0 Universal (public-domain dedication; attribution retained as a courtesy)

## Per-file license-tag policy

No class in this repository carries its own `@license` tag. Stray per-file Creative Commons
Attribution 4.0 tags that predated the MIT relicense were removed from
`utilities/general/Utilities.cls` and `utilities/general/UtilitiesHelper.cls` on 2026-08-13; the
repository [LICENSE](LICENSE) is the single license of record for original code, and the sections
above are the record for derived code.
