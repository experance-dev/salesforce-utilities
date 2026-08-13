/**
 * @description Framework self-tests for the persona-matrix module (persona-matrix-testing §8):
 *              the framework must catch a rigged security gap, not merely pass clean code.
 *              Every §8 table row runs here against the library's own Debug_Log__c object
 *              (OWD Private) using the PersonaDefaults sample personas — no org-specific
 *              schema. Rigged rows (false-green, missed-denial, wrong-exception-type, ledger
 *              rows) exercise runQuietly() and the @TestVisible ledger seams, because an Apex
 *              assertion failure cannot be caught: the rigged mismatch must be observable
 *              without run() ever raising its uncatchable Assert.fail. Denial-message
 *              fragments asserted here are framework-composed strings (configuration errors,
 *              ledger lines), never guessed platform messages.
 * @group Testing
 * @see PersonaMatrix
 * @see PersonaOutcome
 * @see PersonaMatrixResult
 * @see PersonaBuilder
 * @see Persona
 * @see PersonaDefaults
 * @author David Wood
 * @since 2026-08-13
 * @last 2026-08-13 — initial §8 self-test table coverage per design Draft v3.
 */
@IsTest
private inherited sharing class PersonaMatrixTest {
  // ── Constants ────────────────────────────────────────────────────────────

  // Exact admin profile name for fixture contexts — mirrors the provisioning contract.
  private static final String ADMIN_PROFILE_NAME = 'System Administrator';

  // Message on the @TestSetup fixture row the sharing rows compare on.
  private static final String SETUP_LOG_MESSAGE = 'PersonaMatrix self-test fixture row — owned by the Library User for sharing comparisons.';

  // The deterministic username PersonaDefaults.LIBRARY_USER must always derive — the
  // durable-lookup contract under test.
  private static final String LIBRARY_USER_EXPECTED_USERNAME = 'library-user.persona@test.example.com';

  // Permission-set group fixture names for the PSG assignment row.
  private static final String TEST_GROUP_DEVELOPER_NAME = 'Persona_Matrix_Test_Group';
  private static final String MUTING_DEVELOPER_NAME = 'Persona_Matrix_Test_Muting';

  // The Debug_Log__c-granting permission set the PSG fixture wraps.
  private static final String BASE_PERMISSION_SET_NAME = 'BasePermissionsApex';

  // Flipped by TrivialQueueable so the async-rejection fixture has an observable body.
  @TestVisible
  private static Boolean queueableExecuted = false;

  // ── Fixture ──────────────────────────────────────────────────────────────

  /**
   * @description Provisions all three PersonaDefaults personas once (setup-object DML runs
   *              under provision()'s own admin runAs boundary), then inserts one
   *              Debug_Log__c owned by the Library User under an explicit admin context —
   *              the record the row-visibility and row-identity rows compare owner vs peer
   *              on. Non-setup DML sits in its own runAs block per testing-discipline §1.3.
   */
  @TestSetup
  static void setup() {
    Map<String, User> provisionedUsers = PersonaMatrix.provision(
      new List<Persona>{
        PersonaDefaults.LIBRARY_USER,
        PersonaDefaults.LIBRARY_PEER,
        PersonaDefaults.NO_ACCESS_USER
      }
    );
    System.runAs(queryActiveAdminUser()) {
      TestFactory.createSObject(
        new Debug_Log__c(
          OwnerId = provisionedUsers.get(PersonaDefaults.LIBRARY_USER.getName()).Id,
          Class_Name__c = 'PersonaMatrixTest',
          Method_Name__c = 'setup',
          Log_Level__c = 'Info',
          Message__c = SETUP_LOG_MESSAGE
        ),
        true
      );
    }
  }

  // ── §8 rows — positive path and typed denials ────────────────────────────

  /** @description §8 positive path: Library User inserts Debug_Log__c via DMLManager; allowed() passes. */
  @IsTest
  static void testPositivePathInsertViaDmlManagerAllowed() {
    List<PersonaMatrixResult> results = PersonaMatrix.of(
        new InsertDebugLogScenario('positivePath')
      )
      .persona(PersonaDefaults.LIBRARY_USER)
      .expect(PersonaOutcome.allowed())
      .run();

    Assert.areEqual(1, results.size(), 'One declared persona yields one result.');
    Assert.areEqual(
      true,
      results[0].isPassed(),
      'Library User holds create on Debug_Log__c via BasePermissionsApex — the DMLManager insert must be allowed.'
    );
    Assert.areEqual(
      2,
      [SELECT COUNT() FROM Debug_Log__c WITH USER_MODE],
      'The scenario insert must have landed alongside the @TestSetup fixture row.'
    );
  }

  /** @description §8 CRUD denial (write): No Access User's insert surfaces DMLManager.CRUDException; denied() passes. */
  @IsTest
  static void testCrudWriteDenialForNoAccessUser() {
    List<PersonaMatrixResult> results = PersonaMatrix.of(
        new InsertDebugLogScenario('crudDenial')
      )
      .persona(PersonaDefaults.NO_ACCESS_USER)
      .expect(PersonaOutcome.denied(DMLManager.CRUDException.class))
      .run();

    Assert.areEqual(
      true,
      results[0].isPassed(),
      'No Access User holds no create permission — DMLManager\'s CRUD pre-check must throw CRUDException and denied() must pass.'
    );
    Assert.areEqual(
      1,
      [SELECT COUNT() FROM Debug_Log__c WITH USER_MODE],
      'The denied insert must not have created a row — only the @TestSetup fixture exists.'
    );
  }

  /** @description §8 read denial (no object permission): WITH USER_MODE read as No Access User throws System.QueryException. */
  @IsTest
  static void testReadDenialWithoutObjectPermission() {
    List<PersonaMatrixResult> results = PersonaMatrix.of(new ReadDebugLogsScenario())
      .persona(PersonaDefaults.NO_ACCESS_USER)
      .expect(PersonaOutcome.denied(System.QueryException.class))
      .run();

    Assert.areEqual(
      true,
      results[0].isPassed(),
      'Without object read permission a WITH USER_MODE query must throw System.QueryException, satisfying denied().'
    );
  }

  // ── §8 rows — sharing: row visibility and row identity ───────────────────

  /** @description §8 row visibility: owner sees the fixture row, peer with identical permissions sees nothing. */
  @IsTest
  static void testRowVisibilityOwnerSeesPeerDoesNot() {
    List<PersonaMatrixResult> results = PersonaMatrix.of(new ReadDebugLogsScenario())
      .persona(PersonaDefaults.LIBRARY_USER)
      .expect(PersonaOutcome.allowed().returnedRows(1))
      .persona(PersonaDefaults.LIBRARY_PEER)
      .expect(PersonaOutcome.seesNoRows())
      .run();

    Assert.areEqual(
      2,
      results.size(),
      'Both personas ran: the owner returnedRows(1) and the permissions-identical peer seesNoRows() — sharing, not CRUD, is the difference.'
    );
  }

  /** @description §8 row identity (pass half): returnedRowIds over the known fixture record passes for the owner. */
  @IsTest
  static void testRowIdentityMatchesKnownRecords() {
    Set<Id> expectedIds = new Set<Id>{ querySetupLogId() };

    List<PersonaMatrixResult> results = PersonaMatrix.of(new ReadDebugLogsScenario())
      .persona(PersonaDefaults.LIBRARY_USER)
      .expect(PersonaOutcome.allowed().returnedRowIds(expectedIds))
      .run();

    Assert.areEqual(
      true,
      results[0].isPassed(),
      'The owner\'s read must return exactly the fixture record\'s Id — order-insensitive set equality.'
    );
  }

  /** @description §8 row identity (rigged half): a wrong expected-Id set records a mismatch, not a pass. */
  @IsTest
  static void testRowIdentityWrongIdSetRecordsMismatch() {
    Id wrongId = Utilities.getFakeId(Debug_Log__c.SObjectType);

    List<PersonaMatrixResult> results = PersonaMatrix.of(new ReadDebugLogsScenario())
      .persona(PersonaDefaults.LIBRARY_USER)
      .expect(PersonaOutcome.allowed().returnedRowIds(new Set<Id>{ wrongId }))
      .runQuietly();

    Assert.areEqual(
      false,
      results[0].isPassed(),
      'A leaked-wrong-row bug must not pass a row-identity assert — the wrong Id set is a mismatch.'
    );
    Assert.isTrue(
      results[0].getMismatchDetail().contains('expected row Ids'),
      'The mismatch detail must carry the framework\'s row-Id wording. Got: ' +
        results[0].getMismatchDetail()
    );
  }

  // ── §8 rows — rigged-gap detection (runQuietly + ledger seams only) ─────

  /** @description §8 false-green detection: a rigged allowed() on a denied persona fails, and the ledger names the persona. */
  @IsTest
  static void testFalseGreenDetectionFailsMatrix() {
    List<PersonaMatrixResult> results = PersonaMatrix.of(
        new InsertDebugLogScenario('falseGreen')
      )
      .persona(PersonaDefaults.NO_ACCESS_USER)
      .expect(PersonaOutcome.allowed()) // Rigged: this persona cannot insert.
      .runQuietly();

    Assert.areEqual(
      false,
      results[0].isPassed(),
      'The rigged allowed() expectation must be recorded as a mismatch — the framework caught the false green.'
    );
    Assert.isTrue(
      results[0].getMismatchDetail().contains('expected allowed; scenario threw'),
      'The mismatch must carry the framework\'s allowed-but-threw wording. Got: ' +
        results[0].getMismatchDetail()
    );
    String ledger = PersonaMatrix.buildLedger(
      'InsertDebugLogScenario',
      results,
      results.size()
    );
    Assert.isTrue(
      ledger.contains('[FAIL] ' + PersonaDefaults.NO_ACCESS_USER.getName()),
      'The failure ledger must name the rigged persona on its [FAIL] line. Got: ' + ledger
    );
  }

  /** @description §8 missed-denial detection: a rigged denied() on an allowed persona fails — completing is the mismatch. */
  @IsTest
  static void testMissedDenialDetectionFailsMatrix() {
    List<PersonaMatrixResult> results = PersonaMatrix.of(
        new InsertDebugLogScenario('missedDenial')
      )
      .persona(PersonaDefaults.LIBRARY_USER)
      .expect(PersonaOutcome.denied(DMLManager.CRUDException.class)) // Rigged: this persona CAN insert.
      .runQuietly();

    Assert.areEqual(
      false,
      results[0].isPassed(),
      'A scenario completing where a denial was declared is the security gap the framework exists to catch.'
    );
    Assert.isTrue(
      results[0].getMismatchDetail().contains('scenario COMPLETED — security gap'),
      'The mismatch must carry the framework\'s security-gap wording. Got: ' +
        results[0].getMismatchDetail()
    );
  }

  /** @description §8 wrong exception type: a deliberate NullPointerException is a type mismatch against denied(CRUDException), never a pass. */
  @IsTest
  static void testWrongExceptionTypeRecordsMismatch() {
    List<PersonaMatrixResult> results = PersonaMatrix.of(new NullDereferenceScenario())
      .persona(PersonaDefaults.LIBRARY_USER)
      .expect(PersonaOutcome.denied(DMLManager.CRUDException.class))
      .runQuietly();

    Assert.areEqual(
      false,
      results[0].isPassed(),
      'A NullPointerException is not a denial — the exact-type comparison must record a mismatch.'
    );
    Assert.isTrue(
      results[0].getMismatchDetail().contains('expected denied(DMLManager.CRUDException)'),
      'The mismatch must restate the expected type. Got: ' + results[0].getMismatchDetail()
    );
    Assert.isTrue(
      results[0].getMismatchDetail().contains('System.NullPointerException'),
      'The mismatch must name the actually thrown type. Got: ' +
        results[0].getMismatchDetail()
    );
  }

  // ── §8 rows — configuration errors ───────────────────────────────────────

  /** @description §8 unprovisioned persona: a persona never provisioned is a configuration error before any runAs. */
  @IsTest
  static void testUnprovisionedPersonaFailsBeforeAnyRunAs() {
    Persona ghostPersona = PersonaBuilder.named('Ghost User').build();
    String caughtMessage;

    try {
      PersonaMatrix.of(new ReadDebugLogsScenario())
        .persona(ghostPersona)
        .expect(PersonaOutcome.allowed())
        .runQuietly();
    } catch (PersonaMatrix.PersonaMatrixException configurationError) {
      caughtMessage = configurationError.getMessage();
    }

    Assert.isNotNull(
      caughtMessage,
      'A never-provisioned persona must raise a PersonaMatrixException, not execute.'
    );
    Assert.isTrue(
      caughtMessage.contains('not provisioned'),
      'The configuration error must carry the not-provisioned remediation wording. Got: ' +
        caughtMessage
    );
  }

  /** @description §8 incompatible refinements: denied(...).returnedRows(...) is a configuration error at run() start. */
  @IsTest
  static void testIncompatibleRefinementsRejectedAtRunStart() {
    String caughtMessage;

    try {
      PersonaMatrix.of(new ReadDebugLogsScenario())
        .persona(PersonaDefaults.LIBRARY_USER)
        .expect(PersonaOutcome.denied(DMLManager.CRUDException.class).returnedRows(1))
        .runQuietly();
    } catch (PersonaMatrix.PersonaMatrixException configurationError) {
      caughtMessage = configurationError.getMessage();
    }

    Assert.isNotNull(
      caughtMessage,
      'denied(...).returnedRows(...) must be rejected before any runAs executes.'
    );
    Assert.isTrue(
      caughtMessage.contains('cannot carry returnedRows'),
      'The configuration error must carry the refinement-incompatibility wording. Got: ' +
        caughtMessage
    );
  }

  /** @description §8 async rejection: a scenario enqueueing a queueable is a configuration failure naming the persona. */
  @IsTest
  static void testAsyncEnqueueRejectedNamingPersona() {
    String caughtMessage;

    Test.startTest();
    try {
      PersonaMatrix.of(new EnqueueQueueableScenario())
        .persona(PersonaDefaults.LIBRARY_USER)
        .expect(PersonaOutcome.allowed())
        .runQuietly();
    } catch (PersonaMatrix.PersonaMatrixException asyncRejection) {
      caughtMessage = asyncRejection.getMessage();
    }
    Test.stopTest();

    Assert.isNotNull(
      caughtMessage,
      'The loop runner must reject an async enqueue outright — queued work executes after the ledger.'
    );
    Assert.isTrue(
      caughtMessage.contains(PersonaDefaults.LIBRARY_USER.getName()),
      'The rejection must name the enqueuing persona. Got: ' + caughtMessage
    );
    Assert.isTrue(
      caughtMessage.contains('enqueued async work'),
      'The rejection must carry the framework\'s async wording. Got: ' + caughtMessage
    );
  }

  // ── §8 rows — ledger guarantees ──────────────────────────────────────────

  /** @description §8 ledger completeness: three personas, two rigged to fail — the ledger carries all three lines. */
  @IsTest
  static void testLedgerCompletenessNamesEveryPersona() {
    List<PersonaMatrixResult> results = PersonaMatrix.of(
        new InsertDebugLogScenario('ledgerCompleteness')
      )
      .persona(PersonaDefaults.LIBRARY_USER)
      .expect(PersonaOutcome.allowed())
      .persona(PersonaDefaults.LIBRARY_PEER)
      .expect(PersonaOutcome.denied(DMLManager.CRUDException.class)) // Rigged: the peer CAN insert.
      .persona(PersonaDefaults.NO_ACCESS_USER)
      .expect(PersonaOutcome.allowed()) // Rigged: no-access CANNOT insert.
      .runQuietly();

    String ledger = PersonaMatrix.buildLedger(
      'InsertDebugLogScenario',
      results,
      results.size()
    );
    Assert.isTrue(
      ledger.contains('2 of 3 personas failed'),
      'The ledger header must total both rigged failures. Got: ' + ledger
    );
    Assert.isTrue(
      ledger.contains(PersonaDefaults.LIBRARY_USER.getName()) &&
        ledger.contains(PersonaDefaults.LIBRARY_PEER.getName()) &&
        ledger.contains(PersonaDefaults.NO_ACCESS_USER.getName()),
      'The ledger must carry one line per persona, pass or fail — no mid-loop assert may silence a later persona. Got: ' +
        ledger
    );
  }

  /** @description §8 ledger cap: an over-long ledger is capped with the omitted-lines tail; a short ledger passes through untouched. */
  @IsTest
  static void testLedgerCapAppendsOmittedLinesTail() {
    List<String> longLines = new List<String>();
    for (Integer lineIndex = 0; lineIndex < 100; lineIndex++) {
      longLines.add('  [FAIL] Persona ' + lineIndex + '  ' + 'x'.repeat(80));
    }
    String longLedger = String.join(longLines, '\n');

    String cappedLedger = PersonaMatrix.capLedger(longLedger);

    Assert.isTrue(
      cappedLedger.length() <= 3500,
      'The capped ledger must fit the ~3,500-character Assert.fail budget; got length ' +
        cappedLedger.length()
    );
    Assert.isTrue(
      cappedLedger.contains('more lines — see debug log'),
      'The cap must append the omitted-lines tail pointing at the full debug-log ledger. Got tail: ' +
        cappedLedger.right(80)
    );
    String shortLedger = 'PersonaMatrix: 0 of 1 personas failed — scenario ShortScenario';
    Assert.areEqual(
      shortLedger,
      PersonaMatrix.capLedger(shortLedger),
      'A ledger under the cap must pass through unmodified.'
    );
  }

  /** @description §8 limits accounting: exact per-persona SOQL delta; runAs DML charges excluded per-persona but included in the totals line. */
  @IsTest
  static void testLimitsAccountingExactDeltasAndTotals() {
    List<PersonaMatrixResult> results = PersonaMatrix.of(new TwoCountQueriesScenario())
      .persona(PersonaDefaults.LIBRARY_USER)
      .expect(PersonaOutcome.allowed())
      .run();

    Assert.areEqual(
      2,
      results[0].getSoqlDelta(),
      'The scenario issues exactly two SOQL queries — the per-persona delta must match exactly.'
    );
    Assert.areEqual(
      0,
      results[0].getDmlStatementsDelta(),
      'The runAs call\'s own DML-statement charge is excluded from the per-persona delta (snapshot taken inside the block).'
    );
    String ledger = PersonaMatrix.buildLedger(
      'TwoCountQueriesScenario',
      results,
      results.size()
    );
    Assert.isTrue(
      ledger.contains('limits: 2/'),
      'The totals line must carry the scenario SOQL total. Got: ' + ledger
    );
    Assert.isTrue(
      ledger.contains('DML scenario 0 + runAs 1 = 1/'),
      'The totals line must add the runAs charge back into the denominator-facing DML number. Got: ' +
        ledger
    );
  }

  // ── §8 rows — provisioning contract ──────────────────────────────────────

  /** @description §8 durable lookup: provisioned in @TestSetup, re-resolved via userFor() across the transaction boundary. */
  @IsTest
  static void testDurableLookupResolvesAcrossTransactions() {
    User resolvedByPersona = PersonaMatrix.userFor(PersonaDefaults.LIBRARY_USER);
    User resolvedByName = PersonaMatrix.userFor(PersonaDefaults.LIBRARY_USER.getName());

    Assert.areEqual(
      LIBRARY_USER_EXPECTED_USERNAME,
      resolvedByPersona.Username,
      'The deterministic username is the durable lookup key — statics do not survive the @TestSetup boundary, the query does.'
    );
    Assert.areEqual(
      resolvedByPersona.Id,
      resolvedByName.Id,
      'The name-keyed userFor overload must resolve the same provisioned user as the Persona-keyed one.'
    );
  }

  /** @description §8 idempotent re-provision: the identical definition is a no-op returning the same user, no duplicate. */
  @IsTest
  static void testIdempotentReProvisionIsNoOp() {
    User provisionedInSetup = PersonaMatrix.userFor(PersonaDefaults.LIBRARY_USER);

    Map<String, User> reProvisionedUsers = PersonaMatrix.provision(
      new List<Persona>{ PersonaDefaults.LIBRARY_USER }
    );

    Assert.areEqual(
      provisionedInSetup.Id,
      reProvisionedUsers.get(PersonaDefaults.LIBRARY_USER.getName()).Id,
      'Re-provisioning the identical definition must return the existing user, not fabricate another.'
    );
    Assert.areEqual(
      1,
      [
        SELECT COUNT()
        FROM User
        WHERE Username = :LIBRARY_USER_EXPECTED_USERNAME
        WITH USER_MODE
      ],
      'Exactly one user may exist for the deterministic username — idempotency created no duplicate.'
    );
  }

  /** @description §8 conflicting re-provision: same persona name, different ladder — a configuration conflict error. */
  @IsTest
  static void testConflictingReProvisionThrowsConfigurationConflict() {
    // Same name as PersonaDefaults.LIBRARY_USER, but an empty ladder — a different definition.
    Persona conflictingDefinition = PersonaBuilder.named(
        PersonaDefaults.LIBRARY_USER.getName()
      )
      .build();

    String caughtMessage = provisionExpectingConfigurationError(conflictingDefinition);

    Assert.isNotNull(
      caughtMessage,
      'Two fixtures must not silently share one user — the conflicting definition must throw.'
    );
    Assert.isTrue(
      caughtMessage.contains('configuration conflict'),
      'The error must carry the configuration-conflict wording. Got: ' + caughtMessage
    );
  }

  /** @description §8 permission-set resolution: a missing permission-set name fails fast with a named error. */
  @IsTest
  static void testMissingPermissionSetFailsFast() {
    String caughtMessage = provisionExpectingConfigurationError(
      PersonaBuilder.named('Missing Set User')
        .permissionSet('Persona_Matrix_Missing_Set')
        .build()
    );

    Assert.isNotNull(caughtMessage, 'A missing permission set must fail provisioning fast.');
    Assert.isTrue(
      caughtMessage.contains('permission set') &&
        caughtMessage.contains('not found by exact name'),
      'The error must name the kind and the exact-name contract. Got: ' + caughtMessage
    );
  }

  /** @description §8 permission-set resolution (profile): a missing exact profile name fails fast with a named error. */
  @IsTest
  static void testMissingProfileFailsFast() {
    String caughtMessage = provisionExpectingConfigurationError(
      PersonaBuilder.named('Missing Profile User')
        .profile('Persona Matrix Missing Profile')
        .build()
    );

    Assert.isNotNull(caughtMessage, 'A missing profile must fail provisioning fast.');
    Assert.isTrue(
      caughtMessage.contains('profile') &&
        caughtMessage.contains('not found by exact name'),
      'The error must name the kind and the exact-name contract. Got: ' + caughtMessage
    );
  }

  /** @description §8 permission-set resolution (role): a missing role DeveloperName fails fast with a named error. */
  @IsTest
  static void testMissingRoleFailsFast() {
    String caughtMessage = provisionExpectingConfigurationError(
      PersonaBuilder.named('Missing Role User')
        .role('Persona_Matrix_Missing_Role')
        .build()
    );

    Assert.isNotNull(caughtMessage, 'A missing role must fail provisioning fast.');
    Assert.isTrue(
      caughtMessage.contains('role') && caughtMessage.contains('not found by exact name'),
      'The error must name the kind and the exact-name contract. Got: ' + caughtMessage
    );
  }

  /** @description §8 permission-set resolution (group): a missing permission-set-group DeveloperName fails fast with a named error. */
  @IsTest
  static void testMissingPermissionSetGroupFailsFast() {
    String caughtMessage = provisionExpectingConfigurationError(
      PersonaBuilder.named('Missing Group User')
        .permissionSetGroup('Persona_Matrix_Missing_Group')
        .build()
    );

    Assert.isNotNull(
      caughtMessage,
      'A missing permission-set group must fail provisioning fast.'
    );
    Assert.isTrue(
      caughtMessage.contains('permission set group') &&
        caughtMessage.contains('not found by exact name'),
      'The error must name the kind and the exact-name contract. Got: ' + caughtMessage
    );
  }

  // ── §8 rows — permission-set-group assignment ────────────────────────────

  /** @description §8 PSG assignment: an in-test PermissionSetGroup wrapping BasePermissionsApex, calculated and assigned via .permissionSetGroup(), honors its grants; muting coverage is a best-effort probe (§10 item 3). */
  @IsTest
  static void testPermissionSetGroupAssignmentHonorsGrants() {
    User adminUser = queryActiveAdminUser();
    Id personaGroupId = createCalculatedPermissionSetGroup(adminUser);

    Persona groupUser = PersonaBuilder.named('Group User')
      .permissionSetGroup(TEST_GROUP_DEVELOPER_NAME)
      .build();
    PersonaMatrix.provision(new List<Persona>{ groupUser });

    List<PersonaMatrixResult> grantResults = PersonaMatrix.of(
        new InsertDebugLogScenario('psgGrant')
      )
      .persona(groupUser)
      .expect(PersonaOutcome.allowed())
      .run();
    Assert.areEqual(
      true,
      grantResults[0].isPassed(),
      'The PSG wraps BasePermissionsApex — create on Debug_Log__c must be granted through the group assignment.'
    );

    // Muting half of the row: MutingPermissionSet creatability from Apex is spec §10 open
    // item 3. When any muting step is platform-rejected the probe records the gap and the
    // grant assertions above stand as the row's coverage.
    if (tryCreateMutingPermissionSet(adminUser, personaGroupId)) {
      Persona mutedGroupUser = PersonaBuilder.named('Muted Group User')
        .permissionSetGroup(TEST_GROUP_DEVELOPER_NAME)
        .build();
      PersonaMatrix.provision(new List<Persona>{ mutedGroupUser });
      PersonaMatrix.of(new InsertDebugLogScenario('psgMuted'))
        .persona(mutedGroupUser)
        .expect(PersonaOutcome.denied(DMLManager.CRUDException.class))
        .run();
    }
  }

  // ── §8 rows — permutation invariance ─────────────────────────────────────

  /** @description §8 order permutation: the same write matrix run in both declaration orders yields identical per-persona outcomes. */
  @IsTest
  static void testOrderPermutationYieldsIdenticalOutcomes() {
    List<PersonaMatrixResult> forwardResults = PersonaMatrix.of(
        new InsertDebugLogScenario('permutationForward')
      )
      .persona(PersonaDefaults.LIBRARY_USER)
      .expect(PersonaOutcome.allowed())
      .persona(PersonaDefaults.NO_ACCESS_USER)
      .expect(PersonaOutcome.denied(DMLManager.CRUDException.class))
      .runQuietly();

    List<PersonaMatrixResult> reverseResults = PersonaMatrix.of(
        new InsertDebugLogScenario('permutationReverse')
      )
      .persona(PersonaDefaults.NO_ACCESS_USER)
      .expect(PersonaOutcome.denied(DMLManager.CRUDException.class))
      .persona(PersonaDefaults.LIBRARY_USER)
      .expect(PersonaOutcome.allowed())
      .runQuietly();

    for (String personaName : new List<String>{
      PersonaDefaults.LIBRARY_USER.getName(),
      PersonaDefaults.NO_ACCESS_USER.getName()
    }) {
      Assert.areEqual(
        true,
        resultFor(forwardResults, personaName).isPassed(),
        'Persona \'' + personaName + '\' must pass in declaration order A.'
      );
      Assert.areEqual(
        resultFor(forwardResults, personaName).isPassed(),
        resultFor(reverseResults, personaName).isPassed(),
        'Persona \'' +
          personaName +
          '\' must record the identical outcome in both declaration orders — permutation invariance is the contract.'
      );
    }
  }

  // ── §8 rows — custom checks and return shapes ────────────────────────────

  /** @description §8 custom check throws: the throwing check is that persona's mismatch; later personas still run. */
  @IsTest
  static void testCustomCheckThrowingRecordsMismatchOnly() {
    List<PersonaMatrixResult> results = PersonaMatrix.of(new ReadDebugLogsScenario())
      .persona(PersonaDefaults.LIBRARY_USER)
      .expect(PersonaOutcome.custom(new ThrowingCheck()))
      .persona(PersonaDefaults.LIBRARY_PEER)
      .expect(PersonaOutcome.seesNoRows())
      .runQuietly();

    Assert.areEqual(
      2,
      results.size(),
      'The throwing check must not crash the matrix — the later persona still ran.'
    );
    Assert.areEqual(
      false,
      results[0].isPassed(),
      'The throwing check is recorded as its persona\'s mismatch.'
    );
    Assert.isTrue(
      results[0].getMismatchDetail().contains('custom check threw'),
      'The mismatch must carry the framework\'s check-threw wording. Got: ' +
        results[0].getMismatchDetail()
    );
    Assert.areEqual(
      true,
      results[1].isPassed(),
      'The persona after the throwing check must evaluate normally.'
    );
  }

  /** @description §8 return shapes: a returned List is compared by size. */
  @IsTest
  static void testReturnShapeListComparedBySize() {
    List<PersonaMatrixResult> results = PersonaMatrix.of(new ReadDebugLogsScenario())
      .persona(PersonaDefaults.LIBRARY_USER)
      .expect(PersonaOutcome.allowed().returnedRows(1))
      .run();

    Assert.areEqual(
      true,
      results[0].isPassed(),
      'A returned List must satisfy returnedRows by its size.'
    );
  }

  /** @description §8 return shapes: a returned Integer is compared directly — the SELECT COUNT() idiom. */
  @IsTest
  static void testReturnShapeIntegerCountIdiom() {
    List<PersonaMatrixResult> results = PersonaMatrix.of(new CountDebugLogsScenario())
      .persona(PersonaDefaults.LIBRARY_USER)
      .expect(PersonaOutcome.allowed().returnedRows(1))
      .run();

    Assert.areEqual(
      true,
      results[0].isPassed(),
      'A returned Integer must satisfy returnedRows by direct comparison.'
    );
  }

  /** @description §8 return shapes: a null return against returnedRows is a named mismatch, never a pass. */
  @IsTest
  static void testReturnShapeNullReturnIsMismatch() {
    List<PersonaMatrixResult> results = PersonaMatrix.of(new FixedValueScenario(null))
      .persona(PersonaDefaults.LIBRARY_USER)
      .expect(PersonaOutcome.allowed().returnedRows(0))
      .runQuietly();

    Assert.areEqual(
      false,
      results[0].isPassed(),
      'null is not zero rows — returnedRows must record a mismatch for a null return.'
    );
    Assert.isTrue(
      results[0].getMismatchDetail().contains('scenario returned null'),
      'The mismatch must carry the framework\'s null-return wording. Got: ' +
        results[0].getMismatchDetail()
    );
  }

  /** @description §8 return shapes: a return that is neither a List nor an Integer is a mismatch. */
  @IsTest
  static void testReturnShapeUnsupportedTypeIsMismatch() {
    List<PersonaMatrixResult> results = PersonaMatrix.of(
        new FixedValueScenario('not-a-row-shape')
      )
      .persona(PersonaDefaults.LIBRARY_USER)
      .expect(PersonaOutcome.allowed().returnedRows(1))
      .runQuietly();

    Assert.areEqual(
      false,
      results[0].isPassed(),
      'A non-List, non-Integer return cannot satisfy returnedRows.'
    );
    Assert.isTrue(
      results[0].getMismatchDetail().contains('neither a List nor an Integer'),
      'The mismatch must carry the framework\'s unsupported-shape wording. Got: ' +
        results[0].getMismatchDetail()
    );
  }

  // ── Helpers ──────────────────────────────────────────────────────────────

  // Admin context for fixture DML and PSG creation — exact profile name, single row.
  private static User queryActiveAdminUser() {
    // SOQL: exact profile name; test fixture context.
    return [
      SELECT Id
      FROM User
      WHERE Profile.Name = :ADMIN_PROFILE_NAME AND IsActive = TRUE
      WITH USER_MODE
      LIMIT 1
    ];
  }

  // The single @TestSetup fixture row's Id — the known record for row-identity asserts.
  private static Id querySetupLogId() {
    // SOQL: the one fixture row; admin test context sees it.
    return [SELECT Id FROM Debug_Log__c WITH USER_MODE LIMIT 1].Id;
  }

  // Finds one persona's result by name — declaration order differs across permutation runs.
  private static PersonaMatrixResult resultFor(
    List<PersonaMatrixResult> results,
    String personaName
  ) {
    for (PersonaMatrixResult result : results) {
      if (result.getPersonaName() == personaName) {
        return result;
      }
    }
    Assert.fail('No result recorded for persona \'' + personaName + '\'.');
    return null; // Unreachable — Assert.fail always throws.
  }

  // Shared catch harness for provisioning rows that must fail fast: returns the thrown
  // configuration error's message, or null when provisioning wrongly succeeded.
  private static String provisionExpectingConfigurationError(Persona misconfigured) {
    try {
      PersonaMatrix.provision(new List<Persona>{ misconfigured });
    } catch (PersonaMatrix.PersonaMatrixException resolutionFailure) {
      return resolutionFailure.getMessage();
    }
    return null;
  }

  // Creates the PSG fixture wrapping BasePermissionsApex and forces calculation, so an
  // 'Updating' group can never flake the assignment (spec §7). Setup-object fixture DML in
  // SYSTEM_MODE under an explicit admin runAs — the same posture PersonaMatrix provisioning
  // uses.
  private static Id createCalculatedPermissionSetGroup(User adminUser) {
    PermissionSetGroup personaGroup;
    System.runAs(adminUser) {
      // SOQL: exact-name lookup mirroring the provisioning contract; excludes profile-owned
      // shadow rows.
      Id basePermissionSetId = [
        SELECT Id
        FROM PermissionSet
        WHERE Name = :BASE_PERMISSION_SET_NAME AND IsOwnedByProfile = FALSE
        WITH USER_MODE
        LIMIT 1
      ]
      .Id;
      personaGroup = new PermissionSetGroup(
        DeveloperName = TEST_GROUP_DEVELOPER_NAME,
        MasterLabel = 'Persona Matrix Test Group'
      );
      Database.insert(personaGroup, AccessLevel.SYSTEM_MODE);
      Database.insert(
        new PermissionSetGroupComponent(
          PermissionSetGroupId = personaGroup.Id,
          PermissionSetId = basePermissionSetId
        ),
        AccessLevel.SYSTEM_MODE
      );
      Test.calculatePermissionSetGroup(new List<Id>{ personaGroup.Id });
    }
    return personaGroup.Id;
  }

  // Best-effort muting probe for the §8 PSG row. MutingPermissionSet creatability from Apex
  // is spec §10 open item 3, so every step is dynamic and defensive: a platform rejection at
  // any point returns false and the gap evidence lands in the debug log (the sanctioned home
  // for self-test observations — this is @IsTest infrastructure, not a production path).
  // Muting semantics: a true Permissions* value on the muting set MUTES that permission, so
  // PermissionsCreate = true removes create while read stays granted.
  @SuppressWarnings('PMD.AvoidDebugStatements')
  private static Boolean tryCreateMutingPermissionSet(User adminUser, Id personaGroupId) {
    try {
      System.runAs(adminUser) {
        Schema.SObjectType mutingType = Schema.getGlobalDescribe()
          .get('MutingPermissionSet');
        if (mutingType == null) {
          throw new IllegalArgumentException(
            'MutingPermissionSet SObjectType is not present in this org.'
          );
        }
        SObject mutingSet = mutingType.newSObject();
        mutingSet.put('MasterLabel', 'Persona Matrix Test Muting');
        mutingSet.put('DeveloperName', MUTING_DEVELOPER_NAME);
        mutingSet.put('PermissionSetGroupId', personaGroupId);
        Database.insert(mutingSet, AccessLevel.SYSTEM_MODE);
        Database.insert(
          new ObjectPermissions(
            ParentId = mutingSet.Id,
            SobjectType = 'Debug_Log__c',
            PermissionsCreate = true,
            PermissionsRead = false
          ),
          AccessLevel.SYSTEM_MODE
        );
        Test.calculatePermissionSetGroup(new List<Id>{ personaGroupId });
      }
      return true;
    } catch (Exception mutingProbeFailure) {
      System.debug(
        LoggingLevel.WARN,
        'PersonaMatrixTest: muting coverage unavailable — ' +
          mutingProbeFailure.getTypeName() +
          ': ' +
          mutingProbeFailure.getMessage()
      );
      return false;
    }
  }

  // ── Scenario fixtures ────────────────────────────────────────────────────

  // Write scenario: inserts one Debug_Log__c through DMLManager as the running persona.
  // Per-persona payloads derive from ctx.getPersonaName(), so no persona's run can
  // contaminate another's (spec §6.4) and both declaration orders act on their own rows.
  private class InsertDebugLogScenario implements PersonaScenario {
    private final String methodLabel;

    private InsertDebugLogScenario(String methodLabel) {
      this.methodLabel = methodLabel;
    }

    /**
     * @description Inserts one Debug_Log__c via DMLManager.insertAsUser — the CRUD-enforced
     *              write path whose denial surface is DMLManager.CRUDException.
     * @param ctx The running persona's context.
     * @return `Object` always null — only completion (or the typed denial) matters.
     */
    public Object run(PersonaContext ctx) {
      DMLManager.insertAsUser(
        new Debug_Log__c(
          Class_Name__c = 'PersonaMatrixTest',
          Method_Name__c = this.methodLabel,
          Log_Level__c = 'Info',
          Message__c = 'PersonaMatrix self-test insert as ' + ctx.getPersonaName()
        )
      );
      return null;
    }
  }

  // Read scenario: sharing-enforced row visibility. One scenario = one denial mode — this
  // one only reads (spec §6.4).
  private class ReadDebugLogsScenario implements PersonaScenario {
    /**
     * @description Reads every visible Debug_Log__c under USER_MODE — the sharing-enforced
     *              path whose read-denial surface is 0 rows (or System.QueryException when
     *              object permission itself is missing).
     * @param ctx The running persona's context.
     * @return `Object` the visible rows, as a List for returnedRows/returnedRowIds.
     */
    public Object run(PersonaContext ctx) {
      return [SELECT Id FROM Debug_Log__c WITH USER_MODE];
    }
  }

  // Count scenario: the SELECT COUNT() idiom — returnedRows compares the Integer directly.
  private class CountDebugLogsScenario implements PersonaScenario {
    /**
     * @description Counts visible Debug_Log__c rows under USER_MODE.
     * @param ctx The running persona's context.
     * @return `Object` the Integer count.
     */
    public Object run(PersonaContext ctx) {
      return [SELECT COUNT() FROM Debug_Log__c WITH USER_MODE];
    }
  }

  // Limits fixture: exactly two SOQL queries and zero DML, so the delta assert is exact.
  private class TwoCountQueriesScenario implements PersonaScenario {
    /**
     * @description Issues exactly two COUNT queries — the known-SOQL-count fixture for the
     *              limits-accounting row.
     * @param ctx The running persona's context.
     * @return `Object` the summed counts.
     */
    public Object run(PersonaContext ctx) {
      Integer firstCount = [SELECT COUNT() FROM Debug_Log__c WITH USER_MODE];
      Integer secondCount = [SELECT COUNT() FROM Debug_Log__c WITH USER_MODE];
      return firstCount + secondCount;
    }
  }

  // Wrong-exception fixture: raises a genuine System.NullPointerException — system exception
  // types cannot be constructed, so the scenario dereferences a null it manufactured.
  private class NullDereferenceScenario implements PersonaScenario {
    /**
     * @description Deliberately dereferences null so the matrix observes a thrown type that
     *              is NOT a denial.
     * @param ctx The running persona's context.
     * @return `Object` never returns — the dereference always throws.
     */
    public Object run(PersonaContext ctx) {
      String nullString = blankToNull('');
      return nullString.length();
    }
  }

  // Async fixture: enqueues one trivial queueable, which the loop runner must reject.
  private class EnqueueQueueableScenario implements PersonaScenario {
    /**
     * @description Enqueues a trivial Queueable — the loop runner cannot attribute async
     *              outcomes and must reject the enqueue as a configuration failure.
     * @param ctx The running persona's context.
     * @return `Object` always null.
     */
    public Object run(PersonaContext ctx) {
      System.enqueueJob(new TrivialQueueable());
      return null;
    }
  }

  // Return-shape fixture: hands back exactly the constructor-provided value.
  private class FixedValueScenario implements PersonaScenario {
    private final Object fixedValue;

    private FixedValueScenario(Object fixedValue) {
      this.fixedValue = fixedValue;
    }

    /**
     * @description Returns the fixed value unchanged, so return-shape semantics are tested
     *              in isolation from any org state.
     * @param ctx The running persona's context.
     * @return `Object` the constructor-provided value, null included.
     */
    public Object run(PersonaContext ctx) {
      return this.fixedValue;
    }
  }

  // Custom-check fixture: always throws, so the matrix must record the check exception as
  // the persona's mismatch instead of crashing.
  private class ThrowingCheck implements PersonaOutcome.Check {
    /**
     * @description Throws deliberately — the framework must catch this and record it as the
     *              persona's mismatch, never propagate it.
     * @param result The persona's actual outcome (unused).
     * @return `String` never returns — always throws.
     */
    public String check(PersonaMatrixResult result) {
      throw new IllegalArgumentException('Deliberate self-test check failure.');
    }
  }

  // Minimal Queueable for the async-rejection fixture; the flag gives it an observable,
  // non-empty body.
  private class TrivialQueueable implements Queueable {
    /**
     * @description Flips the class-level flag and nothing else.
     * @param context Queueable context (unused).
     */
    public void execute(QueueableContext context) {
      queueableExecuted = true;
    }
  }

  // Manufactures a null the compiler cannot fold away, for the wrong-exception fixture.
  private static String blankToNull(String value) {
    return String.isBlank(value) ? null : value;
  }
}
