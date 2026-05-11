/**
 * @description Flow-invocable wrapper around QuiddityGuard; exposes the API quiddity
 *              check (REST / SOAP / Bulk API) as an Invocable Action.
 *
 * @group   Triggers
 * @see     QuiddityGuard
 * @author  David Wood
 * @since   June 2024
 * @last    May 2026 — Wave 3 conformance
 */
public without sharing class QuiddityGuardInvocable {
  /** @return Single-element list indicating whether the current quiddity is an API context. */
  @InvocableMethod(label='Check Transaction is from APIs')
  public static List<Boolean> invocableIsApiQuiddity() {
    return new List<Boolean>{ QuiddityGuard.isApiQuiddity() };
  }
}
