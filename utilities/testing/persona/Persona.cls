/**
 * @description Immutable value object describing one test persona: identity name, profile,
 *              optional role, the ordered permission-set-group and permission-set ladders,
 *              and persona-trait parameters. Pure definition — no org access, no queries, no
 *              DML; PersonaMatrix owns provisioning (persona-matrix-testing §6.1). Produced
 *              by PersonaBuilder.build(); consumer registries hold instances in static final
 *              constants, which is safe precisely because nothing here can mutate. One
 *              persona = one fabricated user with a fixed ladder — a "same user, more
 *              permissions" comparison is two personas (§6.4).
 * @group Testing
 * @see PersonaBuilder
 * @see PersonaMatrix
 * @see PersonaContext
 * @author David Wood
 * @since 2026-08-13
 * @last 2026-08-13 — initial persona-matrix value object (design §4, §6.1, §7).
 */
@IsTest
// Analyzer suppression, disclosed in the v1.1.0 PR: the constructor is the immutable value
// object's single full-state seam, consumed only by PersonaBuilder.build().
@SuppressWarnings('PMD.ExcessiveParameterList')
public inherited sharing class Persona {
  /**
   * @description Profile applied when a builder never calls .profile(...). A
   *              Salesforce-shipped standard profile present in Developer-Edition-based
   *              scratch orgs, so a persona's capability is exactly its permission-set
   *              ladder (persona-matrix-testing §7). Provisioning fails fast when the exact
   *              name resolves to zero rows — `Standard User` is the documented manual
   *              fallback via .profile(...), never an automatic one.
   */
  public static final String DEFAULT_PROFILE_NAME = 'Minimum Access - Salesforce';

  /**
   * @description Suffix deterministicUsername() appends to the persona-name slug. The
   *              domain reaches no real person per testing-discipline §1.4; the literal is
   *              part of the durable lookup contract and must never change once tests ship.
   */
  public static final String USERNAME_SUFFIX = '.persona@test.example.com';

  private final String name;
  private final String profileName;
  private final String roleDeveloperName;
  private final List<String> permissionSetGroupNames;
  private final List<String> permissionSetNames;
  private final Map<String, Object> parameters;

  /**
   * @description Constructs a frozen persona definition. PersonaBuilder.build() is the
   *              blessed entry point; every collection is defensively copied here so no
   *              caller — builder included — retains a mutation path into a built Persona.
   * @param name                    Persona identity name (registry key), e.g. 'Sales Rep'.
   * @param profileName             Exact profile name; builders default it to
   *                                DEFAULT_PROFILE_NAME.
   * @param roleDeveloperName       Role DeveloperName, or null for no role.
   * @param permissionSetGroupNames Ordered permission-set-group ladder; null treated as
   *                                empty.
   * @param permissionSetNames      Ordered permission-set ladder; null treated as empty.
   * @param parameters              Persona-trait parameters; null treated as empty.
   */
  public Persona(
    String name,
    String profileName,
    String roleDeveloperName,
    List<String> permissionSetGroupNames,
    List<String> permissionSetNames,
    Map<String, Object> parameters
  ) {
    this.name = name;
    this.profileName = profileName;
    this.roleDeveloperName = roleDeveloperName;
    this.permissionSetGroupNames = permissionSetGroupNames == null
      ? new List<String>()
      : new List<String>(permissionSetGroupNames);
    this.permissionSetNames = permissionSetNames == null
      ? new List<String>()
      : new List<String>(permissionSetNames);
    this.parameters = parameters == null
      ? new Map<String, Object>()
      : new Map<String, Object>(parameters);
  }

  /**
   * @description The persona's identity name — its registry key and the input to
   *              deterministicUsername().
   * @return `String`
   */
  public String getName() {
    return this.name;
  }

  /**
   * @description Exact profile name provisioning resolves — never a LIKE match.
   * @return `String`
   */
  public String getProfileName() {
    return this.profileName;
  }

  /**
   * @description Role DeveloperName provisioning applies as UserRoleId, or null when the
   *              persona carries no role.
   * @return `String`
   */
  public String getRoleDeveloperName() {
    return this.roleDeveloperName;
  }

  /**
   * @description Ordered permission-set-group ladder. Returned as a defensive copy —
   *              mutating the returned list cannot alter this persona.
   * @return `List<String>`
   */
  public List<String> getPermissionSetGroupNames() {
    return new List<String>(this.permissionSetGroupNames);
  }

  /**
   * @description Ordered permission-set ladder. Returned as a defensive copy — mutating
   *              the returned list cannot alter this persona.
   * @return `List<String>`
   */
  public List<String> getPermissionSetNames() {
    return new List<String>(this.permissionSetNames);
  }

  /**
   * @description Persona-trait parameters, surfaced to scenarios via
   *              PersonaContext.getParameter(). Returned as a defensive copy.
   * @return `Map<String, Object>`
   */
  public Map<String, Object> getParameters() {
    return new Map<String, Object>(this.parameters);
  }

  /**
   * @description Derives this persona's deterministic username — the durable lookup key
   *              that lets PersonaMatrix.userFor(...) re-resolve a provisioned user by
   *              query in any transaction, because static state does not survive the
   *              @TestSetup / test-method boundary.
   *
   *              Derivation rule (the contract — stable for a given name, never to change
   *              once tests ship, since usernames are org-unique and idempotent
   *              re-provisioning keys off this value):
   *              1. Lowercase the persona name.
   *              2. Collapse every maximal run of characters outside [a-z0-9] into a
   *                 single hyphen.
   *              3. Strip leading and trailing hyphens.
   *              4. Append USERNAME_SUFFIX ('.persona@test.example.com').
   *              Example: 'Sales Rep' → 'sales-rep.persona@test.example.com'.
   * @return `String` — the deterministic username on the reserved test domain.
   */
  public String deterministicUsername() {
    String slug = this.name.toLowerCase()
      .replaceAll('[^a-z0-9]+', '-')
      .replaceAll('(^-+)|(-+$)', '');
    return slug + USERNAME_SUFFIX;
  }

  /**
   * @description Full-definition comparison used by PersonaMatrix's idempotency check
   *              (persona-matrix-testing §6.1): re-provisioning a name whose definition
   *              matches in full is a no-op; the same name with a different definition is a
   *              configuration conflict. Compares name, profile, role, both ladders
   *              (order-sensitive — ladder order is part of the definition), and
   *              parameters. String comparison is exact-match case-sensitive — a security
   *              fixture must not treat 'sales_rep' and 'Sales_Rep' as the same grant.
   * @param other Persona to compare against; null compares false.
   * @return `Boolean` — true only when every part of the definition matches exactly.
   */
  public Boolean definitionEquals(Persona other) {
    if (other == null) {
      return false;
    }
    return exactlyEqual(this.name, other.name) &&
      exactlyEqual(this.profileName, other.profileName) &&
      exactlyEqual(this.roleDeveloperName, other.roleDeveloperName) &&
      this.permissionSetGroupNames.equals(other.permissionSetGroupNames) &&
      this.permissionSetNames.equals(other.permissionSetNames) &&
      this.parameters.equals(other.parameters);
  }

  // Null-safe, case-sensitive string equality. Apex's == on String is case-insensitive,
  // which would let two definitions differing only in case pass the conflict check.
  private static Boolean exactlyEqual(String left, String right) {
    return left == null ? right == null : left.equals(right);
  }
}
