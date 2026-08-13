/**
 * @description Execution-channel guard. Classifies the current transaction's quiddity —
 *              the channel the request arrived through (Aura, REST, batch, queueable,
 *              test runner, ...) — and answers allow/deny questions about it through
 *              immutable membership checks (`isTrusted`, `isUntrusted`, `isTestQuiddity`)
 *              and channel identifiers (`isRestQuiddity`, `isApiQuiddity`, ...).
 *              Adapted from the Apex Recipes quiddity sample.
 *
 *              Contract — what a quiddity verdict does and does not mean. A quiddity
 *              check gates WHICH CHANNEL may reach a code path; it says nothing about
 *              WHO is calling or WHAT they may touch. "Trusted" here means only that
 *              the channel is not a direct, externally-reachable entry point carrying
 *              caller-shaped input — it is NEVER a substitute for sharing enforcement,
 *              CRUD/FLS checks (`WITH USER_MODE` / `AccessLevel.USER_MODE`), or
 *              business-level authorization. A batch or queueable context is a
 *              "trusted" channel and still processes user-authored record data in
 *              system context; every read and write on such a path keeps its full
 *              access-check discipline regardless of what this guard returns.
 *
 *              The trust lists are private. Consumers ask membership questions
 *              through the methods below; nothing outside this class can read or
 *              mutate the lists, so the guard's verdict cannot drift mid-transaction.
 *              Tests that need the guard to see a different quiddity use the
 *              `@TestVisible testQuiddityOverride` seam — the only test seam exposed.
 *
 *              Sharing modifier: `inherited sharing` — this class performs no SOQL
 *              and no DML; it only inspects `System.Request.getCurrent().getQuiddity()`.
 *              Inheriting the caller's context means the guard never imposes a
 *              sharing model of its own on whatever transaction consults it.
 *
 * @group   Triggers
 * @author  David Wood
 * @since   June 2024
 * @last    May 2026 — conformance refactor
 * @last    2026-08-13 — channel-guard contract: trust lists privatized behind immutable
 *          membership checks (isTrusted / isUntrusted / isTestQuiddity); ApexDoc states
 *          quiddity is never a stand-in for sharing/CRUD/FLS/business authorization
 */
public inherited sharing class QuiddityGuard {
  /**
   * Allows tests to inject a synthetic quiddity without executing in a real async context.
   */
  @TestVisible
  private static Quiddity testQuiddityOverride;

  // ─── Trust lists (private — membership methods below are the public surface) ─

  /**
   * Non-exhaustive set of quiddities whose channel is not a direct, externally
   * reachable entry point. Channel classification only — records flowing through
   * these channels still carry user-authored data, and every consumer keeps its
   * full sharing/CRUD/FLS and business-authorization discipline.
   */
  private static final Set<Quiddity> TRUSTED_QUIDDITIES = new Set<Quiddity>{
    Quiddity.SYNCHRONOUS,
    Quiddity.QUEUEABLE,
    Quiddity.BATCH_APEX,
    Quiddity.RUNTEST_SYNC,
    Quiddity.RUNTEST_ASYNC,
    Quiddity.RUNTEST_DEPLOY
  };

  /**
   * Exhaustive set of quiddities that indicate a test execution.
   */
  private static final Set<Quiddity> TRUSTED_TEST_QUIDDITIES = new Set<Quiddity>{
    Quiddity.RUNTEST_SYNC,
    Quiddity.RUNTEST_ASYNC,
    Quiddity.RUNTEST_DEPLOY
  };

  /**
   * Quiddities whose channel is a direct, externally reachable entry point
   * carrying caller-shaped input (UI actions, inbound API calls, email services).
   */
  private static final Set<Quiddity> UNTRUSTED_QUIDDITIES = new Set<Quiddity>{
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

  // ─── Membership checks — the immutable public surface for the trust lists ───

  /**
   * @description Tests a quiddity for membership in the trusted-channel set.
   *              Channel classification only — never a substitute for sharing,
   *              CRUD/FLS, or business authorization (see the class contract).
   * @param quiddity The quiddity to classify.
   * @return True when the supplied quiddity is a trusted channel.
   */
  public static Boolean isTrusted(Quiddity quiddity) {
    return TRUSTED_QUIDDITIES.contains(quiddity);
  }

  /**
   * @description Tests a quiddity for membership in the untrusted-channel set —
   *              direct, externally reachable entry points carrying caller-shaped input.
   * @param quiddity The quiddity to classify.
   * @return True when the supplied quiddity is an untrusted channel.
   */
  public static Boolean isUntrusted(Quiddity quiddity) {
    return UNTRUSTED_QUIDDITIES.contains(quiddity);
  }

  /**
   * @description Tests a quiddity for membership in the test-execution set.
   * @param quiddity The quiddity to classify.
   * @return True when the supplied quiddity indicates a test execution.
   */
  public static Boolean isTestQuiddity(Quiddity quiddity) {
    return TRUSTED_TEST_QUIDDITIES.contains(quiddity);
  }

  /**
   * @description Tests the current transaction's quiddity against the trusted-channel set.
   * @return True when the current quiddity is a trusted channel.
   */
  public static Boolean isCurrentQuiddityTrusted() {
    return isTrusted(getCurrentQuiddity());
  }

  /**
   * @description Tests the current transaction's quiddity against the trusted-channel
   *              set, optionally escalating a rejection into an exception.
   * @param throwError When true, throws AccessException on rejection.
   * @return True when the current quiddity is a trusted channel.
   * @throws AccessException When the current quiddity is not a trusted channel
   *         and `throwError` is true.
   */
  public static Boolean isCurrentQuiddityTrusted(Boolean throwError) {
    Quiddity q = getCurrentQuiddity();
    Boolean trusted = isTrusted(q);
    if (!trusted && throwError) {
      throw new AccessException(
        'Quiddity not acceptable: ' + q + '. Trusted-channel quiddities only.'
      );
    }
    return trusted;
  }

  // ─── Caller-supplied accept lists ───────────────────────────────────────────

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

  // ─── Channel identifiers ────────────────────────────────────────────────────

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

  /**
   * @description Thrown when a quiddity check fails and the caller requests an exception.
   */
  public class AccessException extends UtilitiesModuleException {
  }
}
