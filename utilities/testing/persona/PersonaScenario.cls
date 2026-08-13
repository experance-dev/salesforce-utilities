/**
 * @description The story action a persona matrix executes once per persona, each run inside
 *              its own System.runAs block. Consumer-implemented strategy interface — bare
 *              name, no `I` prefix, per naming.md's interface split (`I` is reserved for
 *              interface+Impl DI pairs; callback/strategy contracts use bare names).
 *              Authoring rules (persona-matrix-testing §6.4): one scenario = one denial
 *              mode — a scenario asserted with denied(...) acts unconditionally on known
 *              Ids, a scenario asserted with row counts only reads; setup-data Ids reach
 *              the scenario as constructor state; write scenarios take per-persona target
 *              records so no persona's run can contaminate another's.
 * @group Testing
 * @see PersonaContext
 * @see PersonaMatrix
 * @author David Wood
 * @since 2026-08-13
 * @last 2026-08-13 — initial persona-matrix scenario contract (design §4).
 */
@IsTest
public interface PersonaScenario {
  /**
   * @description Runs the scenario as the current persona. Invoked by the runner inside
   *              System.runAs(personaUser); any thrown exception is caught and evaluated
   *              against that persona's declared PersonaOutcome, never rethrown mid-matrix.
   * @param ctx The running persona's context: fabricated user, persona name, and the
   *            persona-trait parameters declared on its Persona definition.
   * @return Value evaluated against the declared PersonaOutcome — a List for row
   *         expectations, an Integer for the SELECT COUNT() idiom, any non-null value for
   *         returnedNonNull(), or null when only completion matters.
   */
  Object run(PersonaContext ctx);
}
