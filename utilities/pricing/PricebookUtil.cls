/**
 * @description Utility class for managing the standard pricebook in Salesforce.
 * This class provides a lazy-loaded property to retrieve the standard pricebook Id,
 * and ensures the standard pricebook exists in both test and non-test contexts.
 *
 * @group Pricebook Management
 * @since June 2024
 */
public with sharing class PricebookUtil {
  /**
   * @description Lazy-loaded property to return the standard pricebook Id.
   * This property can be accessed in both Apex and Apex test code.
   * @return The standard pricebook Id.
   */
  @SuppressWarnings('PMD.EmptyCatchBlock')
  public static Id standardPricebookId {
    get {
      // Return the cached Id if already loaded
      if (standardPricebookId != null) {
        return standardPricebookId;
      }

      // Handle the case when running in test context
      if (Test.isRunningTest()) {
        standardPricebookId = Test.getStandardPricebookId();
        ensureStandardPricebookExists(standardPricebookId);
        return standardPricebookId;
      }

      // Query the standard pricebook Id when not running tests
      standardPricebookId = [
        SELECT Id
        FROM Pricebook2
        WHERE IsStandard = TRUE
        LIMIT 1
      ]
      .Id;

      return standardPricebookId;
    }
    set;
  }

  /**
   * @description Ensures that the standard pricebook exists in the org. If it does not exist, it creates one.
   * @param pricebookId The Id of the standard pricebook to verify.
   */
  @SuppressWarnings(
    'PMD.UnusedLocalVariable, PMD.ApexCRUDViolation, PMD.AvoidDebugStatements'
  )
  private static void ensureStandardPricebookExists(Id pricebookId) {
    try {
      // Check if the standard pricebook exists
      Pricebook2 standardPricebook = [
        SELECT Id, Name
        FROM Pricebook2
        WHERE Id = :pricebookId
        WITH SYSTEM_MODE
        LIMIT 1
      ];
    } catch (Exception e) {
      // If the standard pricebook does not exist, create it
      Pricebook2 newPricebook = new Pricebook2(
        Id = pricebookId,
        IsActive = true
      );
      try {
        insert newPricebook;
      } catch (DMLException eDML) {
        // Log the exception in case of an error
        System.debug(
          LoggingLevel.INFO,
          'Error occurred while accessing or creating the standard pricebook in a test context: ' +
          eDML.getMessage()
        );
      }
    }
  }
}
