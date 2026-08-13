/**
 * @description Portable sample personas for the persona-matrix module (persona-matrix-testing
 *              §7) — the same framework/consumer split as TestFactory / TestFactoryDefaults:
 *              the framework owns the machinery, this class is the copy-me example a consuming
 *              org's own registry starts from. Three frozen Persona constants over the
 *              library's own security surface (Debug_Log__c, OWD Private): Library User and
 *              Library Peer share one permission-set ladder so sharing tests can compare owner
 *              vs non-owner with permissions held constant; No Access User carries an empty
 *              ladder and is the CRUD/FLS denial persona. All three ride the default profile
 *              (Persona.DEFAULT_PROFILE_NAME, 'Minimum Access - Salesforce'), so each
 *              persona's capability is exactly its ladder. Constants are safe to share across
 *              every test in a run because PersonaBuilder.build() returns an immutable value.
 * @group Testing
 * @see Persona
 * @see PersonaBuilder
 * @see PersonaMatrix
 * @see PersonaMatrixTest
 * @author David Wood
 * @since 2026-08-13
 * @last 2026-08-13 — initial portable sample personas per design Draft v3 (§7).
 */
@IsTest
public inherited sharing class PersonaDefaults {
  /**
   * @description The library's positive-path persona, mirroring TestFactory's own
   *              testUserPermissionSets ladder: BasePermissionsApex carries the Debug_Log__c
   *              capability (create + read, all field FLS); Utilities_Test_User is the
   *              grant-nothing marker/lookup identity. In sharing self-tests this persona
   *              owns the record under comparison.
   */
  public static final Persona LIBRARY_USER = PersonaBuilder.named('Library User')
    .permissionSet('BasePermissionsApex')
    .permissionSet('Utilities_Test_User')
    .build();

  /**
   * @description Same ladder as LIBRARY_USER, distinct user. Exists so sharing tests can
   *              compare owner vs non-owner on Debug_Log__c (OWD Private) with permissions
   *              held constant — any visibility difference between the two is sharing, not
   *              CRUD/FLS.
   */
  public static final Persona LIBRARY_PEER = PersonaBuilder.named('Library Peer')
    .permissionSet('BasePermissionsApex')
    .permissionSet('Utilities_Test_User')
    .build();

  /**
   * @description Empty ladder on the default minimum-access profile: no object permissions
   *              at all. The CRUD/FLS denial persona — inserts through DMLManager surface
   *              DMLManager.CRUDException, USER_MODE reads surface System.QueryException.
   */
  public static final Persona NO_ACCESS_USER = PersonaBuilder.named('No Access User')
    .build();
}
