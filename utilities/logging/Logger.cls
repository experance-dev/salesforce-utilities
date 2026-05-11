/**
 * @description Centralized logging utility for Salesforce applications.
 *              Provides a simple interface to log messages with varying levels of severity.
 *              Supports logging the originating class and method names.
 * @group Utilities
 * @since September 2024
 * @author David Wood
 */
public inherited sharing class Logger {
  /**
   * @description Logs a message with a specified logging level, class name, and method name.
   * @param level The logging level (e.g., DEBUG, INFO, WARN, ERROR, FATAL)
   * @param message The message to log
   * @param className (Optional) The name of the class where the log is generated
   * @param methodName (Optional) The name of the method where the log is generated
   */
  @TestVisible
  @suppresswarnings('PMD.ExcessiveParameterList')
  private static void log(
    System.LoggingLevel level,
    String message,
    String className,
    String methodName
  ) {
    String logMessage = formatLogMessage(level, message, className, methodName);
    storeLog(level, logMessage);
  }

  /**
   * @description Overloaded method to log a message with a specified logging level.
   * @param level The logging level (e.g., DEBUG, INFO, WARN, ERROR, FATAL)
   * @param message The message to log
   */
  public static void log(System.LoggingLevel level, String message) {
    log(level, message, null, null);
  }

  /**
   * @description Logs an informational message with class and method names.
   * @param message The message to log
   * @param className (Optional) The name of the class where the log is generated
   * @param methodName (Optional) The name of the method where the log is generated
   */
  public static void info(String message, String className, String methodName) {
    log(System.LoggingLevel.INFO, message, className, methodName);
  }

  /**
   * @description Overloaded method to log an informational message without class and method names.
   * @param message The message to log
   */
  public static void info(String message) {
    log(System.LoggingLevel.INFO, message);
  }

  /**
   * @description Logs an error message with class and method names.
   * @param message The message to log
   * @param className (Optional) The name of the class where the log is generated
   * @param methodName (Optional) The name of the method where the log is generated
   */
  public static void error(
    String message,
    String className,
    String methodName
  ) {
    log(System.LoggingLevel.ERROR, message, className, methodName);
  }

  /**
   * @description Overloaded method to log an error message without class and method names.
   * @param message The message to log
   */
  public static void error(String message) {
    log(System.LoggingLevel.ERROR, message);
  }

  /**
   * @description Logs a warning message with class and method names.
   * @param message The message to log
   * @param className (Optional) The name of the class where the log is generated
   * @param methodName (Optional) The name of the method where the log is generated
   */
  public static void warn(String message, String className, String methodName) {
    log(System.LoggingLevel.WARN, message, className, methodName);
  }

  /**
   * @description Overloaded method to log a warning message without class and method names.
   * @param message The message to log
   */
  public static void warn(String message) {
    log(System.LoggingLevel.WARN, message);
  }

  /**
   * @description Logs a debug message only if not in a production environment, with class and method names.
   * @param message The message to log
   * @param className (Optional) The name of the class where the log is generated
   * @param methodName (Optional) The name of the method where the log is generated
   */
  public static void debug(
    String message,
    String className,
    String methodName
  ) {
    if (printLogs) {
      log(System.LoggingLevel.DEBUG, message, className, methodName);
    }
  }

  /**
   * @description Overloaded method to log a debug message only if not in a production environment, without class and method names.
   * @param message The message to log
   */
  public static void debug(String message) {
    if (printLogs) {
      log(System.LoggingLevel.DEBUG, message);
    }
  }

  /**
   * @description Parses an object into a JSON string and logs it with class and method names.
   * @param message The message to log
   * @param objectToParse Object to parse
   * @param className (Optional) The name of the class where the log is generated
   * @param methodName (Optional) The name of the method where the log is generated
   */
  @suppresswarnings('PMD.ExcessiveParameterList')
  public static void debug(
    String message,
    Object objectToParse,
    String className,
    String methodName
  ) {
    if (printLogs) {
      try {
        String jsonString = JSON.serializePretty(objectToParse);
        log(
          System.LoggingLevel.DEBUG,
          message + '\n' + jsonString,
          className,
          methodName
        );
      } catch (Exception e) {
        log(
          LoggingLevel.WARN,
          'Failed to parse object to JSON',
          className,
          methodName
        );
        log(
          System.LoggingLevel.DEBUG,
          message + '\n' + objectToParse,
          className,
          methodName
        );
      }
    }
  }

  /**
   * @description Logs an exception with class and method names.
   * @param e The exception to log
   * @param className (Optional) The name of the class where the log is generated
   * @param methodName (Optional) The name of the method where the log is generated
   */
  public static void logException(
    Exception e,
    String className,
    String methodName
  ) {
    if (printLogs) {
      try {
        String message =
          'Exception in ' +
          className +
          '.' +
          methodName +
          ': ' +
          e.getMessage() +
          '\nStackTrace: ' +
          e.getStackTraceString();
        log(System.LoggingLevel.ERROR, message, className, methodName);
      } catch (Exception ex) {
        log(
          System.LoggingLevel.WARN,
          'Failed to log exception',
          className,
          methodName
        );
        log(
          System.LoggingLevel.ERROR,
          'Exception in ' + className + '.' + methodName + ': ' + e.getMessage()
        );
      }
    }
  }

  /**
   * @description Determines if the current environment is a sandbox.
   * @return True if in a sandbox, false otherwise
   */
  @TestVisible
  private static Boolean printLogs {
    get {
      if (printLogs == null) {
        printLogs = Log_Setting__mdt.getInstance('defaults')
          ?.Print_Debug_Logs__c ?? true;
      }
      return printLogs;
    }
    set;
  }

  /**
   * @description Formats the log message with timestamp, level, class, and method names.
   * @param level The logging level
   * @param message The message to log
   * @param className The class name
   * @param methodName The method name
   * @return The formatted log message
   */
  @TestVisible
  @suppresswarnings('PMD.ExcessiveParameterList')
  private static String formatLogMessage(
    System.LoggingLevel level,
    String message,
    String className,
    String methodName
  ) {
    String formattedMessage =
      '[' +
      Datetime.now().format('yyyy-MM-dd HH:mm:ss') +
      '] ' +
      '[' +
      level.name() +
      '] ' +
      (className != null ? '[' + className + ']' : '') +
      (methodName != null ? '[' + methodName + ']' : '') +
      ' ' +
      message;
    return formattedMessage;
  }

  /**
   * @description Stores the log message using the System.debug method.
   * @param level The logging level
   * @param logMessage The message to log
   */
  @SuppressWarnings('PMD.AvoidDebugStatements')
  @TestVisible
  private static void storeLog(System.LoggingLevel level, String logMessage) {
    System.debug(level, logMessage);
  }
}
