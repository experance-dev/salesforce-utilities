/**
 * @description Test class for StringBuilder and its inner builder classes.
 * @group Strings
 * @see StringBuilder
 * @author David Wood
 * @since 2024
 * @last May 2026 — conformance refactor
 * @last August 2026 — CSV escaping coverage; portable multi-currency expectation; runAs contexts
 */
@isTest
public without sharing class StringBuilderTest {
  @TestSetup
  static void makeData() {
    TestFactory.createMinAccessUser(true);
  }

  @isTest
  static void testStringBuilderAddSingleValue() {
    System.runAs(TestFactory.getMinAccessUser()) {
      // Test single value addition
      StringBuilder sb = new StringBuilder();
      sb.add('Hello');
      sb.add('World');
      String result = sb.getStringValue();

      // Assert that the concatenated string is as expected
      Assert.areEqual(
        'HelloWorld',
        result,
        'The concatenated string should be "HelloWorld".'
      );
    }
  }

  @isTest
  static void testStringBuilderAddMultipleValues() {
    System.runAs(TestFactory.getMinAccessUser()) {
      // Test multiple value addition
      List<String> values = new List<String>{ 'Hello', ' ', 'World' };
      StringBuilder sb = new StringBuilder(values);
      String result = sb.getStringValue();

      // Assert that the concatenated string is as expected
      Assert.areEqual(
        'Hello World',
        result,
        'The concatenated string should be "Hello World".'
      );
    }
  }

  @isTest
  static void testCSVBuilder() {
    System.runAs(TestFactory.getMinAccessUser()) {
      // Test CSVBuilder functionality
      List<String> values = new List<String>{ 'Apple', 'Banana', 'Cherry' };
      StringBuilder.CSVBuilder csvBuilder = new StringBuilder.CSVBuilder(
        values
      );
      String result = csvBuilder.getStringValue();

      // Assert that the CSV string is as expected
      Assert.areEqual(
        'Apple,Banana,Cherry',
        result,
        'The CSV string should be "Apple,Banana,Cherry".'
      );
    }
  }

  @isTest
  static void testCSVBuilderItemPrefix() {
    System.runAs(TestFactory.getMinAccessUser()) {
      StringBuilder.CSVBuilder csvBuilder = new StringBuilder.CSVBuilder(
        new List<String>{ 'One', 'Two' }
      );

      Assert.areEqual(
        '$One,$Two',
        csvBuilder.getStringValue('$'),
        'The prefix should be concatenated before each item.'
      );
      Assert.isNull(
        new StringBuilder.CSVBuilder().getStringValue('$'),
        'An empty builder should return null even when a prefix is supplied.'
      );
    }
  }

  @isTest
  static void testCSVBuilderPreservesApostrophesAndBraces() {
    System.runAs(TestFactory.getMinAccessUser()) {
      // Apostrophes and braces corrupted the old String.format assembly;
      // plain concatenation must pass them through untouched.
      List<String> values = new List<String>{ 'O\'Brien', '{0}', 'It\'s {ok}' };
      StringBuilder.CSVBuilder csvBuilder = new StringBuilder.CSVBuilder(
        values
      );

      Assert.areEqual(
        'O\'Brien,{0},It\'s {ok}',
        csvBuilder.getStringValue(),
        'Apostrophes and braces must survive CSV assembly unchanged.'
      );
    }
  }

  @isTest
  static void testCSVBuilderEscapesCommaQuoteNewline() {
    System.runAs(TestFactory.getMinAccessUser()) {
      List<String> values = new List<String>{
        'a,b',
        'say "hi"',
        'line1\nline2',
        'plain'
      };
      StringBuilder.CSVBuilder csvBuilder = new StringBuilder.CSVBuilder(
        values
      );

      Assert.areEqual(
        '"a,b","say ""hi""","line1\nline2",plain',
        csvBuilder.getStringValue(),
        'Values containing a comma, quote, or newline must be quoted with inner quotes doubled.'
      );
    }
  }

  @isTest
  static void testFieldListBuilder() {
    System.runAs(TestFactory.getMinAccessUser()) {
      // Test FieldListBuilder functionality
      List<Schema.SObjectField> fields = new List<Schema.SObjectField>{
        Account.Name,
        Account.Industry,
        Account.AnnualRevenue
      };
      StringBuilder.FieldListBuilder fieldListBuilder = new StringBuilder.FieldListBuilder(
        fields
      );
      String result = fieldListBuilder.getStringValue();

      // Assert that the field list is as expected
      Assert.areEqual(
        'Name,Industry,AnnualRevenue',
        result,
        'The field list should be "Name,Industry,AnnualRevenue".'
      );
    }
  }

  @isTest
  static void testMultiCurrencyFieldListBuilder() {
    System.runAs(TestFactory.getMinAccessUser()) {
      List<Schema.SObjectField> fields = new List<Schema.SObjectField>{
        Account.Name,
        Account.Industry
      };
      StringBuilder.MultiCurrencyFieldListBuilder fieldListBuilder = new StringBuilder.MultiCurrencyFieldListBuilder(
        fields
      );
      String result = fieldListBuilder.getStringValue();

      // The CurrencyIsoCode column is only appended in multi-currency orgs.
      String expected = UserInfo.isMultiCurrencyOrganization()
        ? 'Name,Industry,CurrencyIsoCode'
        : 'Name,Industry';
      Assert.areEqual(
        expected,
        result,
        'The field list should append CurrencyIsoCode only when the org is multi-currency.'
      );
    }
  }

  @isTest
  static void testReportBuilder() {
    System.runAs(TestFactory.getMinAccessUser()) {
      // Test ReportBuilder functionality
      List<Schema.SObjectField> fields = new List<Schema.SObjectField>{
        Account.Name,
        Account.Industry,
        Account.AnnualRevenue
      };
      StringBuilder.ReportBuilder reportBuilder = new StringBuilder.ReportBuilder(
        fields
      );

      // Create sample in-memory Account records
      Account acc1 = new Account(
        Name = 'Test Account 1',
        Industry = 'Technology',
        AnnualRevenue = 1000000
      );
      Account acc2 = new Account(
        Name = 'Test Account 2',
        Industry = 'Finance',
        AnnualRevenue = 2000000
      );
      Account acc3 = new Account(
        Name = 'Test Account 3',
        Industry = 'Healthcare',
        AnnualRevenue = 3000000
      );

      // Add records to the report
      reportBuilder.addRecord(acc1);
      reportBuilder.addRecord(acc2);
      reportBuilder.addRecord(acc3);

      // Generate the report
      String report = reportBuilder.generateReport();

      // Expected CSV report: header row plus one newline-separated row per record
      String expectedReport =
        'Name,Industry,AnnualRevenue\n' +
        'Test Account 1,Technology,1000000\n' +
        'Test Account 2,Finance,2000000\n' +
        'Test Account 3,Healthcare,3000000';

      // Assert that the generated report matches the expected result
      Assert.areEqual(
        expectedReport,
        report,
        'The generated report should match the expected CSV format.'
      );
    }
  }

  @isTest
  static void testReportBuilderEscapesCommaAndApostropheValues() {
    System.runAs(TestFactory.getMinAccessUser()) {
      List<Schema.SObjectField> fields = new List<Schema.SObjectField>{
        Account.Name,
        Account.Industry
      };
      StringBuilder.ReportBuilder reportBuilder = new StringBuilder.ReportBuilder(
        fields
      );

      // A comma forces quoting; an apostrophe must pass through untouched.
      reportBuilder.addRecord(
        new Account(Name = 'Acme, Inc.', Industry = 'Technology')
      );
      reportBuilder.addRecord(
        new Account(Name = 'O\'Brien Ltd', Industry = 'Finance')
      );

      String expectedReport =
        'Name,Industry\n' +
        '"Acme, Inc.",Technology\n' +
        'O\'Brien Ltd,Finance';

      Assert.areEqual(
        expectedReport,
        reportBuilder.generateReport(),
        'Comma values must be quoted and apostrophes must survive unchanged.'
      );
    }
  }
}
