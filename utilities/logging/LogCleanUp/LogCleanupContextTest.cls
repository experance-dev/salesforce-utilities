/**
 * @description Tests for `LogCleanupContext` — asserts the shipped
 *              `Log_Clean_Up.Debug_Log` CMDT record registers the library log
 *              object, verifies the retention-map shape, and covers the
 *              malformed-row skip path through the `buildRetentionMap` seam.
 * @group LogCleanup
 * @see LogCleanupContext
 * @author David Wood
 * @since November 2024
 * @last May 2026 — conformance refactor
 * @last August 2026 — rewritten against the shipped Debug_Log CMDT record;
 *                      malformed-row negative path added
 */
@IsTest
private without sharing class LogCleanupContextTest {
  @TestSetup
  static void setup() {
    TestFactory.createTestUser();
  }

  @IsTest
  static void testGetLogRetentionDaysIncludesShippedDebugLogRecord() {
    Map<String, Integer> retentionDays;
    System.runAs(TestFactory.getCreatedTestUser()) {
      retentionDays = new LogCleanupContext().getLogRetentionDays();
    }

    Assert.isNotNull(
      retentionDays,
      'The retention map must never be null.'
    );
    Assert.isTrue(
      retentionDays.containsKey('Debug_Log__c'),
      'The shipped Log_Clean_Up.Debug_Log CMDT record must register the library log object.'
    );
    Assert.areEqual(
      30,
      retentionDays.get('Debug_Log__c'),
      'The shipped Debug_Log record configures a 30-day retention window.'
    );
    for (String logName : retentionDays.keySet()) {
      Assert.isTrue(
        String.isNotBlank(logName),
        'Every retention-map key must be a non-blank SObject API name.'
      );
      Assert.isNotNull(
        retentionDays.get(logName),
        'buildRetentionMap must never map an object to a null retention window.'
      );
    }
  }

  @IsTest
  static void testBuildRetentionMapSkipsMalformedRows() {
    Map<String, Integer> retentionDays;
    System.runAs(TestFactory.getCreatedTestUser()) {
      List<Log_Clean_Up__mdt> rows = new List<Log_Clean_Up__mdt>{
        new Log_Clean_Up__mdt(
          DeveloperName = 'Valid_Row',
          Log_Name__c = 'Debug_Log__c',
          Delete_Logs_After__c = 30
        ),
        new Log_Clean_Up__mdt(
          DeveloperName = 'Blank_Log_Name',
          Log_Name__c = '',
          Delete_Logs_After__c = 15
        ),
        new Log_Clean_Up__mdt(
          DeveloperName = 'Missing_Retention',
          Log_Name__c = 'Some_Log__c'
        )
      };

      retentionDays = LogCleanupContext.buildRetentionMap(rows);
    }

    Assert.areEqual(
      1,
      retentionDays.size(),
      'Malformed rows must be skipped, not thrown on.'
    );
    Assert.areEqual(
      30,
      retentionDays.get('Debug_Log__c'),
      'The one well-formed row must survive the fold.'
    );
    Assert.isFalse(
      retentionDays.containsKey('Some_Log__c'),
      'A row missing Delete_Logs_After__c must be omitted from the map.'
    );
  }
}
