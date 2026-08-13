/**
 * @description Provides factory methods for generating test SObjects and test users.
 *              Registered defaults live in TestFactoryDefaults; call createSObject(sObj)
 *              to automatically apply them.
 * @group Testing
 * @author David Wood
 * @since December 2020
 * @last May 2026 — conformance refactor: sharing modifier, SYSTEM_MODE DML, exception base, header normalisation
 * @last August 2026 — createTestUser permission sets injectable via testUserPermissionSets; duplicate
 *                      record-type helper removed (Utilities keeps the canonical one); analyzer conformance
 * @last 2026-08-13 — identity-safe user resolution: exact-Name permission-set matching with descriptive
 *                     missing/ambiguous throws, assignPermSetIfPresent escape hatch, getCreatedTestUser exactly-one enforcement, getTestUserByUsername
 */
@IsTest
@SuppressWarnings(
  'PMD.CognitiveComplexity, PMD.ExcessivePublicCount, PMD.CyclomaticComplexity'
)
public without sharing class TestFactory {
  private static Integer segment = 1;

  // Injection seam for pinning the ambiguous-permission-set path: PermissionSet.Name is unique
  // per namespace, so a real duplicate can't be fabricated in a test — only observed when a
  // managed package's permission set collides with a local one. When non-null, resolution
  // returns this list instead of querying.
  @TestVisible
  private static List<PermissionSet> permissionSetQueryOverride;

  // Permission sets createTestUser() assigns to the default test user.
  // Consumer orgs override this list before calling the factory; the default
  // matches the permission sets this library ships.
  @TestVisible
  static List<String> testUserPermissionSets = new List<String>{
    'BasePermissionsApex',
    TestFactoryDefaults.TEST_USER_PERMISSION
  };

  // When creating a list of SObjects we need a unique name field per record.
  // Objects without a standard Name field are mapped here.
  private static Map<Schema.SObjectType, Schema.SObjectField> nameFieldMap = new Map<Schema.SObjectType, Schema.SObjectField>{
    Contact.SObjectType => Contact.LastName,
    Lead.SObjectType => Lead.LastName,
    Case.SObjectType => Case.CaseNumber,
    OpportunityLineItem.SObjectType => OpportunityLineItem.Description,
    QuoteLineItem.SObjectType => QuoteLineItem.Description,
    User.SObjectType => User.LastName
  };

  // ── createSObject overloads ──────────────────────────────────────────────

  /**
   * @description Applies the auto-discovered TestFactoryDefaults for the SObject's type, when one exists.
   * @param sObj SObject instance to populate with defaults.
   * @return `SObject`
   */
  public static SObject createSObject(SObject sObj) {
    String objectName = String.valueOf(sObj.getSObjectType());
    // Derive the defaults class name: strip __c / __ so custom objects resolve correctly.
    String defaultClassName =
      objectName.replaceAll('__(c|C)$|__', '') + 'Defaults';
    if (Type.forName('TestFactoryDefaults.' + defaultClassName) != null) {
      sObj = createSObject(sObj, 'TestFactoryDefaults.' + defaultClassName);
    }
    return sObj;
  }

  /**
   * @description Applies auto-discovered defaults and optionally inserts the record.
   * @param sObj     SObject instance to populate.
   * @param doInsert When true, inserts the record in SYSTEM_MODE.
   * @return `SObject`
   */
  public static SObject createSObject(SObject sObj, Boolean doInsert) {
    SObject retObject = createSObject(sObj);
    if (doInsert) {
      Database.insert(retObject, AccessLevel.SYSTEM_MODE);
    }
    return retObject;
  }

  /**
   * @description Applies the named defaults class to the record.
   * @param sObj             SObject instance to populate.
   * @param defaultClassName Fully-qualified inner-class name (e.g. 'TestFactoryDefaults.AccountDefaults').
   * @return `SObject`
   * @throws TestFactoryException when defaultClassName is not a resolvable type.
   */
  public static SObject createSObject(SObject sObj, String defaultClassName) {
    Type t = Type.forName(defaultClassName);
    if (t == null) {
      throw new TestFactoryException('Invalid defaults class: ' + defaultClassName);
    }
    FieldDefaults defaults = (FieldDefaults) t.newInstance();
    addFieldDefaults(sObj, defaults.getFieldDefaults());
    return sObj;
  }

  /**
   * @description Applies the named defaults class and optionally inserts the record.
   * @param sObj             SObject instance to populate.
   * @param defaultClassName Fully-qualified inner-class name.
   * @param doInsert         When true, inserts the record in SYSTEM_MODE.
   * @return `SObject`
   */
  public static SObject createSObject(
    SObject sObj,
    String defaultClassName,
    Boolean doInsert
  ) {
    SObject retObject = createSObject(sObj, defaultClassName);
    if (doInsert) {
      Database.insert(retObject, AccessLevel.SYSTEM_MODE);
    }
    return retObject;
  }

  // ── createSObjectList overloads ─────────────────────────────────────────

  /**
   * @description Builds a list of clones of the template with auto-discovered defaults applied.
   * @param sObj            Template SObject.
   * @param numberOfObjects Number of clones to build.
   * @return `SObject[]`
   */
  public static SObject[] createSObjectList(
    SObject sObj,
    Integer numberOfObjects
  ) {
    return createSObjectList(sObj, numberOfObjects, (String) null);
  }

  /**
   * @description Builds a list of clones with auto-discovered defaults and optionally bulk-inserts it.
   * @param sObj            Template SObject.
   * @param numberOfObjects Number of clones to build.
   * @param doInsert        When true, bulk-inserts the list in SYSTEM_MODE.
   * @return `SObject[]`
   */
  public static SObject[] createSObjectList(
    SObject sObj,
    Integer numberOfObjects,
    Boolean doInsert
  ) {
    SObject[] retList = createSObjectList(sObj, numberOfObjects, (String) null);
    if (doInsert) {
      Database.insert(retList, AccessLevel.SYSTEM_MODE);
    }
    return retList;
  }

  /**
   * @description Builds a list of clones with the named defaults applied, uniquifying each record's name field.
   * @param sObj            Template SObject.
   * @param numberOfObjects Number of clones to build.
   * @param defaultClassName Fully-qualified inner-class name (optional, nullable).
   * @return `SObject[]`
   */
  public static SObject[] createSObjectList(
    SObject sObj,
    Integer numberOfObjects,
    String defaultClassName
  ) {
    SObject[] sObjs = new List<SObject>{};
    SObject newObj;

    if (defaultClassName == null) {
      newObj = createSObject(sObj);
    } else {
      newObj = createSObject(sObj, defaultClassName);
    }

    String nameField = String.valueOf(nameFieldMap.get(sObj.getSObjectType()));
    if (nameField == null) {
      nameField = 'Name';
    }
    Boolean nameIsAutoNumber = sObj.getSObjectType()
      .getDescribe()
      .fields.getMap()
      .get(nameField)
      .getDescribe()
      .isAutoNumber();

    for (Integer i = 0; i < numberOfObjects; i++) {
      SObject clonedSObj = newObj.clone(false, true);
      if (!nameIsAutoNumber) {
        clonedSObj.put(nameField, (String) clonedSObj.get(nameField) + ' ' + i);
      }
      sObjs.add(clonedSObj);
    }
    return sObjs;
  }

  /**
   * @description Builds a list of clones with the named defaults applied and optionally bulk-inserts it.
   * @param sObj            Template SObject.
   * @param numberOfObjects Number of clones to build.
   * @param defaultClassName Fully-qualified inner-class name (optional, nullable).
   * @param doInsert        When true, bulk-inserts the list in SYSTEM_MODE.
   * @return `SObject[]`
   */
  @SuppressWarnings('PMD.ExcessiveParameterList')
  public static SObject[] createSObjectList(
    SObject sObj,
    Integer numberOfObjects,
    String defaultClassName,
    Boolean doInsert
  ) {
    SObject[] retList = createSObjectList(
      sObj,
      numberOfObjects,
      defaultClassName
    );
    if (doInsert) {
      Database.insert(retList, AccessLevel.SYSTEM_MODE);
    }
    return retList;
  }

  // ── User helpers ─────────────────────────────────────────────────────────

  /**
   * @description Builds a test User on the given profile, inserting under an admin context when requested.
   * @param profileId Profile Id for the new user.
   * @param doInsert  When true, inserts the user wrapped in System.runAs(admin).
   * @return `User`
   */
  public static User createTestUser(Id profileId, Boolean doInsert) {
    User u = new User(
      profileId = profileId,
      LastName = 'last',
      Email = 'Testuser@test.example.com',
      Username = 'Testuser@test.example.com' + Crypto.getRandomInteger(),
      CompanyName = 'TEST',
      Title = 'title',
      Alias = 'alias',
      TimeZoneSidKey = 'America/Los_Angeles',
      EmailEncodingKey = 'UTF-8',
      LanguageLocaleKey = 'en_US',
      LocaleSidKey = 'en_US'
    );
    if (doInsert) {
      // User inserts require System.runAs(admin) to avoid mixed-DML errors in tests.
      System.runAs(getAdminUser()) {
        Database.insert(u, AccessLevel.SYSTEM_MODE);
      }
    }
    return u;
  }

  /**
   * @description Builds a test User on the named profile.
   * @param doInsert    When true, inserts the user.
   * @param profileName Name of the profile to assign.
   * @return `User`
   */
  public static User createTestUser(Boolean doInsert, String profileName) {
    // SOQL: profile lookup; acceptable in test context — no production path.
    Profile selectedProfile = [
      SELECT Id
      FROM Profile
      WHERE Name = :profileName
    ];
    return createTestUser(selectedProfile.Id, doInsert);
  }

  /**
   * @description Creates and inserts the default test user, assigning every
   *              permission set registered in testUserPermissionSets.
   * @return The default test user with the registered permission sets assigned.
   */
  public static User createTestUser() {
    User u = createMinAccessUser(false);
    System.runAs(getAdminUser()) {
      Database.insert(u, AccessLevel.SYSTEM_MODE);
      for (String permissionSetName : testUserPermissionSets) {
        assignPermSetToUser(u, permissionSetName);
      }
    }
    return u;
  }

  /**
   * @description Creates a minimum-access user and assigns the named permission set.
   * @param permissionSetName Permission set to assign after creating the user.
   * @return The created test user.
   */
  public static User createTestUserFromPermissionSet(String permissionSetName) {
    User u = createMinAccessUser(true);
    assignPermSetToUser(u, permissionSetName);
    return u;
  }

  /**
   * @description Builds a test User on the Minimum Access - Salesforce profile.
   * @param doInsert When true, inserts the user.
   * @return `User` with Minimum Access - Salesforce profile.
   */
  public static User createMinAccessUser(Boolean doInsert) {
    // SOQL: profile lookup; acceptable in test context.
    Id profileId = [
      SELECT Id
      FROM Profile
      WHERE Name = 'Minimum Access - Salesforce'
    ]
    .Id;
    return createTestUser(profileId, doInsert);
  }

  /**
   * @description Builds a test User on the Marketing User profile.
   * @param doInsert When true, inserts the user.
   * @return `User` with Marketing User profile.
   */
  public static User createMarketingUser(Boolean doInsert) {
    // SOQL: profile lookup; acceptable in test context.
    Id profileId = [
      SELECT Id
      FROM Profile
      WHERE Name = 'Marketing User'
      LIMIT 1
    ]
    .Id;
    return createTestUser(profileId, doInsert);
  }

  /**
   * @description Assigns the permission set with the EXACT given Name to the user in SYSTEM_MODE.
   *              Resolution requires exactly one match: a missing or ambiguous Name throws rather
   *              than silently assigning the wrong permission set — a security test running under
   *              the wrong grant is worse than one that fails loudly.
   * @param usr         User to assign the permission set to.
   * @param permSetName Exact API Name of the permission set (no wildcards).
   * @throws TestFactoryException when no permission set — or more than one, across namespaces — matches the Name.
   */
  public static void assignPermSetToUser(User usr, String permSetName) {
    assignPermissionSet(usr, requireExactlyOnePermissionSet(permSetName));
  }

  /**
   * @description Portability escape hatch: assigns the permission set with the EXACT given Name
   *              when it exists in the org, and SKIPS SILENTLY — no exception, no assignment —
   *              when no permission set matches. Use only where absence is an expected,
   *              acceptable state (e.g. shared test source running in an org that doesn't ship
   *              the optional permission set). An ambiguous Name (multiple matches across
   *              namespaces) still throws, because assigning an arbitrary match is never safe.
   * @param usr         User to assign the permission set to.
   * @param permSetName Exact API Name of the permission set (no wildcards).
   * @return `Boolean` — true when the permission set was found and assigned; false when it was
   *         absent and the call skipped.
   * @throws TestFactoryException when more than one permission set matches the Name.
   */
  public static Boolean assignPermSetIfPresent(User usr, String permSetName) {
    List<PermissionSet> matches = findPermissionSetsByExactName(permSetName);
    if (matches.isEmpty()) {
      return false;
    }
    if (matches.size() > 1) {
      throw ambiguousPermissionSetException(permSetName, matches.size());
    }
    assignPermissionSet(usr, matches[0].Id);
    return true;
  }

  // ── Query helpers ────────────────────────────────────────────────────────

  /**
   * @description Resolves the ONE user holding the exactly-named permission set. This is the
   *              cross-transaction rediscovery seam for the `@TestSetup` pattern (createTestUser()
   *              in setup, getCreatedTestUser() in each test method); it never guesses — zero or
   *              multiple holders throw instead of returning "the most recent match", because a
   *              test running as the wrong identity passes for the wrong reason. Prefer holding
   *              the User returned by the create* methods when you're in the same transaction;
   *              use getTestUserByUsername for precise lookup when several users exist.
   * @param permissionName Exact permission set Name whose single holder identifies the test user.
   * @return The single User assigned that permission set.
   * @throws TestFactoryException when no user — or more than one — holds the permission set.
   */
  public static User getCreatedTestUser(String permissionName) {
    // SOQL: sub-select on PermissionSetAssignment; acceptable in test context.
    List<User> holders = [
      SELECT Id, Username
      FROM User
      WHERE
        Id IN (
          SELECT AssigneeId
          FROM PermissionSetAssignment
          WHERE PermissionSet.Name = :permissionName
        )
    ];
    if (holders.isEmpty()) {
      throw new TestFactoryException(
        'No user holds permission set \'' +
          permissionName +
          '\'. Call createTestUser() (or assignPermSetToUser) in @TestSetup before resolving the running user.'
      );
    }
    if (holders.size() > 1) {
      throw new TestFactoryException(
        holders.size() +
          ' users hold permission set \'' +
          permissionName +
          '\' — the test-user identity is ambiguous. Hold the User returned by createTestUser(), or resolve precisely via getTestUserByUsername.'
      );
    }
    return holders[0];
  }

  /**
   * @description Resolves the factory-created default test user via its registered permission set.
   * @return The single User holding TestFactoryDefaults.TEST_USER_PERMISSION.
   * @throws TestFactoryException when no user — or more than one — holds that permission set.
   */
  public static User getCreatedTestUser() {
    return getCreatedTestUser(TestFactoryDefaults.TEST_USER_PERMISSION);
  }

  /**
   * @description Resolves a user by Username — the org-unique identifier, so the result can never
   *              be the wrong identity. Use this to rediscover a specific `@TestSetup`-created
   *              user when several test users exist.
   * @param username Exact Username of the user to resolve.
   * @return The User with that Username.
   * @throws TestFactoryException when no user has that Username.
   */
  public static User getTestUserByUsername(String username) {
    // SOQL: acceptable in test context. Username is platform-unique, so 0 or 1 rows.
    List<User> matches = [
      SELECT Id, Username
      FROM User
      WHERE Username = :username
    ];
    if (matches.isEmpty()) {
      throw new TestFactoryException(
        'No user exists with Username \'' +
          username +
          '\'. Create the user first and use the Username from the returned record.'
      );
    }
    return matches[0];
  }

  /**
   * @description Fetches the most recent minimum-access user in the org.
   * @return Most recently created Minimum Access - Salesforce test user.
   */
  public static User getMinAccessUser() {
    // SOQL: acceptable in test context.
    return [
      SELECT Id
      FROM User
      WHERE Profile.Name = 'Minimum Access - Salesforce'
      ORDER BY CreatedDate DESC
      LIMIT 1
    ];
  }

  /**
   * @description Fetches the most recent active user on the named profile.
   * @param profileName Profile name to match.
   * @return Most recently created active User with that profile.
   */
  public static User getTestUser(String profileName) {
    // SOQL: acceptable in test context.
    return [
      SELECT Id
      FROM User
      WHERE Profile.Name = :profileName AND IsActive = TRUE
      ORDER BY CreatedDate DESC
      LIMIT 1
    ];
  }

  /**
   * @description Resolves the PricebookEntry linking the given pricebook and product.
   * @param pricebookId Pricebook Id.
   * @param productId   Product2 Id.
   * @return The matching PricebookEntry Id.
   */
  public static Id getPricebookEntryId(Id pricebookId, Id productId) {
    // SOQL: acceptable in test context.
    PricebookEntry pbe = [
      SELECT Id
      FROM PricebookEntry
      WHERE Pricebook2Id = :pricebookId AND Product2Id = :productId
      LIMIT 1
    ];
    return pbe.Id;
  }

  /**
   * @description Generates a well-formed fake record Id without any DML.
   * @param sot SObjectType to generate a fake Id for.
   * @return A fake 15-char Id string safe for in-memory test assertions.
   */
  public static String getFakeId(Schema.SObjectType sot) {
    String result = String.valueOf(segment++);
    return sot.getDescribe().getKeyPrefix() +
      '0'.repeat(12 - result.length()) +
      result;
  }

  /**
   * @description Blanks each record's Name so negative-path tests can force validation failures.
   * @param incoming List of SObjects to invalidate (sets Name to empty string).
   * @return `List<SObject>` — same list, mutated.
   */
  public static List<SObject> invalidateSObjectList(List<SObject> incoming) {
    for (SObject obj : incoming) {
      obj.put('name', '');
    }
    return incoming;
  }

  // ── Inner types ──────────────────────────────────────────────────────────

  /**
   * @description Thrown when factory resolution fails: an unresolvable defaults class, a missing
   *              or ambiguous permission set Name, or a test-user lookup that cannot be pinned to
   *              exactly one identity.
   */
  public class TestFactoryException extends UtilitiesModuleException {}

  /** @description Implement this interface in any inner class of TestFactoryDefaults to supply field defaults. */
  public interface FieldDefaults {
    /**
     * @description Supplies the default field values applied to a newly built record of one SObject type.
     * @return Map of SObjectField to default value.
     */
    Map<Schema.SObjectField, Object> getFieldDefaults();
  }

  // ── Private helpers ──────────────────────────────────────────────────────

  private static void addFieldDefaults(
    SObject sObj,
    Map<Schema.SObjectField, Object> defaults
  ) {
    Map<String, Object> populatedFields = sObj.getPopulatedFieldsAsMap();
    for (Schema.SObjectField field : defaults.keySet()) {
      if (!populatedFields.containsKey(String.valueOf(field))) {
        sObj.put(field, defaults.get(field));
      }
    }
  }

  private static List<PermissionSet> findPermissionSetsByExactName(
    String permSetName
  ) {
    if (permissionSetQueryOverride != null) {
      return permissionSetQueryOverride;
    }
    // SOQL: permission set lookup; acceptable in test context. No LIMIT — the row count is the
    // exactly-one contract both assign methods enforce.
    return [
      SELECT Id
      FROM PermissionSet
      WHERE Name = :permSetName
    ];
  }

  private static Id requireExactlyOnePermissionSet(String permSetName) {
    List<PermissionSet> matches = findPermissionSetsByExactName(permSetName);
    if (matches.isEmpty()) {
      throw new TestFactoryException(
        'No permission set exists with Name \'' +
          permSetName +
          '\'. Deploy it (or override TestFactory.testUserPermissionSets with the sets this org ships); use assignPermSetIfPresent only where absence is an expected state.'
      );
    }
    if (matches.size() > 1) {
      throw ambiguousPermissionSetException(permSetName, matches.size());
    }
    return matches[0].Id;
  }

  private static TestFactoryException ambiguousPermissionSetException(
    String permSetName,
    Integer matchCount
  ) {
    return new TestFactoryException(
      matchCount +
        ' permission sets match Name \'' +
        permSetName +
        '\' (Name collides across namespaces) — assignment is ambiguous. Qualify the lookup or remove the collision.'
    );
  }

  private static void assignPermissionSet(User usr, Id permSetId) {
    PermissionSetAssignment psa = new PermissionSetAssignment(
      AssigneeId = usr.Id,
      PermissionSetId = permSetId
    );
    Database.insert(psa, AccessLevel.SYSTEM_MODE);
  }

  private static User getAdminUser() {
    // SOQL: acceptable in test context — needed for mixed-DML workaround.
    return [
      SELECT Id
      FROM User
      WHERE Profile.Name = 'System Administrator' AND IsActive = TRUE
      LIMIT 1
    ];
  }
}
