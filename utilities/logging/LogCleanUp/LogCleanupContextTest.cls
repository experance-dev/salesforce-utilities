/**
 * @description Test class for LogCleanupContext.
 * Validates that log retention days are correctly retrieved from custom metadata.
 * @group LogCleanup
 * @see LogCleanupContext
 * @author David Wood
 * @since November 2024
 * @last May 2026 — Wave 6 conformance
 */
@IsTest
public without sharing class LogCleanupContextTest {
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
      Assert.areNotEqual(
        null,
        retentionDays,
        'Retention days map should not be null.'
      );
      Assert.isTrue(
        !retentionDays.isEmpty(),
        'Retention days map should not be empty.'
      );

      // Example assertions based on expected custom metadata
      // Replace 'Block_Trigger_Log__c' and 'ATM_Endpoint_Log__c' with actual metadata entries
      Assert.isTrue(
        retentionDays.containsKey('Block_Trigger_Log__c'),
        'Retention days should contain Block_Trigger_Log__c.'
      );
      Assert.isTrue(
        retentionDays.containsKey('ATM_Endpoint_Log__c'),
        'Retention days should contain ATM_Endpoint_Log__c.'
      );

      Assert.isTrue(
        retentionDays.get('Block_Trigger_Log__c') != null,
        'Retention days for Block_Trigger_Log__c should not be null.'
      );
      Assert.isTrue(
        retentionDays.get('ATM_Endpoint_Log__c') != null,
        'Retention days for ATM_Endpoint_Log__c should not be null.'
      );
    }
  }
}
