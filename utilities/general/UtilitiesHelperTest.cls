/**
 * @description Test coverage for the UtilitiesHelper class.
 *
 * @group General
 * @see UtilitiesHelper
 *
 * @author David Wood
 * @since June 2024
 * @last May 2026 — Wave 6 conformance
 */
@isTest
public without sharing class UtilitiesHelperTest {
  @TestSetup
  static void makeData() {
    TestFactory.createMinAccessUser(true);
  }

  @isTest
  static void testCreateDynamicIdMap() {
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
      Map<Id, Account> accountMap = (Map<Id, Account>) UtilitiesHelper.createDynamicIdMap(
        'Account',
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
    }
    Test.stopTest();
  }

  @isTest
  static void testCreateDynamicStringMap() {
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
      Map<String, Account> accountMap = (Map<String, Account>) UtilitiesHelper.createDynamicStringMap(
        'Account',
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
    }
    Test.stopTest();
  }

  @isTest
  static void testCreateDynamicIdListMap() {
    List<Contact> contacts = (List<Contact>) TestFactory.createSObjectList(
      new Contact(),
      3,
      'TestFactoryDefaults.ContactWithAccountDefaults',
      true
    );

    Test.startTest();
    System.runAs(TestFactory.getMinAccessUser()) {
      Map<Id, List<Contact>> contactMap = UtilitiesHelper.createDynamicIdListMap(
        'Contact',
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
}
