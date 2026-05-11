/**
 * @description Batch class for cleaning up old Block_Trigger_Log__c records.
 * This class implements the Database.Batchable interface to delete logs older than 7 days.
 * Implements Database.Stateful to maintain state across transaction boundaries.
 *
 * @author David Wood
 * @since September 2024
 * @group Logging
 */
public class LogCleanupBatch implements Database.Batchable<SObject>, Database.Stateful {
  private LogCleanupContext context;

  /**
   * @description Constructor for the LogCleanupBatch class.
   */
  public LogCleanupBatch() {
    this.context = new LogCleanupContext();
  }
  /**
   * @description Test Constructor for the LogCleanupBatch class.
   * @param context The LogCleanupContext to use for testing.
   */
  @TestVisible
  public LogCleanupBatch(LogCleanupContext context) {
    this.context = context;
    Logger.debug(
      'LogCleanupBatch test constructor called. Context initialized.'
    );
  }

  /**
   * @description Start method that provides the QueryLocator for batch processing.
   *
   * @param bc The batchable context reference.
   * @return Iterable<SObject> containing log records to be processed.
   */
  public Iterable<SObject> start(Database.BatchableContext bc) {
    Logger.debug(
      'Start method called. Retrieving log records to be processed.'
    );
    Set<SObject> allLogs = new Set<SObject>();

    // Retrieve log retention settings from context
    Map<String, Integer> logRetentionDays = context.getLogRetentionDays();

    for (String logName : logRetentionDays.keySet()) {
      try {
        Integer daysToKeep = logRetentionDays.get(logName);
        Date cutoffDate = Date.today().addDays(-daysToKeep); //NOPMD - used below in dynamic SOQL query

        // Build dynamic SOQL query
        String query =
          'SELECT Id FROM ' +
          logName +
          ' WHERE CreatedDate < :cutoffDate AND (Do_Not_Delete__c = FALSE OR Do_Not_Delete__c = NULL)';
        List<SObject> logs = Database.query(query); //NOPMD - limited SOQL potential issue

        allLogs.addAll(logs);
      } catch (Exception ex) {
        Logger.error(
          'Error retrieving logs for object: ' +
            logName +
            '. Exception: ' +
            ex.getMessage() +
            '. Stack Trace: ' +
            ex.getStackTraceString()
        );
      }
    }

    return allLogs;
  }

  /**
   * @description Execute method that processes each batch of log records.
   *
   * @param bc The batchable context reference.
   * @param scope The list of log records to be processed in this batch.
   */
  public void execute(Database.BatchableContext bc, List<SObject> scope) {
    if (!scope.isEmpty()) {
      try {
        // Delete the batch of log records
        DMLManager.deleteAsSystem(scope);
      } catch (Exception ex) {
        Logger.logException(ex, 'LogCleanupBatch', 'execute');
      }
    } else {
      Logger.debug('Scope is empty. No records to process.');
    }
  }

  /**
   * @description Finish method called after all batches have been processed.
   *
   * @param bc The batchable context reference.
   */
  @SuppressWarnings(
    'PMD.EmptyStatementBlock'
  ) // Required for interface implementation
  public void finish(Database.BatchableContext bc) {
  }
}
