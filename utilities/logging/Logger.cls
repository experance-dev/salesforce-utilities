/**
 * @description Centralized logging utility for Salesforce applications.
 *              Provides a simple interface to log messages with varying levels of severity.
 *              Supports logging the originating class and method names.
 *              The `printLogs` flag (driven by Log_Setting__mdt) gates debug-level output;
 *              info/warn/error always write. `logException` captures message + stack trace.
 * @group Logger
 * @since September 2024
 * @author David Wood
 * @last May 2026 — conformance refactor
 */
public inherited sharing class Logger {
  // ─── Core dispatch ───────────────────────────────────────────────────────────

  /**
   * @param level The logging level (e.g., DEBUG, INFO, WARN, ERROR, FATAL)
   * @param message The message to log
   * @param className The name of the class where the log is generated
   * @param methodName The name of the method where the log is generated
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
   * @param level The logging level (e.g., DEBUG, INFO, WARN, ERROR, FATAL)
   * @param message The message to log
   */
  public static void log(System.LoggingLevel level, String message) {
    log(level, message, null, null);
  }

  // ─── Severity helpers ─────────────────────────────────────────────────────────

  /**
   * @param message The message to log
   * @param className The name of the class where the log is generated
   * @param methodName The name of the method where the log is generated
   */
  public static void info(String message, String className, String methodName) {
    log(System.LoggingLevel.INFO, message, className, methodName);
  }

  /**
   * @param message The message to log
   */
  public static void info(String message) {
    log(System.LoggingLevel.INFO, message);
  }

  /**
   * @param message The message to log
   * @param className The name of the class where the log is generated
   * @param methodName The name of the method where the log is generated
   */
  public static void error(
    String message,
    String className,
    String methodName
  ) {
    log(System.LoggingLevel.ERROR, message, className, methodName);
  }

  /**
   * @param message The message to log
   */
  public static void error(String message) {
    log(System.LoggingLevel.ERROR, message);
  }

  /**
   * @param message The message to log
   * @param className The name of the class where the log is generated
   * @param methodName The name of the method where the log is generated
   */
  public static void warn(String message, String className, String methodName) {
    log(System.LoggingLevel.WARN, message, className, methodName);
  }

  /**
   * @param message The message to log
   */
  public static void warn(String message) {
    log(System.LoggingLevel.WARN, message);
  }

  // ─── Debug helpers (gated by printLogs) ──────────────────────────────────────

  /**
   * @param message The message to log
   * @param className The name of the class where the log is generated
   * @param methodName The name of the method where the log is generated
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
   * @param message The message to log
   */
  public static void debug(String message) {
    if (printLogs) {
      log(System.LoggingLevel.DEBUG, message);
    }
  }

  /**
   * @param message The message to log
   * @param objectToParse Object to serialize as pretty JSON alongside the message
   * @param className The name of the class where the log is generated
   * @param methodName The name of the method where the log is generated
   */
  @suppresswarnings('PMD.ExcessiveParameterList')
  public static void debug(
    String message,
    Object objectToParse,
    String className,
    String methodName
  ) {
    if (printLogs) {
      logDebugWithObject(message, objectToParse, className, methodName);
    }
  }

  // ─── Exception logging ────────────────────────────────────────────────────────

  /**
   * @param e The exception to log
   * @param className The name of the class where the log is generated
   * @param methodName The name of the method where the log is generated
   */
  public static void logException(
    Exception e,
    String className,
    String methodName
  ) {
    if (printLogs) {
      logExceptionInternal(e, className, methodName);
    }
  }

  // ─── Private helpers ──────────────────────────────────────────────────────────

  private static void logDebugWithObject(
    String message,
    Object objectToParse,
    String className,
    String methodName
  ) {
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
        System.LoggingLevel.WARN,
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

  private static void logExceptionInternal(
    Exception e,
    String className,
    String methodName
  ) {
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

  // ─── Infrastructure ───────────────────────────────────────────────────────────

  /**
   * @return True if debug output is enabled (driven by Log_Setting__mdt)
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
   * @param level The logging level
   * @param message The message to log
   * @param className The class name
   * @param methodName The method name
   * @return The formatted log message with timestamp and context prefix
   */
  @TestVisible
  @suppresswarnings('PMD.ExcessiveParameterList')
  private static String formatLogMessage(
    System.LoggingLevel level,
    String message,
    String className,
    String methodName
  ) {
    return '[' +
      Datetime.now().format('yyyy-MM-dd HH:mm:ss') +
      '] ' +
      '[' +
      level.name() +
      '] ' +
      (className != null ? '[' + className + ']' : '') +
      (methodName != null ? '[' + methodName + ']' : '') +
      ' ' +
      message;
  }

  @SuppressWarnings('PMD.AvoidDebugStatements')
  @TestVisible
  private static void storeLog(System.LoggingLevel level, String logMessage) {
    System.debug(level, logMessage);
  }
}
