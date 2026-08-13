/**
 * @description Test class for UtilPickLists. Ensures that picklist utility functions work as expected,
 * covering both positive scenarios and edge cases. Portable by design: expected values are derived
 * from the running org's Account.Type describe at runtime instead of assuming any specific entry.
 * @group Picklists
 * @see UtilPickLists
 * @see PicklistMatcher
 * @author David Wood
 * @since 2024
 * @last May 2026 — conformance refactor
 * @last 2026-08-13 — pins for the findClosestMatch result-object engine: exact, near,
 *                    below-threshold, tie determinism, and normalization
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

  /**
   * @description An exact candidate (after normalization) wins with confidence 1 and wasExact
   *              true, whether the search hit the value or the label.
   */
  @isTest
  static void testFindClosestMatchExact() {
    Test.startTest();
    System.runAs(TestFactory.getMinAccessUser()) {
      PicklistMatcher.PicklistMatchResult valueHit = UtilPickLists.findClosestMatch(
        new Map<String, String>{ 'Apple' => 'Apple Fruit', 'Banana' => 'Banana Fruit' },
        'Apple',
        0.5
      );
      Assert.areEqual('Apple', valueHit.matchedValue, 'An exact value match should win.');
      Assert.isTrue(valueHit.confidence == 1, 'An exact match carries confidence 1.');
      Assert.isTrue(valueHit.wasExact, 'An exact match sets wasExact.');

      // Label equality counts as exact and returns the entry's VALUE, not the label.
      PicklistMatcher.PicklistMatchResult labelHit = UtilPickLists.findClosestMatch(
        new Map<String, String>{ 'A1' => 'Apple' },
        'APPLE',
        0.9
      );
      Assert.areEqual('A1', labelHit.matchedValue, 'A label match should return the value key.');
      Assert.isTrue(labelHit.wasExact, 'A normalized label match counts as exact.');
    }
    Test.stopTest();
  }

  /**
   * @description A near miss returns the closest candidate with a proportional confidence and
   *              wasExact false.
   */
  @isTest
  static void testFindClosestMatchNear() {
    Test.startTest();
    System.runAs(TestFactory.getMinAccessUser()) {
      PicklistMatcher.PicklistMatchResult result = UtilPickLists.findClosestMatch(
        new Map<String, String>{ 'Apple' => 'Apple', 'Banana' => 'Banana' },
        'Appl',
        0.5
      );
      Assert.areEqual('Apple', result.matchedValue, 'The nearest candidate should win.');
      // Levenshtein 1 over the longer length 5: confidence = 1 - 1/5.
      Assert.isTrue(result.confidence == 0.8, 'Confidence should be 1 minus distance/length (0.8).');
      Assert.isFalse(result.wasExact, 'A near miss must not claim exactness.');
    }
    Test.stopTest();
  }

  /**
   * @description When nothing clears the caller's minimum confidence, no match is returned —
   *              matchedValue null, confidence 0, wasExact false.
   */
  @isTest
  static void testFindClosestMatchBelowThreshold() {
    Test.startTest();
    System.runAs(TestFactory.getMinAccessUser()) {
      PicklistMatcher.PicklistMatchResult result = UtilPickLists.findClosestMatch(
        new Map<String, String>{ 'Apple' => 'Apple' },
        'zzzz',
        0.9
      );
      Assert.isNull(result.matchedValue, 'Below the minimum confidence there is no match.');
      Assert.isTrue(result.confidence == 0, 'The no-match result carries confidence 0.');
      Assert.isFalse(result.wasExact, 'The no-match result is never exact.');

      // Null minimum is treated as 0 — the nearest candidate always returns.
      PicklistMatcher.PicklistMatchResult unbounded = UtilPickLists.findClosestMatch(
        new Map<String, String>{ 'Apple' => 'Apple' },
        'ap',
        null
      );
      Assert.areEqual('Apple', unbounded.matchedValue, 'A null minimum admits any nearest match.');
    }
    Test.stopTest();
  }

  /**
   * @description Confidence ties break to the candidate whose normalized value sorts first
   *              alphabetically — identical results regardless of map insertion order.
   */
  @isTest
  static void testFindClosestMatchTieDeterminism() {
    Test.startTest();
    System.runAs(TestFactory.getMinAccessUser()) {
      PicklistMatcher.PicklistMatchResult forwardOrder = UtilPickLists.findClosestMatch(
        new Map<String, String>{ 'AB' => 'AB', 'AD' => 'AD' },
        'AC',
        0
      );
      PicklistMatcher.PicklistMatchResult reverseOrder = UtilPickLists.findClosestMatch(
        new Map<String, String>{ 'AD' => 'AD', 'AB' => 'AB' },
        'AC',
        0
      );
      Assert.areEqual('AB', forwardOrder.matchedValue, 'A tie resolves alphabetically to AB.');
      Assert.areEqual(
        forwardOrder.matchedValue,
        reverseOrder.matchedValue,
        'Tie resolution must not depend on map insertion order.'
      );
    }
    Test.stopTest();
  }

  /**
   * @description Case and whitespace are normalized before distance: padded, mixed-case,
   *              multi-space input still lands an exact match.
   */
  @isTest
  static void testFindClosestMatchNormalization() {
    Test.startTest();
    System.runAs(TestFactory.getMinAccessUser()) {
      PicklistMatcher.PicklistMatchResult result = UtilPickLists.findClosestMatch(
        new Map<String, String>{ 'Apple Pie' => 'Apple Pie' },
        '  aPPle   pIe ',
        0.9
      );
      Assert.areEqual('Apple Pie', result.matchedValue, 'Normalization should land the exact value.');
      Assert.isTrue(result.wasExact, 'Equality after normalization counts as exact.');
      Assert.isTrue(result.confidence == 1, 'Equality after normalization carries confidence 1.');
    }
    Test.stopTest();
  }

  /**
   * @description Field-based overload: a null field and a blank search both return the no-match
   *              result; a describe-derived real value round-trips as an exact match.
   */
  @isTest
  static void testFindClosestMatchFieldOverload() {
    Test.startTest();
    System.runAs(TestFactory.getMinAccessUser()) {
      PicklistMatcher.PicklistMatchResult nullField = UtilPickLists.findClosestMatch(
        (Schema.SObjectField) null,
        'Customer',
        0.5
      );
      Assert.isNull(nullField.matchedValue, 'A null field yields the no-match result.');

      PicklistMatcher.PicklistMatchResult blankSearch = UtilPickLists.findClosestMatch(
        Account.Type,
        '   ',
        0.5
      );
      Assert.isNull(blankSearch.matchedValue, 'A blank search yields the no-match result.');

      String knownValue = deriveActiveTypeValue();
      if (knownValue != null) {
        PicklistMatcher.PicklistMatchResult roundTrip = UtilPickLists.findClosestMatch(
          Account.Type,
          knownValue,
          0.5
        );
        Assert.isNotNull(roundTrip.matchedValue, 'A real value should clear the minimum.');
        Assert.isTrue(roundTrip.wasExact, 'A real value round-trips as an exact match.');
        Assert.isTrue(roundTrip.confidence == 1, 'A real value round-trips with confidence 1.');
      }
    }
    Test.stopTest();
  }
}
