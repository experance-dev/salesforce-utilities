/**
 * @description Utility methods for working with picklist metadata via Schema.describe.
 * @group Picklists
 * @author David Wood
 * @since June 2024
 * @last May 2026 — Wave 5 conformance
 */
// without sharing: pure Schema.describe metadata operations; no record data access.
public without sharing class UtilPickLists {
  /**
   * @param sObjectField The picklist field to inspect.
   * @return List of raw picklist values; empty if the field is null or not a picklist.
   */
  public static List<String> getPickListValues(
    Schema.SObjectField sObjectField
  ) {
    List<String> picklistValues = new List<String>();

    if (
      sObjectField != null &&
      sObjectField.getDescribe().getType() == Schema.DisplayType.Picklist
    ) {
      for (
        Schema.PicklistEntry entry : sObjectField.getDescribe()
          .getPicklistValues()
      ) {
        picklistValues.add(entry.getValue());
      }
    }

    return picklistValues;
  }

  /**
   * @param sObjectName API name of the sObject.
   * @param fieldName   API name of the field.
   * @return List of raw picklist values; empty if the field is not found or not a picklist.
   */
  public static List<String> getPickListValues(
    String sObjectName,
    String fieldName
  ) {
    Schema.SObjectField sObjectField = Schema.getGlobalDescribe()
      .get(sObjectName)
      .getDescribe()
      .fields.getMap()
      .get(fieldName);
    return getPickListValues(sObjectField);
  }

  /**
   * @param sObjectField The picklist field to inspect.
   * @return Map of value → label for active entries only; empty if null or not a picklist.
   */
  public static Map<String, String> getActivePickListValuesMapWithLabels(
    Schema.SObjectField sObjectField
  ) {
    Map<String, String> activeValues = new Map<String, String>();

    if (
      sObjectField != null &&
      sObjectField.getDescribe().getType() == Schema.DisplayType.Picklist
    ) {
      for (
        Schema.PicklistEntry entry : sObjectField.getDescribe()
          .getPicklistValues()
      ) {
        if (entry.isActive()) {
          activeValues.put(entry.getValue(), entry.getLabel());
        }
      }
    }

    return activeValues;
  }

  /**
   * @param sObjectField  The picklist field to search.
   * @param searchString  String to match against picklist values or labels.
   * @param exactMatch    true for exact match; false for closest Levenshtein match.
   * @return Matching picklist value, or empty string if none found.
   */
  public static String getPickListMatch(
    Schema.SObjectField sObjectField,
    String searchString,
    Boolean exactMatch
  ) {
    Map<String, String> picklistValues = getActivePickListValuesMapWithLabels(
      sObjectField
    );

    if (
      picklistValues.isEmpty() ||
      String.isBlank(searchString) ||
      exactMatch == null
    ) {
      return '';
    }

    return exactMatch
      ? findExactMatch(picklistValues, searchString)
      : findClosestMatch(picklistValues, searchString);
  }

  private static String findExactMatch(
    Map<String, String> picklistValues,
    String searchString
  ) {
    for (String key : picklistValues.keySet()) {
      if (
        key.equals(searchString) ||
        picklistValues.get(key).equals(searchString)
      ) {
        return key;
      }
    }
    return '';
  }

  private static String findClosestMatch(
    Map<String, String> picklistValues,
    String searchString
  ) {
    String closestMatch = '';
    Integer minDistance = null;

    for (String key : picklistValues.keySet()) {
      Integer distForValue = searchString.getLevenshteinDistance(key);
      Integer distForLabel = searchString.getLevenshteinDistance(
        picklistValues.get(key)
      );

      if (minDistance == null || distForValue < minDistance) {
        minDistance = distForValue;
        closestMatch = key;
      }
      // Label may be a closer match than the raw value
      if (distForLabel < minDistance) {
        minDistance = distForLabel;
        closestMatch = key;
      }
    }

    return closestMatch;
  }
}
