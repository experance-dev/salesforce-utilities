/**
 * @description Per-persona expectation model for a PersonaMatrix run. Static factories declare
 *              the outcome kind — allowed(), denied(Type), seesNoRows(), custom(Check) — and
 *              chainable refinements sharpen it (returnedRows, returnedRowIds, returnedNonNull,
 *              messageContains). evaluate() compares a declared expectation against one
 *              persona's PersonaMatrixResult and returns null on pass or a human-readable
 *              mismatch for the failure ledger; validate() reports incompatible refinement
 *              combinations as configuration errors the runner raises before any runAs. Hosts
 *              the Check interface for custom asserts — named Check, never Assert, so it cannot
 *              shadow System.Assert.
 * @group Testing
 * @see PersonaMatrix
 * @see PersonaMatrixResult
 * @author David Wood
 * @since 2026-08-13
 * @last 2026-08-13 — initial version: expectation model + Check seam for PersonaMatrix v1.
 */
@IsTest
// Analyzer suppression, disclosed in the v1.1.0 PR: evaluate()'s outcome-kind dispatch is a
// flat decision table; splitting it would scatter the expectation semantics the spec keeps in one place.
@SuppressWarnings('PMD.CyclomaticComplexity')
public inherited sharing class PersonaOutcome {
  // Truncation length for rendering an unexpected return value inside a mismatch message —
  // enough to identify the value without flooding the capped ledger.
  private static final Integer VALUE_PREVIEW_LENGTH = 120;

  // ── Expectation state — kind fixed at construction, refinements chained ──
  private final ExpectationKind kind;
  private final Type expectedExceptionType;
  private final Check customCheck;
  private Integer expectedRowCount;
  private Set<Id> expectedRowIds;
  private Boolean expectNonNull = false;
  private String expectedMessageFragment;

  // The three outcome kinds a persona can declare. Refinement compatibility per kind is
  // enforced by validate(), not at chain time, so the runner surfaces every configuration
  // error at run() start with persona context attached.
  private enum ExpectationKind {
    ALLOWED,
    DENIED,
    CUSTOM
  }

  private PersonaOutcome(
    ExpectationKind kind,
    Type expectedExceptionType,
    Check customCheck
  ) {
    this.kind = kind;
    this.expectedExceptionType = expectedExceptionType;
    this.customCheck = customCheck;
  }

  // ── Static factories ─────────────────────────────────────────────────────

  /**
   * @description The scenario completes without throwing. Any exception is a mismatch naming
   *              the thrown type and message. Refine with returnedRows / returnedRowIds /
   *              returnedNonNull to also assert on the return value.
   * @return `PersonaOutcome` an allowed expectation, open to refinement.
   */
  public static PersonaOutcome allowed() {
    return new PersonaOutcome(ExpectationKind.ALLOWED, null, null);
  }

  /**
   * @description The scenario must throw exactly this exception type — the thrown exception's
   *              getTypeName() must equal String.valueOf(exceptionType). Exact type-name
   *              equality, not instance-of: name the concrete type (e.g.
   *              DMLManager.CRUDException.class), never a base type. Completing without an
   *              exception is a mismatch — the security gap this framework exists to catch — and
   *              a different thrown type is also a mismatch. Refine with messageContains for a
   *              case-insensitive message-fragment check.
   * @param exceptionType The exact exception type the scenario must throw.
   * @return `PersonaOutcome` a denied expectation, open to messageContains refinement.
   */
  public static PersonaOutcome denied(Type exceptionType) {
    return new PersonaOutcome(ExpectationKind.DENIED, exceptionType, null);
  }

  /**
   * @description Sharing-denial idiom, exactly equivalent to allowed().returnedRows(0): under
   *              Private OWD a read denial is an empty result, not an exception, so the correct
   *              negative assert completes successfully with nothing visible — and a reviewer
   *              scanning for negative coverage can read it as a denial.
   * @return `PersonaOutcome` an allowed expectation refined to exactly zero rows.
   */
  public static PersonaOutcome seesNoRows() {
    return allowed().returnedRows(0);
  }

  /**
   * @description Escape hatch for anything v1 does not model — stripInaccessible redaction
   *              checks, QueryException.getInaccessibleFields() inspection, and similar. The
   *              Check receives the full PersonaMatrixResult and returns null for pass or a
   *              mismatch description. A Check that throws is caught by evaluate() and recorded
   *              as that persona's mismatch — it never crashes the matrix.
   * @param check The custom check implementation.
   * @return `PersonaOutcome` a custom expectation delegating entirely to the Check.
   */
  public static PersonaOutcome custom(Check check) {
    return new PersonaOutcome(ExpectationKind.CUSTOM, null, check);
  }

  // ── Chainable refinements ────────────────────────────────────────────────

  /**
   * @description The scenario's return value carries exactly this many rows — the
   *              row-visibility assert for OWD-Private reads. A returned List is compared by
   *              size; a returned Integer is compared directly (the SELECT COUNT() idiom); a
   *              null return is a mismatch; any other shape is a mismatch. Compatible with
   *              allowed() only — validate() rejects it on denied().
   * @param expectedRowCount The exact row count expected.
   * @return `PersonaOutcome` this expectation, for chaining.
   */
  public PersonaOutcome returnedRows(Integer expectedRowCount) {
    this.expectedRowCount = expectedRowCount;
    return this;
  }

  /**
   * @description The scenario's return value is a List of SObjects whose Ids equal exactly
   *              this set — order-insensitive. Distinguishes "sees the right record" from
   *              "sees some record": a sharing-rule bug that leaks the wrong row must not pass
   *              a row-count assert. Any non-List-of-SObject return (including null) is a
   *              mismatch. Compatible with allowed() only — validate() rejects it on denied().
   * @param expectedIds The exact set of record Ids expected.
   * @return `PersonaOutcome` this expectation, for chaining.
   */
  public PersonaOutcome returnedRowIds(Set<Id> expectedIds) {
    this.expectedRowIds = expectedIds;
    return this;
  }

  /**
   * @description The scenario returned any non-null value — for service calls whose return
   *              shape doesn't fit rows. Compatible with allowed() only — validate() rejects
   *              it on denied().
   * @return `PersonaOutcome` this expectation, for chaining.
   */
  public PersonaOutcome returnedNonNull() {
    this.expectNonNull = true;
    return this;
  }

  /**
   * @description The thrown exception's message contains this fragment, compared
   *              case-insensitively (containsIgnoreCase). Requires denied() — validate()
   *              rejects it on any other kind. Platform denial messages are org/version
   *              observable strings, not documented API: capture every shipped fragment from a
   *              framework self-test run, never assume it.
   * @param fragment The message fragment the denial message must contain.
   * @return `PersonaOutcome` this expectation, for chaining.
   */
  public PersonaOutcome messageContains(String fragment) {
    this.expectedMessageFragment = fragment;
    return this;
  }

  // ── Evaluation ───────────────────────────────────────────────────────────

  /**
   * @description Compares this declared expectation against one persona's actual outcome.
   *              Never throws: a custom Check that throws is caught and returned as the
   *              mismatch (check exception type + message), so no persona's evaluation can
   *              crash the matrix or silence later personas. Note the Check contract returns
   *              mismatch strings rather than asserting — an Assert failure inside a Check is
   *              uncatchable in Apex and would abort the whole matrix.
   * @param actual The persona's actual outcome, built by the runner.
   * @return `String` null on pass; otherwise a human-readable mismatch description for the
   *         failure ledger.
   */
  public String evaluate(PersonaMatrixResult actual) {
    // Defense in depth: an invalid configuration reads as its configuration error even if the
    // runner's validate() gate was skipped.
    String configurationError = validate();
    if (configurationError != null) {
      return configurationError;
    }
    if (actual == null) {
      return 'PersonaOutcome.evaluate(null) — the runner must pass the persona\'s PersonaMatrixResult';
    }
    if (this.kind == ExpectationKind.CUSTOM) {
      return runCustomCheck(actual);
    }
    if (this.kind == ExpectationKind.DENIED) {
      return evaluateDenied(actual);
    }
    return evaluateAllowed(actual);
  }

  /**
   * @description Refinement-compatibility check the runner calls at run() start, before any
   *              runAs: denied() cannot carry returnedRows / returnedRowIds / returnedNonNull
   *              (a scenario that throws returns nothing), and messageContains requires
   *              denied(). Also rejects a null denied type and a null custom Check.
   * @return `String` null when the configuration is valid; otherwise a configuration-error
   *         description for the runner to raise.
   */
  public String validate() {
    Boolean carriesReturnRefinement =
      this.expectedRowCount != null ||
      this.expectedRowIds != null ||
      this.expectNonNull;
    if (this.kind == ExpectationKind.DENIED && this.expectedExceptionType == null) {
      return 'configuration error: denied(null) — pass the exact exception type, e.g. denied(DMLManager.CRUDException.class)';
    }
    if (this.kind == ExpectationKind.CUSTOM && this.customCheck == null) {
      return 'configuration error: custom(null) — pass a PersonaOutcome.Check implementation';
    }
    if (this.kind == ExpectationKind.DENIED && carriesReturnRefinement) {
      return 'configuration error: denied(...) cannot carry returnedRows / returnedRowIds / returnedNonNull — a scenario that throws returns nothing';
    }
    if (this.kind == ExpectationKind.CUSTOM && carriesReturnRefinement) {
      return 'configuration error: custom(...) cannot carry returnedRows / returnedRowIds / returnedNonNull — do that checking inside the Check';
    }
    if (this.expectedMessageFragment != null && this.kind != ExpectationKind.DENIED) {
      return 'configuration error: messageContains requires denied(...)';
    }
    return null;
  }

  // ── Check — the custom-assert seam ───────────────────────────────────────

  /**
   * @description Consumer-implemented custom check, hosted here under a bare name (Check, never
   *              Assert) so it can never shadow System.Assert inside an implementing class.
   *              Return null for pass or a mismatch description for fail — never call Assert
   *              inside a Check: Apex assertion failures cannot be caught, so an assert here
   *              would abort the whole matrix instead of landing in the failure ledger.
   */
  public interface Check {
    /**
     * @description Evaluates one persona's actual outcome.
     * @param result The persona's actual outcome, with full access to the returned value,
     *        caught exception, and limit deltas.
     * @return `String` null on pass; otherwise a mismatch description.
     */
    String check(PersonaMatrixResult result);
  }

  // ── Private evaluation helpers ───────────────────────────────────────────

  // A throwing Check is recorded as the persona's mismatch — never propagated (spec §5).
  private String runCustomCheck(PersonaMatrixResult actual) {
    try {
      return this.customCheck.check(actual);
    } catch (Exception checkException) {
      return 'custom check threw ' +
        checkException.getTypeName() +
        ': ' +
        checkException.getMessage();
    }
  }

  // Denied: an exception is REQUIRED; completing is the security gap this framework exists to
  // catch. Type comparison is exact name equality — getTypeName() vs String.valueOf(Type).
  private String evaluateDenied(PersonaMatrixResult actual) {
    String expectedTypeName = String.valueOf(this.expectedExceptionType);
    Exception caught = actual.getCaughtException();
    if (caught == null) {
      return 'expected denied(' + expectedTypeName + '); scenario COMPLETED — security gap';
    }
    if (caught.getTypeName() != expectedTypeName) {
      return 'expected denied(' +
        expectedTypeName +
        '); got ' +
        caught.getTypeName() +
        ': ' +
        caught.getMessage();
    }
    if (
      this.expectedMessageFragment != null &&
      (caught.getMessage() == null ||
        !caught.getMessage().containsIgnoreCase(this.expectedMessageFragment))
    ) {
      return 'expected denied(' +
        expectedTypeName +
        ') message to contain \'' +
        this.expectedMessageFragment +
        '\' (case-insensitive); got: ' +
        caught.getMessage();
    }
    return null;
  }

  // Allowed: no exception, then each declared return-value refinement in turn.
  private String evaluateAllowed(PersonaMatrixResult actual) {
    if (actual.getCaughtException() != null) {
      return 'expected allowed; scenario threw ' +
        actual.getCaughtException().getTypeName() +
        ': ' +
        actual.getCaughtException().getMessage();
    }
    if (this.expectedRowCount != null) {
      String rowCountMismatch = evaluateRowCount(actual.getReturnedValue());
      if (rowCountMismatch != null) {
        return rowCountMismatch;
      }
    }
    if (this.expectedRowIds != null) {
      String rowIdsMismatch = evaluateRowIds(actual.getReturnedValue());
      if (rowIdsMismatch != null) {
        return rowIdsMismatch;
      }
    }
    if (this.expectNonNull && actual.getReturnedValue() == null) {
      return 'expected a non-null return; scenario returned null';
    }
    return null;
  }

  // returnedRows semantics per spec §5: List → size, Integer → direct (the SELECT COUNT()
  // idiom), null → named mismatch, anything else → mismatch.
  private String evaluateRowCount(Object returnedValue) {
    if (returnedValue == null) {
      return 'expected ' + this.expectedRowCount + ' rows, scenario returned null';
    }
    if (returnedValue instanceof List<Object>) {
      Integer actualSize = ((List<Object>) returnedValue).size();
      return actualSize == this.expectedRowCount
        ? null
        : 'expected allowed with ' +
            this.expectedRowCount +
            ' row(s); got ' +
            actualSize +
            ' row(s)';
    }
    if (returnedValue instanceof Integer) {
      Integer actualCount = (Integer) returnedValue;
      return actualCount == this.expectedRowCount
        ? null
        : 'expected allowed with ' +
            this.expectedRowCount +
            ' row(s); got count ' +
            actualCount;
    }
    return 'expected ' +
      this.expectedRowCount +
      ' row(s); scenario returned neither a List nor an Integer: ' +
      previewOf(returnedValue);
  }

  // returnedRowIds semantics per spec §5: order-insensitive Set<Id> equality over a returned
  // List<SObject>; any other shape (including null) is a mismatch.
  private String evaluateRowIds(Object returnedValue) {
    if (!(returnedValue instanceof List<SObject>)) {
      return 'expected row Ids ' +
        String.valueOf(this.expectedRowIds) +
        '; scenario did not return a List<SObject>: ' +
        previewOf(returnedValue);
    }
    Set<Id> actualIds = new Set<Id>();
    for (SObject returnedRecord : (List<SObject>) returnedValue) {
      actualIds.add(returnedRecord.Id);
    }
    return actualIds.equals(this.expectedRowIds)
      ? null
      : 'expected row Ids ' +
          String.valueOf(this.expectedRowIds) +
          '; got ' +
          String.valueOf(actualIds);
  }

  // Renders an unexpected return value for a mismatch message without flooding the ledger.
  private static String previewOf(Object value) {
    return value == null ? 'null' : String.valueOf(value).abbreviate(VALUE_PREVIEW_LENGTH);
  }
}
