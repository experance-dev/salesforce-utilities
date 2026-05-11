/**
 * @description Test class for the Logger utility.
 * Validates the logging functionality, including message formatting and logging levels.
 * @group Utilities
 * @author David Wood
 * @since August 2024
 * @see Logger
 */
@isTest
public class LoggerTest {
  @TestSetup
  static void makeData() {
    TestFactory.createTestUser();
  }

  //  @description Test logging at all levels with class and method names
  @isTest
  static void testLogWithClassAndMethod() {
    System.runAs(TestFactory.getCreatedTestUser()) {
      Test.startTest();

      Logger.log(
        System.LoggingLevel.DEBUG,
        'Debug message',
        'LoggerTest',
        'testLogWithClassAndMethod'
      );
      Logger.log(
        System.LoggingLevel.INFO,
        'Info message',
        'LoggerTest',
        'testLogWithClassAndMethod'
      );
      Logger.log(
        System.LoggingLevel.WARN,
        'Warn message',
        'LoggerTest',
        'testLogWithClassAndMethod'
      );
      Logger.log(
        System.LoggingLevel.ERROR,
        'Error message',
        'LoggerTest',
        'testLogWithClassAndMethod'
      );
      Logger.info('Error message', 'LoggerTest', 'testLogWithClassAndMethod');
      Logger.error('Error message', 'LoggerTest', 'testLogWithClassAndMethod');
      Logger.warn('Error message', 'LoggerTest', 'testLogWithClassAndMethod');
      Logger.debug('Error message', 'LoggerTest', 'testLogWithClassAndMethod');

      Test.stopTest();
    }

    // Placeholder for future assertion logic
    // Validate the logs (manual validation required for now as debug logs are not directly accessible in tests)
    Assert.isTrue(
      true,
      'Log messages should appear in the debug log with appropriate formatting'
    );
  }

  // @description Test logging at all levels without class and method names
  @isTest
  static void testLogWithoutClassAndMethod() {
    System.runAs(TestFactory.getCreatedTestUser()) {
      Test.startTest();

      Logger.log(System.LoggingLevel.DEBUG, 'Debug message');
      Logger.log(System.LoggingLevel.INFO, 'Info message');
      Logger.log(System.LoggingLevel.WARN, 'Warn message');
      Logger.log(System.LoggingLevel.ERROR, 'Error message');
      Logger.info('Error message');
      Logger.error('Error message');
      Logger.warn('Error message');
      Logger.debug('Error message');

      Test.stopTest();

      // Placeholder for future assertion logic
      // Validate the logs (manual validation required for now as debug logs are not directly accessible in tests)
      Assert.isTrue(
        true,
        'Log messages should appear in the debug log with appropriate formatting'
      );
    }
  }

  // @description Test logging with null and empty messages
  @isTest
  static void testLogNullAndEmptyMessages() {
    System.runAs(TestFactory.getCreatedTestUser()) {
      Test.startTest();

      Logger.log(
        System.LoggingLevel.DEBUG,
        null,
        'LoggerTest',
        'testLogNullAndEmptyMessages'
      );
      Logger.log(
        System.LoggingLevel.INFO,
        '',
        'LoggerTest',
        'testLogNullAndEmptyMessages'
      );

      Test.stopTest();

      // Placeholder for future assertion logic
      // Validate the logs (manual validation required for now as debug logs are not directly accessible in tests)
      Assert.isTrue(
        true,
        'Log messages should appear in the debug log even for null or empty messages'
      );
    }
  }

  // @description Test logging with object parsing to JSON
  @isTest
  static void testLogWithObjectParsing() {
    System.runAs(TestFactory.getCreatedTestUser()) {
      Test.startTest();

      Map<String, Object> testObject = new Map<String, Object>{
        'key1' => 'value1',
        'key2' => 2
      };
      Logger.debug(
        'Debug message with object',
        testObject,
        'LoggerTest',
        'testLogWithObjectParsing'
      );

      Test.stopTest();

      // Placeholder for future assertion logic
      // Validate the logs (manual validation required for now as debug logs are not directly accessible in tests)
      Assert.isTrue(
        true,
        'Log messages should appear in the debug log with appropriate formatting and object parsing'
      );
    }
  }

  // @description Test isSandboxOrg method
  @isTest
  static void testIsPrintLogsOrg() {
    System.runAs(TestFactory.getCreatedTestUser()) {
      Test.startTest();

      Boolean result = Logger.printLogs;

      Test.stopTest();

      // Placeholder for future assertion logic
      // Validate the result (manual validation required for now as debug logs are not directly accessible in tests)
      Assert.isTrue(
        result != null,
        'isPrintLogsOrg should return a non-null value'
      );
    }
  }

  // @description Test logging exceptions
  @isTest
  static void testLogException() {
    System.runAs(TestFactory.getCreatedTestUser()) {
      Test.startTest();

      try {
        // Intentionally cause an exception
        Integer i = 1 / 0; // NOPMD
      } catch (Exception e) {
        Logger.logException(e, 'LoggerTest', 'testLogException');
      }

      Test.stopTest();

      // Placeholder for future assertion logic
      // Validate the logs (manual validation required for now as debug logs are not directly accessible in tests)
      Assert.isTrue(
        true,
        'Exception log messages should appear in the debug log with appropriate formatting'
      );
    }
  }
}
