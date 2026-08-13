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
 *
 *              Outbound-integration failures have their own sink: `logApiException`
 *              persists one `API_Exception_Log__c` row per failure under the same
 *              never-break-the-host-transaction contract. Everything free-text bound
 *              for that sink first passes through allowlist-based redaction
 *              (`scrubApiDiagnostic`) — only known-safe token shapes survive; raw
 *              request/response bodies are never persisted by default.
 * @group Logger
 * @since September 2024
 * @author David Wood
 * @last May 2026 — conformance refactor
 * @last August 2026 — error path hardened: logException ungated from printLogs, captures the exception
 *                      type name, persists Debug_Log__c as the durable sink; analyzer conformance
 * @last 2026-08-13 — API-exception sink ported; zero-DML-headroom guard on both durable sinks (read-only contexts)
 *                     behind allowlist-based redaction; logException guarded against a null exception
 */
// PMD waiver per docs/standards/static-analysis.md §3.6: facade aggregates 20+ narrow
// logging operations; per-method budgets satisfied (highest method complexity 6 < 8).
@SuppressWarnings('PMD.CyclomaticComplexity')
public inherited sharing class Logger {
  /**
   * @description Test seam: when non-null, the API-exception persist path throws this
   *              instead of inserting, so the swallow-without-rethrow contract is
   *              testable without granting a way to make real DML fail.
   */
  @TestVisible
  private static Exception apiPersistFailureForTest;

  /**
   * @description Forces `hasDmlHeadroom()` to report a zero-DML context so tests can
   *              exercise the read-only guard — the real condition (a spent or zero
   *              DML governor) cannot be fabricated inside a test transaction.
   */
  @TestVisible
  private static Boolean simulateZeroDmlHeadroom = false;

  /**
   * @description Allowlisted token shapes that survive `scrubApiDiagnostic` — short
   *              numerics (HTTP status codes, line/column refs), HTTP verbs,
   *              identifier-shaped and dotted-path tokens (class names, exception
   *              types, stack frames), UUID-shaped correlation ids, and freestanding
   *              punctuation. `@TestVisible` so tests can pin the default behavior and
   *              a consuming org can widen the list deliberately — widening is a
   *              data-governance decision, so it lives in one seam, not scattered
   *              call-site formatting.
   */
  @TestVisible
  private static List<String> apiDiagnosticAllowlist = new List<String>{
    '\\d{1,4}',
    'GET|POST|PUT|PATCH|DELETE|HEAD|OPTIONS',
    '[A-Za-z_][A-Za-z0-9_]*(?:[.:$][A-Za-z0-9_<>]+)*',
    '[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}',
    '\\p{Punct}{1,3}'
  };

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

  // ─── API exception logging ────────────────────────────────────────────────────

  /**
   * @description Persists one `API_Exception_Log__c` row for an outbound-integration
   *              failure (Jira, Slack, Workday, …) so support can report on what broke
   *              without scavenging debug logs, and mirrors an allowlist-scrubbed
   *              summary to the debug log. Self-wraps its DML — the caller never needs
   *              a try-catch, and a persistence failure degrades to a debug-log
   *              warning and is swallowed. Null-safe: a null exception still persists
   *              a row carrying the caller's context fields.
   *
   *              What lands in the row is a redacted diagnostic summary — status
   *              codes, endpoint host+path (query strings stripped), correlation ids,
   *              exception type names, and identifier-shaped tokens survive; anything
   *              else is masked. Raw request/response bodies are never persisted by
   *              default; widen the allowlist deliberately via the
   *              `apiDiagnosticAllowlist` seam if an org needs more.
   * @param apiName        Logical API / integration name (e.g. 'Jira').
   * @param operation      Specific method or step that failed.
   * @param sourceObject   SObject API name the failure was about (nullable).
   * @param sourceRecordId Record Id the failure was about (nullable).
   * @param transactionId  Correlation id, e.g. System.Request.getCurrent().getRequestId() (nullable).
   * @param ex             The thrown Apex exception (nullable).
   */
  @SuppressWarnings('PMD.ExcessiveParameterList')
  public static void logApiException(
    String apiName,
    String operation,
    String sourceObject,
    Id sourceRecordId,
    String transactionId,
    Exception ex
  ) {
    writeApiException(
      apiName,
      operation,
      sourceObject,
      sourceRecordId,
      transactionId,
      ex?.getMessage(),
      ex?.getTypeName(),
      ex?.getStackTraceString()
    );
  }

  /**
   * @description Same sink as the Exception overload, for non-exception error
   *              conditions (invalid payload, missing config, unexpected status).
   *              The message passes through the same allowlist-based redaction
   *              before it persists.
   * @param apiName        Logical API / integration name (e.g. 'Jira').
   * @param operation      Specific method or step that failed.
   * @param sourceObject   SObject API name the failure was about (nullable).
   * @param sourceRecordId Record Id the failure was about (nullable).
   * @param transactionId  Correlation id, e.g. System.Request.getCurrent().getRequestId() (nullable).
   * @param message        Free-text description of the failure (nullable; scrubbed before persist).
   */
  @SuppressWarnings('PMD.ExcessiveParameterList')
  public static void logApiException(
    String apiName,
    String operation,
    String sourceObject,
    Id sourceRecordId,
    String transactionId,
    String message
  ) {
    writeApiException(
      apiName,
      operation,
      sourceObject,
      sourceRecordId,
      transactionId,
      message,
      null,
      null
    );
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

  /**
   * @description Builds and persists the API_Exception_Log__c row. The insert runs at
   *              `AccessLevel.SYSTEM_MODE` by the same deliberate durable-sink policy
   *              as `persistErrorLog`: Logger sits beneath the DML layer (DMLManager
   *              logs through Logger, so routing back through it would create a
   *              dependency cycle), and a diagnostic sink must capture the row
   *              regardless of the running user's CRUD/FLS — dropping errors for
   *              exactly the users who lack log-object access would blind support to
   *              every failure those users generate. Contract: can never break the
   *              host transaction — the insert is wrapped in its own try-catch, and
   *              the failure fallback references only the persistence failure, never
   *              the caller's original exception (which may be null).
   * @param apiName        Logical API / integration name; truncated to field length.
   * @param operation      Failing operation or step; truncated to field length.
   * @param sourceObject   SObject API name the failure was about (nullable).
   * @param sourceRecordId Record Id the failure was about (nullable).
   * @param transactionId  Correlation id (nullable); truncated to field length.
   * @param message        Raw failure message; scrubbed and truncated before persist.
   * @param exceptionType  Exception type name, or null for non-exception failures.
   * @param stackTrace     Raw stack trace; scrubbed and truncated before persist.
   */
  @SuppressWarnings('PMD.ExcessiveParameterList')
  private static void writeApiException(
    String apiName,
    String operation,
    String sourceObject,
    Id sourceRecordId,
    String transactionId,
    String message,
    String exceptionType,
    String stackTrace
  ) {
    String scrubbedMessage = scrubApiDiagnostic(message);
    storeLog(
      System.LoggingLevel.ERROR,
      formatLogMessage(
        System.LoggingLevel.ERROR,
        '[' + apiName + '/' + operation + '] ' + scrubbedMessage,
        'Logger',
        'logApiException'
      )
    );
    if (!hasDmlHeadroom()) {
      // Read-only context: same zero-DML-governor trap as persistErrorLog — the
      // debug mirror above is the only safe sink.
      return;
    }
    try {
      if (apiPersistFailureForTest != null) {
        throw apiPersistFailureForTest;
      }
      // SYSTEM_MODE bypass is intentional — see method ApexDoc above.
      Database.insert( //NOPMD
        new API_Exception_Log__c(
          API_Name__c = apiName?.abbreviate(255),
          Operation__c = operation?.abbreviate(255),
          Source_Object__c = sourceObject?.abbreviate(255),
          Source_Record_Id__c = sourceRecordId, // implicit null-safe Id → String
          Transaction_Id__c = transactionId?.abbreviate(255),
          Severity__c = 'Error',
          Message__c = scrubbedMessage?.abbreviate(32768),
          Exception_Type__c = exceptionType?.abbreviate(255),
          Stack_Trace__c = scrubApiDiagnostic(stackTrace)?.abbreviate(32768)
        ),
        AccessLevel.SYSTEM_MODE
      );
    } catch (Exception writeFail) {
      // Warn stays debug-log-only, so this cannot recurse back into persistence,
      // and only writeFail is dereferenced — the original exception may be null.
      log(
        System.LoggingLevel.WARN,
        'API_Exception_Log__c persistence failed: ' + writeFail.getTypeName(),
        'Logger',
        'logApiException'
      );
    }
  }

  /**
   * @description Allowlist-based redaction for content destined for
   *              API_Exception_Log__c. Inverts the usual scrub direction: instead of
   *              masking known-bad patterns (which misses every PII shape nobody
   *              predicted), only tokens matching an allowlisted diagnostic shape
   *              survive, URL tokens are reduced to scheme + host + path with query
   *              strings and fragments stripped, and everything else is replaced with
   *              `[REDACTED]`. Line structure is preserved so stack traces stay
   *              readable. Null- and blank-safe.
   * @param input Raw message or stack-trace string (nullable).
   * @return Scrubbed string, or the input unchanged when null/blank.
   */
  @TestVisible
  private static String scrubApiDiagnostic(String input) {
    if (String.isBlank(input)) {
      return input;
    }
    // One alternation over the allowlist, tolerant of wrapping brackets and
    // trailing sentence punctuation so prose and stack frames survive intact.
    // Compiled per call because the allowlist itself is a mutable test seam.
    Pattern allowed = Pattern.compile(
      '[\\(\\[\\{]*(?:' +
        String.join(apiDiagnosticAllowlist, '|') +
        ')[\\)\\]\\}\\.,;:!\\?]*'
    );
    List<String> scrubbedLines = new List<String>();
    for (String line : input.split('\r?\n')) {
      List<String> keptTokens = new List<String>();
      for (String token : line.split('[ \t]+')) {
        keptTokens.add(scrubToken(token, allowed));
      }
      scrubbedLines.add(String.join(keptTokens, ' '));
    }
    return String.join(scrubbedLines, '\n');
  }

  private static String scrubToken(String token, Pattern allowed) {
    if (String.isBlank(token)) {
      return token;
    }
    if (
      token.startsWithIgnoreCase('http://') ||
      token.startsWithIgnoreCase('https://')
    ) {
      return scrubUrlToken(token);
    }
    return allowed.matcher(token).matches() ? token : '[REDACTED]';
  }

  // Reduces a URL token to scheme + host + path; query strings and fragments are
  // where credentials and record data ride, so they never survive. An authority
  // carrying embedded credentials (user:pass@host) is redacted outright.
  private static String scrubUrlToken(String token) {
    String base = token.substringBefore('?').substringBefore('#');
    return base.contains('@') ? '[REDACTED]' : base;
  }

  private static void logExceptionInternal(
    Exception e,
    String className,
    String methodName
  ) {
    if (e == null) {
      // Guard, not a throw: dereferencing a null exception in the try block would
      // land in the catch below and NPE again on the fallback's e.getMessage().
      log(
        System.LoggingLevel.WARN,
        'logException called with a null exception',
        className,
        methodName
      );
      return;
    }
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
   * @description True when the current transaction can still issue at least one DML
   *              statement. Read-only contexts (cacheable Aura reads, Visualforce
   *              getters) run with a ZERO DML governor: there, even a try-wrapped
   *              insert dies to an uncatchable `LimitException`, so callers must
   *              check headroom and skip persistence rather than attempt-and-catch.
   * @return `Boolean` true when one DML statement of headroom remains.
   */
  private static Boolean hasDmlHeadroom() {
    return !simulateZeroDmlHeadroom &&
      Limits.getLimitDmlStatements() - Limits.getDmlStatements() >= 1;
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
    if (!hasDmlHeadroom()) {
      // Read-only context (cacheable Aura read, VF getter): the DML governor is zero
      // and LimitException is uncatchable — the debug stream already written by
      // storeLog is the only safe sink here.
      return;
    }
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
