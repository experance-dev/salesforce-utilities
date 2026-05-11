/**
 * @description Utility class for managing the standard pricebook in Salesforce.
 *              Provides lazy-loaded access to the standard pricebook Id for use
 *              across pricing operations.
 * @group Pricing
 * @since June 2024
 * @last May 2026 — Wave 5 conformance: inherited sharing, USER_MODE SOQL,
 *                  Test.isRunningTest() removed (Option A @TestVisible setter)
 */
public inherited sharing class PricebookUtil {
  // Tests inject a known Id here instead of branching on Test.isRunningTest().
  @TestVisible
  private static Id testStandardPricebookId;

  // Lazy-loaded standard pricebook Id.
  public static Id standardPricebookId {
    get {
      if (standardPricebookId != null) {
        return standardPricebookId;
      }
      if (testStandardPricebookId != null) {
        standardPricebookId = testStandardPricebookId;
        return standardPricebookId;
      }
      standardPricebookId = [
        SELECT Id
        FROM Pricebook2
        WHERE IsStandard = TRUE
        WITH USER_MODE
        LIMIT 1
      ]
      .Id;
      return standardPricebookId;
    }
    private set;
  }
}
