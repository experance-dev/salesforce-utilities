/**
 * @description Test coverage for the Utilities class.
 *
 * @group General
 * @see Utilities
 *
 * @author David Wood
 * @since June 2024
 * @last May 2026 — Wave 6 conformance
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
      // Test the standardPricebookId method
      Id pricebookId = Utilities.standardPricebookId;
      // Assert that the pricebookId is not null
      Assert.isNotNull(pricebookId, 'Standard Pricebook Id should not be null');
    }
    Test.stopTest();
  }

  @isTest
  static void testGetRecordTypeMap() {
    Test.startTest();
    System.runAs(TestFactory.getMinAccessUser()) {
      // Get the record types for Account
      Map<String, Schema.RecordTypeInfo> mapRecordTypesById = Utilities.getRecordTypeMap(
        'Account'
      );
      // Assert that the map is not null
      Assert.isNotNull(
        mapRecordTypesById,
        'Record types for Account should not be null'
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
    insert accounts;

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
    insert accounts;

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
    List<Contact> contacts = (List<Contact>) TestFactory.createSObjectList(
      new Contact(),
      3,
      'TestFactoryDefaults.ContactWithAccountDefaults',
      true
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
        contactMap.get(contacts[0].AccountId).size(),
        'There should be 3 contacts for the first account'
      );
    }
    Test.stopTest();
  }

  @isTest
  static void testGenerateRandomCounter() {
    Test.startTest();
    System.runAs(TestFactory.getMinAccessUser()) {
      String counter1 = Utilities.generateRandomCounter();
      String counter2 = Utilities.generateRandomCounter();

      Assert.isInstanceOfType(
        counter1,
        String.class,
        'Expected a string return'
      );
      Assert.isInstanceOfType(
        counter2,
        String.class,
        'Expected a string return'
      );
      Assert.areNotEqual(counter1, counter2, 'The values should not be equal');
    }
    Test.stopTest();
  }

  @isTest
  static void testGenerateUUID() {
    Test.startTest();
    System.runAs(TestFactory.getMinAccessUser()) {
      String uuid1 = Utilities.generateUUID();
      String uuid2 = Utilities.generateUUID();

      Assert.isInstanceOfType(uuid1, String.class, 'Expected a string return');
      Assert.isInstanceOfType(uuid2, String.class, 'Expected a string return');
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
    Id recordTypeId;
    Test.startTest();
    System.runAs(TestFactory.getMinAccessUser()) {
      recordTypeId = Utilities.getRecordTypeId('Account', 'Prospect_Account');
    }
    Test.stopTest();
    Assert.isNotNull(
      recordTypeId,
      'The RecordTypeId should not be null for valid inputs'
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
  private static void getFakeIdProductItemTest() {
    System.runAs(TestFactory.getMinAccessUser()) {
      Schema.SObjectType sot = Account.SObjectType;

      Test.startTest();
      Id actualResult = Utilities.getFakeId(sot);
      Test.stopTest();

      Assert.areEqual(
        Account.SObjectType,
        actualResult.getSobjectType(),
        'getFakeIdProductItemTest'
      );
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
