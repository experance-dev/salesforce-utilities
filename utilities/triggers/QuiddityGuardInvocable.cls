/**
 * @description Flow-invocable wrapper around QuiddityGuard; exposes the API quiddity
 *              check (REST / SOAP / Bulk API) as an Invocable Action.
 *
 *              Sharing modifier: `inherited sharing` — this wrapper performs no SOQL
 *              and no DML; it only relays the quiddity classification. Inheriting the
 *              calling Flow's context keeps the wrapper from imposing a sharing model
 *              on transactions it merely observes.
 *
 * @group   Triggers
 * @see     QuiddityGuard
 * @author  David Wood
 * @since   June 2024
 * @last    May 2026 — conformance refactor
 * @last    August 2026 — inherited sharing with documented rationale
 */
public inherited sharing class QuiddityGuardInvocable {
  /** @return Single-element list indicating whether the current quiddity is an API context. */
  @InvocableMethod(label='Check Transaction is from APIs')
  public static List<Boolean> invocableIsApiQuiddity() {
    return new List<Boolean>{ QuiddityGuard.isApiQuiddity() };
  }
}
