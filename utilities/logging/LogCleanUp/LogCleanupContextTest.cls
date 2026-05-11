/**
 * @description Test class for LogCleanupContext.
 * @group Log Management Tests
 * @see LogCleanupContext.cls
 * @since November 2024
 * @last November 2024 - Updated annotations and test method documentation.
 */
@IsTest
public class LogCleanupContextTest {
  static void setup() {
    // Create test user
    TestFactory.createTestUser(true, 'System Administrator');
  }
  /**
   * @description Tests the retrieval of mock log retention days to ensure the correct data is returned.
   */
  @IsTest
  static void testGetLogRetentionDays() {
    System.runAs(TestFactory.getTestUser('System Administrator')) {
      // Instantiate the context
      LogCleanupContext context = new LogCleanupContext();

      // Invoke the method
      Map<String, Integer> retentionDays = context.getLogRetentionDays();

      // Assertions
      System.assertNotEquals(
        null,
        retentionDays,
        'Retention days map should not be null.'
      );
      System.assert(
        !retentionDays.isEmpty(),
        'Retention days map should not be empty.'
      );

      // Example assertions based on expected custom metadata
      // Replace 'Block_Trigger_Log__c' and 'ATM_Endpoint_Log__c' with actual metadata entries
      System.assert(
        retentionDays.containsKey('Block_Trigger_Log__c'),
        'Retention days should contain Block_Trigger_Log__c.'
      );
      System.assert(
        retentionDays.containsKey('ATM_Endpoint_Log__c'),
        'Retention days should contain ATM_Endpoint_Log__c.'
      );

      System.assert(
        retentionDays.get('Block_Trigger_Log__c') != null,
        'Retention days for Block_Trigger_Log__c should not be null.'
      );
      System.assert(
        retentionDays.get('ATM_Endpoint_Log__c') != null,
        'Retention days for ATM_Endpoint_Log__c should not be null.'
      );
    }
  }
}
