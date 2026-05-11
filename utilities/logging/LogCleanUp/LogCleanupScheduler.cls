/**
 * @description Schedulable entry point that fires `LogCleanupBatch` on its
 *              configured cron schedule.  Contains no business logic; delegates
 *              entirely to the batch.  `global` is required so external orgs
 *              (e.g. subscriber orgs in a managed package) can schedule this
 *              class via the Setup UI or `System.schedule()`.
 * @group LogCleanup
 * @author David Wood
 * @since November 2024
 * @last May 2026 — conformance refactor: header cleanup, removed context
 *                   field and passthrough (scheduler owns no business state),
 *                   kept global + without sharing.
 */
@SuppressWarnings('PMD.AvoidGlobalModifier')
global without sharing class LogCleanupScheduler implements Schedulable {

  /**
   * @description Launches `LogCleanupBatch` with the default production context.
   *
   * @param sc The schedulable context reference.
   */
  global void execute(SchedulableContext sc) {
    Database.executeBatch(new LogCleanupBatch());
  }
}
