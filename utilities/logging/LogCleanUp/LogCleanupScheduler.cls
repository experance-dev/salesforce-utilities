/**
 * @description Batch class for cleaning up old log records.
 * This class deletes both Block_Trigger_Log__c and ATM_Endpoint_Log__c records older than a specified number of days.
 * Implements Database.Stateful to maintain state across transaction boundaries.
 *
 * @author David Wood
 * @since November 2024
 * @group Logging
 */
@SuppressWarnings('PMD.AvoidGlobalModifier')
global without sharing class LogCleanupScheduler implements Schedulable {
  private LogCleanupContext context;

  /**
   * @description Constructor for the LogCleanupScheduler class.
   */
  public LogCleanupScheduler() {
    this.context = new LogCleanupContext();
  }

  /**
   * @description Test Constructor for the LogCleanupScheduler class.
   * @param context The LogCleanupContext to use for testing.
   */
  @TestVisible
  public LogCleanupScheduler(LogCleanupContext context) {
    this.context = context;
  }

  /**
   * @description Execute method for the Schedulable interface. Starts the LogCleanupBatch.
   *
   * @param sc The schedulable context reference.
   */
  global void execute(SchedulableContext sc) {
    // Start the batch job with injected context
    Database.executeBatch(new LogCleanupBatch(this.context));
  }
}
