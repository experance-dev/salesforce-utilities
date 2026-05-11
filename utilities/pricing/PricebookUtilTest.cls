/**
 * @description Test coverage for PricebookUtil — standard pricebook ID retrieval in system and test contexts.
 * @group Pricing
 * @see PricebookUtil
 * @author David Wood
 * @since June 2024
 * @last May 2026 — Wave 6 migration + conformance
 */
@IsTest
private without sharing class PricebookUtilTest {
  @TestSetup
  static void makeData() {
    TestFactory.createTestUser();
  }

  @IsTest
  static void testGetStandardPricebookIdSytemContext() {
    System.runAs(TestFactory.getCreatedTestUser()) {
      // Setup: inject null to reset cached value
      PricebookUtil.testStandardPricebookId = null;

      // Execute: Retrieve the standard pricebook Id
      Id standardPricebookId = PricebookUtil.standardPricebookId;

      // Verify: Ensure the standard pricebook Id is retrieved correctly
      Assert.areNotEqual(
        null,
        standardPricebookId,
        'The standard pricebook Id should not be null.'
      );

      // Execute: check that lazily stored value is returned
      standardPricebookId = null;
      standardPricebookId = PricebookUtil.standardPricebookId;

      // Verify: Ensure the standard pricebook Id is retrieved correctly
      Assert.areNotEqual(
        null,
        standardPricebookId,
        'The standard pricebook Id should not be null.'
      );
    }
  }

  @IsTest
  static void testGetStandardPricebookIdTestContext() {
    // Setup: Create a test user and run the test as that user
    User testUser = TestFactory.createMinAccessUser(true);
    System.runAs(testUser) {
      // Activate the standard pricebook and inject via @TestVisible field
      Id pbId = Test.getStandardPricebookId();
      upsert new Pricebook2(Id = pbId, IsActive = true);
      PricebookUtil.testStandardPricebookId = pbId;

      // Execute: Retrieve the standard pricebook Id in test context
      Test.startTest();
      Id standardPricebookId = PricebookUtil.standardPricebookId;
      Test.stopTest();

      // Verify: Ensure the standard pricebook Id is retrieved correctly
      Assert.areNotEqual(
        null,
        standardPricebookId,
        'The standard pricebook Id should not be null in test context.'
      );
    }
  }
}
