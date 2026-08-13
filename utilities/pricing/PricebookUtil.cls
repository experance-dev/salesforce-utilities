/**
 * @description Utility class for managing the standard pricebook in Salesforce.
 *              Provides lazy-loaded access to the standard pricebook Id for use
 *              across pricing operations.
 * @group Pricing
 * @author David Wood
 * @since June 2024
 * @last May 2026 — conformance refactor: inherited sharing, USER_MODE SOQL,
 *                  Test.isRunningTest() removed (Option A @TestVisible setter)
 * @last August 2026 — documented the lazy-load contract on the property surface
 */
public inherited sharing class PricebookUtil {
  // Tests inject a known Id here instead of branching on Test.isRunningTest().
  @TestVisible
  private static Id testStandardPricebookId;

  /**
   * @description Lazy-loaded standard pricebook Id. The first read queries Pricebook2
   *              under USER_MODE and caches the result for the rest of the transaction;
   *              later reads return the cached value without another query.
   * @throws QueryException When no standard pricebook is visible to the running user —
   *         including test context when no Id was injected through the @TestVisible seam.
   */
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
