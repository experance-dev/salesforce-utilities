/**
 * @description This class is used for creating a Test Rig for various scenarios.
 * It creates a complete set of SObjects
 *
 * @author      David Wood
 * @since       June 2018
 *
 */
@isTest
public without sharing class TestFactoryRig {
  public static final String FAMILY_HEXMC = 'HEXMC';
  public static final String FAMILY_CTL = TestFactoryDefaults.DEFAULT_PRODUCT_FAMILY;
  public static final String TEST_QUOTE = 'Test quote';
  public static final String TEST_QUOTE_2 = 'Test quote 2';
  public static final String TEST_QUOTE_2017 = 'Test quote 2017';
  public static final String TEST_QUOTE_2018 = 'Test quote 2018';
  // Constants
  public static final String DESCRIPTION_PRODUCT_WITH_MODEL_NUMBER = 'Test - Product with model number';
  public static final String QUOTED_WARRANTY = 'QUOTED MANUAL WARRANTY';
  public static final String REMAINING_WARRANTY = 'REMAINING MANUAL WARRANTY';
  public static final String ADDITIONAL_WARRANTY_MODEL_NUMBER = '2267';
  public static final Integer NUMBER_OF_ATTACHMENTS = 4;
  public static String modelNumber;

  /**
   * @description Creates a test rig for generating multiple opportunities.
   * Uses the default User Permission Set assigned in TestFactoryDefaults
   *
   * @param numberOfOpportunities The number of opportunities to create in the test rig.
   */
  public static void createOpportunityRig(Integer numberOfOpportunities) {
    createOpportunityRig(
      numberOfOpportunities,
      TestFactoryDefaults.TEST_USER_PERMISSION
    );
  }

  /**
   * @description Creates an Opportunity Line Item Rig.
   * Note: Because of Opportunity Sharing Rules, you should always use the same profile in your test if you
   * want them to work in a with sharing basis
   * @param numberOfOpportunities The number of Opportunities to create.
   * @param permissionSetName The name of the permission set to assign to the user.
   */
  public static void createOpportunityRig(
    Integer numberOfOpportunities,
    String permissionSetName
  ) {
    User usr = TestFactory.createMinAccessUser(true);
    TestFactory.assignPermSetToUser(usr, 'BasePermissionsApex');
    TestFactory.assignPermSetToUser(usr, permissionSetName);

    System.runAs(usr) {
      TestFactory.createSObject(
        new OpportunityLineItem(
          Description = DESCRIPTION_PRODUCT_WITH_MODEL_NUMBER
        ),
        TestFactoryDefaults.OpportunityLineItemTestSuiteUsedMachineDefaults.class
          .getName(),
        true
      );

      //TestFactoryRig.debugTestRig();

      Integer additionalOpportunities = numberOfOpportunities - 1;
      for (Integer i = 0; i < additionalOpportunities; i++) {
        TestFactory.createSObject(
          new OpportunityLineItem(),
          TestFactoryDefaults.OpportunityLineItemTestSuiteUsedMachineDefaults.class
            .getName(),
          true
        );
      }

      //TestFactoryRig.debugTestRig();

      List<Product2> products = (List<Product2>) TestFactory.createSObjectList(
        new Product2(
          Warranty_Model__c = TestFactoryDefaults.DEFAULT_WARRANTY_PRODUCT
        ),
        7,
        TestFactoryDefaults.ProductWarrantiesDefaults.class.getName(),
        false
      );

      products[0].Coverage_Type__c = 'POWERTRAIN';
      products[0].Name = 'Powertrain';
      products[1].Coverage_Type__c = 'PREMIER';
      products[1].Name = 'Premier';
      products[1].Warranty_Model__c = ADDITIONAL_WARRANTY_MODEL_NUMBER;
      products[2].Model__c = null;
      products[2].Name = 'Warranty without model number';
      products[2].Warranty_Model__c = ADDITIONAL_WARRANTY_MODEL_NUMBER;
      products[3].Cost__c = 100;
      products[3].IsActive = true;
      products[3].Name = REMAINING_WARRANTY;
      products[3].Type__c = 'Warranty';
      products[3].Warranty_Model__c = '';
      products[4].Cost__c = 100;
      products[4].IsActive = true;
      products[4].Name = QUOTED_WARRANTY;
      products[4].Type__c = 'Warranty';
      products[4].Warranty_Model__c = '';
      products[5].Coverage_Type__c = 'PREMIER';
      products[5].Name = 'Premier';
      products[6].Coverage_Type__c = 'POWERTRAIN';
      products[6].Name = 'Powertrain - 100';
      products[6].Warranty_Hours__c = '100';

      products.addAll(
        (List<Product2>) TestFactory.createSObjectList(
          new Product2(),
          NUMBER_OF_ATTACHMENTS,
          TestFactoryDefaults.Product2AttachementDefaults.class.getName(),
          false
        )
      );

      products.addAll(
        (List<Product2>) TestFactory.createSObjectList(
          new Product2(),
          numberOfOpportunities,
          TestFactoryDefaults.Product2UsedMachineDefaults.class.getName(),
          false
        )
      );

      insert products;
    }
  }

  /**
   * @description Creates a Quote Line Item Rig.
   * Note: Because of Opportunity Sharing Rules, you should always use the same profile in your test if you
   * want them to work in a with sharing basis
   */
  public static void createQuoteLineItemRig() {
    createQuoteLineItemRig(TestFactoryDefaults.TEST_USER_PERMISSION);
  }

  /**
   * @description Creates a Quote Line Item Rig.
   * Note: Because of Opportunity Sharing Rules, you should always use the same profile in your test if you
   * want them to work in a with sharing basis
   * @param permissionSetName The name of the permission set to assign to the user.
   */
  public static void createQuoteLineItemRig(String permissionSetName) {
    User usr = TestFactory.createMinAccessUser(true);
    TestFactory.assignPermSetToUser(usr, 'BasePermissionsApex');
    TestFactory.assignPermSetToUser(usr, permissionSetName);
    System.runAs(usr) {
      TestFactory.createSObject(
        new QuoteLineItem(),
        TestFactoryDefaults.QuoteLineItemTestSuiteUsedMachineDefaults.class
          .getName(),
        true
      );
    }
  }

  /**
   * @description Creates a quote program rig.
   */
  public static void createQuoteProgramRig() {
    User user = TestFactory.createTestUser();

    System.runAs(user) {
      List<QuoteLineItem> quoteLineItems = createQuoteLineItems();
      List<Quote> quotes = assignQuoteNames(quoteLineItems);
      update quotes;

      List<Product2> products = updateProductYear(quoteLineItems);
      update products;

      quoteLineItems[1].PricebookEntryId = quoteLineItems[0].PricebookEntryId;
      // System.debug('Quote Line Items: ' + JSON.serializePretty(quoteLineItems));
      insert quoteLineItems;

      List<Program_Rate__c> programRates = createProgramRates();
      insert programRates;

      List<Quote_Program__c> quotePrograms = createQuotePrograms(
        quoteLineItems,
        programRates
      );
      insert quotePrograms;

      update quoteLineItems;
    }
  }

  /**
   * @description Creates QuoteLineItem records for the quote program rig.
   * @return List of created QuoteLineItem records.
   */
  private static List<QuoteLineItem> createQuoteLineItems() {
    List<QuoteLineItem> quoteLineItems = new List<QuoteLineItem>();
    for (Integer i = 0; i < 4; i++) {
      quoteLineItems.add(
        (QuoteLineItem) TestFactory.createSObject(
          new QuoteLineItem(),
          TestFactoryDefaults.QuoteLineItemTestSuiteUsedMachineDefaults.class
            .getName(),
          false
        )
      );
    }
    return quoteLineItems;
  }

  /**
   * @description Assigns names to the quotes based on predefined constants.
   * @param quoteLineItems List of QuoteLineItem records.
   * @return List of updated Quote records with names assigned.
   */
  private static List<Quote> assignQuoteNames(
    List<QuoteLineItem> quoteLineItems
  ) {
    List<Quote> quotes = new List<Quote>();
    quotes.add(new Quote(Id = quoteLineItems[0].QuoteId, Name = TEST_QUOTE));
    quotes.add(new Quote(Id = quoteLineItems[1].QuoteId, Name = TEST_QUOTE_2));
    quotes.add(
      new Quote(Id = quoteLineItems[2].QuoteId, Name = TEST_QUOTE_2017)
    );
    quotes.add(
      new Quote(Id = quoteLineItems[3].QuoteId, Name = TEST_QUOTE_2018)
    );
    // System.debug('Quotes: ' + JSON.serializePretty(quotes));
    return quotes;
  }

  /**
   * @description Updates the product year for the QuoteLineItem records.
   * @param quoteLineItems List of QuoteLineItem records.
   * @return List of updated Product2 records with new manufacture years.
   */
  private static List<Product2> updateProductYear(
    List<QuoteLineItem> quoteLineItems
  ) {
    List<Product2> products = new List<Product2>();
    products.add(
      new Product2(
        Id = quoteLineItems[0].Product2Id,
        Manufacture_Year__c = '2018'
      )
    );
    products.add(
      new Product2(
        Id = quoteLineItems[1].Product2Id,
        Manufacture_Year__c = '2017'
      )
    );
    products.add(
      new Product2(
        Id = quoteLineItems[2].Product2Id,
        Manufacture_Year__c = '2018'
      )
    );
    // System.debug('Products: ' + JSON.serializePretty(products));
    return products;
  }

  /**
   * @description Creates program rates for the quote program rig.
   * @return List of created Program_Rate__c records.
   */
  private static List<Program_Rate__c> createProgramRates() {
    List<Program_Rate__c> programRates = new List<Program_Rate__c>();

    programRates.add(
      new Program_Rate__c(
        Name = 'Discretionary Support(%)',
        Program_Rate_Type__c = 'Discretionary Support (%)',
        Product_Family__c = FAMILY_CTL,
        Year__c = Date.newInstance(2018, 1, 1),
        Amount__c = 200,
        base_rate__c = 20
      )
    );

    programRates.add(
      new Program_Rate__c(
        Name = 'TAR23NASHGG',
        Program_Rate_Type__c = 'TAR',
        Product_Family__c = FAMILY_CTL,
        Year__c = Date.newInstance(2018, 1, 1),
        Amount__c = 100
      )
    );

    programRates.add(
      new Program_Rate__c(
        Name = 'RSA21GNRL1',
        Program_Rate_Type__c = 'RSA',
        Product_Family__c = FAMILY_CTL,
        Year__c = Date.newInstance(2018, 1, 1),
        base_rate__c = 8
      )
    );

    programRates.add(
      new Program_Rate__c(
        Name = 'STR18DINVAN',
        Program_Rate_Type__c = 'MBD',
        Product_Family__c = FAMILY_CTL,
        Year__c = Date.newInstance(2018, 1, 1),
        base_rate__c = 10
      )
    );

    programRates.add(
      new Program_Rate__c(
        Name = 'STR18DINVAN',
        Program_Rate_Type__c = 'MBD',
        Product_Family__c = FAMILY_CTL,
        Year__c = Date.newInstance(2017, 1, 1),
        base_rate__c = 11
      )
    );

    programRates.add(
      new Program_Rate__c(
        Name = 'RSA21GNRL1',
        Program_Rate_Type__c = 'RSA',
        Product_Family__c = FAMILY_CTL,
        Year__c = Date.newInstance(2016, 1, 1),
        base_rate__c = 8
      )
    );

    programRates.add(
      new Program_Rate__c(
        Name = 'MBD23HYBSE-4',
        Program_Rate_Type__c = 'Hybrid',
        Product_Family__c = FAMILY_CTL,
        Year__c = Date.newInstance(2017, 1, 1),
        base_rate__c = 8.5
      )
    );

    programRates.add(
      new Program_Rate__c(
        Name = 'MBD23HYBSE-4',
        Program_Rate_Type__c = 'Hybrid',
        Product_Family__c = FAMILY_HEXMC,
        Year__c = Date.newInstance(2023, 1, 1),
        base_rate__c = 8.5
      )
    );

    programRates.add(
      new Program_Rate__c(
        Name = 'Discretionary Support(%)',
        Program_Rate_Type__c = 'Discretionary Support (%)',
        Support_type__c = '% of List',
        Product_Family__c = FAMILY_CTL,
        Year__c = Date.newInstance(2018, 1, 1),
        Amount__c = 200,
        base_rate__c = 20
      )
    );

    programRates.add(
      new Program_Rate__c(
        Name = 'Discretionary Support',
        Program_Rate_Type__c = 'Discretionary Support',
        Support_type__c = '$ Amount',
        Product_Family__c = FAMILY_CTL,
        Year__c = Date.newInstance(2018, 1, 1),
        Amount__c = 200,
        base_rate__c = 20
      )
    );

    programRates.add(
      new Program_Rate__c(
        Name = 'TAR23NASHGG',
        Program_Rate_Type__c = 'TAR',
        Product_Family__c = FAMILY_CTL,
        Year__c = Date.newInstance(2016, 1, 1),
        Amount__c = 100
      )
    );

    return programRates;
  }

  /**
   * @description Creates quote programs for the quote program rig.
   * @param quoteLineItems List of QuoteLineItem records.
   * @param programRates List of Program_Rate__c records.
   * @return List of created Quote_Program__c records.
   */
  private static List<Quote_Program__c> createQuotePrograms(
    List<QuoteLineItem> quoteLineItems,
    List<Program_Rate__c> programRates
  ) {
    List<Quote_Program__c> quotePrograms = new List<Quote_Program__c>();

    String tarTar = UtilPickLists.getPickListMatch(
      Quote_Program__c.TAR_Number__c,
      'TAR23NASHGG',
      false
    );
    String tarCorporateNational = UtilPickLists.getPickListMatch(
      Quote_Program__c.TAR_Number__c,
      'STR24PAVCVA',
      false
    );

    quotePrograms.add(
      createQuoteProgram(
        500.00,
        'prodDescription',
        quoteLineItems[0].QuoteId,
        Utilities.getRecordTypeId('QUote_Program__c', 'Corporate_National'),
        programRates[0].Id,
        quoteLineItems[0].Id,
        900,
        tarCorporateNational,
        null
      )
    );

    quotePrograms.add(
      createQuoteProgram(
        100.00,
        programRates[1].Name,
        quoteLineItems[0].QuoteId,
        Utilities.getRecordTypeId('QUote_Program__c', 'TAR'),
        programRates[1].Id,
        quoteLineItems[0].Id,
        900,
        tarTar,
        null
      )
    );

    quotePrograms.add(
      createQuoteProgram(
        100.00,
        programRates[1].Name,
        quoteLineItems[0].QuoteId,
        Utilities.getRecordTypeId('QUote_Program__c', 'Corporate_National'),
        programRates[1].Id,
        quoteLineItems[0].Id,
        900,
        tarCorporateNational,
        null
      )
    );

    quotePrograms.add(
      createQuoteProgram(
        null,
        'prodDescription',
        quoteLineItems[0].QuoteId,
        Utilities.getRecordTypeId('QUote_Program__c', 'TAR'),
        null,
        quoteLineItems[0].Id,
        900,
        tarTar,
        null
      )
    );

    quotePrograms.add(
      createQuoteProgram(
        null,
        programRates[2].Name,
        quoteLineItems[0].QuoteId,
        Utilities.getRecordTypeId('QUote_Program__c', 'RSA'),
        programRates[2].Id,
        quoteLineItems[0].Id,
        900,
        null,
        programRates[2].Base_Rate__c
      )
    );

    quotePrograms.add(
      createQuoteProgram(
        null,
        programRates[3].Name,
        quoteLineItems[0].QuoteId,
        Utilities.getRecordTypeId('QUote_Program__c', 'RSA'),
        programRates[3].Id,
        quoteLineItems[0].Id,
        900,
        null,
        programRates[3].Base_Rate__c
      )
    );

    quotePrograms.add(
      createQuoteProgram(
        null,
        programRates[3].Name,
        quoteLineItems[1].QuoteId,
        Utilities.getRecordTypeId('QUote_Program__c', 'RSA'),
        programRates[3].Id,
        quoteLineItems[1].Id,
        900,
        null,
        programRates[3].Base_Rate__c
      )
    );

    quotePrograms.add(
      createQuoteProgram(
        null,
        programRates[3].Name,
        quoteLineItems[0].QuoteId,
        Utilities.getRecordTypeId('QUote_Program__c', 'MBD'),
        programRates[3].Id,
        quoteLineItems[0].Id,
        900,
        null,
        programRates[4].Base_Rate__c
      )
    );

    return quotePrograms;
  }

  /**
   * @description Helper method to create a Quote_Program__c record.
   * @param amount Amount for the quote program.
   * @param description Program description.
   * @param quoteId Related Quote ID.
   * @param recordTypeId Record Type ID for the quote program.
   * @param programRateId Related Program Rate ID.
   * @param quoteLineItemId Related Quote Line Item ID.
   * @param listPrice List Price for the quote program.
   * @param tarNumber TAR number for the quote program.
   * @param rate Rate for the quote program.
   * @return Created Quote_Program__c record.
   */
  @SuppressWarnings(
    'PMD.ExcessiveParameterList'
  ) //this is a factory method in a test class.
  private static Quote_Program__c createQuoteProgram(
    Decimal amount,
    String description,
    Id quoteId,
    Id recordTypeId,
    Id programRateId,
    Id quoteLineItemId,
    Decimal listPrice,
    String tarNumber,
    Decimal rate
  ) {
    Quote_Program__c quoteProgram = new Quote_Program__c();
    quoteProgram.Amount__c = amount;
    quoteProgram.Program_Description__c = description;
    quoteProgram.Related_Quote__c = quoteId;
    quoteProgram.RecordTypeId = recordTypeId;
    quoteProgram.Related_Program_Rate__c = programRateId;
    quoteProgram.Quote_Line_Item__c = quoteLineItemId;
    quoteProgram.List_Price__c = listPrice;
    quoteProgram.TAR_Number__c = tarNumber;
    quoteProgram.Rate__c = rate;
    return quoteProgram;
  }

  /**
   * @description Gets a Map of the Objects created by the Test Factory Rig.
   * Add fields as you may need
   * @return Map of the Map<String, Map<Id, SObject>>, where String is the SObjectName, Id is the Id of Sobject
   */
  public static Map<String, Map<Id, SObject>> getSObjects() {
    Map<String, Map<Id, SObject>> sObjectMap = new Map<String, Map<Id, SObject>>();
    sObjectMap.put(
      'Account',
      new Map<Id, SObject>(
        [SELECT Id, Name, RecordType.Name, RecordTypeId FROM Account]
      )
    );
    sObjectMap.put(
      'Contact',
      new Map<Id, SObject>(
        [SELECT Id, FirstName, LastName, AccountId FROM Contact]
      )
    );
    sObjectMap.put(
      'Opportunity',
      new Map<Id, SObject>(
        [
          SELECT
            Id,
            AccountId,
            Amount,
            CloseDate,
            Name,
            Opportunity_URL__c,
            RecordType.Name,
            RecordTypeId,
            StageName
          FROM Opportunity
        ]
      )
    );
    sObjectMap.put(
      'Product2',
      new Map<Id, SObject>(
        [
          SELECT
            Id,
            Acquisition_Cost__c,
            Availability__c,
            Cost__c,
            Family,
            IsActive,
            List_Price__c,
            Machine_Status__c,
            Manufacture_Year__c,
            Name,
            Price_List__c,
            Serial_Number__c,
            Type__c,
            Warranty_Hours__c,
            Warranty_Model__c,
            Warranty_Months__c
          FROM Product2
        ]
      )
    );
    sObjectMap.put(
      'OpportunityLineItem',
      new Map<Id, SObject>(
        [
          SELECT
            Id,
            Cost__c,
            Description,
            Is_Machine__c,
            Name,
            OpportunityId,
            PricebookEntryId,
            Product_Family__c,
            Product_Serial_Number__c,
            Product_Type__c,
            Product_Type_Picklist__c,
            Product2Id,
            Quantity,
            UnitPrice
          FROM OpportunityLineItem
        ]
      )
    );
    sObjectMap.put(
      'Quote',
      new Map<Id, SObject>(
        [
          SELECT
            Id,
            Name,
            OpportunityId,
            RecordType.Name,
            RecordTypeId,
            Sync__c,
            Sync_Status__c
          FROM Quote
        ]
      )
    );
    sObjectMap.put(
      'QuoteLineItem',
      new Map<Id, SObject>(
        [
          SELECT
            Id,
            Cost__c,
            OpportunityId__c,
            OpportunityLineItemId,
            PricebookEntryId,
            Product2Id,
            Product2.Family,
            Product2.Manufacture_Year__c,
            Quantity,
            QuoteId,
            UnitPrice
          FROM QuoteLineItem
        ]
      )
    );

    sObjectMap.put(
      'Machine',
      new Map<Id, SObject>(
        [
          SELECT
            Account__c,
            Availability__c,
            DBS_Customer_Number__c,
            Dealer_Net__c,
            Id,
            Model__c,
            Product_Code__c,
            Product_Family__c,
            Product_Type__c,
            RecordType.Name,
            Serial_Number_DBS__c,
            Type__c,
            Year__c
          FROM Machine__c
        ]
      )
    );

    if (!sObjectMap.get('Product2').isEmpty()) {
      Id pricebookId = PricebookUtil.standardPricebookId;
      sObjectMap.put(
        'PriceBook2',
        new Map<Id, SObject>(
          [SELECT Id, Name, isStandard FROM Pricebook2 WHERE Id = :pricebookId]
        )
      );
      sObjectMap.put(
        'PricebookEntry',
        new Map<Id, SObject>(
          [
            SELECT Id, Pricebook2Id, Product2Id, UnitPrice, isActive
            FROM PricebookEntry
            WHERE Pricebook2Id = :pricebookId
          ]
        )
      );
    }
    if (!sObjectMap.get('Quote').isEmpty()) {
      sObjectMap.put(
        'Quote_Program__c',
        new Map<Id, SObject>(
          [
            SELECT
              Id,
              Amount__c,
              Program_Description__c,
              Quote_Line_Item__c,
              RecordTypeId,
              Related_Program_Rate__c,
              Related_Quote__c,
              TAR_Number__c,
              List_Price__c,
              Rate__c,
              Support_Amount__c
            FROM Quote_Program__c
          ]
        )
      );
      sObjectMap.put(
        'Program_Rate__c',
        new Map<Id, SObject>(
          [
            SELECT
              Id,
              Amount__c,
              base_rate__c,
              Name,
              Product_Family__c,
              Program_Rate_Type__c,
              Support_type__c,
              Year__c
            FROM Program_Rate__c
          ]
        )
      );
    }

    return sObjectMap;
  }

  /**
   * @description Gets the Opportunity Cluster related to the first Opportunity in the Test Factory Rig.
   * This is an overloaded method that gets the first Opportunity in the rig.
   * @return Map<String,List<SObject>> A map of Sobjects with a key of their API name
   */
  public static Map<String, List<SObject>> getOpportunityCluster() {
    Map<String, Map<Id, SObject>> currentMap = getSObjects();
    Id oppId = currentMap.get('Opportunity').values()[0].Id;
    return getOpportunityCluster(oppId, currentMap);
  }

  /**
   * @description Gets the Opportunity Cluster related to a specified Opportunity.
   * @param oppId Id of the Opportunity to get the Cluster for.
   * @param currentMap Map<String, Map<Id, SObject>> of the SObjects created by the Test Factory Rig.
   * @return Map<String,List<SObject>> A map of Sobjects with a key of their API name
   */
  public static Map<String, List<SObject>> getOpportunityCluster(
    Id oppId,
    Map<String, Map<Id, SObject>> currentMap
  ) {
    Map<String, List<SObject>> returnSObjectMap = new Map<String, List<SObject>>();

    Opportunity opportunity = (Opportunity) currentMap.get('Opportunity')
      .get(oppId);
    Account account = (Account) currentMap.get('Account')
      .get(opportunity.AccountId);
    List<Contact> contacts = [
      SELECT Id, FirstName, LastName, AccountId
      FROM Contact
      WHERE AccountId = :account.Id
    ];

    returnSObjectMap.put('Opportunity', new List<SObject>{ opportunity });
    returnSObjectMap.put('Account', new List<SObject>{ account });
    returnSObjectMap.put('Contact', contacts);

    returnSObjectMap.put(
      'OpportunityLineItem',
      Utilities.filterSObjectListById(
        'OpportunityId',
        String.valueOf(oppId),
        currentMap.get('OpportunityLineItem').values()
      )
    );
    returnSObjectMap.put(
      'Quote',
      Utilities.filterSObjectListById(
        'OpportunityId',
        String.valueOf(oppId),
        currentMap.get('Quote').values()
      )
    );
    returnSObjectMap.put(
      'QuoteLineItem',
      Utilities.filterSObjectListById(
        'OpportunityId__c',
        String.valueOf(oppId),
        currentMap.get('QuoteLineItem').values()
      )
    );

    Set<Id> productIds = new Set<Id>();
    List<SObject> products = new List<SObject>();
    for (SObject item : returnSObjectMap.get('OpportunityLineItem')) {
      if (productIds.contains(((OpportunityLineItem) item).Product2Id)) {
        continue;
      }
      productIds.add(((OpportunityLineItem) item).Product2Id);
      products.add(
        (SObject) currentMap.get('Product2')
          .get(((OpportunityLineItem) item).Product2Id)
      );
    }
    returnSObjectMap.put('Product2', products);

    return returnSObjectMap;
  }

  /**
   * @description This method is used to debug the test rig.
   */
  public static void debugTestRig() {
    Map<String, Map<Id, SObject>> testRig = getSObjects();

    // Get all keys and sort them for consistent debug output
    List<String> keys = new List<String>(testRig.keySet());
    keys.sort();

    // Initialize the debug string
    String debug = '************************    Test Rig  ************************\n';

    // Iterate over each key and serialize the associated SObjects to a pretty JSON string
    for (String key : keys) {
      debug += 'Key: ' + key + '\n';
      debug += JSON.serializePretty(testRig.get(key)) + '\n';
    }

    // Log the debug string
    System.debug(debug); //NOPMD - Logging the test rig
  }

  // @SuppressWarnings(
  //     'PMD.OperationWithLimitsInLoop, PMD.EmptyCatchBlock'
  // ) //this is designed to run once in a test class. not production
  // private static Quote_Program__c saveQuoteProgramWithAValidTARValue(Quote_Program__c quoteProgram) {
  //     for (String tar : UtilPickLists.getPickListValues(Quote_Program__c.TAR_Number__c)) {
  //         try {
  //             //try to insert with this tar value
  //             quoteProgram.TAR_Number__c = tar;
  //             insert quoteProgram;
  //             return quoteProgram;
  //         } catch (Exception e) {
  //         }
  //     }

  //     //if we get here, we couldn't insert with any tar value
  //     return null;
  // }
}
