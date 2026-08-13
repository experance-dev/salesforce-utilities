# Apex — Test classes

## Header

- Name: `<ClassName>Test` for new tests; keep existing names when editing.
- Class-level header annotations only:

| Tag | Value |
| --- | --- |
| `@description` | Purpose of the test class. |
| `@group` | Category. |
| `@see` | Reference to the class under test. |
| `@author` | Author name. |
| `@since` | Existing or current month/year. |
| `@last` | Current date + change note. |

## Conventions

- Method names: CamelCase, **no underscores**.
- ApexDoc on the class header and on each `@IsTest` method (`@description`, `@param`, `@return` as applicable).

## Test patterns

- Use the **`Assert` class** (`Assert.areEqual`, `Assert.isTrue`, …) — never `System.assertEquals`. Every assertion gets a comment-tag message explaining what's being verified.
- Wrap every test case in `System.runAs(...)` against an explicit test user.
- Reusable setup in `@TestSetup`:

```apex
@TestSetup
static void setup() {
    TestFactory.createTestUser(true, 'Standard User');
}
```

- Fake IDs from [`Utilities.getFakeId(SObjectType)`](../../utilities/general/Utilities.cls) (e.g. `Utilities.getFakeId(Account.SObjectType)`) — never manually concatenate ID strings.

## Canonical example

```apex
/** @description Test the construction of a successful response when an Account is created. */
@IsTest
static void testSuccessResponseCreated() {
    System.runAs(TestFactory.getTestUser('Standard User')) {
        Id fakeId = Utilities.getFakeId(Account.SObjectType);
        Account acc = new Account(Id = fakeId);
        TestFactory.createSObject(acc, false);
        AccountResponse response = new AccountResponse.Builder()
            .setSuccess(true)
            .setCreated(true)
            .setId(fakeId)
            .setTrackingId('track1')
            .setAction('ADD')
            .build();

        Assert.isTrue(response.success, 'Expected success to be true.');
        Assert.isTrue(response.created, 'Expected created to be true.');
        Assert.areEqual(String.valueOf(fakeId), response.id, 'Expected id to match the provided ID.');
        Assert.isNull(response.errors, 'Expected no errors.');
    }
}
```

---

## Proposed additions

### Scope `Test.startTest()` / `Test.stopTest()` deliberately

`Test.startTest()` resets governor limits and forces queued async to run when `Test.stopTest()` is hit. Wrap **only the section under test**, not the whole method. Setup, fixture creation, and assertions go outside the start/stop block when they don't need fresh limits.

### Coverage threshold

Touched classes ≥ 75 % coverage on the PR — measured per-class, not aggregate. CI should fail if a modified class drops below threshold.

### Negative-path tests are mandatory

Every public method gets at least one negative test (invalid input, permission denial, governor-limit edge, or thrown-exception path). A class with only happy-path tests is incomplete.

### Use `Test.isRunningTest()` sparingly

If your production code branches on `Test.isRunningTest()`, the test isn't testing production code. Refactor to inject the test-mode behavior (dependency injection, mock service, `@TestVisible` setter) instead.

### Mock callouts with [`HttpCalloutMockFactory`](../../utilities/testing/HttpCalloutMockFactory.cls)

Standardize callout mocking through the factory — don't inline anonymous `HttpCalloutMock` classes per test.
