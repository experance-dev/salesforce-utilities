/**
 * @description Provides factory methods for generating test SObjects and test users.
 *              Registered defaults live in TestFactoryDefaults; call createSObject(sObj)
 *              to automatically apply them.
 * @group Testing
 * @author David Wood
 * @since December 2020
 * @last May 2026 — Wave 2 conformance: sharing modifier, SYSTEM_MODE DML, exception base, header normalisation
 */
@IsTest
@SuppressWarnings(
  'PMD.CognitiveComplexity, PMD.ExcessivePublicCount, PMD.CyclomaticComplexity'
)
public without sharing class TestFactory {
  private static Integer segment = 1;

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
   * @param sObj             SObject instance to populate.
   * @param defaultClassName Fully-qualified inner-class name (e.g. 'TestFactoryDefaults.AccountDefaults').
   * @return `SObject`
   * @exception TestFactoryException when defaultClassName is not a resolvable type.
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
   * @return The default test user with BasePermissionsApex and TEST_USER_PERMISSION assigned.
   */
  public static User createTestUser() {
    User u = createMinAccessUser(false);
    System.runAs(getAdminUser()) {
      Database.insert(u, AccessLevel.SYSTEM_MODE);
      assignPermSetToUser(u, 'BasePermissionsApex');
      assignPermSetToUser(u, TestFactoryDefaults.TEST_USER_PERMISSION);
    }
    return u;
  }

  /**
   * @param permissionSetName Permission set to assign after creating the user.
   * @return The created test user.
   */
  public static User createTestUserFromPermissionSet(String permissionSetName) {
    User u = createMinAccessUser(true);
    assignPermSetToUser(u, permissionSetName);
    return u;
  }

  /**
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
   * @param usr         User to assign the permission set to.
   * @param permSetName Name of the permission set.
   */
  public static void assignPermSetToUser(User usr, String permSetName) {
    // SOQL: permission set lookup; acceptable in test context.
    Id permSetId = [
      SELECT Id
      FROM PermissionSet
      WHERE Name LIKE :permSetName
      LIMIT 1
    ]
    .Id;
    PermissionSetAssignment psa = new PermissionSetAssignment(
      AssigneeId = usr.Id,
      PermissionSetId = permSetId
    );
    Database.insert(psa, AccessLevel.SYSTEM_MODE);
  }

  // ── Query helpers ────────────────────────────────────────────────────────

  /**
   * @param permissionName Permission set name to match.
   * @return Most recently created User with that permission set and LastName = 'last'.
   */
  public static User getCreatedTestUser(String permissionName) {
    // SOQL: sub-select on PermissionSetAssignment; acceptable in test context.
    return [
      SELECT Id
      FROM User
      WHERE
        Id IN (
          SELECT AssigneeId
          FROM PermissionSetAssignment
          WHERE PermissionSet.Name = :permissionName
        )
        AND LastName = 'last'
      ORDER BY CreatedDate DESC
      LIMIT 1
    ];
  }

  /**
   * @return Most recently created test user matching TestFactoryDefaults.TEST_USER_PERMISSION.
   */
  public static User getCreatedTestUser() {
    return getCreatedTestUser(TestFactoryDefaults.TEST_USER_PERMISSION);
  }

  /**
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
   * @param sObjectName API name of the SObject.
   * @return Map of record type name to RecordTypeInfo.
   */
  public static Map<String, Schema.RecordTypeInfo> getRecordTypes(
    String sObjectName
  ) {
    Schema.DescribeSObjectResult describeResult = Schema.getGlobalDescribe()
      .get(sObjectName)
      .getDescribe();
    return describeResult.getRecordTypeInfosByName();
  }

  /**
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
   * @param sot SObjectType to generate a fake Id for.
   * @return A fake 18-char Id string safe for in-memory test assertions.
   */
  public static String getFakeId(Schema.SObjectType sot) {
    String result = String.valueOf(segment++);
    return sot.getDescribe().getKeyPrefix() +
      '0'.repeat(12 - result.length()) +
      result;
  }

  /**
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

  /** @description Thrown when a defaults class name cannot be resolved or is otherwise invalid. */
  public class TestFactoryException extends UtilitiesModuleException {}

  /** @description Implement this interface in any inner class of TestFactoryDefaults to supply field defaults. */
  public interface FieldDefaults {
    /** @return Map of SObjectField to default value. */
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
