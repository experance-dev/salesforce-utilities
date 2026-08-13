/**
 * @description Test class for UtilPickLists. Ensures that picklist utility functions work as expected,
 * covering both positive scenarios and edge cases. Portable by design: expected values are derived
 * from the running org's Account.Type describe at runtime instead of assuming any specific entry.
 * @group Picklists
 * @see UtilPickLists
 * @author David Wood
 * @since 2024
 * @last May 2026 — conformance refactor
 * @last August 2026 — portable describe-derived expectations; null-guard coverage for unknown sObject names
 */
@isTest
public without sharing class UtilPickListsTest {
  @TestSetup
  static void makeData() {
    TestFactory.createMinAccessUser(true); // Create a user with minimal permissions.
  }

  /**
   * @description Picks an active Account.Type value from the running org's describe.
   *              Prefers a value with an uppercase letter and length >= 4 so the
   *              case-insensitive and prefix round-trips are meaningful.
   * @return An active picklist value, or null when the org has none.
   */
  private static String deriveActiveTypeValue() {
    String fallback = null;
    for (
      Schema.PicklistEntry entry : Account.Type.getDescribe()
        .getPicklistValues()
    ) {
      if (!entry.isActive()) {
        continue;
      }
      String value = entry.getValue();
      if (fallback == null) {
        fallback = value;
      }
      // equals(), not ==, because Apex String == compares case-insensitively.
      if (value.length() >= 4 && !value.equals(value.toLowerCase())) {
        return value;
      }
    }
    return fallback;
  }

  @isTest
  static void testGetPicklistValues() {
    Test.startTest();
    System.runAs(TestFactory.getMinAccessUser()) {
      String knownValue = deriveActiveTypeValue();
      List<String> lstPicklistValues = UtilPickLists.getPicklistValues(
        'Account',
        'Type'
      );

      if (knownValue == null) {
        // Org ships no active Account.Type values; the raw list may still hold inactive ones.
        Assert.isNotNull(
          lstPicklistValues,
          'Picklist values for Account.Type should never be null.'
        );
      } else {
        Assert.isFalse(
          lstPicklistValues.isEmpty(),
          'Picklist values for Account.Type should not be empty.'
        );
        Assert.isTrue(
          lstPicklistValues.contains(knownValue),
          'The list should contain the describe-derived value "' +
            knownValue +
            '".'
        );
      }

      // Negative path: an unknown sObject name returns empty per the documented contract.
      Assert.isTrue(
        UtilPickLists.getPicklistValues('No_Such_Object__x', 'Type').isEmpty(),
        'An unknown sObject name should return an empty list, not throw.'
      );
    }
    Test.stopTest();
  }

  @isTest
  static void testGetActivePickListValuesMapWithLabelsFromSObjectField() {
    Test.startTest();
    System.runAs(TestFactory.getMinAccessUser()) {
      String knownValue = deriveActiveTypeValue();
      Map<String, String> pickListValueMap = UtilPickLists.getActivePickListValuesMapWithLabels(
        Account.Type
      );

      if (knownValue == null) {
        Assert.isTrue(
          pickListValueMap.isEmpty(),
          'With no active Account.Type values the map should be empty.'
        );
        return;
      }

      Assert.isFalse(
        pickListValueMap.isEmpty(),
        'The active-values map for Account.Type should not be empty.'
      );
      Assert.isTrue(
        pickListValueMap.containsKey(knownValue),
        'The map should key the describe-derived value "' + knownValue + '".'
      );
      Assert.isTrue(
        String.isNotBlank(pickListValueMap.get(knownValue)),
        'The describe-derived value should map to a non-blank label.'
      );
    }
    Test.stopTest();
  }

  @isTest
  static void testGetPickListMatchExact() {
    Test.startTest();
    System.runAs(TestFactory.getMinAccessUser()) {
      String knownValue = deriveActiveTypeValue();
      if (knownValue == null) {
        return; // No active values to round-trip in this org.
      }

      String value = UtilPickLists.getPickListMatch(
        Account.Type,
        knownValue,
        true
      );
      Assert.areEqual(
        knownValue,
        value,
        'An exact search for an existing value should round-trip it.'
      );
    }
    Test.stopTest();
  }

  @isTest
  static void testGetPickListMatchCaseInsensitive() {
    Test.startTest();
    System.runAs(TestFactory.getMinAccessUser()) {
      String knownValue = deriveActiveTypeValue();
      if (knownValue == null) {
        return; // No active values to round-trip in this org.
      }

      String value = UtilPickLists.getPickListMatch(
        Account.Type,
        knownValue.toLowerCase(),
        false
      );
      Assert.areEqual(
        knownValue,
        value,
        'A lowercased search should resolve to the real value via closest match.'
      );
    }
    Test.stopTest();
  }

  @isTest
  static void testGetPickListMatchClosestPrefix() {
    Test.startTest();
    System.runAs(TestFactory.getMinAccessUser()) {
      String knownValue = deriveActiveTypeValue();
      if (knownValue == null || knownValue.length() < 3) {
        return; // Too short to build a meaningful prefix in this org.
      }

      // Drop the tail of the real value; the closest match should recover it.
      String prefix = knownValue.substring(0, knownValue.length() - 2);
      String value = UtilPickLists.getPickListMatch(
        Account.Type,
        prefix,
        false
      );
      Assert.areEqual(
        knownValue,
        value,
        'A prefix of the real value should resolve to it via closest match.'
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

      // Exact search for a value no org would carry finds nothing.
      value = UtilPickLists.getPickListMatch(
        field,
        'zz-no-such-picklist-value-zz',
        true
      );
      Assert.areEqual(
        '',
        value,
        'Should return an empty string when no value or label matches exactly.'
      );
    }
    Test.stopTest();
  }
}
