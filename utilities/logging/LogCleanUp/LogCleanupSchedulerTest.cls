/**
 * @description Tests for `LogCleanupScheduler` — verifies that scheduling
 *              registers the cron trigger and that firing the schedule enqueues
 *              `LogCleanupBatch`.
 * @group LogCleanup
 * @see LogCleanupScheduler
 * @author David Wood
 * @since August 2026
 * @last August 2026 — initial coverage: cron registration + batch kick
 */
@IsTest
private without sharing class LogCleanupSchedulerTest {
  // Arbitrary future daily fire time; Test.stopTest fires the job synchronously
  // regardless of the expression.
  private static final String CRON_EXPRESSION = '0 0 3 * * ?';

  @TestSetup
  static void setup() {
    TestFactory.createTestUser();
  }

  @IsTest
  static void testScheduleRegistersCronAndKicksBatch() {
    System.runAs(TestFactory.getCreatedTestUser()) {
      Test.startTest();
      String jobId = System.schedule(
        'LogCleanupSchedulerTest',
        CRON_EXPRESSION,
        new LogCleanupScheduler()
      );

      CronTrigger cronTrigger = [
        SELECT CronExpression, TimesTriggered, NextFireTime
        FROM CronTrigger
        WHERE Id = :jobId
      ];
      Assert.areEqual(
        CRON_EXPRESSION,
        cronTrigger.CronExpression,
        'The registered cron expression must match the scheduled one.'
      );
      Assert.areEqual(
        0,
        cronTrigger.TimesTriggered,
        'The job must not have fired before Test.stopTest.'
      );
      Assert.isNotNull(
        cronTrigger.NextFireTime,
        'A registered job must carry a next fire time.'
      );
      Test.stopTest(); // Fires the scheduler synchronously, which enqueues the batch.

      Assert.areEqual(
        1,
        [
          SELECT COUNT()
          FROM AsyncApexJob
          WHERE JobType = 'BatchApex' AND ApexClass.Name = 'LogCleanupBatch'
        ],
        'Firing the schedule must enqueue exactly one LogCleanupBatch run.'
      );
    }
  }
}
