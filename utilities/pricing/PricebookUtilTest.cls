/**
 * @description Test class for PricebookUtil. Ensures all functionalities of the PricebookUtil class are properly tested.
 * @author David Wood
 * @since June 2024
 * @group Pricebook Management Tests
 * @see PricebookUtil
 */
@IsTest
private class PricebookUtilTest {
  @TestSetup
  static void makeData() {
    TestFactory.createTestUser();
  }
  /**
   * @description Tests the retrieval of the standard pricebook Id in a non-test context.
   */
  @IsTest
  static void testGetStandardPricebookIdSytemContext() {
    System.runAs(TestFactory.getCreatedTestUser()) {
      // Setup: Ensure there is no standard pricebook Id initially
      PricebookUtil.standardPricebookId = null;

      // Execute: Retrieve the standard pricebook Id
      Id standardPricebookId = PricebookUtil.standardPricebookId;

      // Verify: Ensure the standard pricebook Id is retrieved correctly
      System.assertNotEquals(
        null,
        standardPricebookId,
        'The standard pricebook Id should not be null.'
      );

      // Execute: check that lazily stored value is returned
      standardPricebookId = null;
      standardPricebookId = PricebookUtil.standardPricebookId;

      // Verify: Ensure the standard pricebook Id is retrieved correctly
      System.assertNotEquals(
        null,
        standardPricebookId,
        'The standard pricebook Id should not be null.'
      );
    }
  }

  /**
   * @description Tests the retrieval of the standard pricebook Id in a test context.
   */
  @IsTest
  static void testGetStandardPricebookIdTestContext() {
    // Setup: Create a test user and run the test as that user
    User testUser = TestFactory.createMinAccessUser(true);
    System.runAs(testUser) {
      // Ensure there is no standard pricebook Id initially
      PricebookUtil.standardPricebookId = null;

      // Execute: Retrieve the standard pricebook Id in test context
      Test.startTest();
      Id standardPricebookId = PricebookUtil.standardPricebookId;
      Test.stopTest();

      // Verify: Ensure the standard pricebook Id is retrieved correctly
      System.assertNotEquals(
        null,
        standardPricebookId,
        'The standard pricebook Id should not be null in test context.'
      );
    }
  }
}
