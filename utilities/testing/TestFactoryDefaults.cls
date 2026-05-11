/**
 * @format            :
 * @description       : Based upon multiple test factories
 * @author            : Salesforce Apex Receipes et al
 * @group             :
 * @last modified on  : 04-03-2024
 * @last modified by  : David Wood  david@experancepartners.com
 * Modifications Log
 * Ver   Date         Author                        Modification
 * 1.0   12-29-2020   david@experancepartners.com   Initial Version
 * 1.1   02*09*2022   david@experancepartners.com   removed freight line item from OLI default and cleaned up debug calls
 * 2.0   08-04-2022   david@experancepartbers.com   Reverting to base from Hoechst
 **/

@IsTest
public class TestFactoryDefaults {
  public static final String DEFAULT_PRODUCT_FAMILY = 'TestFam';
  public static final String DEFAULT_WARRANTY_PRODUCT = '226';

  public static final String TEST_USER_PERMISSION = 'TestMachineRep';
  private static Id priceBookId;

  // To specify defaults for objects, use the naming convention [ObjectName]Defaults.
  // For custom objects, omit the __c from the Object Name

  /**
   * @description This class implements the TestFactory.FieldDefaults interface and provides default values for Account fields.
   */
  public class AccountDefaults implements TestFactory.FieldDefaults {
    String randomizer = Utilities.generateRandomCounter();

    /**
     * @description Implements required method for custom object creation
     * @return A map of default field values.
     */
    public Map<Schema.SObjectField, Object> getFieldDefaults() {
      Id recordTypeId = Utilities.getRecordTypeMap('Account')
        .get('Customer Account')
        .getRecordTypeId();
      return new Map<Schema.SObjectField, Object>{
        Account.Name => 'Test Account' + randomizer,
        Account.RecordTypeId => recordTypeId,
        Account.DBS_Customer_Number__c => generateDBSCustomerNo(),
        Account.BillingStreet => randomizer + ' Test St',
        Account.BillingCity => 'Test ' +
        randomizer +
        ' City',
        Account.BillingState => 'TN',
        Account.BillingPostalCode => '1' + randomizer,
        Account.ShippingStreet => 2 +
        randomizer +
        ' Shipping St',
        Account.ShippingCity => 'Shipping City ' + randomizer,
        Account.ShippingState => 'TN',
        Account.ShippingPostalCode => '1' + randomizer
      };
    }
  }

  /**
   * @description This class implements the TestFactory.FieldDefaults interface and provides default values for User fields.
   */
  public class UserDefaults implements TestFactory.FieldDefaults {
    /**
     * @description Implements required method for custom object creation
     * @return A map of default field values.
     */
    public Map<Schema.SObjectField, Object> getFieldDefaults() {
      String code = Utilities.generateRandomCounter();
      Profile standardUserProfile = [
        SELECT Id
        FROM Profile
        WHERE Name = 'Standard User'
        LIMIT 1
      ];
      return new Map<Schema.SObjectField, Object>{
        User.Alias => 'st' + code,
        User.Email => 'standarduser' +
        code +
        '@mailinator.com',
        User.EmailEncodingKey => 'UTF-8',
        User.LastName => 'User',
        User.LanguageLocaleKey => 'en_US',
        User.LocaleSidKey => 'en_US',
        User.ProfileId => standardUserProfile.Id,
        User.TimeZoneSidKey => 'America/New_York',
        User.UserName => 'standarduser' +
        code +
        '@mailinator.com'
      };
    }
  }

  /**
   * @description This class provides and expanded Account object used in test classes.
   */
  public class MyAccountDefaults implements TestFactory.FieldDefaults {
    String randomizer = Utilities.generateRandomCounter();

    /**
     * @description Implements required method for custom object creation
     * @return A map of default field values.
     */
    public Map<Schema.SObjectField, Object> getFieldDefaults() {
      return new Map<Schema.SObjectField, Object>{
        Account.Name => 'My Test Account',
        Account.DBS_Customer_Number__c => generateDBSCustomerNo(),
        Account.BillingStreet => randomizer + ' Test St',
        Account.BillingCity => 'Test ' +
        randomizer +
        ' City',
        Account.BillingState => 'TN',
        Account.BillingPostalCode => '1' + randomizer,
        Account.ShippingStreet => 2 +
        randomizer +
        ' Shipping St',
        Account.ShippingCity => 'Shipping City ' + randomizer,
        Account.ShippingState => 'TN',
        Account.ShippingPostalCode => '1' + randomizer
      };
    }
  }

  /**
   * @description This class provides default field values for the Contact object in test classes.
   */
  public class ContactDefaults implements TestFactory.FieldDefaults {
    /**
     * @description Implements required method for custom object creation
     * @return A map of default field values.
     */
    public Map<Schema.SObjectField, Object> getFieldDefaults() {
      return new Map<Schema.SObjectField, Object>{
        Contact.FirstName => 'First',
        Contact.LastName => 'Last',
        Contact.Title => 'Owner'
      };
    }
  }

  /**
   * @description This class provides default field values for the Contact object with an associated Account in test classes.
   */
  public class ContactWithAccountDefaults implements TestFactory.FieldDefaults {
    Account account = (Account) TestFactory.createSObject(new Account(), true);

    /**
     * @description Implements required method for custom object creation
     * @return A map of default field values.
     */
    public Map<Schema.SObjectField, Object> getFieldDefaults() {
      return new Map<Schema.SObjectField, Object>{
        Contact.FirstName => 'First',
        Contact.LastName => 'Last',
        Contact.Title => 'Owner',
        Contact.AccountId => account.Id
      };
    }
  }

  /**
   * @description This class provides default field values for the Opportunity object in test classes.
   */
  public class OpportunityDefaults implements TestFactory.FieldDefaults {
    /**
     * @description Implements required method for custom object creation
     * @return A map of default field values.
     */
    public Map<Schema.SObjectField, Object> getFieldDefaults() {
      String code = Utilities.generateRandomCounter();

      return new Map<Schema.SObjectField, Object>{
        Opportunity.Name => 'Test Opportunity ' + code,
        Opportunity.StageName => 'Quoting',
        Opportunity.CloseDate => Date.today().addDays(10)
      };
    }
  }

  /**
   * @description This class provides default field values for the Opportunity object and creates the associated Account object with default values in test classes.
   */
  public class OpportunityWithAccountDefaults implements TestFactory.FieldDefaults {
    /**
     * @description Implements required method for custom object creation
     * @return A map of default field values.
     */
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

  /**
   * @description This class provides default field values for the OpportunityLineItem object in test classes.
   */
  public class OpportunityLineItemDefaults implements TestFactory.FieldDefaults {
    /**
     * @description Implements required method for custom object creation
     * @return A map of default field values.
     */
    public Map<Schema.SObjectField, Object> getFieldDefaults() {
      return new Map<Schema.SObjectField, Object>{
        OpportunityLineItem.Is_Machine__c => false,
        OpportunityLineItem.Quantity => 1
      };
    }
  }

  /**
   * @description This class provides default field values for the Campaign object in test classes.
   */
  public class CampaignDefaults implements TestFactory.FieldDefaults {
    /**
     * @description Implements required method for custom object creation
     * @return A map of default field values.
     */
    public Map<Schema.SObjectField, Object> getFieldDefaults() {
      return new Map<Schema.SObjectField, Object>{
        Campaign.Campaign_Division__c => UtilPickLists.getPickListValues(
          Campaign.Campaign_Division__c
        )[0]
      };
    }
  }

  /**
   * @description This class provides default field values for the Product2 object in test classes.
   */
  public class Product2Defaults implements TestFactory.FieldDefaults {
    /**
     * @description Implements required method for custom object creation
     * @return A map of default field values.
     */
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

  /**
   * @description This class provides default field values for the Product2 object in test classes.
   */
  public class Product2UsedMachineDefaults implements TestFactory.FieldDefaults {
    /**
     * @description Implements required method for custom object creation
     * @return A map of default field values.
     */

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

  /**
   * @description This class provides default field values for the Product2 object in test classes.
   */
  public class Product2AttachementDefaults implements TestFactory.FieldDefaults {
    /**
     * @description Implements required method for custom object creation
     * @return A map of default field values.
     */
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

  /**
   * @description This class provides default field values for the Product2 Warrany for tests
   */
  public class ProductWarrantiesDefaults implements TestFactory.FieldDefaults {
    /**
     * @description Implements required method for custom object creation
     * @return A map of default field values.
     */
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

  /**
   * @description This class provides default field values for the Case object in test classes.
   */
  public class CaseDefaults implements TestFactory.FieldDefaults {
    /**
     * @description Implements required method for custom object creation
     * @return A map of default field values.
     */
    public Map<Schema.SObjectField, Object> getFieldDefaults() {
      return new Map<Schema.SObjectField, Object>{
        Case.Subject => 'Test Case'
      };
    }
  }

  /**
   * @description This class provides default field values for the Machine object in test classes.
   */
  public class MachineDefaults implements TestFactory.FieldDefaults {
    //get Machine RecordId
    Id machineRecordTypeId = Utilities.getRecordTypeId(
      'Machine__c',
      'Dealer_Inventory'
    );
    Account accountOwner = (Account) TestFactory.createSObject(
      new Account(),
      true
    );
    String serialNo = Utilities.generateUUID();

    /**
     * @description Implements required method for custom object creation
     * @return A map of default field values.
     */
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

  /**
   * @description This class provides default field values for the Machine object in test classes.
   */
  public class MachineWithoutAccountDefaults implements TestFactory.FieldDefaults {
    //get Machine RecordId
    Id machineRecordTypeId = Utilities.getRecordTypeId(
      'Machine__c',
      'Customer_Machine'
    );

    /**
     * @description Implements required method for custom object creation
     * @return A map of default field values.
     */
    public Map<Schema.SObjectField, Object> getFieldDefaults() {
      return new Map<Schema.SObjectField, Object>{
        Machine__c.RecordTypeId => machineRecordTypeId
      };
    }
  }

  /**
   * @description This class provides default field values for the Lead object in test classes.
   */
  public class LeadDefaults implements TestFactory.FieldDefaults {
    /**
     * @description Implements required method for custom object creation
     * @return A map of default field values.
     */
    public Map<Schema.SObjectField, Object> getFieldDefaults() {
      return new Map<Schema.SObjectField, Object>{
        Lead.LastName => 'Test Lead',
        Lead.Company => 'Test Company'
      };
    }
  }

  /**
   * @description This class provides default values for a complete Test Suite for the OpportunityLineItem object.
   * Objects created and linked are Account, Contact, Opportunity, OpportunityLineItem, Product2, and PricebookEntry
   * Sale price is 100K and cost is 50K
   */
  public class OpportunityLineItemTestSuiteUsedMachineDefaults implements TestFactory.FieldDefaults {
    /**
     * @description Implements required method for custom object creation
     * @return A map of default field values.
     */
    public Map<Schema.SObjectField, Object> getFieldDefaults() {
      String code = Utilities.generateRandomCounter();

      //setup the Used Machine
      Product2 product = (Product2) TestFactory.createSObject(
        new Product2(),
        'TestFactoryDefaults.Product2UsedMachineDefaults',
        true
      );
      Id pricebookEntryId = TestFactory.getPricebookEntryId(
        getPricebookId(),
        product.Id
      );

      //set opportunity and opportunitylineitem
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
   * @description This class provides default values for a complete Test Suite for the OpportunityLineItem object.
   * Objects created and linked are Account, Contact, Opportunity, OpportunityLineItem, Product2, and PricebookEntry
   * Sale price is 10K and cost is 50K
   */
  public class OpportunityLineItemTestSuiteAttachementDefaults implements TestFactory.FieldDefaults {
    /**
     * @description Implements required method for custom object creation
     * @return A map of default field values.
     */
    public Map<Schema.SObjectField, Object> getFieldDefaults() {
      String code = Utilities.generateRandomCounter();

      //setup the Used Machine
      Product2 product = (Product2) TestFactory.createSObject(
        new Product2(),
        'TestFactoryDefaults.Product2AttachementDefaults',
        true
      );

      Id pbeId = TestFactory.getPricebookEntryId(getPricebookId(), product.Id);

      //set opportunity and opportunitylineitem
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
   * @description This class provides default values for a QuoteLineItem object.
   * Objects created and linked are Opportunity, Product2, PricebookEntry Quote, and QuoteLineItem
   * Sale price is 6000 and cost is 5000
   */
  public class QuoteLineItemTestSuiteUsedMachineDefaults implements TestFactory.FieldDefaults {
    /**
     * @description Implements required method for custom object creation
     * @return A map of default field values.
     */
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
   * @description This class, QuoteDefaults, implements the TestFactory.FieldDefaults interface.
   * It provides default values for fields used in test data generation.
   */
  public class QuoteDefaults implements TestFactory.FieldDefaults {
    /**
     * @description Implements required method for custom object creation
     * @return A map of default field values.
     */
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
