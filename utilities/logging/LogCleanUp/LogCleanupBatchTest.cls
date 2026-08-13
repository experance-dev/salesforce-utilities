/**
 * @description Tests for `LogCleanupBatch` — seeds library-owned `Debug_Log__c`
 *              fixtures with back-dated `CreatedDate` values and verifies
 *              age-based purging, the `Do_Not_Delete__c` opt-out, and
 *              log-and-continue behavior when a configured object cannot be
 *              queried. Fixtures are deterministic: each carries a marker in
 *              `Method_Name__c` and is back-dated by its own record Id — no
 *              ORDER BY CreatedDate ties, no foreign schema.
 * @group LogCleanup
 * @see LogCleanupBatch
 * @author David Wood
 * @since November 2024
 * @last May 2026 — conformance refactor
 * @last August 2026 — rewritten against library-owned Debug_Log__c with
 *                      deterministic Id-keyed fixtures
 */
@IsTest
private without sharing class LogCleanupBatchTest {
  private static final Integer RETENTION_DAYS = 30;
  private static final Integer OLD_DELETABLE_COUNT = 6;
  private static final Integer OLD_PROTECTED_COUNT = 2;
  private static final Integer RECENT_COUNT = 3;

  private static final String MARKER_OLD_DELETABLE = 'OLD_DELETABLE';
  private static final String MARKER_OLD_PROTECTED = 'OLD_PROTECTED';
  private static final String MARKER_RECENT = 'RECENT';

  @TestSetup
  static void setup() {
    // Setup-object DML (the User insert) is wrapped in System.runAs(admin)
    // inside the factory; fixture DML runs as the test's own running user.
    User runningUser = TestFactory.createTestUser();

    System.runAs(runningUser) {
      List<Debug_Log__c> fixtures = new List<Debug_Log__c>();
      for (Integer i = 0; i < OLD_DELETABLE_COUNT; i++) {
        fixtures.add(buildFixture(MARKER_OLD_DELETABLE, false));
      }
      for (Integer i = 0; i < OLD_PROTECTED_COUNT; i++) {
        fixtures.add(buildFixture(MARKER_OLD_PROTECTED, true));
      }
      for (Integer i = 0; i < RECENT_COUNT; i++) {
        fixtures.add(buildFixture(MARKER_RECENT, false));
      }
      DMLManager.insertAsSystem(fixtures);

      // Back-date each fixture keyed by its own Id and marker — deterministic,
      // no reliance on insert order or CreatedDate sorting.
      Datetime oldTimestamp = Datetime.now().addDays(-(RETENTION_DAYS + 5));
      Datetime recentTimestamp = Datetime.now().addDays(-(RETENTION_DAYS - 5));
      for (Debug_Log__c fixture : fixtures) {
        Test.setCreatedDate(
          fixture.Id,
          fixture.Method_Name__c == MARKER_RECENT
            ? recentTimestamp
            : oldTimestamp
        );
      }
    }
  }

  private static Debug_Log__c buildFixture(String marker, Boolean doNotDelete) {
    return (Debug_Log__c) TestFactory.createSObject(
      new Debug_Log__c(
        Message__c = 'LogCleanupBatchTest fixture — ' + marker,
        Class_Name__c = 'LogCleanupBatchTest',
        Method_Name__c = marker,
        Log_Level__c = 'Error',
        Do_Not_Delete__c = doNotDelete
      )
    );
  }

  @IsTest
  static void testBatchPurgesOldDeletableRowsOnly() {
    System.runAs(TestFactory.getCreatedTestUser()) {
      Set<Id> expectedSurvivorIds = new Map<Id, Debug_Log__c>(
          [
            SELECT Id
            FROM Debug_Log__c
            WHERE Method_Name__c != :MARKER_OLD_DELETABLE
          ]
        )
        .keySet();

      Test.startTest();
      Database.executeBatch(
        new LogCleanupBatch(
          new MockLogCleanupContext(
            new Map<String, Integer>{ 'Debug_Log__c' => RETENTION_DAYS }
          )
        ),
        200
      );
      Test.stopTest();

      Map<Id, Debug_Log__c> survivors = new Map<Id, Debug_Log__c>(
        [SELECT Id FROM Debug_Log__c]
      );
      Assert.areEqual(
        OLD_PROTECTED_COUNT + RECENT_COUNT,
        survivors.size(),
        'Only rows past retention without the Do_Not_Delete__c opt-out may be purged.'
      );
      Assert.areEqual(
        expectedSurvivorIds,
        survivors.keySet(),
        'Exactly the protected and recent rows must survive the purge.'
      );
    }
  }

  @IsTest
  static void testBatchContinuesPastUnqueryableObject() {
    System.runAs(TestFactory.getCreatedTestUser()) {
      Map<String, Integer> retentionWithBadObject = new Map<String, Integer>{
        'Not_A_Real_Object__c' => 10,
        'Debug_Log__c' => RETENTION_DAYS
      };

      Test.startTest();
      Database.executeBatch(
        new LogCleanupBatch(new MockLogCleanupContext(retentionWithBadObject)),
        200
      );
      Test.stopTest();

      Assert.areEqual(
        0,
        [
          SELECT COUNT()
          FROM Debug_Log__c
          WHERE Method_Name__c = :MARKER_OLD_DELETABLE
        ],
        'Old deletable rows must still purge after the unqueryable object is logged and skipped.'
      );
      Assert.areEqual(
        1,
        [
          SELECT COUNT()
          FROM Debug_Log__c
          WHERE Class_Name__c = 'LogCleanupBatch' AND Method_Name__c = 'start'
        ],
        'The unqueryable object failure must land in the durable sink via Logger.logException.'
      );
    }
  }

  @IsTest
  static void testBatchWithNoConfiguredObjectsIsANoOp() {
    System.runAs(TestFactory.getCreatedTestUser()) {
      Test.startTest();
      Database.executeBatch(
        new LogCleanupBatch(
          new MockLogCleanupContext(new Map<String, Integer>())
        ),
        200
      );
      Test.stopTest();

      Assert.areEqual(
        OLD_DELETABLE_COUNT + OLD_PROTECTED_COUNT + RECENT_COUNT,
        [SELECT COUNT() FROM Debug_Log__c],
        'With no configured objects the batch must delete nothing.'
      );
    }
  }

  @IsTest
  static void testDefaultConstructorUsesProductionContext() {
    System.runAs(TestFactory.getCreatedTestUser()) {
      LogCleanupBatch batchInstance = new LogCleanupBatch();

      Assert.isNotNull(
        batchInstance,
        'The default constructor must build a batch wired to the production LogCleanupContext.'
      );
    }
  }
}
