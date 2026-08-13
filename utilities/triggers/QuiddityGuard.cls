/**
 * @description Classifies the current Salesforce execution context (quiddity) and
 *              exposes pre-built trusted/untrusted quiddity lists for guard checks.
 *
 *              Sharing modifier: `inherited sharing` — this class performs no SOQL
 *              and no DML; it only inspects `System.Request.getCurrent().getQuiddity()`.
 *              Inheriting the caller's context means the guard never imposes a
 *              sharing model of its own on whatever transaction consults it.
 *
 * @group   Triggers
 * @author  Apex Recipes, David Wood
 * @since   June 2024
 * @last    May 2026 — conformance refactor
 * @last    August 2026 — trust-list contract hardening: final lists, inherited sharing, @throws doc
 */
public inherited sharing class QuiddityGuard {
  /**
   * Allows tests to inject a synthetic quiddity without executing in a real async context.
   */
  @TestVisible
  private static Quiddity testQuiddityOverride;

  /**
   * Non-exhaustive list of quiddities that do not include user-controlled data paths;
   * safe to trust without manual FLS/CRUD checks.
   *
   * Trust contract (applies to all three lists below): these lists are published,
   * read-only reference data. `final` blocks reassignment but Apex `final` does not
   * block element mutation — `.add()` still compiles — so this comment carries the
   * rest of the contract: never mutate a list's contents. A caller that mutates a
   * trust list changes the guard's verdict for every other consumer in the
   * transaction. Tests that need the guard to see a different quiddity use the
   * `@TestVisible testQuiddityOverride` seam, not list mutation.
   */
  public static final List<Quiddity> trustedQuiddities = new List<Quiddity>{
    Quiddity.SYNCHRONOUS,
    Quiddity.QUEUEABLE,
    Quiddity.BATCH_APEX,
    Quiddity.RUNTEST_SYNC,
    Quiddity.RUNTEST_ASYNC,
    Quiddity.RUNTEST_DEPLOY
  };

  /**
   * Exhaustive list of quiddities that indicate a test execution.
   * Read-only by contract — see the trust contract on `trustedQuiddities`.
   */
  public static final List<Quiddity> trustedTestQuiddities = new List<Quiddity>{
    Quiddity.RUNTEST_SYNC,
    Quiddity.RUNTEST_ASYNC,
    Quiddity.RUNTEST_DEPLOY
  };

  /**
   * Quiddities that may carry user-defined data; require FLS/CRUD checks before trusting.
   * Read-only by contract — see the trust contract on `trustedQuiddities`.
   */
  public static final List<Quiddity> untrustedQuiddities = new List<Quiddity>{
    Quiddity.AURA,
    Quiddity.DISCOVERABLE_LOGIN,
    Quiddity.INBOUND_EMAIL_SERVICE,
    Quiddity.INVOCABLE_ACTION,
    Quiddity.IOT,
    Quiddity.QUICK_ACTION,
    Quiddity.REMOTE_ACTION,
    Quiddity.REST,
    Quiddity.SOAP,
    Quiddity.VF
  };

  // ─── Helpers ────────────────────────────────────────────────────────────────

  private static Quiddity getCurrentQuiddity() {
    Quiddity q = System.Request.getCurrent().getQuiddity();
    if (testQuiddityOverride != null) {
      q = testQuiddityOverride;
    }
    return q;
  }

  // ─── Public API ─────────────────────────────────────────────────────────────

  /**
   * @description Tests the current quiddity against the supplied accept list.
   * @param acceptableQuiddities Quiddities to accept.
   * @return True when the current quiddity is in the supplied list.
   */
  public static Boolean isAcceptableQuiddity(
    List<Quiddity> acceptableQuiddities
  ) {
    return acceptableQuiddities.contains(getCurrentQuiddity());
  }

  /**
   * @description Tests the current quiddity against the supplied accept list,
   *              optionally escalating a rejection into an exception.
   * @param acceptableQuiddities Quiddities to accept.
   * @param throwError           When true, throws AccessException on rejection.
   * @return True when the current quiddity is in the supplied list.
   * @throws AccessException When the current quiddity is not in the supplied list
   *         and `throwError` is true.
   */
  public static Boolean isAcceptableQuiddity(
    List<Quiddity> acceptableQuiddities,
    Boolean throwError
  ) {
    Quiddity q = getCurrentQuiddity();
    Boolean isAcceptable = acceptableQuiddities.contains(q);
    if (!isAcceptable && throwError) {
      throw new AccessException(
        'Quiddity not acceptable: ' +
          q +
          '. Acceptable quiddities: ' +
          acceptableQuiddities
      );
    }
    return isAcceptable;
  }

  /**
   * @description Convenience negation of `isAcceptableQuiddity`.
   * @param acceptableQuiddities Quiddities to accept.
   * @return True when the current quiddity is NOT in the supplied list.
   */
  public static Boolean isNotAcceptableQuiddity(
    List<Quiddity> acceptableQuiddities
  ) {
    return !isAcceptableQuiddity(acceptableQuiddities);
  }

  /**
   * @description Identifies a REST execution context.
   * @return True when the current quiddity is REST.
   */
  public static Boolean isRestQuiddity() {
    return getCurrentQuiddity() == Quiddity.REST;
  }

  /**
   * @description Identifies a SOAP execution context.
   * @return True when the current quiddity is SOAP.
   */
  public static Boolean isSoapQuiddity() {
    return getCurrentQuiddity() == Quiddity.SOAP;
  }

  /**
   * @description Identifies a Bulk API execution context.
   * @return True when the current quiddity is Bulk API.
   */
  public static Boolean isBulkAPIQuiddity() {
    return getCurrentQuiddity() == Quiddity.BULK_API;
  }

  /**
   * @description Identifies any inbound-API execution context.
   * @return True when the current quiddity is REST, SOAP, or Bulk API.
   */
  public static Boolean isApiQuiddity() {
    return isRestQuiddity() || isSoapQuiddity() || isBulkAPIQuiddity();
  }

  // ─── Exceptions ─────────────────────────────────────────────────────────────

  /** Thrown when a quiddity check fails and the caller requests an exception. */
  public class AccessException extends UtilitiesModuleException {
  }
}
