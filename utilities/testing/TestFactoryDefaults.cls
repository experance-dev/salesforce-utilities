/**
 * @description Default field-value sets for every SObject type used in tests.
 *              Inner class names follow the convention [ObjectName]Defaults (strip __c/__).
 *              TestFactory.createSObject auto-discovers these by convention.
 * @group Testing
 * @author David Wood
 * @since December 2020
 * @last May 2026 — Wave 2 conformance: sharing modifier, header normalisation, method-level ApexDoc stripped
 */
@IsTest
public without sharing class TestFactoryDefaults {
  public static final String DEFAULT_PRODUCT_FAMILY = 'TestFam';
  public static final String DEFAULT_WARRANTY_PRODUCT = '226';
  public static final String TEST_USER_PERMISSION = 'TestMachineRep';

  private static Id priceBookId;

  // ── Standard object defaults ─────────────────────────────────────────────

  public class AccountDefaults implements TestFactory.FieldDefaults {
    String randomizer = Utilities.generateRandomCounter();

    public Map<Schema.SObjectField, Object> getFieldDefaults() {
      Id recordTypeId = Utilities.getRecordTypeMap('Account')
        .get('Customer Account')
        .getRecordTypeId();
      return new Map<Schema.SObjectField, Object>{
        Account.Name => 'Test Account' + randomizer,
        Account.RecordTypeId => recordTypeId,
        Account.DBS_Customer_Number__c => generateDBSCustomerNo(),
        Account.BillingStreet => randomizer + ' Test St',
        Account.BillingCity => 'Test ' + randomizer + ' City',
        Account.BillingState => 'TN',
        Account.BillingPostalCode => '1' + randomizer,
        Account.ShippingStreet => 2 + randomizer + ' Shipping St',
        Account.ShippingCity => 'Shipping City ' + randomizer,
        Account.ShippingState => 'TN',
        Account.ShippingPostalCode => '1' + randomizer
      };
    }
  }

  public class MyAccountDefaults implements TestFactory.FieldDefaults {
    String randomizer = Utilities.generateRandomCounter();

    public Map<Schema.SObjectField, Object> getFieldDefaults() {
      return new Map<Schema.SObjectField, Object>{
        Account.Name => 'My Test Account',
        Account.DBS_Customer_Number__c => generateDBSCustomerNo(),
        Account.BillingStreet => randomizer + ' Test St',
        Account.BillingCity => 'Test ' + randomizer + ' City',
        Account.BillingState => 'TN',
        Account.BillingPostalCode => '1' + randomizer,
        Account.ShippingStreet => 2 + randomizer + ' Shipping St',
        Account.ShippingCity => 'Shipping City ' + randomizer,
        Account.ShippingState => 'TN',
        Account.ShippingPostalCode => '1' + randomizer
      };
    }
  }

  public class UserDefaults implements TestFactory.FieldDefaults {
    public Map<Schema.SObjectField, Object> getFieldDefaults() {
      String code = Utilities.generateRandomCounter();
      // SOQL: profile lookup; acceptable in test context.
      Profile standardUserProfile = [
        SELECT Id
        FROM Profile
        WHERE Name = 'Standard User'
        LIMIT 1
      ];
      return new Map<Schema.SObjectField, Object>{
        User.Alias => 'st' + code,
        User.Email => 'standarduser' + code + '@mailinator.com',
        User.EmailEncodingKey => 'UTF-8',
        User.LastName => 'User',
        User.LanguageLocaleKey => 'en_US',
        User.LocaleSidKey => 'en_US',
        User.ProfileId => standardUserProfile.Id,
        User.TimeZoneSidKey => 'America/New_York',
        User.UserName => 'standarduser' + code + '@mailinator.com'
      };
    }
  }

  public class ContactDefaults implements TestFactory.FieldDefaults {
    public Map<Schema.SObjectField, Object> getFieldDefaults() {
      return new Map<Schema.SObjectField, Object>{
        Contact.FirstName => 'First',
        Contact.LastName => 'Last',
        Contact.Title => 'Owner'
      };
    }
  }

  public class ContactWithAccountDefaults implements TestFactory.FieldDefaults {
    Account account = (Account) TestFactory.createSObject(new Account(), true);

    public Map<Schema.SObjectField, Object> getFieldDefaults() {
      return new Map<Schema.SObjectField, Object>{
        Contact.FirstName => 'First',
        Contact.LastName => 'Last',
        Contact.Title => 'Owner',
        Contact.AccountId => account.Id
      };
    }
  }

  public class OpportunityDefaults implements TestFactory.FieldDefaults {
    public Map<Schema.SObjectField, Object> getFieldDefaults() {
      String code = Utilities.generateRandomCounter();
      return new Map<Schema.SObjectField, Object>{
        Opportunity.Name => 'Test Opportunity ' + code,
        Opportunity.StageName => 'Quoting',
        Opportunity.CloseDate => Date.today().addDays(10)
      };
    }
  }

  public class OpportunityWithAccountDefaults implements TestFactory.FieldDefaults {
    public Map<Schema.SObjectField, Object> getFieldDefaults() {
      String code = Utilities.generateRandomCounter();
      Account account = (Account) TestFactory.createSObject(
        new Account(Name = 'Test Account ' + code),
        true
      );
      return new Map<Schema.SObjectField, Object>{
        Opportunity.Name => 'Test Opportunity ' + code,
        Opportunity.StageName => 'Quoting',
        Opportunity.AccountId => account.Id,
        Opportunity.CloseDate => Date.today()
      };
    }
  }

  public class OpportunityLineItemDefaults implements TestFactory.FieldDefaults {
    public Map<Schema.SObjectField, Object> getFieldDefaults() {
      return new Map<Schema.SObjectField, Object>{
        OpportunityLineItem.Is_Machine__c => false,
        OpportunityLineItem.Quantity => 1
      };
    }
  }

  public class CampaignDefaults implements TestFactory.FieldDefaults {
    public Map<Schema.SObjectField, Object> getFieldDefaults() {
      return new Map<Schema.SObjectField, Object>{
        Campaign.Campaign_Division__c => UtilPickLists.getPickListValues(
          Campaign.Campaign_Division__c
        )[0]
      };
    }
  }

  public class CaseDefaults implements TestFactory.FieldDefaults {
    public Map<Schema.SObjectField, Object> getFieldDefaults() {
      return new Map<Schema.SObjectField, Object>{
        Case.Subject => 'Test Case'
      };
    }
  }

  public class LeadDefaults implements TestFactory.FieldDefaults {
    public Map<Schema.SObjectField, Object> getFieldDefaults() {
      return new Map<Schema.SObjectField, Object>{
        Lead.LastName => 'Test Lead',
        Lead.Company => 'Test Company'
      };
    }
  }

  // ── Product defaults ─────────────────────────────────────────────────────

  public class Product2Defaults implements TestFactory.FieldDefaults {
    public Map<Schema.SObjectField, Object> getFieldDefaults() {
      String code = Utilities.generateRandomCounter();
      return new Map<Schema.SObjectField, Object>{
        Product2.productCode => 'Test Product ' + code,
        Product2.Family => DEFAULT_PRODUCT_FAMILY,
        Product2.Type__c => 'Machine',
        Product2.Name => 'Test Product ' + code,
        Product2.Description => 'Test Description ' + code,
        Product2.Availability__c => true,
        Product2.Callable_Config_Product__c => false,
        Product2.IsActive => true,
        Product2.Manual_Maintenance_Product__c => false,
        Product2.Machine_Status__c => 'New',
        Product2.Price_List__c => true,
        Product2.List_Price__c => 100,
        Product2.Acquisition_Cost__c => 50,
        Product2.Cost__c => 50
      };
    }
  }

  public class Product2UsedMachineDefaults implements TestFactory.FieldDefaults {
    public Map<Schema.SObjectField, Object> getFieldDefaults() {
      String code = Utilities.generateRandomCounter();
      TestFactory.createSObject(
        new Machine__c(Serial_Number_DBS__c = code, Availability__c = true),
        true
      );
      return new Map<Schema.SObjectField, Object>{
        Product2.Acquisition_Cost__c => 6000,
        Product2.Availability__c => true,
        Product2.Callable_Config_Product__c => false,
        Product2.Cost__c => 6000,
        Product2.Description => 'Test Description ' + code,
        Product2.Family => DEFAULT_PRODUCT_FAMILY,
        Product2.IsActive => true,
        Product2.List_Price__c => 5500,
        Product2.Machine_Status__c => 'Used',
        Product2.Manual_Maintenance_Product__c => false,
        Product2.Manufacture_Year__c => '2018',
        Product2.Name => 'Test Product ' + code,
        Product2.Price_List__c => true,
        Product2.productCode => 'CBD-123',
        Product2.Serial_Number__c => code,
        Product2.Type__c => 'Machine'
      };
    }
  }

  public class Product2AttachementDefaults implements TestFactory.FieldDefaults {
    public Map<Schema.SObjectField, Object> getFieldDefaults() {
      String code = Utilities.generateRandomCounter();
      return new Map<Schema.SObjectField, Object>{
        Product2.Acquisition_Cost__c => 50,
        Product2.Availability__c => true,
        Product2.Callable_Config_Product__c => false,
        Product2.Cost__c => 50,
        Product2.Description => 'Test Description ' + code,
        Product2.Family => DEFAULT_PRODUCT_FAMILY,
        Product2.IsActive => true,
        Product2.List_Price__c => 100,
        Product2.Machine_Status__c => 'New',
        Product2.Manual_Maintenance_Product__c => false,
        Product2.Name => 'Test Product ' + code,
        Product2.Price_List__c => true,
        Product2.productCode => 'Test Product ' + code,
        Product2.Type__c => 'Attachment'
      };
    }
  }

  public class ProductWarrantiesDefaults implements TestFactory.FieldDefaults {
    public Map<Schema.SObjectField, Object> getFieldDefaults() {
      return new Map<Schema.SObjectField, Object>{
        Product2.Acquisition_Cost__c => 1000,
        Product2.Coverage_Type__c => 'POWERTRAIN',
        Product2.Family => DEFAULT_PRODUCT_FAMILY,
        Product2.IsActive => true,
        Product2.List_Price__c => 1000,
        Product2.Name => 'Test Warranty',
        Product2.Type__c => 'Warranty',
        Product2.Warranty_Hours__c => '1500',
        Product2.Warranty_Model__c => DEFAULT_WARRANTY_PRODUCT,
        Product2.Warranty_Months__c => '24'
      };
    }
  }

  // ── Machine defaults ─────────────────────────────────────────────────────

  public class MachineDefaults implements TestFactory.FieldDefaults {
    Id machineRecordTypeId = Utilities.getRecordTypeId('Machine__c', 'Dealer_Inventory');
    Account accountOwner = (Account) TestFactory.createSObject(new Account(), true);
    String serialNo = Utilities.generateUUID();

    public Map<Schema.SObjectField, Object> getFieldDefaults() {
      return new Map<Schema.SObjectField, Object>{
        Machine__c.RecordTypeId => machineRecordTypeId,
        Machine__c.Account__c => accountOwner.Id,
        Machine__c.Serial_Number_DBS__c => serialNo.left(12),
        Machine__c.Equipment_Manufacturer_Code__c => 'AA',
        Machine__c.External_ID__c => 'AA-' + serialNo.left(12)
      };
    }
  }

  public class MachineWithoutAccountDefaults implements TestFactory.FieldDefaults {
    Id machineRecordTypeId = Utilities.getRecordTypeId('Machine__c', 'Customer_Machine');

    public Map<Schema.SObjectField, Object> getFieldDefaults() {
      return new Map<Schema.SObjectField, Object>{
        Machine__c.RecordTypeId => machineRecordTypeId
      };
    }
  }

  // ── Quote / OLI test-suite defaults ─────────────────────────────────────

  /**
   * @description Full OLI test suite: Account + Opportunity + Used-Machine Product2 + PricebookEntry.
   */
  public class OpportunityLineItemTestSuiteUsedMachineDefaults implements TestFactory.FieldDefaults {
    public Map<Schema.SObjectField, Object> getFieldDefaults() {
      String code = Utilities.generateRandomCounter();
      Product2 product = (Product2) TestFactory.createSObject(
        new Product2(),
        'TestFactoryDefaults.Product2UsedMachineDefaults',
        true
      );
      Id pricebookEntryId = TestFactory.getPricebookEntryId(
        getPricebookId(),
        product.Id
      );
      Opportunity opportunity = (Opportunity) TestFactory.createSObject(
        new Opportunity(
          Name = 'Test Opportunity ' + code,
          StageName = 'Quoting'
        ),
        TestFactoryDefaults.OpportunityWithAccountDefaults.class.getName(),
        true
      );
      return new Map<Schema.SObjectField, Object>{
        OpportunityLineItem.OpportunityId => opportunity.Id,
        OpportunityLineItem.PricebookEntryId => pricebookEntryId,
        OpportunityLineItem.Quantity => 1,
        OpportunityLineItem.UnitPrice => 10000
      };
    }
  }

  /**
   * @description Full OLI test suite: Account + Opportunity + Attachment Product2 + PricebookEntry.
   */
  public class OpportunityLineItemTestSuiteAttachementDefaults implements TestFactory.FieldDefaults {
    public Map<Schema.SObjectField, Object> getFieldDefaults() {
      String code = Utilities.generateRandomCounter();
      Product2 product = (Product2) TestFactory.createSObject(
        new Product2(),
        'TestFactoryDefaults.Product2AttachementDefaults',
        true
      );
      Id pbeId = TestFactory.getPricebookEntryId(getPricebookId(), product.Id);
      Opportunity opportunity = (Opportunity) TestFactory.createSObject(
        new Opportunity(
          Name = 'Test Opportunity ' + code,
          StageName = 'Quoting'
        ),
        TestFactoryDefaults.OpportunityWithAccountDefaults.class.getName(),
        true
      );
      return new Map<Schema.SObjectField, Object>{
        OpportunityLineItem.OpportunityId => opportunity.Id,
        OpportunityLineItem.PricebookEntryId => pbeId,
        OpportunityLineItem.Quantity => 1,
        OpportunityLineItem.UnitPrice => 10000
      };
    }
  }

  /**
   * @description Full QuoteLineItem test suite: Opportunity + Used-Machine Product2 + PricebookEntry + Quote.
   */
  public class QuoteLineItemTestSuiteUsedMachineDefaults implements TestFactory.FieldDefaults {
    public Map<Schema.SObjectField, Object> getFieldDefaults() {
      Quote quote = (Quote) TestFactory.createSObject(new Quote(), true);
      Product2 product = (Product2) TestFactory.createSObject(
        new Product2(),
        TestFactoryDefaults.Product2UsedMachineDefaults.class.getName(),
        true
      );
      Id pricebookEntryId = TestFactory.getPricebookEntryId(
        getPricebookId(),
        product.Id
      );
      return new Map<Schema.SObjectField, Object>{
        QuoteLineItem.QuoteId => quote.Id,
        QuoteLineItem.Product2Id => product.Id,
        QuoteLineItem.PricebookEntryId => pricebookEntryId,
        QuoteLineItem.Quantity => 1,
        QuoteLineItem.UnitPrice => 6000,
        QuoteLineItem.Cost__c => 5500
      };
    }
  }

  /**
   * @description Quote defaults: creates an Opportunity with Account, sets pricebook and record type.
   */
  public class QuoteDefaults implements TestFactory.FieldDefaults {
    public Map<Schema.SObjectField, Object> getFieldDefaults() {
      Opportunity opportunity = (Opportunity) TestFactory.createSObject(
        new Opportunity(),
        TestFactoryDefaults.OpportunityWithAccountDefaults.class.getName(),
        true
      );
      return new Map<Schema.SObjectField, Object>{
        Quote.Name => 'Test Quote',
        Quote.Pricebook2Id => getPricebookId(),
        Quote.OpportunityId => opportunity.Id,
        Quote.RecordTypeId => Schema.Quote.getSObjectType()
          .getDescribe()
          .getRecordTypeInfosByName()
          .get('New Machine Quote')
          .getRecordTypeId()
      };
    }
  }

  // ── Private helpers ──────────────────────────────────────────────────────

  private static String generateDBSCustomerNo() {
    return String.valueOf(Utilities.generateUUID()).substring(0, 8);
  }

  private static Id getPricebookId() {
    if (priceBookId == null) {
      priceBookId = Utilities.standardPricebookId;
    }
    return priceBookId;
  }
}
