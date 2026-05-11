/**
 * @description contains methods and static lists for rapid acceptance of a
 * particular set of quiddities
 *
 * @group   Utilities
 * @group   Quiddity Guard
 *
 * @author  Apex Recipes, David Wood
 * @since   June 2024
 */
public with sharing class QuiddityGuard {
  /**
   * @description a private testvisible variable allowing developers to
   * inject a custom quiddity value during test execution.
   */
  @TestVisible
  private static Quiddity testQuiddityOverride;

  /**
   * @description a non-exhaustive list of Quiddities that do not include user
   * situations where users could be injecting malicious data.
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
   * @description An exhaustive list of quiddities that are valid for a test
   * execution.
   */
  public static List<Quiddity> trustedTestQuiddities = new List<Quiddity>{
    Quiddity.RUNTEST_SYNC,
    Quiddity.RUNTEST_ASYNC,
    Quiddity.RUNTEST_DEPLOY
  };

  /**
   * @description A list of quiddities that may include user-defined data and
   * therefore should not be trusted without manual FLS/CRUD checks.
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

  /**
   * @description Private method to get the current quiddity, considering the override if present.
   * @return `Quiddity`
   */
  private static Quiddity getCurrentQuiddity() {
    Quiddity q = System.Request.getCurrent().getQuiddity();
    if (testQuiddityOverride != null) {
      q = testQuiddityOverride;
    }
    return q;
  }

  /**
   * @description A method to determine if the current Quiddity context is
   * within a caller-supplied list of acceptable quiddity values.
   * @param acceptableQuiddities A list of quiddities to check against.
   * @return `boolean`
   */
  public static Boolean isAcceptableQuiddity(
    List<Quiddity> acceptableQuiddities
  ) {
    Quiddity q = getCurrentQuiddity();
    return acceptableQuiddities.contains(q);
  }

  /**
   * @description A method to determine if the current Quiddity context is
   * within a caller-supplied list of acceptable quiddity values, and optionally throw an exception.
   * @param acceptableQuiddities A list of quiddities to check against.
   * @param throwError A boolean indicating whether to throw an exception if the quiddity is not acceptable.
   * @return `boolean`
   * @throws `AccessException` if throwError is true and the quiddity is not acceptable.
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
   * @description A method to determine if the current Quiddity context is not
   * within a caller-supplied list of acceptable quiddity values.
   * @param acceptableQuiddities A list of quiddities to check against.
   * @return `boolean`
   */
  public static Boolean isNotAcceptableQuiddity(
    List<Quiddity> acceptableQuiddities
  ) {
    return !isAcceptableQuiddity(acceptableQuiddities);
  }

  /**
   * @description A method to determine if the current Quiddity context is REST.
   * @return `boolean`
   */
  public static Boolean isRestQuiddity() {
    return getCurrentQuiddity() == Quiddity.REST;
  }

  /**
   * @description A method to determine if the current Quiddity context is SOAP.
   * @return `boolean`
   */
  public static Boolean isSoapQuiddity() {
    return getCurrentQuiddity() == Quiddity.SOAP;
  }

  /**
   * @description Determines if the current execution is using the Bulk API quiddity.
   *
   * @return Boolean value indicating if the current execution is using the Bulk API quiddity.
   */
  public static Boolean isBulkAPIQuiddity() {
    return getCurrentQuiddity() == Quiddity.BULK_API;
  }

  /**
   * @description A method to determine if the current Quiddity context is either REST or SOAP.
   * @return `boolean`
   */
  public static Boolean isApiQuiddity() {
    return isRestQuiddity() || isSoapQuiddity() || isBulkAPIQuiddity();
  }

  /**
   * @description A custom exception class to report the quiddity and acceptable quiddities.
   */
  public class AccessException extends Exception {
  }
}
