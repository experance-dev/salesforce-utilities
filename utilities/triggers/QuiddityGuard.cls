/**
 * @description Classifies the current Salesforce execution context (quiddity) and
 *              exposes pre-built trusted/untrusted quiddity lists for guard checks.
 *
 * @group   Triggers
 * @author  Apex Recipes, David Wood
 * @since   June 2024
 * @last    May 2026 — Wave 3 conformance
 */
public without sharing class QuiddityGuard {
  /**
   * Allows tests to inject a synthetic quiddity without executing in a real async context.
   */
  @TestVisible
  private static Quiddity testQuiddityOverride;

  /**
   * Non-exhaustive list of quiddities that do not include user-controlled data paths;
   * safe to trust without manual FLS/CRUD checks.
   */
  public static List<Quiddity> trustedQuiddities = new List<Quiddity>{
    Quiddity.SYNCHRONOUS,
    Quiddity.QUEUEABLE,
    Quiddity.BATCH_APEX,
    Quiddity.RUNTEST_SYNC,
    Quiddity.RUNTEST_ASYNC,
    Quiddity.RUNTEST_DEPLOY
  };

  /**
   * Exhaustive list of quiddities that indicate a test execution.
   */
  public static List<Quiddity> trustedTestQuiddities = new List<Quiddity>{
    Quiddity.RUNTEST_SYNC,
    Quiddity.RUNTEST_ASYNC,
    Quiddity.RUNTEST_DEPLOY
  };

  /**
   * Quiddities that may carry user-defined data; require FLS/CRUD checks before trusting.
   */
  public static List<Quiddity> untrustedQuiddities = new List<Quiddity>{
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
   * @param acceptableQuiddities Quiddities to accept.
   * @return True when the current quiddity is in the supplied list.
   */
  public static Boolean isAcceptableQuiddity(
    List<Quiddity> acceptableQuiddities
  ) {
    return acceptableQuiddities.contains(getCurrentQuiddity());
  }

  /**
   * @param acceptableQuiddities Quiddities to accept.
   * @param throwError           When true, throws AccessException on rejection.
   * @return True when the current quiddity is in the supplied list.
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
   * @param acceptableQuiddities Quiddities to accept.
   * @return True when the current quiddity is NOT in the supplied list.
   */
  public static Boolean isNotAcceptableQuiddity(
    List<Quiddity> acceptableQuiddities
  ) {
    return !isAcceptableQuiddity(acceptableQuiddities);
  }

  /** @return True when the current quiddity is REST. */
  public static Boolean isRestQuiddity() {
    return getCurrentQuiddity() == Quiddity.REST;
  }

  /** @return True when the current quiddity is SOAP. */
  public static Boolean isSoapQuiddity() {
    return getCurrentQuiddity() == Quiddity.SOAP;
  }

  /** @return True when the current quiddity is Bulk API. */
  public static Boolean isBulkAPIQuiddity() {
    return getCurrentQuiddity() == Quiddity.BULK_API;
  }

  /** @return True when the current quiddity is REST, SOAP, or Bulk API. */
  public static Boolean isApiQuiddity() {
    return isRestQuiddity() || isSoapQuiddity() || isBulkAPIQuiddity();
  }

  // ─── Exceptions ─────────────────────────────────────────────────────────────

  /** Thrown when a quiddity check fails and the caller requests an exception. */
  public class AccessException extends UtilitiesModuleException {
  }
}
