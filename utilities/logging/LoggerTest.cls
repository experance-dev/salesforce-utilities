/**
 * @description Tests for `Logger` — covers message formatting through the
 *              `formatLogMessage` seam, the `printLogs` verbosity gate, the
 *              `Debug_Log__c` durable-sink contract (error-severity entries
 *              persist exactly one record, lower severities persist nothing),
 *              and the `API_Exception_Log__c` sink: both `logApiException`
 *              overloads persist, allowlist redaction, null-exception safety,
 *              swallow-without-rethrow on persistence failure, and the shipped
 *              retention CMDT row.
 * @group Logger
 * @see Logger
 * @see LogCleanupContext
 * @author David Wood
 * @since August 2024
 * @last May 2026 — conformance refactor
 * @last August 2026 — rewritten with real assertions against the formatting seam
 *                      and the Debug_Log__c durable sink
 * @last 2026-08-13 — API-exception sink coverage: overload persistence, allowlist
 *                     scrub, null-exception + failure paths, retention CMDT row
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

  @IsTest
  static void testLogApiExceptionWithExceptionPersistsOneRow() {
    System.runAs(TestFactory.getCreatedTestUser()) {
      Id fakeAccountId = Utilities.getFakeId(Account.SObjectType);

      Test.startTest();
      try {
        Integer unused = 1 / 0; // NOPMD — intentional exception source
      } catch (Exception e) {
        Logger.logApiException(
          'Jira',
          'createIssue',
          'Account',
          fakeAccountId,
          'txn-001',
          e
        );
      }
      Test.stopTest();

      List<API_Exception_Log__c> persisted = [
        SELECT
          API_Name__c,
          Operation__c,
          Source_Object__c,
          Source_Record_Id__c,
          Transaction_Id__c,
          Severity__c,
          Message__c,
          Exception_Type__c,
          Stack_Trace__c,
          Do_Not_Delete__c
        FROM API_Exception_Log__c
      ];
      Assert.areEqual(
        1,
        persisted.size(),
        'The Exception overload must persist exactly one API_Exception_Log__c row.'
      );
      Assert.areEqual(
        'Jira',
        persisted[0].API_Name__c,
        'The integration name must land in API_Name__c.'
      );
      Assert.areEqual(
        'createIssue',
        persisted[0].Operation__c,
        'The failing operation must land in Operation__c.'
      );
      Assert.areEqual(
        'Account',
        persisted[0].Source_Object__c,
        'The source SObject API name must land in Source_Object__c.'
      );
      Assert.areEqual(
        String.valueOf(fakeAccountId),
        persisted[0].Source_Record_Id__c,
        'The source record Id must persist as its 18-character string form.'
      );
      Assert.areEqual(
        'txn-001',
        persisted[0].Transaction_Id__c,
        'The correlation id must land in Transaction_Id__c.'
      );
      Assert.areEqual(
        'Error',
        persisted[0].Severity__c,
        'API exception rows persist at Error severity.'
      );
      Assert.areEqual(
        'System.MathException',
        persisted[0].Exception_Type__c,
        'The exception type name must land in Exception_Type__c.'
      );
      Assert.isTrue(
        persisted[0].Message__c.contains('Divide'),
        'Identifier-shaped exception detail must survive the allowlist scrub: ' +
          persisted[0].Message__c
      );
      Assert.isTrue(
        persisted[0].Stack_Trace__c.contains('LoggerTest'),
        'Stack frames are identifier-shaped and must survive the scrub: ' +
          persisted[0].Stack_Trace__c
      );
      Assert.isFalse(
        persisted[0].Do_Not_Delete__c,
        'New API exception rows default to deletable — the retention opt-out is per-record and manual.'
      );
      Assert.areEqual(
        0,
        [SELECT COUNT() FROM Debug_Log__c],
        'API exception rows have their own sink — the debug-log mirror must not double-persist to Debug_Log__c.'
      );
    }
  }

  @IsTest
  static void testLogApiExceptionWithMessagePersistsAndScrubs() {
    System.runAs(TestFactory.getCreatedTestUser()) {
      Test.startTest();
      Logger.logApiException(
        'Workday',
        'syncWorker',
        null,
        null,
        null,
        'POST https://api.workday.example.com/v1/workers?ssn=123-45-6789&key=sk_live_x9 returned 401 for jane.doe@example.com'
      );
      Test.stopTest();

      List<API_Exception_Log__c> persisted = [
        SELECT Message__c, Exception_Type__c, Source_Object__c, Severity__c
        FROM API_Exception_Log__c
      ];
      Assert.areEqual(
        1,
        persisted.size(),
        'The message overload must persist exactly one API_Exception_Log__c row.'
      );
      String message = persisted[0].Message__c;
      Assert.isFalse(
        message.contains('jane.doe@example.com'),
        'An email-like token must be redacted: ' + message
      );
      Assert.isFalse(
        message.contains('123-45-6789'),
        'Query-string payload must be stripped with the query string: ' +
          message
      );
      Assert.isFalse(
        message.contains('sk_live_x9'),
        'Credential material riding the query string must never persist: ' +
          message
      );
      Assert.isTrue(
        message.contains('https://api.workday.example.com/v1/workers'),
        'The endpoint host+path must survive for operational triage: ' + message
      );
      Assert.isTrue(
        message.contains('401'),
        'The HTTP status code must survive the scrub: ' + message
      );
      Assert.isTrue(
        message.contains('[REDACTED]'),
        'Redacted tokens must be visibly masked, not silently dropped: ' +
          message
      );
      Assert.isNull(
        persisted[0].Exception_Type__c,
        'The non-exception overload persists no exception type.'
      );
      Assert.isNull(
        persisted[0].Source_Object__c,
        'Nullable context fields persist as null when the caller has none.'
      );
    }
  }

  @IsTest
  static void testScrubAllowlistSeamAdmitsCustomTokenShape() {
    System.runAs(TestFactory.getCreatedTestUser()) {
      String seeded = 'corr#A1B2 jane.doe@example.com';

      String defaultScrub = Logger.scrubApiDiagnostic(seeded);
      Assert.isFalse(
        defaultScrub.contains('corr#A1B2'),
        'A token shape outside the default allowlist must be redacted: ' +
          defaultScrub
      );

      Logger.apiDiagnosticAllowlist.add('corr#[A-Za-z0-9]+');
      String widenedScrub = Logger.scrubApiDiagnostic(seeded);
      Assert.isTrue(
        widenedScrub.contains('corr#A1B2'),
        'The @TestVisible allowlist seam must admit a deliberately added token shape: ' +
          widenedScrub
      );
      Assert.isFalse(
        widenedScrub.contains('jane.doe@example.com'),
        'Widening the allowlist for one shape must not weaken redaction elsewhere: ' +
          widenedScrub
      );
    }
  }

  @IsTest
  static void testLogApiExceptionNullExceptionStillPersists() {
    System.runAs(TestFactory.getCreatedTestUser()) {
      Test.startTest();
      Logger.logApiException(
        'Slack',
        'postMessage',
        null,
        null,
        null,
        (Exception) null
      );
      Test.stopTest();

      List<API_Exception_Log__c> persisted = [
        SELECT API_Name__c, Message__c, Exception_Type__c, Stack_Trace__c
        FROM API_Exception_Log__c
      ];
      Assert.areEqual(
        1,
        persisted.size(),
        'A null exception must still persist a row carrying the caller context rather than throw.'
      );
      Assert.areEqual(
        'Slack',
        persisted[0].API_Name__c,
        'Caller context must persist even without an exception.'
      );
      Assert.isNull(
        persisted[0].Exception_Type__c,
        'A null exception persists a null Exception_Type__c.'
      );
      Assert.isNull(
        persisted[0].Message__c,
        'A null exception persists a null Message__c.'
      );
      Assert.isNull(
        persisted[0].Stack_Trace__c,
        'A null exception persists a null Stack_Trace__c.'
      );
    }
  }

  @IsTest
  static void testLogApiExceptionSwallowsPersistenceFailure() {
    System.runAs(TestFactory.getCreatedTestUser()) {
      Logger.apiPersistFailureForTest = new DmlException(
        'injected persistence failure'
      );

      Test.startTest();
      Logger.logApiException('Jira', 'createIssue', null, null, null, 'boom');
      Test.stopTest();

      Assert.areEqual(
        0,
        [SELECT COUNT() FROM API_Exception_Log__c],
        'A persistence failure must be swallowed — no row, and reaching this assertion proves no rethrow.'
      );
      Assert.areEqual(
        0,
        [SELECT COUNT() FROM Debug_Log__c],
        'The failure fallback warns to the debug log only — it must not recurse into any durable sink.'
      );
    }
  }

  @IsTest
  static void testPersistErrorLogSkipsInZeroDmlHeadroomContext() {
    System.runAs(TestFactory.getCreatedTestUser()) {
      Logger.simulateZeroDmlHeadroom = true;

      Test.startTest();
      Logger.log(System.LoggingLevel.ERROR, 'read-only context error', 'LoggerTest', 'zeroHeadroom');
      Test.stopTest();

      Assert.areEqual(
        0,
        [SELECT COUNT() FROM Debug_Log__c],
        'With zero DML headroom the durable sink must be skipped entirely — reaching this assertion proves no uncatchable-limit attempt was made.'
      );
    }
  }

  @IsTest
  static void testLogApiExceptionSkipsInZeroDmlHeadroomContext() {
    System.runAs(TestFactory.getCreatedTestUser()) {
      Logger.simulateZeroDmlHeadroom = true;

      Test.startTest();
      Logger.logApiException('Jira', 'createIssue', null, null, null, 'read-only boom');
      Test.stopTest();

      Assert.areEqual(
        0,
        [SELECT COUNT() FROM API_Exception_Log__c],
        'With zero DML headroom the API sink must be skipped — debug mirror only, no insert attempt.'
      );
    }
  }

  @IsTest
  static void testRetentionConfigCoversApiExceptionLog() {
    System.runAs(TestFactory.getCreatedTestUser()) {
      Map<String, Integer> retention = new LogCleanupContext()
        .getLogRetentionDays();

      Assert.isTrue(
        retention.containsKey('API_Exception_Log__c'),
        'The shipped Log_Clean_Up__mdt record must register API_Exception_Log__c for retention.'
      );
      Assert.isTrue(
        retention.get('API_Exception_Log__c') > 0,
        'The API_Exception_Log__c retention window must be a positive day count.'
      );
    }
  }
}
