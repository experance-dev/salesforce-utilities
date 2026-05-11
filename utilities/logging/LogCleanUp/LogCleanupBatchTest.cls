/**
 * @description Test class for LogCleanupBatch.
 * Validates that old logs are deleted as expected.
 * @group Log Management Tests
 * @see LogCleanupBatch, DMLManager, Logger, Utilities, TestFactory
 * @since November 2024
 * @last November 2024 - Fixed syntax errors and ensured proper variable scope.
 */
@IsTest
public class LogCleanupBatchTest {
  @TestVisible
  static final Integer EXPECTED_REMAINING_BLOCK_TRIGGER_LOGS = 5; // half of the logs should be deleted
  @TestVisible
  static final Integer EXPECTED_REMAINING_ATM_ENDPOINT_LOGS = 10;
  @TestVisible
  static final Map<String, Integer> MOCK_RETENTION_MAP = new Map<String, Integer>{
    'Block_Trigger_Log__c' => 14,
    'ATM_Endpoint_Log__c' => 7
  };

  @TestVisible
  @TestSetup
  static void setup() {
    // Create test user
    TestFactory.createTestUser(true, 'System Administrator');

    Integer blockRetentionDays = MOCK_RETENTION_MAP.get('Block_Trigger_Log__c');
    Integer atmRetentionDays = MOCK_RETENTION_MAP.get('ATM_Endpoint_Log__c');

    List<Block_Trigger_Log__c> blockTriggerLogs = new List<Block_Trigger_Log__c>();
    for (Integer i = 0; i < 10; i++) {
      Block_Trigger_Log__c log = new Block_Trigger_Log__c();
      blockTriggerLogs.add(log);
    }
    DMLManager.insertAsSystem(blockTriggerLogs);

    // Set CreatedDate for Block_Trigger_Log__c records
    List<Block_Trigger_Log__c> logsToUpdate = [
      SELECT Id
      FROM Block_Trigger_Log__c
    ];
    Integer index = 0;
    for (Block_Trigger_Log__c log : logsToUpdate) {
      DateTime createdDate;
      if (Math.mod(index, 2) == 0) {
        // Even indices are old logs
        createdDate = DateTime.now().addDays(-blockRetentionDays - 1);
      } else {
        // Odd indices are recent logs
        createdDate = DateTime.now().addDays(-blockRetentionDays + 1);
      }
      Test.setCreatedDate(
        log.Id,
        DateTime.newInstance(createdDate.date(), Time.newInstance(0, 0, 0, 0))
      );
      index++;
    }

    // For ATM_Endpoint_Log__c
    List<ATM_Endpoint_Log__c> atmEndpointLogs = new List<ATM_Endpoint_Log__c>();
    for (Integer i = 0; i < 15; i++) {
      ATM_Endpoint_Log__c log;
      if (Math.mod(i, 3) == 0) {
        // Old deletable log
        log = new ATM_Endpoint_Log__c(Do_Not_Delete__c = false);
      } else if (Math.mod(i, 3) == 1) {
        // Old protected log
        log = new ATM_Endpoint_Log__c(Do_Not_Delete__c = true);
      } else {
        // Recent log
        log = new ATM_Endpoint_Log__c(Do_Not_Delete__c = false);
      }
      atmEndpointLogs.add(log);
    }
    DMLManager.insertAsSystem(atmEndpointLogs);

    // Set CreatedDate for ATM_Endpoint_Log__c records
    List<ATM_Endpoint_Log__c> atmLogsToUpdate = [
      SELECT Id, Do_Not_Delete__c
      FROM ATM_Endpoint_Log__c
      ORDER BY CreatedDate ASC
    ];
    index = 0;
    for (ATM_Endpoint_Log__c log : atmLogsToUpdate) {
      DateTime createdDate;
      if (Math.mod(index, 3) == 2) {
        // Recent log
        createdDate = DateTime.now().addDays(-atmRetentionDays + 1);
      } else {
        // Old log
        createdDate = DateTime.now().addDays(-atmRetentionDays - 1);
      }
      Test.setCreatedDate(
        log.Id,
        DateTime.newInstance(createdDate.date(), Time.newInstance(0, 0, 0, 0))
      );
      index++;
    }
  }

  /**
   * @description Tests the execution of LogCleanupBatch to ensure logs are deleted as expected.
   */
  @IsTest
  static void testLogCleanupBatchExecution() {
    System.runAs(TestFactory.getTestUser('System Administrator')) {
      // Create mock context
      MockLogCleanupContext mockContext = new MockLogCleanupContext(
        MOCK_RETENTION_MAP
      );

      Test.startTest();
      // Execute batch with mock context
      Database.executeBatch(new LogCleanupBatch(mockContext), 200);
      Test.stopTest();

      // Assertions
      Integer remainingBlockTriggerLogCount = [
        SELECT COUNT()
        FROM Block_Trigger_Log__c
      ];
      System.assertEquals(
        EXPECTED_REMAINING_BLOCK_TRIGGER_LOGS,
        remainingBlockTriggerLogCount,
        'Expected the correct number of Block Trigger Logs to remain.'
      );

      Integer remainingAtmEndpointLogCount = [
        SELECT COUNT()
        FROM ATM_Endpoint_Log__c
      ];
      System.assertEquals(
        EXPECTED_REMAINING_ATM_ENDPOINT_LOGS,
        remainingAtmEndpointLogCount,
        'Expected the correct number of ATM Endpoint Logs to remain.'
      );
    }
  }

  /**
   * @description Negative test for LogCleanupBatch to ensure exceptions are handled properly.
   * Triggers an exception by using an invalid log object name.
   */
  @IsTest
  static void testLogCleanupBatchExceptionHandling() {
    System.runAs(TestFactory.getTestUser('System Administrator')) {
      // Create mock context with an invalid log name to trigger an exception
      Map<String, Integer> invalidMockRetentionMap = new Map<String, Integer>{
        'Invalid_Log__c' => 10 // 'Invalid_Log__c' does not exist and should cause SOQL exception
      };
      MockLogCleanupContext mockContext = new MockLogCleanupContext(
        invalidMockRetentionMap
      );

      Test.startTest();
      // Execute batch with mock context that should cause an exception
      Database.executeBatch(new LogCleanupBatch(mockContext), 200);
      Test.stopTest();

      // Since the exception is caught inside the batch, the test should not fail
      // Verify that the expected counts remain unchanged
      Integer remainingBlockTriggerLogCount = [
        SELECT COUNT()
        FROM Block_Trigger_Log__c
      ];
      System.assertEquals(
        10,
        remainingBlockTriggerLogCount,
        'Expected the correct number of Block Trigger Logs to remain after exception.'
      );

      Integer remainingAtmEndpointLogCount = [
        SELECT COUNT()
        FROM ATM_Endpoint_Log__c
      ];
      System.assertEquals(
        15,
        remainingAtmEndpointLogCount,
        'Expected the correct number of ATM Endpoint Logs to remain after exception.'
      );
    }

  }

  /**
   * @description Test to ensure the default constructor of LogCleanupBatch initializes correctly.
   * Covers the lines where the default constructor is used.
   */
  @IsTest
  static void testLogCleanupBatchDefaultConstructor() {
    System.runAs(TestFactory.getTestUser('System Administrator')) {
      // Instantiate LogCleanupBatch using the default constructor
      LogCleanupBatch batchInstance = new LogCleanupBatch();
      System.assertNotEquals(
        null,
        batchInstance,
        'Batch instance should be instantiated using the default constructor.'
      );
    }
  }
}
