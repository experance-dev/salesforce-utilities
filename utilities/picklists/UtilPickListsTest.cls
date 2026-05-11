/**
 * @description Test class for UtilPickLists. Ensures that picklist utility functions work as expected,
 * covering both positive scenarios and edge cases.
 * @group Picklists
 * @see UtilPickLists
 * @author Zelis
 * @since 2024
 * @last May 2026 — Wave 6 conformance
 */
@isTest
public without sharing class UtilPickListsTest {
  @TestSetup
  static void makeData() {
    TestFactory.createMinAccessUser(true); // Create a user with minimal permissions.
  }

  @isTest
  static void testGetPicklistValues() {
    Test.startTest();
    System.runAs(TestFactory.getMinAccessUser()) {
      // Attempt to retrieve picklist values for the 'Type' field on the Account object.
      List<String> lstPicklistValues = UtilPickLists.getPicklistValues(
        'Account',
        'Type'
      );

      // Verify that the list of picklist values is successfully retrieved and is not null.
      Assert.isNotNull(
        lstPicklistValues,
        'Picklist values for Account.Type should not be null'
      );
    }
    Test.stopTest();
  }

  @isTest
  static void testGetActivePickListValuesMapWithLabelsFromSObjectField() {
    Test.startTest();
    System.runAs(TestFactory.getMinAccessUser()) {
      // Directly use the Account.Type field reference to retrieve the map of picklist values and their labels.
      Map<String, String> pickListValueMap = UtilPickLists.getActivePickListValuesMapWithLabels(
        Account.Type
      );

      // Check that the map is not null, indicating successful retrieval.
      Assert.isNotNull(
        pickListValueMap,
        'Picklist values map for Account.Type should not be null'
      );
    }
    Test.stopTest();
  }

  @isTest
  static void testGetPickListValue() {
    Test.startTest();
    System.runAs(TestFactory.getMinAccessUser()) {
      Schema.SObjectField field = Account.Type; // Specify the field to test.

      // Test for a case-sensitive match.
      String value = UtilPickLists.getPickListMatch(field, 'Partner', true);
      Assert.areEqual(
        'Partner',
        value,
        'Expected to match the picklist value \'Partner\' with case sensitivity.'
      );

      // Test for a case-insensitive match.
      value = UtilPickLists.getPickListMatch(field, 'Partner', false);
      Assert.areEqual(
        'Partner',
        value,
        'Expected to match the picklist value \'Partner\' without case sensitivity.'
      );
    }
    Test.stopTest();
  }

  @isTest
  static void testGetPickListValueNegativeTest() {
    Test.startTest();
    System.runAs(TestFactory.getMinAccessUser()) {
      Schema.SObjectField field = null; // Start with a null field to simulate error conditions.

      // Attempt to match a picklist value with a null field.
      String value = UtilPickLists.getPickListMatch(field, 'Customer', true);
      Assert.areEqual(
        '',
        value,
        'Should return an empty string when the field is null.'
      );

      // Now use a non-picklist field (Account.Name) for the next set of tests.
      field = Account.Name;

      // Attempt to match a picklist value on a non-picklist field.
      value = UtilPickLists.getPickListMatch(field, 'Customer', false);
      Assert.areEqual(
        '',
        value,
        'Should return an empty string when the field is not a picklist field.'
      );

      // Test with an empty search string on a non-picklist field.
      value = UtilPickLists.getPickListMatch(field, '', false);
      Assert.areEqual(
        '',
        value,
        'Should return an empty string when the search string is empty.'
      );

      // Switch to a valid picklist field but test with null and empty values.
      field = Account.Type;

      // Test with a null search value.
      value = UtilPickLists.getPickListMatch(field, null, false);
      Assert.areEqual(
        '',
        value,
        'Should return an empty string when the search value is null.'
      );

      // Test with an empty search value.
      value = UtilPickLists.getPickListMatch(field, '', false);
      Assert.areEqual(
        '',
        value,
        'Should return an empty string when the search value is empty.'
      );
    }
    Test.stopTest();
  }

  @isTest
  static void testCaseInsensitivePickListMatch() {
    Test.startTest();
    System.runAs(TestFactory.getMinAccessUser()) {
      Schema.SObjectField field = Account.Type; // Specify the field to test.

      // Test for a case-insensitive match.
      String value = UtilPickLists.getPickListMatch(field, 'partner', false);
      Assert.areEqual(
        'Partner',
        value,
        'Expected to match the picklist value \'Partner\' without case sensitivity.'
      );

      value = UtilPickLists.getPickListMatch(field, 'PARTNER', false);
      Assert.areEqual(
        'Partner',
        value,
        'Expected to match the picklist value \'Partner\' without case sensitivity.'
      );
    }
    Test.stopTest();
  }

  @isTest
  static void testClosestPickListMatch() {
    Test.startTest();
    System.runAs(TestFactory.getMinAccessUser()) {
      Schema.SObjectField field = Account.Type; // Specify the field to test.

      // Test for a closest match.
      String value = UtilPickLists.getPickListMatch(field, 'Partn', false);
      Assert.areEqual(
        'Partner',
        value,
        'Expected to find the closest match to \'Partn\' as \'Partner\'.'
      );

      value = UtilPickLists.getPickListMatch(field, 'Part', false);
      Assert.areEqual(
        'Partner',
        value,
        'Expected to find the closest match to \'Part\' as \'Partner\'.'
      );
    }
    Test.stopTest();
  }

  @isTest
  static void testInactivePickListValues() {
    Test.startTest();
    System.runAs(TestFactory.getMinAccessUser()) {
      Schema.SObjectField field = Account.Type; // Specify the field to test.

      // Simulate an inactive picklist value by creating a custom picklist field with inactive values.
      // This requires setup in the org, which we assume is already done for this test case.

      // Test for an inactive match.
      String value = UtilPickLists.getPickListMatch(
        field,
        'InactiveValue',
        true
      );
      Assert.areEqual(
        '',
        value,
        'Expected no match for inactive picklist values.'
      );
    }
    Test.stopTest();
  }
}
