/**
 * @description Purges old log SObject records whose age exceeds the retention
 *              threshold defined in `Log_Clean_Up__mdt` custom metadata.
 *              Implements `Database.Stateful` so future aggregation across
 *              batch chunks remains possible.
 * @group LogCleanup
 * @author David Wood
 * @since September 2024
 * @last May 2026 — conformance refactor: explicit sharing, option-c SYSTEM_MODE
 *                   delete, Logger.logException in start(), custom exception.
 */
public without sharing class LogCleanupBatch
  implements Database.Batchable<SObject>, Database.Stateful {

  /** @description Custom exception for errors raised inside this batch. */
  public class LogCleanupBatchException extends UtilitiesModuleException {}

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
   *              same reason; bind variables are used to prevent injection.
   *
   * @param bc The batchable context reference.
   * @return All log records eligible for deletion across all configured objects.
   */
  public Iterable<SObject> start(Database.BatchableContext bc) {
    Logger.info('LogCleanupBatch starting — collecting eligible log records.', 'LogCleanupBatch', 'start');

    Map<String, Integer> logRetentionDays = context.getLogRetentionDays();
    List<SObject> allLogs = new List<SObject>();

    for (String logName : logRetentionDays.keySet()) {
      try {
        Integer daysToKeep = logRetentionDays.get(logName);
        Date cutoffDate = Date.today().addDays(-daysToKeep); //NOPMD — used as bind variable below

        // Dynamic SOQL is unavoidable: object name is runtime data from metadata.
        // No user input is concatenated; logName comes from a trusted CMT record.
        String query =
          'SELECT Id FROM ' +
          logName +
          ' WHERE CreatedDate < :cutoffDate' +
          ' AND (Do_Not_Delete__c = FALSE OR Do_Not_Delete__c = NULL)';

        allLogs.addAll(Database.query(query)); //NOPMD
      } catch (Exception ex) {
        Logger.logException(ex, 'LogCleanupBatch', 'start');
      }
    }

    return allLogs;
  }

  /**
   * @description Deletes one batch chunk of eligible log records.
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
    if (scope.isEmpty()) {
      Logger.debug('LogCleanupBatch.execute — empty scope, nothing to delete.', 'LogCleanupBatch', 'execute');
      return;
    }
    try {
      // SYSTEM_MODE bypass is intentional — see method comment above.
      Database.delete(scope, AccessLevel.SYSTEM_MODE); //NOPMD
    } catch (Exception ex) {
      Logger.logException(ex, 'LogCleanupBatch', 'execute');
      throw new LogCleanupBatchException(
        'Error deleting log records: ' + ex.getMessage() + ' — ' + ex.getStackTraceString()
      );
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
