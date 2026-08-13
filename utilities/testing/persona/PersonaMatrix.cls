/**
 * @description Fluent persona-matrix runner and provisioning owner for security-model testing
 *              (persona-matrix-testing §6): declare one PersonaScenario, chain
 *              .persona(...).expect(...) pairs, and run() executes the scenario as every persona
 *              in declaration order — each inside its own System.runAs block — collecting every
 *              actual outcome before raising one aggregate failure ledger, so no mid-loop assert
 *              can silence a later persona. provision(List&lt;Persona&gt;) owns user fabrication
 *              end to end: exact-name resolution (never LIKE), deterministic usernames as the
 *              durable lookup key, and one bulk setup-object sequence under an explicit admin
 *              context. userFor(...) re-resolves provisioned users by username query, which is
 *              what survives the @TestSetup / test-method transaction boundary — statics do not.
 * @group Testing
 * @see Persona
 * @see PersonaBuilder
 * @see PersonaScenario
 * @see PersonaContext
 * @see PersonaOutcome
 * @see PersonaMatrixResult
 * @author David Wood
 * @since 2026-08-13
 * @last 2026-08-13 — initial persona-matrix runner + provisioning per design Draft v3 (§6, §7).
 */
@IsTest
// Analyzer suppression, disclosed in the v1.1.0 PR: the runner deliberately keeps grammar,
// provisioning, execution, and ledger in one cohesive class (same waiver shape as DMLManager);
// class totals trip the budget through breadth of small methods, not nesting depth.
@SuppressWarnings('PMD.CognitiveComplexity, PMD.CyclomaticComplexity')
public without sharing class PersonaMatrix {
  // `without sharing` deliberately: provisioning and userFor(...) must resolve org state
  // (User, Profile, PermissionSet rows) deterministically no matter which context calls them —
  // including from inside a restricted persona's runAs block. Same posture as TestFactory.

  // ── Constants ────────────────────────────────────────────────────────────

  // Assert.fail message cap (~3,500 chars): ApexTestResult.Message persists ~4,000 chars
  // (empirically checked by the §8 ledger-cap self-test; no first-party citation exists).
  private static final Integer LEDGER_MESSAGE_CAP = 3500;

  // Headroom reserved inside the cap for the '(+N more lines — see debug log)' tail.
  private static final Integer LEDGER_TAIL_RESERVE = 64;

  // Exact profile name for the provisioning admin context — never a LIKE match.
  private static final String ADMIN_PROFILE_NAME = 'System Administrator';

  // Shared remediation hint for every "not provisioned" error (spec §6.1 wording).
  private static final String PROVISION_HINT = ' — call PersonaMatrix.provision in @TestSetup';

  // User field ceilings applied when deriving fields from the persona name.
  private static final Integer ALIAS_MAX_LENGTH = 8;
  private static final Integer LAST_NAME_MAX_LENGTH = 80;

  // ── Matrix state — one instance per PersonaMatrix.of(...) chain ─────────

  private final PersonaScenario matrixScenario;
  private final List<Persona> declaredPersonas = new List<Persona>();
  private final List<PersonaOutcome> declaredOutcomes = new List<PersonaOutcome>();
  private final Map<String, Object> matrixParameters = new Map<String, Object>();

  // Matrices are created through of(...) only.
  private PersonaMatrix(PersonaScenario matrixScenario) {
    this.matrixScenario = matrixScenario;
  }

  // ── Fluent grammar ───────────────────────────────────────────────────────

  /**
   * @description Entry point: starts a matrix over the given scenario. Chain
   *              .persona(...).expect(...) pairs and finish with run() or runQuietly().
   * @param scenario The story action every declared persona will execute.
   * @return `PersonaMatrix` — a new matrix, ready for persona declarations.
   * @throws IllegalArgumentException when the scenario is null.
   */
  public static PersonaMatrix of(PersonaScenario scenario) {
    if (scenario == null) {
      throw new IllegalArgumentException(
        'PersonaMatrix.of(null) — pass the PersonaScenario the matrix runs.'
      );
    }
    return new PersonaMatrix(scenario);
  }

  /**
   * @description Declares the next persona to run the scenario. Returns a PersonaStep whose
   *              only operation is expect(PersonaOutcome) — the compile-safe grammar: a
   *              persona without an expectation, or an expectation without a persona, cannot
   *              be expressed (spec §6.1). Accepts a built Persona only — a builder is never
   *              a handle.
   * @param declaredPersona The persona, produced by PersonaBuilder.build().
   * @return `PersonaStep` — the grammar stage exposing only expect(...).
   * @throws IllegalArgumentException when the persona is null.
   */
  public PersonaStep persona(Persona declaredPersona) {
    if (declaredPersona == null) {
      throw new IllegalArgumentException(
        'PersonaMatrix.persona(null) — pass a built Persona.'
      );
    }
    return new PersonaStep(this, declaredPersona);
  }

  /**
   * @description Declares a matrix-level parameter surfaced to the scenario via
   *              PersonaContext.getParameter(key) for every persona. Merged over each
   *              persona's own parameters — on a key collision the matrix-level value wins.
   * @param key   Parameter key; map keys are case-sensitive.
   * @param value Parameter value; null is a legal value.
   * @return `PersonaMatrix` — this matrix, for chaining.
   * @throws IllegalArgumentException when the key is blank.
   */
  public PersonaMatrix parameter(String key, Object value) {
    if (String.isBlank(key)) {
      throw new IllegalArgumentException(
        'PersonaMatrix.parameter(...) requires a non-blank key.'
      );
    }
    this.matrixParameters.put(key, value);
    return this;
  }

  // ── Execution ────────────────────────────────────────────────────────────

  /**
   * @description Runs the matrix: validates configuration first (empty matrix, unprovisioned
   *              personas, incompatible outcome refinements — all before any runAs), then
   *              executes the scenario as every persona in declaration order, evaluates each
   *              declared outcome, and — if any persona mismatched — raises ONE Assert.fail
   *              whose message is the capped failure ledger (full ledger always goes to the
   *              debug log). No assert fires mid-loop, so every persona always runs.
   * @return `List<PersonaMatrixResult>` — every persona's evaluated result, on an all-pass
   *         matrix only (a mismatch raises the ledger instead of returning).
   * @throws PersonaMatrixException on any configuration error, before any runAs executes.
   */
  public List<PersonaMatrixResult> run() {
    return execute(true);
  }

  /**
   * @description Identical execution to run() — same validation, same per-persona runAs
   *              loop, same evaluation, same debug-log ledger — but never asserts: all
   *              results come back, failures included, for consumers building their own
   *              reporting. Configuration errors still throw; they are defects in the test,
   *              not persona mismatches.
   * @return `List<PersonaMatrixResult>` — every persona's evaluated result, pass or fail.
   * @throws PersonaMatrixException on any configuration error, before any runAs executes.
   */
  public List<PersonaMatrixResult> runQuietly() {
    return execute(false);
  }

  // Shared engine behind run()/runQuietly(); the flag is the only difference (spec §6.3).
  private List<PersonaMatrixResult> execute(Boolean raiseOnMismatch) {
    validateConfiguration();
    Map<String, User> usersByPersonaName = resolveDeclaredUsers();
    List<PersonaMatrixResult> results = new List<PersonaMatrixResult>();
    for (Integer index = 0; index < this.declaredPersonas.size(); index++) {
      Persona declaredPersona = this.declaredPersonas[index];
      PersonaMatrixResult result = runScenarioAs(
        declaredPersona,
        usersByPersonaName.get(declaredPersona.getName())
      );
      // Evaluation runs OUTSIDE the runAs block: PersonaOutcome.evaluate never throws, and
      // keeping it out of the block keeps custom-Check overhead out of the scenario's deltas.
      result.recordEvaluation(this.declaredOutcomes[index].evaluate(result));
      results.add(result);
    }
    reportResults(results, raiseOnMismatch);
    return results;
  }

  // Validation gate — every configuration error surfaces here, before any runAs (spec §6.2).
  private void validateConfiguration() {
    if (this.declaredPersonas.isEmpty()) {
      throw new PersonaMatrixException(
        'PersonaMatrix.run(): empty matrix — declare at least one ' +
        '.persona(...).expect(...) pair before running.'
      );
    }
    for (Integer index = 0; index < this.declaredPersonas.size(); index++) {
      String configurationError = this.declaredOutcomes[index].validate();
      if (configurationError != null) {
        throw new PersonaMatrixException(
          'Persona \'' +
          this.declaredPersonas[index].getName() +
          '\': ' +
          configurationError
        );
      }
    }
  }

  // Re-resolves every declared persona's user by deterministic-username query — statics do
  // not survive the @TestSetup / test-method boundary, so the database is the registry.
  private Map<String, User> resolveDeclaredUsers() {
    Map<String, String> usernamesByPersonaName = new Map<String, String>();
    for (Persona declaredPersona : this.declaredPersonas) {
      usernamesByPersonaName.put(
        declaredPersona.getName(),
        declaredPersona.deterministicUsername()
      );
    }
    Map<String, User> usersByUsername = queryUsersByUsername(
      usernamesByPersonaName.values()
    );
    Map<String, User> usersByPersonaName = new Map<String, User>();
    for (String personaName : usernamesByPersonaName.keySet()) {
      User provisionedUser = usersByUsername.get(
        usernamesByPersonaName.get(personaName)
      );
      if (provisionedUser == null) {
        throw new PersonaMatrixException(
          'Persona \'' + personaName + '\' not provisioned' + PROVISION_HINT + '.'
        );
      }
      usersByPersonaName.put(personaName, provisionedUser);
    }
    return usersByPersonaName;
  }

  // One persona's execution (spec §6.2): enter runAs, snapshot Limits INSIDE the block (the
  // runAs call itself charges one DML statement, kept out of the scenario's delta), run the
  // scenario catching every exception, snapshot again, reject async enqueues, build the result.
  private PersonaMatrixResult runScenarioAs(Persona declaredPersona, User personaUser) {
    PersonaMatrixResult result;
    System.runAs(personaUser) {
      Integer soqlBefore = Limits.getQueries();
      Integer dmlStatementsBefore = Limits.getDmlStatements();
      Integer dmlRowsBefore = Limits.getDmlRows();
      Integer cpuBefore = Limits.getCpuTime();
      Integer queueableJobsBefore = Limits.getQueueableJobs();
      Integer futureCallsBefore = Limits.getFutureCalls();
      Object returnedValue;
      Exception caughtException;
      try {
        returnedValue = this.matrixScenario.run(
          new PersonaContext(
            personaUser,
            declaredPersona.getName(),
            mergedParametersFor(declaredPersona)
          )
        );
      } catch (Exception scenarioException) {
        // Every catchable exception lands in the result for outcome evaluation. Assertion
        // failures and LimitException are uncatchable by platform rule and abort the matrix —
        // which is why scenarios must never assert (use PersonaOutcome) and why §6.5's 50%
        // guidance keeps matrices away from the governor cliff.
        caughtException = scenarioException;
      }
      Integer soqlDelta = Limits.getQueries() - soqlBefore;
      Integer dmlStatementsDelta = Limits.getDmlStatements() - dmlStatementsBefore;
      Integer dmlRowsDelta = Limits.getDmlRows() - dmlRowsBefore;
      Integer cpuDeltaMs = Limits.getCpuTime() - cpuBefore;
      rejectAsyncEnqueues(
        declaredPersona,
        Limits.getQueueableJobs() - queueableJobsBefore,
        Limits.getFutureCalls() - futureCallsBefore
      );
      result = new PersonaMatrixResult(
        declaredPersona.getName(),
        returnedValue,
        caughtException,
        soqlDelta,
        dmlStatementsDelta,
        dmlRowsDelta,
        cpuDeltaMs
      );
    }
    return result;
  }

  // Async-enqueue detection covers the kinds Limits can observe: Queueable
  // (Limits.getQueueableJobs) and @future (Limits.getFutureCalls). Batch and scheduled
  // enqueues have no Limits delta and are NOT detected — they are equally unsupported in the
  // loop runner and belong in the per-method form (spec §6.2, §6.5).
  private static void rejectAsyncEnqueues(
    Persona declaredPersona,
    Integer queueableJobsEnqueued,
    Integer futureCallsEnqueued
  ) {
    if (queueableJobsEnqueued <= 0 && futureCallsEnqueued <= 0) {
      return;
    }
    throw new PersonaMatrixException(
      'Persona \'' +
      declaredPersona.getName() +
      '\': scenario enqueued async work (queueable +' +
      queueableJobsEnqueued +
      ', future +' +
      futureCallsEnqueued +
      ') — the loop runner cannot attribute async outcomes, because queued work executes at ' +
      'Test.stopTest(), after the ledger. Use the per-method form (persona-matrix-testing ' +
      '§6.5): one persona per test method, each run() wrapped in Test.startTest()/stopTest().'
    );
  }

  // Persona-level parameters first, matrix-level merged on top — matrix wins on collision.
  private Map<String, Object> mergedParametersFor(Persona declaredPersona) {
    Map<String, Object> mergedParameters = declaredPersona.getParameters();
    mergedParameters.putAll(this.matrixParameters);
    return mergedParameters;
  }

  // ── Failure ledger (spec §6.3) ───────────────────────────────────────────

  // Debug always carries the FULL ledger; only the Assert.fail message is capped.
  // The debug statement is the spec-mandated uncapped home of the ledger — deliberate here,
  // never a production-path pattern (this class is @IsTest infrastructure).
  @SuppressWarnings('PMD.AvoidDebugStatements')
  private void reportResults(List<PersonaMatrixResult> results, Boolean raiseOnMismatch) {
    String fullLedger = buildLedger(scenarioLabel(), results, results.size());
    System.debug(LoggingLevel.INFO, fullLedger);
    if (raiseOnMismatch && countFailed(results) > 0) {
      Assert.fail(capLedger(fullLedger));
    }
  }

  // Renders the scenario's type name from its instance ('ReadQuotes:[...]' → 'ReadQuotes').
  // A scenario overriding toString() only changes the label, never the semantics.
  private String scenarioLabel() {
    return String.valueOf(this.matrixScenario).substringBefore(':');
  }

  // @TestVisible seam (spec §6.3): self-tests verify ledger content by calling this directly
  // on runQuietly() results — no uncatchable Assert.fail needs to fire to inspect the ledger.
  @TestVisible
  private static String buildLedger(
    String scenarioLabel,
    List<PersonaMatrixResult> results,
    Integer runAsDmlCharges
  ) {
    Integer scenarioSoql = 0;
    Integer scenarioDml = 0;
    List<String> ledgerLines = new List<String>();
    for (PersonaMatrixResult result : results) {
      scenarioSoql += result.getSoqlDelta();
      scenarioDml += result.getDmlStatementsDelta();
      ledgerLines.add(ledgerLineFor(result));
    }
    ledgerLines.add(
      0,
      'PersonaMatrix: ' +
      countFailed(results) +
      ' of ' +
      results.size() +
      ' personas failed — scenario ' +
      scenarioLabel
    );
    // Totals stay denominator-facing: per-persona deltas exclude the runAs DML charge, but
    // the transaction pays it either way, so the totals line adds it back (spec §6.3).
    ledgerLines.add(
      '  limits: ' +
      scenarioSoql +
      '/' +
      Limits.getLimitQueries() +
      ' SOQL · DML scenario ' +
      scenarioDml +
      ' + runAs ' +
      runAsDmlCharges +
      ' = ' +
      (scenarioDml + runAsDmlCharges) +
      '/' +
      Limits.getLimitDmlStatements() +
      ', total'
    );
    return String.join(ledgerLines, '\n');
  }

  // One ledger line per persona — [PASS]/[FAIL], detail, per-persona SOQL / DML / ~CPU.
  // A result never evaluated (isPassed() null — reachable only through the @TestVisible
  // seam) renders as 'not evaluated' rather than silently reading as a pass.
  private static String ledgerLineFor(PersonaMatrixResult result) {
    Boolean failed = result.isPassed() == false;
    String detail = failed
      ? result.getMismatchDetail()
      : (result.isPassed() == null ? 'not evaluated' : 'passed');
    return '  ' +
      (failed ? '[FAIL]' : '[PASS]') +
      ' ' +
      result.getPersonaName() +
      '  ' +
      detail +
      '  (' +
      result.getSoqlDelta() +
      ' SOQL / ' +
      result.getDmlStatementsDelta() +
      ' DML / ~' +
      result.getCpuDeltaMs() +
      'ms CPU)';
  }

  private static Integer countFailed(List<PersonaMatrixResult> results) {
    Integer failedCount = 0;
    for (PersonaMatrixResult result : results) {
      if (result.isPassed() == false) {
        failedCount++;
      }
    }
    return failedCount;
  }

  // @TestVisible seam for the §8 ledger-cap self-test: caps at ~3,500 chars, dropping whole
  // trailing lines and appending the '(+N more lines — see debug log)' tail.
  @TestVisible
  private static String capLedger(String fullLedger) {
    if (fullLedger.length() <= LEDGER_MESSAGE_CAP) {
      return fullLedger;
    }
    List<String> allLines = fullLedger.split('\n');
    List<String> keptLines = new List<String>();
    Integer budget = LEDGER_MESSAGE_CAP - LEDGER_TAIL_RESERVE;
    Integer runningLength = 0;
    for (String ledgerLine : allLines) {
      if (runningLength + ledgerLine.length() + 1 > budget) {
        break;
      }
      keptLines.add(ledgerLine);
      runningLength += ledgerLine.length() + 1;
    }
    Integer omittedLines = allLines.size() - keptLines.size();
    if (keptLines.isEmpty()) {
      // Degenerate case: the very first line alone exceeds the budget — hard-truncate it.
      return fullLedger.abbreviate(budget) +
        '\n(+' +
        omittedLines +
        ' more lines — see debug log)';
    }
    keptLines.add('(+' + omittedLines + ' more lines — see debug log)');
    return String.join(keptLines, '\n');
  }

  // ── Provisioning (spec §6.1, §3 item 4, §7) ─────────────────────────────

  /**
   * @description Fabricates one user per persona — owned here end to end; TestFactory's user
   *              seams are deliberately not used (spec §7). Resolves every profile, role,
   *              permission set, and permission-set group by EXACT name, failing fast with a
   *              named error on zero rows or ambiguity. Builds all User records in memory
   *              with Persona.deterministicUsername(), applies UserRoleId, then performs ONE
   *              bulk setup-object sequence under System.runAs(admin): insert users,
   *              Test.calculatePermissionSetGroup for any groups used, insert all
   *              permission-set and permission-set-group assignments — one clean mixed-DML
   *              boundary instead of one per persona. Idempotency is definition-strict: an
   *              existing user found by deterministic username is a no-op only when org
   *              state matches the full definition (ProfileId, UserRoleId, complete
   *              assignment ladder); any mismatch is a configuration conflict error naming
   *              the persona. Call from @TestSetup so every test method reuses the users.
   * @param personas The personas to provision; duplicate names with identical definitions
   *        collapse to one user, duplicate names with different definitions conflict.
   * @return `Map<String, User>` — persona name to its provisioned user.
   * @throws PersonaMatrixException on any resolution failure, ambiguity, or definition
   *         conflict — always before any DML executes.
   */
  public static Map<String, User> provision(List<Persona> personas) {
    List<Persona> uniquePersonas = dedupeByDefinition(personas);
    ResolvedDirectory directory = resolveDirectory(uniquePersonas);
    Map<String, User> usersByUsername = queryUsersByUsername(
      usernamesOf(uniquePersonas)
    );
    Map<String, User> provisionedUsersByPersonaName = new Map<String, User>();
    List<Persona> personasToCreate = new List<Persona>();
    List<User> usersToInsert = new List<User>();
    List<Persona> existingPersonas = new List<Persona>();
    List<User> existingUsers = new List<User>();
    for (Persona requested : uniquePersonas) {
      User existingUser = usersByUsername.get(requested.deterministicUsername());
      if (existingUser == null) {
        User builtUser = buildUserInMemory(requested, directory);
        personasToCreate.add(requested);
        usersToInsert.add(builtUser);
        provisionedUsersByPersonaName.put(requested.getName(), builtUser);
      } else {
        existingPersonas.add(requested);
        existingUsers.add(existingUser);
        provisionedUsersByPersonaName.put(requested.getName(), existingUser);
      }
    }
    verifyExistingUsersMatchDefinitions(existingPersonas, existingUsers, directory);
    insertUsersAndAssignments(personasToCreate, usersToInsert, directory);
    return provisionedUsersByPersonaName;
  }

  /**
   * @description Re-resolves a provisioned persona's user by deterministic-username query.
   *              Works identically in @TestSetup and in any test method — static state does
   *              not survive that transaction boundary, so the query IS the durable lookup.
   * @param provisionedPersona The persona whose user to resolve.
   * @return `User` — the provisioned user.
   * @throws PersonaMatrixException when no user exists for the persona's username.
   */
  public static User userFor(Persona provisionedPersona) {
    if (provisionedPersona == null) {
      throw new IllegalArgumentException('PersonaMatrix.userFor(null Persona).');
    }
    return queryProvisionedUser(
      provisionedPersona.getName(),
      provisionedPersona.deterministicUsername()
    );
  }

  /**
   * @description Name-keyed overload of userFor(Persona) for call sites that hold only the
   *              persona's identity name. Derives the same deterministic username the
   *              persona's definition would.
   * @param personaName The persona's identity name, e.g. 'Sales Rep'.
   * @return `User` — the provisioned user.
   * @throws PersonaMatrixException when no user exists for the derived username.
   */
  public static User userFor(String personaName) {
    if (String.isBlank(personaName)) {
      throw new IllegalArgumentException(
        'PersonaMatrix.userFor(...) requires a non-blank persona name.'
      );
    }
    // Route the name through a throwaway Persona so the slug derivation has exactly one
    // home — Persona.deterministicUsername() is the contract, never re-implemented here.
    Persona lookupKey = new Persona(
      personaName,
      Persona.DEFAULT_PROFILE_NAME,
      null,
      null,
      null,
      null
    );
    return queryProvisionedUser(personaName, lookupKey.deterministicUsername());
  }

  // ── Private provisioning machinery ───────────────────────────────────────

  // Rejects null/empty input, collapses identical duplicate definitions, and conflicts on
  // same-username-different-definition — keyed by deterministic username, not raw name, so
  // two names that slug identically ('Sales Rep' / 'sales rep') cannot silently collide.
  private static List<Persona> dedupeByDefinition(List<Persona> personas) {
    requireProvisionablePersonaList(personas);
    Map<String, Persona> personasByUsername = new Map<String, Persona>();
    List<Persona> uniquePersonas = new List<Persona>();
    for (Persona requested : personas) {
      Persona alreadyRequested = personasByUsername.get(
        requested.deterministicUsername()
      );
      if (alreadyRequested == null) {
        personasByUsername.put(requested.deterministicUsername(), requested);
        uniquePersonas.add(requested);
      } else if (!alreadyRequested.definitionEquals(requested)) {
        throw new PersonaMatrixException(
          'Persona \'' +
          requested.getName() +
          '\' configuration conflict — provision(...) received two different definitions ' +
          'resolving to username \'' +
          requested.deterministicUsername() +
          '\'; two fixtures must not silently share one user.'
        );
      }
    }
    return uniquePersonas;
  }

  private static void requireProvisionablePersonaList(List<Persona> personas) {
    if (personas == null || personas.isEmpty()) {
      throw new IllegalArgumentException(
        'PersonaMatrix.provision(...) requires at least one Persona.'
      );
    }
    for (Persona requested : personas) {
      if (requested == null) {
        throw new IllegalArgumentException(
          'PersonaMatrix.provision(...) — the persona list contains a null entry.'
        );
      }
    }
  }

  private static List<String> usernamesOf(List<Persona> personas) {
    List<String> usernames = new List<String>();
    for (Persona requested : personas) {
      usernames.add(requested.deterministicUsername());
    }
    return usernames;
  }

  // Resolves every referenced name to an Id up front — all four lookups fail fast on zero
  // rows or ambiguity before any User is built, so provisioning never half-completes.
  private static ResolvedDirectory resolveDirectory(List<Persona> personas) {
    Set<String> profileNames = new Set<String>();
    Set<String> roleDeveloperNames = new Set<String>();
    Set<String> permissionSetNames = new Set<String>();
    Set<String> groupDeveloperNames = new Set<String>();
    for (Persona requested : personas) {
      profileNames.add(requested.getProfileName());
      if (requested.getRoleDeveloperName() != null) {
        roleDeveloperNames.add(requested.getRoleDeveloperName());
      }
      permissionSetNames.addAll(requested.getPermissionSetNames());
      groupDeveloperNames.addAll(requested.getPermissionSetGroupNames());
    }
    ResolvedDirectory directory = new ResolvedDirectory();
    resolveProfiles(profileNames, directory);
    resolveRoles(roleDeveloperNames, directory);
    resolvePermissionSets(permissionSetNames, directory);
    resolvePermissionSetGroups(groupDeveloperNames, directory);
    return directory;
  }

  private static void resolveProfiles(Set<String> profileNames, ResolvedDirectory directory) {
    // SOQL: setup-object lookup by EXACT name (WHERE Name IN — never LIKE, so a loose match
    // can never catch 'Minimum Access - API Only Integrations'); test context.
    for (Profile resolvedProfile : [
      SELECT Id, Name
      FROM Profile
      WHERE Name IN :profileNames
    ]) {
      directory.profiles.record(resolvedProfile.Name, resolvedProfile.Id);
    }
    directory.profiles.requireAllResolved(profileNames);
  }

  private static void resolveRoles(
    Set<String> roleDeveloperNames,
    ResolvedDirectory directory
  ) {
    if (roleDeveloperNames.isEmpty()) {
      return;
    }
    // SOQL: setup-object lookup by exact DeveloperName; test context.
    for (UserRole resolvedRole : [
      SELECT Id, DeveloperName
      FROM UserRole
      WHERE DeveloperName IN :roleDeveloperNames
    ]) {
      directory.roles.record(resolvedRole.DeveloperName, resolvedRole.Id);
    }
    directory.roles.requireAllResolved(roleDeveloperNames);
  }

  private static void resolvePermissionSets(
    Set<String> permissionSetNames,
    ResolvedDirectory directory
  ) {
    if (permissionSetNames.isEmpty()) {
      return;
    }
    // SOQL: exact-name lookup; IsOwnedByProfile = false excludes profile-owned shadow sets,
    // and Type != 'Group' excludes a permission-set group's shadow permission set — a PSG
    // name declared via .permissionSet() must fail fast, not silently assign the shadow row.
    for (PermissionSet resolvedSet : [
      SELECT Id, Name
      FROM PermissionSet
      WHERE
        Name IN :permissionSetNames
        AND IsOwnedByProfile = FALSE
        AND Type != 'Group'
    ]) {
      directory.permissionSets.record(resolvedSet.Name, resolvedSet.Id);
    }
    directory.permissionSets.requireAllResolved(permissionSetNames);
  }

  private static void resolvePermissionSetGroups(
    Set<String> groupDeveloperNames,
    ResolvedDirectory directory
  ) {
    if (groupDeveloperNames.isEmpty()) {
      return;
    }
    // SOQL: exact-DeveloperName lookup; test context.
    for (PermissionSetGroup resolvedGroup : [
      SELECT Id, DeveloperName
      FROM PermissionSetGroup
      WHERE DeveloperName IN :groupDeveloperNames
    ]) {
      directory.groups.record(resolvedGroup.DeveloperName, resolvedGroup.Id);
    }
    directory.groups.requireAllResolved(groupDeveloperNames);
  }

  // Builds one User in memory — no DML here; the standard-field set mirrors what
  // TestFactory.createTestUser populates, with persona-derived identity fields.
  private static User buildUserInMemory(Persona requested, ResolvedDirectory directory) {
    String username = requested.deterministicUsername();
    String aliasSlug = username
      .removeEnd(Persona.USERNAME_SUFFIX)
      .replaceAll('-', '');
    User builtUser = new User(
      ProfileId = directory.profiles.idFor(requested.getProfileName()),
      LastName = requested.getName().abbreviate(LAST_NAME_MAX_LENGTH),
      Email = username,
      Username = username,
      Alias = aliasSlug.left(ALIAS_MAX_LENGTH),
      CompanyName = 'TEST',
      Title = requested.getName().abbreviate(LAST_NAME_MAX_LENGTH),
      TimeZoneSidKey = 'America/Los_Angeles',
      EmailEncodingKey = 'UTF-8',
      LanguageLocaleKey = 'en_US',
      LocaleSidKey = 'en_US'
    );
    if (requested.getRoleDeveloperName() != null) {
      builtUser.UserRoleId = directory.roles.idFor(requested.getRoleDeveloperName());
    }
    return builtUser;
  }

  // Definition-strict idempotency (spec §6.1): every existing user must match the full
  // definition — ProfileId, UserRoleId, and the complete assignment ladder — or conflict.
  private static void verifyExistingUsersMatchDefinitions(
    List<Persona> existingPersonas,
    List<User> existingUsers,
    ResolvedDirectory directory
  ) {
    if (existingPersonas.isEmpty()) {
      return;
    }
    DefinitionAudit audit = new DefinitionAudit(
      directory,
      queryAssignmentLadders(existingUsers)
    );
    for (Integer index = 0; index < existingPersonas.size(); index++) {
      audit.verify(existingPersonas[index], existingUsers[index]);
    }
  }

  // One bulk read of every existing user's live assignment ladder, split into direct
  // permission-set rows and permission-set-group rows.
  private static AssignmentLadders queryAssignmentLadders(List<User> existingUsers) {
    AssignmentLadders ladders = new AssignmentLadders();
    // SOQL: IsOwnedByProfile = false excludes the profile-owned assignment every user
    // carries; a row with PermissionSetGroupId is a group assignment, otherwise direct.
    for (PermissionSetAssignment assignment : [
      SELECT AssigneeId, PermissionSetId, PermissionSetGroupId
      FROM PermissionSetAssignment
      WHERE AssigneeId IN :existingUsers AND PermissionSet.IsOwnedByProfile = FALSE
    ]) {
      if (assignment.PermissionSetGroupId != null) {
        addLadderEntry(
          ladders.groupIdsByUserId,
          assignment.AssigneeId,
          assignment.PermissionSetGroupId
        );
      } else {
        addLadderEntry(
          ladders.permissionSetIdsByUserId,
          assignment.AssigneeId,
          assignment.PermissionSetId
        );
      }
    }
    return ladders;
  }

  private static void addLadderEntry(Map<Id, Set<Id>> ladder, Id userId, Id entryId) {
    if (!ladder.containsKey(userId)) {
      ladder.put(userId, new Set<Id>());
    }
    ladder.get(userId).add(entryId);
  }

  private static Set<Id> expectedIdsFor(
    List<String> requestedNames,
    ExactNameLookup lookup
  ) {
    Set<Id> expectedIds = new Set<Id>();
    for (String requestedName : requestedNames) {
      expectedIds.add(lookup.idFor(requestedName));
    }
    return expectedIds;
  }

  private static Set<Id> actualIdsFor(Map<Id, Set<Id>> ladder, Id userId) {
    return ladder.containsKey(userId) ? ladder.get(userId) : new Set<Id>();
  }

  private static PersonaMatrixException configurationConflict(
    Persona requested,
    String mismatch
  ) {
    return new PersonaMatrixException(
      'Persona \'' +
      requested.getName() +
      '\' configuration conflict — a user already exists for username \'' +
      requested.deterministicUsername() +
      '\' but its ' +
      mismatch +
      '. Re-provisioning is a no-op only when org state matches the full definition; ' +
      'rename the persona or align the definitions.'
    );
  }

  // THE one bulk setup-object sequence (spec §3 item 4), under an explicit admin context:
  // insert all Users, force PSG recalculation, insert every assignment — one clean
  // mixed-DML boundary instead of one per persona.
  private static void insertUsersAndAssignments(
    List<Persona> personasToCreate,
    List<User> usersToInsert,
    ResolvedDirectory directory
  ) {
    if (usersToInsert.isEmpty()) {
      return;
    }
    System.runAs(queryAdminUser()) {
      Database.insert(usersToInsert, AccessLevel.SYSTEM_MODE);
      calculatePermissionSetGroups(personasToCreate, directory);
      List<PermissionSetAssignment> assignments = buildAssignments(
        personasToCreate,
        usersToInsert,
        directory
      );
      if (!assignments.isEmpty()) {
        Database.insert(assignments, AccessLevel.SYSTEM_MODE);
      }
    }
  }

  // A PSG still in 'Updating' state cannot flake the fixture: recalculate before assigning
  // (spec §7). Detected per provisioning call, only for groups the new users reference.
  private static void calculatePermissionSetGroups(
    List<Persona> personasToCreate,
    ResolvedDirectory directory
  ) {
    Set<Id> groupIdsToCalculate = new Set<Id>();
    for (Persona requested : personasToCreate) {
      for (String groupDeveloperName : requested.getPermissionSetGroupNames()) {
        groupIdsToCalculate.add(directory.groups.idFor(groupDeveloperName));
      }
    }
    if (!groupIdsToCalculate.isEmpty()) {
      Test.calculatePermissionSetGroup(new List<Id>(groupIdsToCalculate));
    }
  }

  // Builds every assignment row for the whole batch — permission sets AND groups — so a
  // single bulk insert covers the complete ladder of every new user.
  private static List<PermissionSetAssignment> buildAssignments(
    List<Persona> personasToCreate,
    List<User> usersToInsert,
    ResolvedDirectory directory
  ) {
    List<PermissionSetAssignment> assignments = new List<PermissionSetAssignment>();
    for (Integer index = 0; index < personasToCreate.size(); index++) {
      Persona requested = personasToCreate[index];
      Id assigneeId = usersToInsert[index].Id;
      for (String permissionSetName : requested.getPermissionSetNames()) {
        assignments.add(
          new PermissionSetAssignment(
            AssigneeId = assigneeId,
            PermissionSetId = directory.permissionSets.idFor(permissionSetName)
          )
        );
      }
      for (String groupDeveloperName : requested.getPermissionSetGroupNames()) {
        assignments.add(
          new PermissionSetAssignment(
            AssigneeId = assigneeId,
            PermissionSetGroupId = directory.groups.idFor(groupDeveloperName)
          )
        );
      }
    }
    return assignments;
  }

  // Admin context for setup-object DML — exact profile name, fail fast when absent.
  private static User queryAdminUser() {
    // SOQL: exact profile name; test context.
    List<User> adminUsers = [
      SELECT Id
      FROM User
      WHERE Profile.Name = :ADMIN_PROFILE_NAME AND IsActive = TRUE
      LIMIT 1
    ];
    if (adminUsers.isEmpty()) {
      throw new PersonaMatrixException(
        'PersonaMatrix.provision(...): no active \'' +
        ADMIN_PROFILE_NAME +
        '\' user found — provisioning needs an admin context for setup-object DML.'
      );
    }
    return adminUsers[0];
  }

  // Shared exact-username lookup. Deterministic usernames are always lowercase, so the
  // case-sensitive map keying below cannot miss a row the query returned.
  private static Map<String, User> queryUsersByUsername(List<String> usernames) {
    Map<String, User> usersByUsername = new Map<String, User>();
    // SOQL: exact usernames only — the deterministic-username contract; test context.
    for (User provisionedUser : [
      SELECT Id, Username, ProfileId, UserRoleId
      FROM User
      WHERE Username IN :usernames
    ]) {
      usersByUsername.put(provisionedUser.Username, provisionedUser);
    }
    return usersByUsername;
  }

  private static User queryProvisionedUser(String personaName, String username) {
    Map<String, User> usersByUsername = queryUsersByUsername(
      new List<String>{ username }
    );
    User provisionedUser = usersByUsername.get(username);
    if (provisionedUser == null) {
      throw new PersonaMatrixException(
        'Persona \'' +
        personaName +
        '\' has no provisioned user (username \'' +
        username +
        '\')' +
        PROVISION_HINT +
        '.'
      );
    }
    return provisionedUser;
  }

  // ── Inner types ──────────────────────────────────────────────────────────

  /**
   * @description Compile-safe grammar stage between .persona(...) and .expect(...): the only
   *              exposed operation is expect(PersonaOutcome), so a persona without an
   *              expectation — or an expectation without a persona — cannot be expressed
   *              (spec §6.1). Calling expect(...) twice on one held step is a configuration
   *              error, closing the runtime loophole the compile-time grammar cannot.
   */
  public without sharing class PersonaStep {
    private final PersonaMatrix owningMatrix;
    private final Persona stagedPersona;
    private Boolean expectationRecorded = false;

    private PersonaStep(PersonaMatrix owningMatrix, Persona stagedPersona) {
      this.owningMatrix = owningMatrix;
      this.stagedPersona = stagedPersona;
    }

    /**
     * @description Declares the staged persona's expected outcome and returns the matrix
     *              for the next .persona(...) or run().
     * @param expectedOutcome The persona's expectation, e.g. PersonaOutcome.allowed().
     * @return `PersonaMatrix` — the owning matrix, for chaining.
     * @throws IllegalArgumentException when the outcome is null.
     * @throws PersonaMatrixException when expect(...) is called twice on this step.
     */
    public PersonaMatrix expect(PersonaOutcome expectedOutcome) {
      if (expectedOutcome == null) {
        throw new IllegalArgumentException(
          'PersonaStep.expect(null) — declare a PersonaOutcome, e.g. PersonaOutcome.allowed().'
        );
      }
      if (this.expectationRecorded) {
        throw new PersonaMatrixException(
          'Persona \'' +
          this.stagedPersona.getName() +
          '\': expect(...) called twice on one .persona(...) step.'
        );
      }
      this.expectationRecorded = true;
      this.owningMatrix.declaredPersonas.add(this.stagedPersona);
      this.owningMatrix.declaredOutcomes.add(expectedOutcome);
      return this.owningMatrix;
    }
  }

  /**
   * @description Thrown for persona-matrix configuration errors: empty matrix, unprovisioned
   *              or conflicting personas, failed exact-name resolution, ambiguous names,
   *              incompatible outcome refinements, and async enqueues inside the loop runner.
   *              Configuration errors are defects in the test, not persona mismatches — they
   *              throw before (or instead of) the failure ledger.
   */
  public class PersonaMatrixException extends UtilitiesModuleException {
  }

  // One exact-name-to-Id lookup table: records resolutions (duplicate exact names are
  // ambiguity — a security fixture must resolve deterministically) and fails fast on any
  // requested name that never resolved. Lookups are case-sensitive on purpose: SOQL matches
  // names case-insensitively, but the definition contract is case-exact, so a case-mismatched
  // reference reads as unresolved rather than silently binding.
  private class ExactNameLookup {
    private final Map<String, Id> resolvedIdsByName = new Map<String, Id>();
    private final String kindLabel;
    private final String missingHint;

    private ExactNameLookup(String kindLabel, String missingHint) {
      this.kindLabel = kindLabel;
      this.missingHint = missingHint;
    }

    private void record(String resolvedName, Id resolvedId) {
      if (this.resolvedIdsByName.containsKey(resolvedName)) {
        throw new PersonaMatrixException(
          'PersonaMatrix.provision(...): ' +
          this.kindLabel +
          ' \'' +
          resolvedName +
          '\' is ambiguous — more than one record matches the exact name; a security ' +
          'fixture must resolve deterministically.'
        );
      }
      this.resolvedIdsByName.put(resolvedName, resolvedId);
    }

    private void requireAllResolved(Set<String> requestedNames) {
      for (String requestedName : requestedNames) {
        if (!this.resolvedIdsByName.containsKey(requestedName)) {
          throw new PersonaMatrixException(
            'PersonaMatrix.provision(...): ' +
            this.kindLabel +
            ' \'' +
            requestedName +
            '\' not found by exact name (names are case-exact)' +
            this.missingHint +
            '.'
          );
        }
      }
    }

    private Id idFor(String requestedName) {
      return this.resolvedIdsByName.get(requestedName);
    }
  }

  // Bundles the four exact-name lookups provisioning fills up front, each carrying its own
  // kind label and remediation hint for fail-fast messages.
  private class ResolvedDirectory {
    private final ExactNameLookup profiles = new ExactNameLookup(
      'profile',
      ' — override .profile(...) on the persona'
    );
    private final ExactNameLookup roles = new ExactNameLookup(
      'role',
      ' — roles are referenced, never created'
    );
    private final ExactNameLookup permissionSets = new ExactNameLookup(
      'permission set',
      ' — for a permission-set group use .permissionSetGroup(...)'
    );
    private final ExactNameLookup groups = new ExactNameLookup(
      'permission set group',
      ''
    );
  }

  // Bundles the live per-user assignment ladders the idempotency check compares against.
  private class AssignmentLadders {
    private final Map<Id, Set<Id>> permissionSetIdsByUserId = new Map<Id, Set<Id>>();
    private final Map<Id, Set<Id>> groupIdsByUserId = new Map<Id, Set<Id>>();
  }

  // Definition-strict idempotency audit (spec §6.1): compares one existing user's live org
  // state — ProfileId, UserRoleId, complete assignment ladder — against the requested
  // persona definition, and throws a configuration conflict naming the persona on mismatch.
  private class DefinitionAudit {
    private final ResolvedDirectory directory;
    private final AssignmentLadders actualLadders;

    private DefinitionAudit(ResolvedDirectory directory, AssignmentLadders actualLadders) {
      this.directory = directory;
      this.actualLadders = actualLadders;
    }

    private void verify(Persona requested, User existingUser) {
      verifyProfile(requested, existingUser);
      verifyRole(requested, existingUser);
      verifyLadders(requested, existingUser);
    }

    private void verifyProfile(Persona requested, User existingUser) {
      Id expectedProfileId = this.directory.profiles.idFor(requested.getProfileName());
      if (existingUser.ProfileId != expectedProfileId) {
        throw PersonaMatrix.configurationConflict(
          requested,
          'ProfileId (' +
          existingUser.ProfileId +
          ') does not match the definition\'s profile \'' +
          requested.getProfileName() +
          '\''
        );
      }
    }

    private void verifyRole(Persona requested, User existingUser) {
      Id expectedRoleId = requested.getRoleDeveloperName() == null
        ? null
        : this.directory.roles.idFor(requested.getRoleDeveloperName());
      if (existingUser.UserRoleId != expectedRoleId) {
        throw PersonaMatrix.configurationConflict(
          requested,
          'UserRoleId (' +
          existingUser.UserRoleId +
          ') does not match the definition\'s role (' +
          expectedRoleId +
          ')'
        );
      }
    }

    private void verifyLadders(Persona requested, User existingUser) {
      Set<Id> expectedSetIds = PersonaMatrix.expectedIdsFor(
        requested.getPermissionSetNames(),
        this.directory.permissionSets
      );
      Set<Id> actualSetIds = PersonaMatrix.actualIdsFor(
        this.actualLadders.permissionSetIdsByUserId,
        existingUser.Id
      );
      if (!actualSetIds.equals(expectedSetIds)) {
        throw PersonaMatrix.configurationConflict(
          requested,
          'permission-set ladder ' +
          String.valueOf(actualSetIds) +
          ' does not match the definition\'s ladder ' +
          String.valueOf(expectedSetIds)
        );
      }
      Set<Id> expectedGroupIds = PersonaMatrix.expectedIdsFor(
        requested.getPermissionSetGroupNames(),
        this.directory.groups
      );
      Set<Id> actualGroupIds = PersonaMatrix.actualIdsFor(
        this.actualLadders.groupIdsByUserId,
        existingUser.Id
      );
      if (!actualGroupIds.equals(expectedGroupIds)) {
        throw PersonaMatrix.configurationConflict(
          requested,
          'permission-set-group ladder ' +
          String.valueOf(actualGroupIds) +
          ' does not match the definition\'s ladder ' +
          String.valueOf(expectedGroupIds)
        );
      }
    }
  }
}
