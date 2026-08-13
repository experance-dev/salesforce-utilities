# Changelog

All notable changes to this library are documented here. One entry per released version; the library versions as a whole (git tags, semver) — individual classes carry their own `@since`/`@last` narrative in their headers.

## v1.0.0 — 2026-08-13

First public release.

- **Standards set** — 18-domain engineering standards under [docs/standards/](docs/standards/), with the quick-reference conventions layer in [docs/best-practices/](docs/best-practices/). The standards cite the shipped classes as their enforcement mechanism; the classes pass the standards' own gates.
- **Library hardening** — nine behavior fixes from the full-library review: access-level enforcement on every DML verb including merge (and genuinely elevated AsSystem paths), a rewritten `RestClient` (named-credential-only, per-instance headers, native PATCH, explicit timeout), a build/dispatch split in `SingleEmail` with a mockable result seam, CSV escaping in `StringBuilder`, a corrected `TestDouble` overload guard, and per-type continue-on-failure log purges.
- **`Debug_Log__c`** — library-owned durable sink for error-severity `Logger` entries, shipped with its retention configuration.
- **Portable test infrastructure** — `TestFactory` defaults carry standard objects only; the suite deploys and runs green in a clean scratch org: 135 tests, 135 passing, ~13 seconds, 87% org coverage.
- **Analyzer-clean** — Salesforce Code Analyzer (Recommended rules) at zero gating violations, with six narrow, justified inline suppressions.
