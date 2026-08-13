/**
 * @description Mutable recipe for a Persona, frozen by build(). Entry point:
 *              PersonaBuilder.named('Sales Rep'), then chain .profile / .role /
 *              .permissionSetGroup / .permissionSet (one ladder entry per call — Apex has
 *              no varargs) / .parameter, and finish with .build(). build() snapshot-copies
 *              every collection into the immutable Persona, so mutating the builder after
 *              build() can never touch an already-built value. A builder is never a handle
 *              — PersonaMatrix.provision() and .persona() accept Persona only
 *              (persona-matrix-testing §4, §7). Production personas prefer
 *              .permissionSetGroup(): assigning the real PSG exercises muting behavior a
 *              reconstruction from individual sets cannot.
 * @group Testing
 * @see Persona
 * @see PersonaMatrix
 * @author David Wood
 * @since 2026-08-13
 * @last 2026-08-13 — initial persona-matrix builder (design §4, §7).
 */
@IsTest
public inherited sharing class PersonaBuilder {
  private final String name;
  private String profileName = Persona.DEFAULT_PROFILE_NAME;
  private String roleDeveloperName;
  private final List<String> permissionSetGroupNames = new List<String>();
  private final List<String> permissionSetNames = new List<String>();
  private final Map<String, Object> parameters = new Map<String, Object>();

  // Builders are created through named(...) only, so every builder carries a valid name.
  private PersonaBuilder(String name) {
    this.name = name;
  }

  /**
   * @description Static entry point: starts a builder for the persona with this identity
   *              name. The name is the persona's registry key and the sole input to
   *              Persona.deterministicUsername(), so it must contain at least one
   *              alphanumeric character — otherwise the username slug would be empty and
   *              the durable lookup contract unusable.
   * @param name Persona identity name, e.g. 'Sales Rep'. Blank or slug-empty names throw.
   * @return `PersonaBuilder`
   * @throws IllegalArgumentException when the name is blank or contains no alphanumerics.
   */
  public static PersonaBuilder named(String name) {
    if (String.isBlank(name)) {
      throw new IllegalArgumentException(
        'PersonaBuilder.named(...) requires a non-blank persona name.'
      );
    }
    if (String.isBlank(name.replaceAll('[^a-zA-Z0-9]', ''))) {
      throw new IllegalArgumentException(
        'PersonaBuilder.named(\'' +
          name +
          '\') — persona name must contain at least one alphanumeric character, ' +
          'because the deterministic username slug is derived from it.'
      );
    }
    return new PersonaBuilder(name);
  }

  /**
   * @description Overrides the default profile (Persona.DEFAULT_PROFILE_NAME). Provisioning
   *              resolves the exact name — never LIKE — and fails fast on zero rows.
   * @param profileName Exact profile name, e.g. 'Standard User'.
   * @return `PersonaBuilder` — this builder, for chaining.
   * @throws IllegalArgumentException when the profile name is blank.
   */
  public PersonaBuilder profile(String profileName) {
    requireNonBlank(profileName, 'profile(...)');
    this.profileName = profileName;
    return this;
  }

  /**
   * @description Sets the persona's role by DeveloperName; provisioning applies it as
   *              UserRoleId. Role hierarchy is how managers see subordinate-owned records
   *              under Private OWD. Roles are referenced, never created.
   * @param roleDeveloperName Role DeveloperName, e.g. 'Sales_Manager'.
   * @return `PersonaBuilder` — this builder, for chaining.
   * @throws IllegalArgumentException when the role DeveloperName is blank.
   */
  public PersonaBuilder role(String roleDeveloperName) {
    requireNonBlank(roleDeveloperName, 'role(...)');
    this.roleDeveloperName = roleDeveloperName;
    return this;
  }

  /**
   * @description Appends one permission-set-group name to the ordered ladder — one entry
   *              per call. The preferred grant mechanism for production personas: the real
   *              PSG carries its muting behavior with it.
   * @param groupName Exact PermissionSetGroup DeveloperName.
   * @return `PersonaBuilder` — this builder, for chaining.
   * @throws IllegalArgumentException when the group name is blank.
   */
  public PersonaBuilder permissionSetGroup(String groupName) {
    requireNonBlank(groupName, 'permissionSetGroup(...)');
    this.permissionSetGroupNames.add(groupName);
    return this;
  }

  /**
   * @description Appends one permission-set name to the ordered ladder — one entry per
   *              call. For direct or exceptional grants and library-internal fixtures;
   *              production personas prefer permissionSetGroup(...).
   * @param permissionSetName Exact PermissionSet Name.
   * @return `PersonaBuilder` — this builder, for chaining.
   * @throws IllegalArgumentException when the permission-set name is blank.
   */
  public PersonaBuilder permissionSet(String permissionSetName) {
    requireNonBlank(permissionSetName, 'permissionSet(...)');
    this.permissionSetNames.add(permissionSetName);
    return this;
  }

  /**
   * @description Declares a persona-trait parameter, surfaced to scenarios via
   *              PersonaContext.getParameter(key). Re-declaring a key overwrites it.
   * @param key   Parameter key; map keys are case-sensitive.
   * @param value Parameter value; null is a legal value.
   * @return `PersonaBuilder` — this builder, for chaining.
   * @throws IllegalArgumentException when the key is blank.
   */
  public PersonaBuilder parameter(String key, Object value) {
    requireNonBlank(key, 'parameter(...)');
    this.parameters.put(key, value);
    return this;
  }

  /**
   * @description Freezes the recipe into an immutable Persona. Snapshot-copies both
   *              ladders and the parameters map (and Persona's constructor copies again on
   *              receipt), so no mutation of this builder after build() can reach a built
   *              Persona — which is what makes static final registry constants safe to
   *              share across every test in a run.
   * @return `Persona` — the frozen definition.
   */
  public Persona build() {
    return new Persona(
      this.name,
      this.profileName,
      this.roleDeveloperName,
      new List<String>(this.permissionSetGroupNames),
      new List<String>(this.permissionSetNames),
      new Map<String, Object>(this.parameters)
    );
  }

  // Shared fail-fast guard: a blank token in a security fixture definition is always a
  // configuration mistake, never something to resolve later.
  private static void requireNonBlank(String value, String methodLabel) {
    if (String.isBlank(value)) {
      throw new IllegalArgumentException(
        'PersonaBuilder.' + methodLabel + ' requires a non-blank value.'
      );
    }
  }
}
