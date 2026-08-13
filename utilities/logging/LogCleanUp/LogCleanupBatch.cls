/**
 * @description Purges old log SObject records whose age exceeds the retention
 *              threshold defined in `Log_Clean_Up__mdt` custom metadata.
 *
 *              Schema contract: every SObject named in a `Log_Clean_Up__mdt` row
 *              must carry a `Do_Not_Delete__c` checkbox (default unchecked).
 *              Checked rows are excluded from the purge — the retention
 *              framework's per-record opt-out. The library ships `Debug_Log__c`
 *              as the default target, with its own `Log_Clean_Up.Debug_Log`
 *              record.
 *
 *              Capacity: `start()` returns an in-memory `Iterable`, so one run
 *              collects at most the transaction's SOQL row ceiling (50,000 rows)
 *              across all configured objects; each object's query is capped to
 *              the capacity remaining so a large backlog can never blow the
 *              limit. A backlog beyond the ceiling converges over successive
 *              scheduled runs — each run deletes up to 50k eligible rows and the
 *              next run picks up the remainder.
 * @group LogCleanup
 * @author David Wood
 * @since September 2024
 * @last May 2026 — conformance refactor: explicit sharing, option-c SYSTEM_MODE
 *                   delete, Logger.logException in start(), custom exception.
 * @last August 2026 — per-SObjectType delete isolation with log-and-continue on
 *                      failure (whole-job rethrow and its custom exception
 *                      removed); dropped unused Database.Stateful; query-row
 *                      capacity cap documented and enforced in start().
 */
public without sharing class LogCleanupBatch implements Database.Batchable<SObject> {
  private LogCleanupContext context;

  /** @description Default constructor; uses the production `LogCleanupContext`. */
  public LogCleanupBatch() {
    this.context = new LogCleanupContext();
  }

  /**
   * @description Injection constructor used in tests.
   *
   * @param context The `LogCleanupContext` (or mock) to source retention data from.
   */
  @TestVisible
  public LogCleanupBatch(LogCleanupContext context) {
    this.context = context;
  }

  /**
   * @description Queries every configured log SObject for records older than
   *              their retention threshold.  Returns an `Iterable<SObject>`
   *              rather than a `QueryLocator` because the batch spans multiple
   *              heterogeneous SObject types — a single QueryLocator cannot
   *              cover more than one object.  Dynamic SOQL is required for the
   *              same reason; the cutoff date is a bind variable.  Each object's
   *              query is capped to the remaining query-row capacity so a large
   *              backlog degrades to a partial (re-run-converging) purge instead
   *              of an uncatchable LimitException.  An unqueryable object (bad
   *              API name, missing Do_Not_Delete__c) is logged and skipped so
   *              the other configured objects still purge.
   *
   * @param bc The batchable context reference.
   * @return Log records eligible for deletion across all configured objects, up
   *         to the transaction's query-row ceiling.
   */
  public Iterable<SObject> start(Database.BatchableContext bc) {
    Logger.info(
      'LogCleanupBatch starting — collecting eligible log records.',
      'LogCleanupBatch',
      'start'
    );

    Map<String, Integer> logRetentionDays = context.getLogRetentionDays();
    List<SObject> allLogs = new List<SObject>();
    Integer remainingRowCapacity =
      Limits.getLimitQueryRows() - Limits.getQueryRows();

    for (String logName : logRetentionDays.keySet()) {
      try {
        Integer daysToKeep = logRetentionDays.get(logName);
        Date cutoffDate = Date.today().addDays(-daysToKeep); //NOPMD — used as bind variable below

        // Dynamic SOQL is unavoidable: object name is runtime data from metadata.
        // No user input is concatenated; logName comes from a trusted CMT record.
        String query =
          'SELECT Id FROM ' +
          logName +
          ' WHERE CreatedDate < :cutoffDate AND Do_Not_Delete__c = FALSE' +
          ' LIMIT ' +
          remainingRowCapacity;

        List<SObject> eligibleLogs = Database.query(query); //NOPMD
        allLogs.addAll(eligibleLogs);
        remainingRowCapacity -= eligibleLogs.size();
        if (remainingRowCapacity <= 0) {
          Logger.warn(
            'Query-row capacity reached; remaining objects purge on the next run.',
            'LogCleanupBatch',
            'start'
          );
          break;
        }
      } catch (Exception ex) {
        Logger.logException(ex, 'LogCleanupBatch', 'start');
      }
    }

    return allLogs;
  }

  /**
   * @description Deletes one batch chunk of eligible log records, grouped by
   *              SObjectType so each type's delete is isolated: a failure on one
   *              type is logged via `Logger.logException` and the remaining
   *              types still purge — the job never rethrows.
   *              Uses `Database.delete` with `AccessLevel.SYSTEM_MODE` directly,
   *              bypassing `DMLManager`, because:
   *              (a) `DMLManager.SimpleDML` now enforces `USER_MODE` on every
   *                  delete path, and (b) a scheduled purge batch must be able
   *                  to remove log records regardless of the running user's
   *                  field-level permissions.  This is the one site in the
   *                  codebase where a conscious, documented SYSTEM_MODE bypass
   *                  is appropriate.
   *
   * @param bc    The batchable context reference.
   * @param scope The log records to delete in this chunk.
   */
  public void execute(Database.BatchableContext bc, List<SObject> scope) {
    Map<Schema.SObjectType, List<SObject>> scopeByType = new Map<Schema.SObjectType, List<SObject>>();
    for (SObject record : scope) {
      Schema.SObjectType recordType = record.getSObjectType();
      if (!scopeByType.containsKey(recordType)) {
        scopeByType.put(recordType, new List<SObject>());
      }
      scopeByType.get(recordType).add(record);
    }

    for (Schema.SObjectType recordType : scopeByType.keySet()) {
      try {
        // SYSTEM_MODE bypass is intentional — see method comment above.
        Database.delete(scopeByType.get(recordType), AccessLevel.SYSTEM_MODE); //NOPMD
      } catch (Exception ex) {
        // One type's failure must not strand the others: log and continue.
        Logger.logException(ex, 'LogCleanupBatch', 'execute');
      }
    }
  }

  /**
   * @description No-op finish handler — required by the `Database.Batchable` interface.
   *
   * @param bc The batchable context reference.
   */
  @SuppressWarnings('PMD.EmptyStatementBlock') // Required for interface implementation
  public void finish(Database.BatchableContext bc) {
  }
}
