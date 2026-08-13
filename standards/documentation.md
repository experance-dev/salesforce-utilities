# Documentation — Headers, Attribution & Comment Discipline

This file governs what goes in a class or component's header, how authorship and change history are recorded there, and which methods carry ApexDoc or jsdoc versus which are left to their names. Read it before shipping a new Apex class or LWC, and before reviewing a PR that adds or touches either.

## 1 Header attribution

### 1.1 Attribute every shipped class to the human author of record

Every shipped Apex class header and every LWC file's `@author` line names the human author of record — the person accountable for the artifact, not a tool, a bot identity, or a rotating session label. Headers are provenance for whoever debugs this in production eighteen months from now; "who do I ask about this" has to resolve to one real person, consistently, across the whole codebase.

```apex
/**
 * @description Coordinates discount eligibility checks and applies the winning tier to an order.
 * @group Service
 * @author Jane Developer
 * @since June 2026
 * @last June 2026 — initial ship
 */
public inherited sharing class OrderDiscountService {
```

[`DMLManager.cls`](../utilities/dml/DMLManager.cls) and [`Logger.cls`](../utilities/logging/Logger.cls) in this repo follow the same shape — one named author, one `@since`, one running `@last`.

## 2 Change-log discipline in the header

### 2.1 `@last` records at most one entry per day — one line preferred, two at the outside

The `@last` entry is the audit trail of what the class does *now*, not a mirror of the git log. The granularity rule: **one entry per calendar day, no matter how many changes landed that day.** A day's work — even several distinct fixes — collapses into a single entry: date plus a short description of what shipped. Keep it to one line; when a day genuinely carried two unrelated feature-level changes, the entry may stretch to two lines, never more. Routine refactors, formatting passes, and lint fixes don't earn an entry at all — commit messages are the per-modification record; `@last` is the header's summary.

```apex
/**
 * @last June 2026 — initial ship
 * @last August 2026 — tiered discount stacking for bundled orders;
 *                     order-total rounding moved to currency scale
 */
```

If two entries carry the same date, they were written wrong — merge them on the next touch. [`DMLManager.cls`](../utilities/dml/DMLManager.cls) is a real example of the discipline: its `@last` line reads `May 2026 — USER_MODE migration; DMLManagerException now extends UtilitiesModuleException` — one line summarizing the day's change, not a list of every commit that touched the file.

Letting `@last` grow into a full change history defeats its purpose: a reader scanning the header wants "what does this class do and when did that last change," not a duplicate of `git log --follow`. If you find yourself appending an entry for every PR, the class is overdue for a squash of its own header.

## 3 ApexDoc and jsdoc coverage on the public surface

### 3.1 Every public method gets ApexDoc; every `@api` LWC member gets jsdoc

All `public`, `global`, `@AuraEnabled`, `virtual`, and `abstract` Apex methods carry ApexDoc on their declaration. All LWC `@api` properties and methods carry jsdoc on their declaration. This is not negotiable — the public surface is the contract other engineers (and other teams) code against, and an undocumented public method forces every caller to read the implementation to learn what it promises.

Minimum ApexDoc per public method:

```apex
/**
 * @description One-sentence purpose statement (the contract this method honors).
 * @param paramName Description of what each parameter means, plus any constraint.
 * @return Description of the return shape and any null-or-empty semantics.
 * @throws ExceptionType Conditions under which this method throws (named exception types only).
 */
public static SomeReturn someMethod(SomeParam paramName) { ... }
```

If a method takes no params and returns `void`, the `@description` line alone is enough — drop `@param` and `@return`.

Minimum jsdoc per `@api` declaration:

```js
/**
 * @api
 * @description One-sentence purpose or contract of this public property or method.
 * @type {string}  // for properties
 * @param {string} paramName Description of the param.
 * @returns {Promise<Result>} Description of the return.
 */
@api recordId;
```

For LWC events dispatched on the public surface, document the dispatch site with `@fires eventName { detail shape }` so consumers know what they're subscribing to without reading the component's internals.

### 3.2 Document a private method only when one of four criteria fires

The default for a private method is **no ApexDoc.** A well-named identifier carries the meaning, the class header carries the why, and mechanical docblocks on every private helper age badly — they drift from the code the first time someone edits the body without remembering to update the comment above it. Document a private method only when at least one of these applies:

1. **It encodes a business rule as a predicate.** The signature says `Boolean isEligibleForAutoApproval(Invoice__c inv)`; the business rule itself — the actual conditions that make an invoice eligible — is invisible from the name and needs to live in the docblock or it's locked inside the method body where only the next reader who opens the file will find it.
2. **It manages cached state.** The caching contract — per-transaction, per-class, lazy-loaded, when it invalidates — isn't visible from the signature. A method named `loadDiscountTierMap()` doesn't tell you it's a static cache that survives the rest of the transaction; that's exactly what the docblock is for.
3. **It has non-obvious side effects.** Mutates an input list, writes to a shared map, increments a stateful counter — anything beyond "input in, return value out." Document what gets mutated: `applyDiscountTier(List<Order_Line__c>)` that mutates each line's `Discount_Tier__c` in place needs that spelled out, because nothing about the name says the input is being changed rather than read.
4. **It has a subtle ordering or idempotency contract.** Must run before or after another method, must be invoked once per transaction, depends on call order, or short-circuits based on prior state. If `assembleLineItemSummaries()` depends on the caller having pre-grouped the input, that dependency belongs in the docblock, not in a comment three call sites away.

When you're genuinely unsure whether a criterion applies, document it — the cost of an extra docblock is a few lines of bloat; the cost of skipping one is opaque code for the next maintainer, and increasingly, for any AI coding assistant that reads the file as context to reason about it. A documented contract is the difference between a tool inferring the right behavior and it guessing from a name alone.

What still doesn't need ApexDoc: pure-function transforms with self-documenting names (`collectContactIds`, `groupLinesByOrder`, `discountTierKey`), one-line wrappers, and trivial accessors. The body is the documentation; the name is the contract.
