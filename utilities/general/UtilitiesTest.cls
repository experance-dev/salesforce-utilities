/**
 * @description Test coverage for the Utilities class.
 *
 * @group General
 * @see Utilities
 *
 * @author David Wood
 * @since June 2024
 * @last May 2026 — conformance refactor
 * @last August 2026 — DML-free map-builder fixtures; describe-derived record-type expectations;
 *                     direct coverage for list/type helpers; shape asserts over type asserts
 */
@isTest
public without sharing class UtilitiesTest {
  static final Id FAKE_OPPORTUNITY_ID = TestFactory.getFakeId(
    Opportunity.SObjectType
  );

  @TestSetup
  static void makeData() {
    TestFactory.createMinAccessUser(true);
  }

  @isTest
  static void testStandardPricebookId() {
    Test.startTest();
    System.runAs(TestFactory.getMinAccessUser()) {
      // Inject a known Id through PricebookUtil's @TestVisible seam so the
      // delegation is verified without depending on org data.
      Id injectedId = Test.getStandardPricebookId();
      PricebookUtil.testStandardPricebookId = injectedId;

      Id pricebookId = Utilities.standardPricebookId;

      Assert.areEqual(
        injectedId,
        pricebookId,
        'Utilities.standardPricebookId should delegate to PricebookUtil and return the injected Id.'
      );
    }
    Test.stopTest();
  }

  @isTest
  static void testConvertNullToZero() {
    Integer i = null;
    Double d = null;
    Decimal dec = null;

    Test.startTest();
    System.runAs(TestFactory.getMinAccessUser()) {
      // Test null values
      Assert.isTrue(
        Utilities.convertNullToZero(i) == 0,
        'Integer convertNullToZero failed'
      );
      Assert.isTrue(
        Utilities.convertNullToZero(d) == 0,
        'Double convertNullToZero failed'
      );
      Assert.isTrue(
        Utilities.convertNullToZero(dec) == 0,
        'Decimal convertNullToZero failed'
      );
      // Test non-null values
      i = 12;
      d = 12.2;
      dec = 12.2;
      Assert.isTrue(
        Utilities.convertNullToZero(i) == 12,
        'Integer convertNullToZero failed'
      );
      Assert.isTrue(
        Utilities.convertNullToZero(d) == 12.2,
        'Double convertNullToZero failed'
      );
      Assert.isTrue(
        Utilities.convertNullToZero(dec) == 12.2,
        'Decimal convertNullToZero failed'
      );
    }
    Test.stopTest();
  }

  @isTest
  static void testCreateIdMapFromCollectionByKey() {
    // Pure in-memory map building — fake Ids, no DML.
    List<Account> accounts = new List<Account>();
    accounts.add(
      (Account) TestFactory.createSObject(
        new Account(Name = 'Acme', BillingStreet = '123 Main St'),
        false
      )
    );
    accounts.add(
      (Account) TestFactory.createSObject(
        new Account(Name = 'Globex', BillingStreet = '456 Oak Rd'),
        false
      )
    );
    Utilities.createFakeIdsForList(accounts);

    Test.startTest();
    System.runAs(TestFactory.getMinAccessUser()) {
      Map<Id, Account> accountMap = (Map<Id, Account>) Utilities.createIdMapFromCollectionByKey(
        'Id',
        accounts
      );
      Assert.areEqual(
        2,
        accountMap.size(),
        'There should be 2 accounts in the map'
      );
      Assert.areEqual(
        accounts[0].Id,
        accountMap.get(accounts[0].Id).Id,
        'The first account should be in the map'
      );

      Map<Id, SObject> accountMap2 = Utilities.createIdMapFromCollectionByKey(
        'Id',
        new List<Account>()
      );
      Assert.areEqual(
        0,
        accountMap2.size(),
        'There should be 0 accounts in the map'
      );
    }
    Test.stopTest();
  }

  @isTest
  static void testCreateStringMapFromCollectionByKey() {
    // Pure in-memory map building — no DML needed for a String-keyed map.
    List<Account> accounts = new List<Account>();
    accounts.add(
      (Account) TestFactory.createSObject(
        new Account(Name = 'Acme', BillingStreet = '123 Main St'),
        false
      )
    );
    accounts.add(
      (Account) TestFactory.createSObject(
        new Account(Name = 'Globex', BillingStreet = '456 Oak Rd'),
        false
      )
    );

    Test.startTest();
    System.runAs(TestFactory.getMinAccessUser()) {
      Map<String, Account> accountMap = (Map<String, Account>) Utilities.createStringMapFromCollectionByKey(
        'BillingStreet',
        accounts
      );
      Assert.areEqual(
        2,
        accountMap.size(),
        'There should be 2 accounts in the map'
      );
      Assert.areEqual(
        accounts[0].BillingStreet,
        accountMap.get(accounts[0].BillingStreet).BillingStreet,
        'The first account should be in the map'
      );
      Map<String, SObject> accountMap2 = Utilities.createStringMapFromCollectionByKey(
        'BillingStreet',
        new List<Account>()
      );
      Assert.areEqual(
        0,
        accountMap2.size(),
        'There should be 0 accounts in the map'
      );
    }
    Test.stopTest();
  }

  @isTest
  static void testCreateMapFromCollectionWithCollectionValues() {
    // Pure in-memory map building — three contacts sharing one fake parent Id, no DML.
    Id fakeAccountId = TestFactory.getFakeId(Account.SObjectType);
    List<Contact> contacts = (List<Contact>) TestFactory.createSObjectList(
      new Contact(AccountId = fakeAccountId),
      3,
      false
    );

    Test.startTest();
    System.runAs(TestFactory.getMinAccessUser()) {
      Map<Id, List<Contact>> contactMap = (Map<Id, List<Contact>>) Utilities.createMapFromCollectionWithCollectionValues(
        'AccountId',
        contacts
      );
      Assert.areEqual(1, contactMap.size(), 'There should be 1 account Id key');
      Assert.areEqual(
        3,
        contactMap.get(fakeAccountId).size(),
        'There should be 3 contacts for the first account'
      );
    }
    Test.stopTest();
  }

  @isTest
  static void testGenerateRandomCounter() {
    Test.startTest();
    System.runAs(TestFactory.getMinAccessUser()) {
      String counter = Utilities.generateRandomCounter();

      // Counter contract: the first four hex characters of a generated UUID.
      Assert.areEqual(
        4,
        counter.length(),
        'The counter should be exactly 4 characters long.'
      );
      Assert.isTrue(
        Pattern.matches('[0-9a-f]{4}', counter),
        'The counter should be 4 lowercase hex characters; got "' +
          counter +
          '".'
      );
    }
    Test.stopTest();
  }

  @isTest
  static void testGenerateUUID() {
    Test.startTest();
    System.runAs(TestFactory.getMinAccessUser()) {
      String uuid1 = Utilities.generateUUID();
      String uuid2 = Utilities.generateUUID();

      // UUID contract: 8-4-4-4-12 lowercase hex groups.
      Assert.isTrue(
        Pattern.matches(
          '[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}',
          uuid1
        ),
        'The UUID should match the 8-4-4-4-12 hex shape; got "' + uuid1 + '".'
      );
      Assert.areNotEqual(uuid1, uuid2, 'The values should not be equal');
    }
    Test.stopTest();
  }

  @isTest
  static void testFilterSObjectListByIdWithMatchingIds() {
    Test.startTest();
    System.runAs(TestFactory.getMinAccessUser()) {
      // Setup
      List<OpportunityLineItem> items = createTestObjects();
      // Execution
      List<SObject> filteredItems = Utilities.filterSObjectListById(
        'OpportunityId',
        FAKE_OPPORTUNITY_ID,
        items
      );
      // Assertions
      Assert.areEqual(
        9,
        filteredItems.size(),
        'There should be nine matching SObjects.'
      );
    }
    Test.stopTest();
  }

  @isTest
  static void testFilterSObjectListByIdWithNoMatchingIds() {
    Test.startTest();
    System.runAs(TestFactory.getMinAccessUser()) {
      // Setup
      List<OpportunityLineItem> items = createTestObjects();
      // Execution
      List<SObject> filteredItems = Utilities.filterSObjectListById(
        'OpportunityId',
        TestFactory.getFakeId(Opportunity.SObjectType),
        items
      );
      // Assertions
      Assert.areEqual(
        0,
        filteredItems.size(),
        'There should be no matching SObjects.'
      );
    }
    Test.stopTest();
  }

  @isTest
  static void testFilterSObjectListByIdWithEmptyList() {
    Test.startTest();
    System.runAs(TestFactory.getMinAccessUser()) {
      // Setup
      List<OpportunityLineItem> items = new List<OpportunityLineItem>();
      // Execution
      List<SObject> filteredItems = Utilities.filterSObjectListById(
        'OpportunityId',
        TestFactory.getFakeId(Opportunity.SObjectType),
        items
      );
      // Assertions
      Assert.areEqual(0, filteredItems.size(), 'The list should be empty.');
    }
    Test.stopTest();
  }

  @isTest
  static void testFilterSObjectListByIdWithNullList() {
    Test.startTest();
    System.runAs(TestFactory.getMinAccessUser()) {
      // Setup
      List<OpportunityLineItem> items = null;
      // Execution
      List<SObject> filteredItems = Utilities.filterSObjectListById(
        'OpportunityId',
        TestFactory.getFakeId(Opportunity.SObjectType),
        items
      );
      // Assertions
      Assert.areEqual(
        0,
        filteredItems.size(),
        'The list should be empty when null.'
      );
    }
    Test.stopTest();
  }

  private static List<OpportunityLineItem> createTestObjects() {
    // Create a list of 10 OpportunityLineItems using TestFactory
    List<OpportunityLineItem> items = (List<OpportunityLineItem>) TestFactory.createSObjectList(
      new OpportunityLineItem(OpportunityId = FAKE_OPPORTUNITY_ID),
      10,
      false
    );
    // Change the id of the first item
    items[0].OpportunityId = TestFactory.getFakeId(Opportunity.SObjectType);
    return items;
  }

  @isTest
  static void testGetRecordTypeIdValid() {
    // Derive an existing Account record type from the describe so the test
    // travels between orgs instead of assuming a specific developer name.
    Map<String, Schema.RecordTypeInfo> infosByDeveloperName = Account.SObjectType.getDescribe()
      .getRecordTypeInfosByDeveloperName();
    String existingDeveloperName = null;
    for (String developerName : infosByDeveloperName.keySet()) {
      existingDeveloperName = developerName;
      if (!infosByDeveloperName.get(developerName).isMaster()) {
        break; // Prefer a non-master record type when the org has one.
      }
    }
    if (existingDeveloperName == null) {
      return; // No record type information at all — nothing to assert in this org.
    }

    Id recordTypeId;
    Test.startTest();
    System.runAs(TestFactory.getMinAccessUser()) {
      recordTypeId = Utilities.getRecordTypeId(
        'Account',
        existingDeveloperName
      );
    }
    Test.stopTest();
    Assert.areEqual(
      infosByDeveloperName.get(existingDeveloperName).getRecordTypeId(),
      recordTypeId,
      'The RecordTypeId should match the describe entry for "' +
        existingDeveloperName +
        '".'
    );
  }

  @isTest
  static void testGetRecordTypeIdInvalid() {
    Id recordTypeId;
    Test.startTest();
    System.runAs(TestFactory.getMinAccessUser()) {
      recordTypeId = Utilities.getRecordTypeId(
        'Account',
        'NonExistent_RecordType'
      );
    }
    Test.stopTest();
    Assert.isNull(
      recordTypeId,
      'The RecordTypeId should be null for invalid inputs'
    );
  }

  @isTest
  private static void testGetFakeId() {
    System.runAs(TestFactory.getMinAccessUser()) {
      Test.startTest();
      Id firstId = Utilities.getFakeId(Account.SObjectType);
      Id secondId = Utilities.getFakeId(Account.SObjectType);
      Test.stopTest();

      Assert.areEqual(
        Account.SObjectType,
        firstId.getSobjectType(),
        'The fake Id should carry the requested SObject type\'s key prefix.'
      );
      Assert.areNotEqual(
        firstId,
        secondId,
        'Successive fake Ids should differ — the counter must advance per call.'
      );
    }
  }

  @isTest
  static void testExtractSObjectTypeFromList() {
    System.runAs(TestFactory.getMinAccessUser()) {
      List<Account> accounts = new List<Account>{ new Account(Name = 'Acme') };

      Test.startTest();
      String populatedResult = Utilities.extractSObjectTypeFromList(accounts);
      String emptyResult = Utilities.extractSObjectTypeFromList(
        new List<SObject>()
      );
      Test.stopTest();

      Assert.areEqual(
        'Account',
        populatedResult,
        'A populated list should report its member SObject type.'
      );
      Assert.areEqual(
        'SObject',
        emptyResult,
        'An empty list should fall back to the generic "SObject" type name.'
      );
    }
  }

  @isTest
  static void testIsNullOrEmpty() {
    System.runAs(TestFactory.getMinAccessUser()) {
      Test.startTest();
      Boolean nullResult = Utilities.isNullOrEmpty(null);
      Boolean emptyResult = Utilities.isNullOrEmpty(new List<Account>());
      Boolean populatedResult = Utilities.isNullOrEmpty(
        new List<Account>{ new Account(Name = 'Acme') }
      );
      Test.stopTest();

      Assert.isTrue(nullResult, 'A null list should report null-or-empty.');
      Assert.isTrue(emptyResult, 'An empty list should report null-or-empty.');
      Assert.isFalse(
        populatedResult,
        'A populated list should not report null-or-empty.'
      );
    }
  }

  @isTest
  static void testCreateFakeIdsForList() {
    System.runAs(TestFactory.getMinAccessUser()) {
      List<Account> accounts = new List<Account>{
        new Account(Name = 'Acme'),
        new Account(Name = 'Globex')
      };

      Test.startTest();
      List<SObject> result = Utilities.createFakeIdsForList(accounts);
      Test.stopTest();

      Assert.areEqual(
        2,
        result.size(),
        'The same two records should come back.'
      );
      Assert.isNotNull(accounts[0].Id, 'Each record should receive a fake Id.');
      Assert.isNotNull(accounts[1].Id, 'Each record should receive a fake Id.');
      Assert.areNotEqual(
        accounts[0].Id,
        accounts[1].Id,
        'Each record should receive a distinct fake Id.'
      );
      Assert.areEqual(
        Account.SObjectType,
        accounts[0].Id.getSobjectType(),
        'Fake Ids should carry the record\'s own SObject type.'
      );
    }
  }

  @isTest
  static void testCreateFakeIdsForListNullList() {
    System.runAs(TestFactory.getMinAccessUser()) {
      try {
        Utilities.createFakeIdsForList(null);
        Assert.fail('Expected a NullPointerException for a null list.');
      } catch (NullPointerException e) {
        Assert.isTrue(
          String.isNotBlank(e.getMessage()),
          'The NullPointerException should carry the platform message.'
        );
      }
    }
  }

  @isTest
  static void testExtractStringSetFromField() {
    System.runAs(TestFactory.getMinAccessUser()) {
      // Test data setup
      List<Account> accList = TestFactory.createSObjectList(
        new Account(),
        2,
        false
      );

      // Test method execution
      Test.startTest();
      Set<String> stringSet = Utilities.extractStringSetFromField(
        accList,
        Account.Name
      );
      Test.stopTest();

      // Assertions
      Assert.areEqual(
        2,
        stringSet.size(),
        'The set should contain the 2 Account names'
      );
    }
  }

  @isTest
  static void testExtractIdsetFromField() {
    System.runAs(TestFactory.getMinAccessUser()) {
      // Test data setup
      List<Account> accList = TestFactory.createSObjectList(
        new Account(),
        2,
        false
      );
      Utilities.createFakeIdsForList(accList);

      // Test method execution
      Test.startTest();
      Set<Id> idSet = Utilities.extractIdSetFromField(accList, Account.Id);
      Test.stopTest();

      // Assertions
      Assert.areEqual(
        2,
        idSet.size(),
        'The set should contain the 2 Account Ids'
      );
    }
  }
}
