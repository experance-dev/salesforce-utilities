/**
 * @description Tests for `Logger` — covers message formatting through the
 *              `formatLogMessage` seam, the `printLogs` verbosity gate, and the
 *              `Debug_Log__c` durable-sink contract: error-severity entries
 *              persist exactly one record, lower severities persist nothing.
 * @group Logger
 * @see Logger
 * @author David Wood
 * @since August 2024
 * @last May 2026 — conformance refactor
 * @last August 2026 — rewritten with real assertions against the formatting seam
 *                      and the Debug_Log__c durable sink
 */
@IsTest
private without sharing class LoggerTest {
  @TestSetup
  static void makeData() {
    TestFactory.createTestUser();
  }

  @IsTest
  static void testFormatLogMessageIncludesLevelContextAndMessage() {
    String formatted;
    System.runAs(TestFactory.getCreatedTestUser()) {
      formatted = Logger.formatLogMessage(
        System.LoggingLevel.ERROR,
        'Something broke',
        'LoggerTest',
        'testFormatLogMessageIncludesLevelContextAndMessage'
      );
    }

    Assert.isTrue(
      formatted.contains('[ERROR]'),
      'Formatted message must carry the severity: ' + formatted
    );
    Assert.isTrue(
      formatted.contains('[LoggerTest]'),
      'Formatted message must carry the class context: ' + formatted
    );
    Assert.isTrue(
      formatted.contains(
        '[testFormatLogMessageIncludesLevelContextAndMessage]'
      ),
      'Formatted message must carry the method context: ' + formatted
    );
    Assert.isTrue(
      formatted.endsWith('Something broke'),
      'Formatted message must end with the raw message: ' + formatted
    );
  }

  @IsTest
  static void testFormatLogMessageOmitsMissingContext() {
    String formatted;
    System.runAs(TestFactory.getCreatedTestUser()) {
      formatted = Logger.formatLogMessage(
        System.LoggingLevel.INFO,
        'No context here',
        null,
        null
      );
    }

    Assert.isTrue(
      formatted.contains('[INFO]'),
      'Formatted message must carry the severity: ' + formatted
    );
    Assert.isFalse(
      formatted.contains('[null]'),
      'Null class/method context must be omitted, not rendered: ' + formatted
    );
    Assert.isTrue(
      formatted.endsWith('No context here'),
      'Formatted message must end with the raw message: ' + formatted
    );
  }

  @IsTest
  static void testErrorPersistsOneDebugLogRecord() {
    System.runAs(TestFactory.getCreatedTestUser()) {
      Test.startTest();
      Logger.error(
        'Order sync failed',
        'LoggerTest',
        'testErrorPersistsOneDebugLogRecord'
      );
      Test.stopTest();

      List<Debug_Log__c> persisted = [
        SELECT
          Message__c,
          Class_Name__c,
          Method_Name__c,
          Log_Level__c,
          Do_Not_Delete__c
        FROM Debug_Log__c
      ];
      Assert.areEqual(
        1,
        persisted.size(),
        'An error-severity entry must persist exactly one Debug_Log__c record.'
      );
      Assert.areEqual(
        'Order sync failed',
        persisted[0].Message__c,
        'The raw (unformatted) message must land in Message__c.'
      );
      Assert.areEqual(
        'LoggerTest',
        persisted[0].Class_Name__c,
        'The originating class must land in Class_Name__c.'
      );
      Assert.areEqual(
        'testErrorPersistsOneDebugLogRecord',
        persisted[0].Method_Name__c,
        'The originating method must land in Method_Name__c.'
      );
      Assert.areEqual(
        'Error',
        persisted[0].Log_Level__c,
        'The persisted severity must be Error.'
      );
      Assert.isFalse(
        persisted[0].Do_Not_Delete__c,
        'New log rows default to deletable — the retention opt-out is per-record and manual.'
      );
    }
  }

  @IsTest
  static void testLogExceptionPersistsTypeNameAndStackTrace() {
    System.runAs(TestFactory.getCreatedTestUser()) {
      Test.startTest();
      try {
        Integer unused = 1 / 0; // NOPMD — intentional exception source
      } catch (Exception e) {
        Logger.logException(
          e,
          'LoggerTest',
          'testLogExceptionPersistsTypeNameAndStackTrace'
        );
      }
      Test.stopTest();

      List<Debug_Log__c> persisted = [
        SELECT Message__c, Class_Name__c, Log_Level__c
        FROM Debug_Log__c
      ];
      Assert.areEqual(
        1,
        persisted.size(),
        'logException must persist exactly one Debug_Log__c record.'
      );
      Assert.isTrue(
        persisted[0].Message__c.contains('System.MathException'),
        'logException must capture e.getTypeName(): ' + persisted[0].Message__c
      );
      Assert.isTrue(
        persisted[0].Message__c.contains('StackTrace'),
        'logException must capture the stack trace: ' + persisted[0].Message__c
      );
      Assert.areEqual(
        'Error',
        persisted[0].Log_Level__c,
        'Exceptions persist at Error severity.'
      );
    }
  }

  @IsTest
  static void testErrorStillPersistsWithDebugFlagOff() {
    System.runAs(TestFactory.getCreatedTestUser()) {
      // Simulates Log_Setting__mdt.Print_Debug_Logs__c = false via the seam.
      Logger.printLogs = false;

      Test.startTest();
      Logger.error('Error with verbosity gate off');
      Test.stopTest();

      Assert.areEqual(
        1,
        [SELECT COUNT() FROM Debug_Log__c],
        'The Print_Debug_Logs__c gate governs debug verbosity only — error-severity entries persist regardless.'
      );
    }
  }

  @IsTest
  static void testDebugInfoAndWarnDoNotPersist() {
    System.runAs(TestFactory.getCreatedTestUser()) {
      Logger.printLogs = true;

      Test.startTest();
      Logger.debug(
        'Debug entry',
        'LoggerTest',
        'testDebugInfoAndWarnDoNotPersist'
      );
      Logger.debug(
        'Debug entry with payload',
        new Map<String, Object>{ 'key' => 'value' },
        'LoggerTest',
        'testDebugInfoAndWarnDoNotPersist'
      );
      Logger.info('Info entry');
      Logger.warn('Warn entry');
      Test.stopTest();

      Assert.areEqual(
        0,
        [SELECT COUNT() FROM Debug_Log__c],
        'Only error-severity entries reach the durable sink; debug/info/warn stay debug-log-only.'
      );
    }
  }

  @IsTest
  static void testErrorWithNullMessagePersistsWithoutThrowing() {
    System.runAs(TestFactory.getCreatedTestUser()) {
      Test.startTest();
      Logger.log(System.LoggingLevel.ERROR, null);
      Test.stopTest();

      List<Debug_Log__c> persisted = [
        SELECT Message__c, Class_Name__c, Method_Name__c
        FROM Debug_Log__c
      ];
      Assert.areEqual(
        1,
        persisted.size(),
        'A null message must still persist an error record rather than throw.'
      );
      Assert.isNull(
        persisted[0].Message__c,
        'A null message persists as a null Message__c.'
      );
      Assert.isNull(
        persisted[0].Class_Name__c,
        'Absent class context persists as null.'
      );
    }
  }

  @IsTest
  static void testPrintLogsResolvesToNonNullDefault() {
    Boolean result;
    System.runAs(TestFactory.getCreatedTestUser()) {
      result = Logger.printLogs;
    }

    Assert.isNotNull(
      result,
      'printLogs must resolve to a non-null default whether or not the org ships a Log_Setting__mdt record.'
    );
  }
}
