/**
 * @description Centralized logging utility for Salesforce applications.
 *              Provides a simple interface to log messages with varying levels of severity.
 *              Supports logging the originating class and method names.
 *              The `printLogs` flag (driven by Log_Setting__mdt) gates debug-level output;
 *              info/warn/error always write. `logException` captures the exception's
 *              type name, message, and stack trace.
 *
 *              Durable-sink contract: error-severity entries additionally persist one
 *              `Debug_Log__c` record via a system-mode insert wrapped in its own
 *              try-catch, so logging can never break the host transaction — a failed
 *              persistence degrades to debug-log output and is swallowed. Debug, info,
 *              and warn entries remain debug-log-only until an org opts lower
 *              severities into the sink.
 * @group Logger
 * @since September 2024
 * @author David Wood
 * @last May 2026 — conformance refactor
 * @last August 2026 — error path hardened: logException ungated from printLogs, captures the exception
 *                      type name, persists Debug_Log__c as the durable sink; analyzer conformance
 */
public inherited sharing class Logger {
  // ─── Core dispatch ───────────────────────────────────────────────────────────

  /**
   * @description Core dispatch — formats the entry, writes it to the debug log,
   *              and routes error-severity entries to the durable sink.
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
    if (level == System.LoggingLevel.ERROR) {
      persistErrorLog(message, className, methodName);
    }
  }

  /**
   * @description Logs a message at the given level with no class/method context.
   * @param level The logging level (e.g., DEBUG, INFO, WARN, ERROR, FATAL)
   * @param message The message to log
   */
  public static void log(System.LoggingLevel level, String message) {
    log(level, message, null, null);
  }

  // ─── Severity helpers ─────────────────────────────────────────────────────────

  /**
   * @description Logs an info-level message with class/method context.
   * @param message The message to log
   * @param className The name of the class where the log is generated
   * @param methodName The name of the method where the log is generated
   */
  public static void info(String message, String className, String methodName) {
    log(System.LoggingLevel.INFO, message, className, methodName);
  }

  /**
   * @description Logs an info-level message.
   * @param message The message to log
   */
  public static void info(String message) {
    log(System.LoggingLevel.INFO, message);
  }

  /**
   * @description Logs an error-level message with class/method context;
   *              error severity also persists to the durable sink.
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
   * @description Logs an error-level message; error severity also persists to
   *              the durable sink.
   * @param message The message to log
   */
  public static void error(String message) {
    log(System.LoggingLevel.ERROR, message);
  }

  /**
   * @description Logs a warn-level message with class/method context.
   * @param message The message to log
   * @param className The name of the class where the log is generated
   * @param methodName The name of the method where the log is generated
   */
  public static void warn(String message, String className, String methodName) {
    log(System.LoggingLevel.WARN, message, className, methodName);
  }

  /**
   * @description Logs a warn-level message.
   * @param message The message to log
   */
  public static void warn(String message) {
    log(System.LoggingLevel.WARN, message);
  }

  // ─── Debug helpers (gated by printLogs) ──────────────────────────────────────

  /**
   * @description Logs a debug-level message with class/method context; gated by
   *              the printLogs flag.
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
   * @description Logs a debug-level message; gated by the printLogs flag.
   * @param message The message to log
   */
  public static void debug(String message) {
    if (printLogs) {
      log(System.LoggingLevel.DEBUG, message);
    }
  }

  /**
   * @description Logs a debug-level message plus a pretty-JSON rendering of the
   *              supplied object; gated by the printLogs flag.
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
   * @description Logs an exception at error severity — type name, message, and
   *              stack trace — and persists it to the durable sink. Never gated
   *              by the printLogs flag.
   * @param e The exception to log
   * @param className The name of the class where the log is generated
   * @param methodName The name of the method where the log is generated
   */
  public static void logException(
    Exception e,
    String className,
    String methodName
  ) {
    logExceptionInternal(e, className, methodName);
  }

  // ─── Private helpers ──────────────────────────────────────────────────────────

  // Mirrors the four-argument public debug overload it backs; the class/method context pair does not decompose.
  @SuppressWarnings('PMD.ExcessiveParameterList')
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
        e.getTypeName() +
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
   * @description Lazily-resolved flag gating debug-level output, driven by the
   *              `Log_Setting__mdt` 'defaults' record; defaults to true when no
   *              record exists.
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
   * @description Builds the timestamped, level- and context-prefixed log line.
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

  /**
   * @description Persists one `Debug_Log__c` record for an error-severity entry — the
   *              library's durable sink. Side effect: issues one DML insert in the
   *              caller's transaction (it counts against the caller's DML limits and,
   *              like any DML, precludes a same-transaction callout issued afterwards).
   *              Contract: this method can never break the host transaction — the
   *              insert is wrapped in its own try-catch, and a persistence failure
   *              degrades to a debug-log warning and is swallowed.
   *
   *              The insert deliberately bypasses `DMLManager` for two reasons:
   *              `Logger` sits beneath the DML layer (`DMLManager` logs through
   *              `Logger`, so routing back through it would create a dependency
   *              cycle), and log persistence must succeed regardless of the running
   *              user's CRUD/FLS — hence the direct `AccessLevel.SYSTEM_MODE` insert.
   *
   * @param message    The raw (unformatted) log message; truncated to the field length.
   * @param className  The originating class name, when the caller supplied one.
   * @param methodName The originating method name, when the caller supplied one.
   */
  @TestVisible
  private static void persistErrorLog(
    String message,
    String className,
    String methodName
  ) {
    try {
      // SYSTEM_MODE bypass is intentional — see method comment above.
      Database.insert( //NOPMD
        new Debug_Log__c(
          Message__c = message?.abbreviate(32768),
          Class_Name__c = className?.abbreviate(255),
          Method_Name__c = methodName?.abbreviate(255),
          Log_Level__c = 'Error'
        ),
        AccessLevel.SYSTEM_MODE
      );
    } catch (Exception persistFailure) {
      // Warn stays debug-log-only, so this cannot recurse back into persistence.
      log(
        System.LoggingLevel.WARN,
        'Debug_Log__c persistence failed: ' + persistFailure.getTypeName(),
        'Logger',
        'persistErrorLog'
      );
    }
  }
}
