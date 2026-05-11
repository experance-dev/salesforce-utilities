/**
 * @description Invocable class to check whether the current transaction is REST or SOAP.
 *
 * @group   Quiddity Recipes
 * @see     QuiddityGuard
 *
 * @author  David Wood
 * @since   June 2024
 */
public with sharing class QuiddityGuardInvocable {
  /**
   * @description Invocable method to check if the current Quiddity context is either REST or SOAP.
   * @return A boolean value indicating if the current quiddity is REST or SOAP.
   * @label Check Transaction is from APIs
   */
  @InvocableMethod(label='Check Transaction is from APIs')
  public static List<Boolean> invocableIsApiQuiddity() {
    List<Boolean> results = new List<Boolean>();
    results.add(QuiddityGuard.isApiQuiddity());
    return results;
  }
}
