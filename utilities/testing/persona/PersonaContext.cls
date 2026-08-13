/**
 * @description Immutable context handed to a PersonaScenario for each persona run: the
 *              fabricated user the scenario executes as, the persona's identity name, and
 *              the persona-trait parameters declared on its Persona definition. Constructed
 *              by the runner — scenario authors only read from it. Setup-data record Ids do
 *              NOT ride this context; they reach a scenario as constructor state
 *              (persona-matrix-testing §6.4).
 * @group Testing
 * @see PersonaScenario
 * @see Persona
 * @see PersonaMatrix
 * @author David Wood
 * @since 2026-08-13
 * @last 2026-08-13 — initial persona-matrix scenario context (design §4).
 */
@IsTest
public inherited sharing class PersonaContext {
  private final User personaUser;
  private final String personaName;
  private final Map<String, Object> parameters;

  /**
   * @description Constructs a frozen per-persona context. The parameters map is snapshot-
   *              copied so no later mutation of the source map can reach a scenario run.
   * @param personaUser The fabricated user this persona run executes as (the runner's
   *                    System.runAs target).
   * @param personaName The persona's identity name, e.g. 'Sales Rep' — the key a write
   *                    scenario uses to pick its per-persona target record.
   * @param parameters  Persona-trait parameters from the Persona definition; null is
   *                    treated as empty.
   */
  public PersonaContext(
    User personaUser,
    String personaName,
    Map<String, Object> parameters
  ) {
    this.personaUser = personaUser;
    this.personaName = personaName;
    this.parameters = parameters == null
      ? new Map<String, Object>()
      : new Map<String, Object>(parameters);
  }

  /**
   * @description The fabricated user this persona run executes as.
   * @return `User`
   */
  public User getUser() {
    return this.personaUser;
  }

  /**
   * @description The persona's identity name (its registry key), e.g. 'Sales Rep'.
   * @return `String`
   */
  public String getPersonaName() {
    return this.personaName;
  }

  /**
   * @description Looks up a persona-trait parameter declared via
   *              PersonaBuilder.parameter(key, value).
   * @param key Parameter key, exact match (map keys are case-sensitive).
   * @return `Object` — the declared value, or null when the key was never declared.
   */
  public Object getParameter(String key) {
    return this.parameters.get(key);
  }
}
