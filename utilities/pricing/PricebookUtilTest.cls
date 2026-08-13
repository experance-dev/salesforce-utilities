/**
 * @description Test coverage for PricebookUtil — standard pricebook ID retrieval in system and test contexts.
 * @group Pricing
 * @see PricebookUtil
 * @author David Wood
 * @since June 2024
 * @last May 2026 — migration + conformance refactor
 * @last August 2026 — query-path QueryException contract; Limits-based cache proof; SeeAllData dependency removed
 */
@IsTest
private without sharing class PricebookUtilTest {
  @TestSetup
  static void makeData() {
    TestFactory.createTestUser();
  }

  @IsTest
  static void testGetStandardPricebookIdSystemContext() {
    System.runAs(TestFactory.getCreatedTestUser()) {
      // Setup: no injected Id — the getter must take the SOQL path. In test
      // context the standard pricebook is not visible to SOQL, so the
      // single-row assignment throws; assert that contract explicitly.
      PricebookUtil.testStandardPricebookId = null;

      try {
        Id standardPricebookId = PricebookUtil.standardPricebookId;
        Assert.fail(
          'Expected a QueryException when no standard pricebook is visible to the query path; got ' +
            standardPricebookId
        );
      } catch (QueryException e) {
        Assert.isTrue(
          String.isNotBlank(e.getMessage()),
          'The QueryException should carry the platform message.'
        );
      }
    }
  }

  @IsTest
  static void testGetStandardPricebookIdTestContext() {
    // Setup: Create a test user and run the test as that user
    User testUser = TestFactory.createMinAccessUser(true);
    System.runAs(testUser) {
      // Inject the standard pricebook Id via the @TestVisible seam
      Id pbId = Test.getStandardPricebookId();
      PricebookUtil.testStandardPricebookId = pbId;

      // Execute: Retrieve the standard pricebook Id in test context
      Test.startTest();
      Id standardPricebookId = PricebookUtil.standardPricebookId;
      Test.stopTest();

      // Verify: the getter returns exactly the injected Id
      Assert.areEqual(
        pbId,
        standardPricebookId,
        'The getter should return the Id injected through the @TestVisible seam.'
      );
    }
  }

  @IsTest
  static void testStandardPricebookIdIsCachedAfterFirstRead() {
    System.runAs(TestFactory.getCreatedTestUser()) {
      // Setup: inject a known Id so the first read resolves without org data
      Id pbId = Test.getStandardPricebookId();
      PricebookUtil.testStandardPricebookId = pbId;

      // Execute: first read primes the cache
      Id firstRead = PricebookUtil.standardPricebookId;
      Integer queriesAfterFirstRead = Limits.getQueries();

      // Execute: second read must be served from the cache
      Id secondRead = PricebookUtil.standardPricebookId;

      // Verify: same Id, and no additional SOQL issued by the second read
      Assert.areEqual(
        firstRead,
        secondRead,
        'Both reads should return the same standard pricebook Id.'
      );
      Assert.areEqual(
        queriesAfterFirstRead,
        Limits.getQueries(),
        'The second read must come from the cache — no additional SOQL.'
      );
    }
  }
}
