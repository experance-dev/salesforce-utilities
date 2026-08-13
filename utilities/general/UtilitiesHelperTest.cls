/**
 * @description Test coverage for the UtilitiesHelper class.
 *
 * @group General
 * @see UtilitiesHelper
 *
 * @author David Wood
 * @since June 2024
 * @last May 2026 — conformance refactor
 * @last August 2026 — DML-free fixtures via fake Ids; negative path for an unknown field key
 * @last 2026-08-13 — pinned the plain-generic-map contract and the descriptive validation paths
 *                    (blank/null inputs, type mismatch, unknown field, non-Id key field)
 */
@isTest
public without sharing class UtilitiesHelperTest {
  @TestSetup
  static void makeData() {
    TestFactory.createMinAccessUser(true);
  }

  private static List<Account> buildAccounts() {
    // Pure in-memory fixtures — fake Ids, no DML.
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
    return accounts;
  }

  @isTest
  static void testCreateDynamicIdMap() {
    List<Account> accounts = buildAccounts();

    Test.startTest();
    System.runAs(TestFactory.getMinAccessUser()) {
      Map<Id, SObject> accountsById = UtilitiesHelper.createDynamicIdMap(
        'Account',
        'Id',
        accounts
      );
      Assert.areEqual(
        2,
        accountsById.size(),
        'There should be 2 accounts in the map'
      );
      Assert.areEqual(
        accounts[0].Id,
        accountsById.get(accounts[0].Id).Id,
        'The first account should be in the map'
      );
    }
    Test.stopTest();
  }

  @isTest
  static void testCreateDynamicIdMapReturnsGenericMap() {
    List<Account> accounts = buildAccounts();

    Test.startTest();
    System.runAs(TestFactory.getMinAccessUser()) {
      // Contract pin: the map is a plain generic Map<Id, SObject> — the old
      // Type.forName construction produced a runtime-concrete Map<Id, Account>;
      // that cast is no longer supported. Values still cast individually.
      Object result = UtilitiesHelper.createDynamicIdMap(
        'Account',
        'Id',
        accounts
      );
      try {
        Map<Id, Account> concreteMap = (Map<Id, Account>) result;
        Assert.fail(
          'Casting the generic map to Map<Id, Account> should throw; got ' +
            concreteMap
        );
      } catch (System.TypeException e) {
        Assert.isTrue(
          String.isNotBlank(e.getMessage()),
          'The TypeException should carry the platform cast message.'
        );
      }
      Account firstAccount = (Account) ((Map<Id, SObject>) result)
        .get(accounts[0].Id);
      Assert.areEqual(
        accounts[0].Id,
        firstAccount.Id,
        'Individual values should still cast to the concrete SObject type.'
      );
    }
    Test.stopTest();
  }

  @isTest
  static void testCreateDynamicStringMap() {
    List<Account> accounts = buildAccounts();

    Test.startTest();
    System.runAs(TestFactory.getMinAccessUser()) {
      Map<String, SObject> accountsByStreet = UtilitiesHelper.createDynamicStringMap(
        'Account',
        'BillingStreet',
        accounts
      );
      Assert.areEqual(
        2,
        accountsByStreet.size(),
        'There should be 2 accounts in the map'
      );
      Account firstAccount = (Account) accountsByStreet.get(
        accounts[0].BillingStreet
      );
      Assert.areEqual(
        accounts[0].BillingStreet,
        firstAccount.BillingStreet,
        'The first account should be in the map'
      );
    }
    Test.stopTest();
  }

  @isTest
  static void testCreateDynamicStringMapSkipsNullKeyValues() {
    List<Account> accounts = buildAccounts();
    accounts[1].BillingStreet = null;

    Test.startTest();
    System.runAs(TestFactory.getMinAccessUser()) {
      Map<String, SObject> accountsByStreet = UtilitiesHelper.createDynamicStringMap(
        'Account',
        'BillingStreet',
        accounts
      );
      Assert.areEqual(
        1,
        accountsByStreet.size(),
        'A record with a null key value should be skipped, not mapped under null.'
      );
      Assert.isNotNull(
        accountsByStreet.get(accounts[0].BillingStreet),
        'The record with a populated key should still be mapped.'
      );
    }
    Test.stopTest();
  }

  @isTest
  static void testCreateDynamicIdListMap() {
    // Three contacts sharing one fake parent Id, plus one with no parent — no DML.
    Id fakeAccountId = TestFactory.getFakeId(Account.SObjectType);
    List<Contact> contacts = (List<Contact>) TestFactory.createSObjectList(
      new Contact(AccountId = fakeAccountId),
      3,
      false
    );
    contacts.add(
      (Contact) TestFactory.createSObject(
        new Contact(LastName = 'Orphan'),
        false
      )
    );

    Test.startTest();
    System.runAs(TestFactory.getMinAccessUser()) {
      Map<Id, List<SObject>> contactsByAccountId = UtilitiesHelper.createDynamicIdListMap(
        'Contact',
        'AccountId',
        contacts
      );
      Assert.areEqual(
        1,
        contactsByAccountId.size(),
        'There should be 1 account Id key — the null-key contact is skipped'
      );
      Assert.areEqual(
        3,
        contactsByAccountId.get(fakeAccountId).size(),
        'There should be 3 contacts for the first account'
      );
    }
    Test.stopTest();
  }

  @isTest
  static void testCreateDynamicIdMapBadFieldKey() {
    List<Account> accounts = buildAccounts();

    Test.startTest();
    System.runAs(TestFactory.getMinAccessUser()) {
      try {
        UtilitiesHelper.createDynamicIdMap(
          'Account',
          'No_Such_Field__c',
          accounts
        );
        Assert.fail(
          'Expected an IllegalArgumentException for an unknown field key.'
        );
      } catch (IllegalArgumentException e) {
        Assert.isTrue(
          e.getMessage().contains('No_Such_Field__c') &&
            e.getMessage().contains('Account'),
          'The error should name the bad field and the object; got "' +
            e.getMessage() +
            '".'
        );
      }
    }
    Test.stopTest();
  }

  @isTest
  static void testCreateDynamicIdMapNonIdKeyField() {
    List<Account> accounts = buildAccounts();

    Test.startTest();
    System.runAs(TestFactory.getMinAccessUser()) {
      try {
        UtilitiesHelper.createDynamicIdMap('Account', 'Name', accounts);
        Assert.fail(
          'Expected an IllegalArgumentException for a non-Id key field on an Id-keyed map.'
        );
      } catch (IllegalArgumentException e) {
        Assert.isTrue(
          e.getMessage().contains('Name') &&
            e.getMessage().contains('Id or lookup/reference'),
          'The error should name the field and the required field type; got "' +
            e.getMessage() +
            '".'
        );
      }
    }
    Test.stopTest();
  }

  @isTest
  static void testCreateDynamicIdMapObjectTypeMismatch() {
    List<Account> accounts = buildAccounts();

    Test.startTest();
    System.runAs(TestFactory.getMinAccessUser()) {
      try {
        UtilitiesHelper.createDynamicIdMap('Contact', 'Id', accounts);
        Assert.fail(
          'Expected an IllegalArgumentException when objType does not match the list.'
        );
      } catch (IllegalArgumentException e) {
        Assert.isTrue(
          e.getMessage().contains('Contact') &&
            e.getMessage().contains('Account'),
          'The error should name both the declared and the actual type; got "' +
            e.getMessage() +
            '".'
        );
      }
    }
    Test.stopTest();
  }

  @isTest
  static void testValidationRejectsBlankAndNullInputs() {
    List<Account> accounts = buildAccounts();

    Test.startTest();
    System.runAs(TestFactory.getMinAccessUser()) {
      try {
        UtilitiesHelper.createDynamicIdMap('', 'Id', accounts);
        Assert.fail('Expected an IllegalArgumentException for a blank objType.');
      } catch (IllegalArgumentException e) {
        Assert.isTrue(
          e.getMessage().contains('objType'),
          'The error should name the blank objType input; got "' +
            e.getMessage() +
            '".'
        );
      }
      try {
        UtilitiesHelper.createDynamicStringMap('Account', ' ', accounts);
        Assert.fail('Expected an IllegalArgumentException for a blank key.');
      } catch (IllegalArgumentException e) {
        Assert.isTrue(
          e.getMessage().contains('key'),
          'The error should name the blank key input; got "' +
            e.getMessage() +
            '".'
        );
      }
      try {
        UtilitiesHelper.createDynamicIdListMap('Account', 'Id', null);
        Assert.fail('Expected an IllegalArgumentException for a null list.');
      } catch (IllegalArgumentException e) {
        Assert.isTrue(
          e.getMessage().contains('sObjectList'),
          'The error should name the null list input; got "' +
            e.getMessage() +
            '".'
        );
      }
    }
    Test.stopTest();
  }

  @isTest
  static void testEmptyListReturnsEmptyMapWithoutFieldValidation() {
    Test.startTest();
    System.runAs(TestFactory.getMinAccessUser()) {
      // Field-level validation needs a record to describe against, so an empty
      // list short-circuits to an empty map even with an unresolvable key.
      Map<Id, SObject> emptyIdMap = UtilitiesHelper.createDynamicIdMap(
        'Account',
        'No_Such_Field__c',
        new List<Account>()
      );
      Map<String, SObject> emptyStringMap = UtilitiesHelper.createDynamicStringMap(
        'Account',
        'BillingStreet',
        new List<Account>()
      );
      Map<Id, List<SObject>> emptyListMap = UtilitiesHelper.createDynamicIdListMap(
        'Contact',
        'AccountId',
        new List<Contact>()
      );
      Assert.areEqual(0, emptyIdMap.size(), 'An empty list yields an empty map.');
      Assert.areEqual(
        0,
        emptyStringMap.size(),
        'An empty list yields an empty String-keyed map.'
      );
      Assert.areEqual(
        0,
        emptyListMap.size(),
        'An empty list yields an empty grouped map.'
      );
    }
    Test.stopTest();
  }
}
