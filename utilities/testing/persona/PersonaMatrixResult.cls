/**
 * @description Per-persona actual-outcome carrier for a PersonaMatrix run: what the scenario
 *              returned (or threw) while executing as one persona, the governor-limit deltas
 *              that execution consumed, and — once the runner evaluates the declared
 *              PersonaOutcome — pass/fail plus the mismatch detail that feeds the failure
 *              ledger. The runner builds one instance per persona; consumers receive them from
 *              run() / runQuietly(), and PersonaOutcome.Check implementations receive them as
 *              the evaluation input.
 * @group Testing
 * @see PersonaMatrix
 * @see PersonaOutcome
 * @author David Wood
 * @since 2026-08-13
 * @last 2026-08-13 — initial version: per-persona actual-outcome carrier for PersonaMatrix v1.
 */
@IsTest
// Analyzer suppression, disclosed in the v1.1.0 PR: the constructor is the runner-built
// result carrier's single full-state seam.
@SuppressWarnings('PMD.ExcessiveParameterList')
public inherited sharing class PersonaMatrixResult {
  // ── Execution facts — fixed at construction by the runner ────────────────
  private final String personaName;
  private final Object returnedValue;
  private final Exception caughtException;
  private final Integer soqlDelta;
  private final Integer dmlStatementsDelta;
  private final Integer dmlRowsDelta;
  private final Integer cpuDeltaMs;

  // ── Evaluation verdict — the one mutable seam, written exactly once by the
  //    runner via recordEvaluation() after PersonaOutcome.evaluate() returns.
  private Boolean passed;
  private String mismatchDetail;

  /**
   * @description Builds the carrier from one persona's execution. Called by the runner inside
   *              the persona's System.runAs block, after the scenario has run and the post-run
   *              limit snapshot is taken. All execution facts are immutable from here on; only
   *              the evaluation verdict (recordEvaluation) is written later.
   * @param personaName The persona's declared name — its identity key in the matrix.
   * @param returnedValue Whatever the scenario returned; null when it returned null or threw.
   * @param caughtException The exception the scenario threw, or null when it completed.
   * @param soqlDelta SOQL queries consumed by the scenario (post minus pre snapshot).
   * @param dmlStatementsDelta DML statements consumed by the scenario, excluding the runAs
   *        call's own DML-statement charge (snapshots are taken inside the runAs block).
   * @param dmlRowsDelta DML rows consumed by the scenario.
   * @param cpuDeltaMs Approximate CPU milliseconds consumed — excludes database time and
   *        includes runner overhead, so report it as "~Nms", never as an exact budget signal.
   */
  public PersonaMatrixResult(
    String personaName,
    Object returnedValue,
    Exception caughtException,
    Integer soqlDelta,
    Integer dmlStatementsDelta,
    Integer dmlRowsDelta,
    Integer cpuDeltaMs
  ) {
    this.personaName = personaName;
    this.returnedValue = returnedValue;
    this.caughtException = caughtException;
    this.soqlDelta = soqlDelta;
    this.dmlStatementsDelta = dmlStatementsDelta;
    this.dmlRowsDelta = dmlRowsDelta;
    this.cpuDeltaMs = cpuDeltaMs;
  }

  /**
   * @description Records the evaluation verdict. The runner calls this exactly once per
   *              persona, passing PersonaOutcome.evaluate()'s return value: null means the
   *              persona passed; any string is the human-readable mismatch that becomes this
   *              persona's [FAIL] ledger line.
   * @param evaluatedMismatch Null on pass; otherwise the mismatch description.
   */
  public void recordEvaluation(String evaluatedMismatch) {
    this.passed = evaluatedMismatch == null;
    this.mismatchDetail = evaluatedMismatch;
  }

  /**
   * @description The persona's declared name — its identity key in the matrix.
   * @return `String` the persona name.
   */
  public String getPersonaName() {
    return this.personaName;
  }

  /**
   * @description Whatever the scenario returned for this persona. Null when the scenario
   *              returned null or threw — check getCaughtException() to tell those apart.
   * @return `Object` the scenario's return value, or null.
   */
  public Object getReturnedValue() {
    return this.returnedValue;
  }

  /**
   * @description The exception the scenario threw for this persona, or null when it completed.
   * @return `Exception` the caught exception, or null.
   */
  public Exception getCaughtException() {
    return this.caughtException;
  }

  /**
   * @description SOQL queries the scenario consumed for this persona.
   * @return `Integer` the SOQL-query delta.
   */
  public Integer getSoqlDelta() {
    return this.soqlDelta;
  }

  /**
   * @description DML statements the scenario consumed for this persona. Excludes the runAs
   *              call's own DML-statement charge — the runner snapshots inside the runAs block,
   *              and the ledger's totals line carries the runAs charges separately.
   * @return `Integer` the DML-statement delta.
   */
  public Integer getDmlStatementsDelta() {
    return this.dmlStatementsDelta;
  }

  /**
   * @description DML rows the scenario consumed for this persona.
   * @return `Integer` the DML-row delta.
   */
  public Integer getDmlRowsDelta() {
    return this.dmlRowsDelta;
  }

  /**
   * @description Approximate CPU milliseconds the scenario consumed for this persona.
   *              Structurally valid across runAs but excludes database time and includes
   *              runner overhead — SOQL/DML deltas are the authoritative budget signals.
   * @return `Integer` the approximate CPU delta in milliseconds.
   */
  public Integer getCpuDeltaMs() {
    return this.cpuDeltaMs;
  }

  /**
   * @description Whether this persona's actual outcome matched its declared expectation.
   *              Null until the runner has called recordEvaluation().
   * @return `Boolean` true on pass, false on mismatch, null before evaluation.
   */
  public Boolean isPassed() {
    return this.passed;
  }

  /**
   * @description The human-readable mismatch description for this persona — the [FAIL] ledger
   *              line's detail. Null on pass, and null until the runner has evaluated.
   * @return `String` the mismatch description, or null.
   */
  public String getMismatchDetail() {
    return this.mismatchDetail;
  }
}
