/**
 * @description Test class for StringBuilder and its inner builder classes.
 * @group Strings
 * @see StringBuilder
 * @author Zelis
 * @since 2024
 * @last May 2026 — Wave 6 conformance
 */
@isTest
public without sharing class StringBuilderTest {
  @isTest
  static void testStringBuilderAddSingleValue() {
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

  @isTest
  static void testStringBuilderAddMultipleValues() {
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

  @isTest
  static void testCSVBuilder() {
    // Test CSVBuilder functionality
    List<String> values = new List<String>{ 'Apple', 'Banana', 'Cherry' };
    StringBuilder.CSVBuilder csvBuilder = new StringBuilder.CSVBuilder(values);
    String result = csvBuilder.getStringValue();

    // Assert that the CSV string is as expected
    Assert.areEqual(
      'Apple,Banana,Cherry',
      result,
      'The CSV string should be "Apple,Banana,Cherry".'
    );
  }

  @isTest
  static void testFieldListBuilder() {
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

  @isTest
  static void testMultiCurrencyFieldListBuilder() {
    // Test MultiCurrencyFieldListBuilder functionality in a multi-currency org
    // Assume this test runs in a multi-currency organization

    List<Schema.SObjectField> fields = new List<Schema.SObjectField>{
      Account.Name,
      Account.Industry
    };
    StringBuilder.MultiCurrencyFieldListBuilder fieldListBuilder = new StringBuilder.MultiCurrencyFieldListBuilder(
      fields
    );
    String result = fieldListBuilder.getStringValue();

    // Assert that the field list includes the CurrencyIsoCode field
    Assert.areEqual(
      'Name,Industry,CurrencyIsoCode',
      result,
      'The field list should be "Name,Industry,CurrencyIsoCode".'
    );
  }

  @isTest
  static void testReportBuilder() {
    // Test ReportBuilder functionality
    List<Schema.SObjectField> fields = new List<Schema.SObjectField>{
      Account.Name,
      Account.Industry,
      Account.AnnualRevenue
    };
    StringBuilder.ReportBuilder reportBuilder = new StringBuilder.ReportBuilder(
      fields
    );

    // Create sample Account records
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

    // Expected CSV report
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
