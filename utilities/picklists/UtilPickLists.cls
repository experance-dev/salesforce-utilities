/**
 * @description This class provides utility methods for working with picklists.
 */
public with sharing class UtilPickLists {
  /**
   * @description Retrieves all the picklist values for a specified field on an sObject as a list of strings.
   *
   * @param sObjectField The field of the sObject to retrieve picklist values from.
   * @return List<String> A list of picklist value strings; empty if the field is not a picklist or is null.
   */
  public static List<String> getPickListValues(
    Schema.SObjectField sObjectField
  ) {
    // Initialize an empty list to store picklist values
    List<String> picklistValuesString = new List<String>();

    // Validate the field is not null and is a picklist field
    if (
      sObjectField != null &&
      sObjectField.getDescribe().getType() == Schema.DisplayType.Picklist
    ) {
      // Describe the field to access its properties
      Schema.DescribeFieldResult d = sObjectField.getDescribe();
      // Retrieve and loop through all picklist entries
      for (Schema.PicklistEntry picklistValue : d.getPicklistValues()) {
        // Add the value of each picklist entry to the list
        picklistValuesString.add(picklistValue.getValue());
      }
    }

    return picklistValuesString;
  }

  /**
   * @description Overloaded method to retrieve picklist values by sObject name and field name.
   *
   * @param sObjectName The API name of the sObject.
   * @param fieldName   The API name of the field.
   * @return List<String> A list of picklist value strings; empty if the field is not found or not a picklist.
   */
  public static List<String> getPickListValues(
    String sObjectName,
    String fieldName
  ) {
    // Use Schema to find the sObject and field, then pass it to the original getPickListValues method

    Schema.SObjectField sObjectField = Schema.getGlobalDescribe()
      .get(sObjectName)
      .getDescribe()
      .fields.getMap()
      .get(fieldName);
    return getPickListValues(sObjectField);
  }

  /**
   * @description Retrieves all the picklist values and their labels for a specified field on an sObject as a map.
   *
   * @param sObjectField The field of the sObject to retrieve picklist values and labels from.
   * @return Map<String, String> A map where each key is a picklist value and each value is the corresponding label; empty if the field is not a picklist or is null.
   */
  /**
   * @description Retrieves all the active picklist values and their labels for a specified field on an sObject as a map.
   *
   * @param sObjectField The field of the sObject to retrieve active picklist values and labels from.
   * @return Map<String, String> A map where each key is an active picklist value and each value is the corresponding label; empty if the field is not a picklist or is null.
   */
  public static Map<String, String> getActivePickListValuesMapWithLabels(
    Schema.SObjectField sObjectField
  ) {
    // Initialize an empty map to store active picklist values and labels
    Map<String, String> activePicklistValuesMap = new Map<String, String>();

    // Validate the field is not null and is a picklist field
    if (
      sObjectField != null &&
      sObjectField.getDescribe().getType() == Schema.DisplayType.Picklist
    ) {
      // Describe the field to access its properties
      Schema.DescribeFieldResult d = sObjectField.getDescribe();
      // Retrieve and loop through all picklist entries
      for (Schema.PicklistEntry picklistValue : d.getPicklistValues()) {
        // Check if the picklist value is active
        if (picklistValue.isActive()) {
          // Add each active picklist value and its label to the map
          activePicklistValuesMap.put(
            picklistValue.getValue(),
            picklistValue.getLabel()
          );
        }
      }
    }

    return activePicklistValuesMap;
  }

  /**
   * @description Retrieves the best matching picklist value based on a search string.
   * If exactMatch is true, it searches for an exact match. If false, it finds the closest match using a similarity measurement.
   *
   * @param sObjectField The SObject field representing the picklist.
   * @param searchString The string to match against picklist values or labels.
   * @param exactMatch   Determines if the search should be for an exact match (true) or the closest match (false).
   * @return String      The matching picklist value or its label, or an empty string if no match is found.
   */
  public static String getPickListMatch(
    Schema.SObjectField sObjectField,
    String searchString,
    Boolean exactMatch
  ) {
    // Retrieve the picklist values and their labels
    Map<String, String> picklistValues = getActivePickListValuesMapWithLabels(
      sObjectField
    );

    // Basic validation of inputs
    if (
      picklistValues.isEmpty() ||
      String.isBlank(searchString) ||
      exactMatch == null
    ) {
      return '';
    }

    // Handle exact match scenario
    if (exactMatch) {
      return findExactMatch(picklistValues, searchString);
    } else {
      return findClosestMatch(picklistValues, searchString);
    }
  }

  // @description Helper method to find an exact match in the picklist values or labels
  private static String findExactMatch(
    Map<String, String> picklistValues,
    String searchString
  ) {
    for (String key : picklistValues.keySet()) {
      // Check if we find an exact match in either picklist values or labels
      if (
        key.equals(searchString) || picklistValues.get(key).equals(searchString)
      ) {
        // Return the picklist value if a match is found
        return key;
      }
    }
    // If no exact match is found, return an empty string
    return '';
  }

  // @description Helper method to find the closest match in the picklist values or labels
  private static String findClosestMatch(
    Map<String, String> picklistValues,
    String searchString
  ) {
    String closestMatch = '';
    Integer minDistance = null;

    // Iterate through the picklist to find the closest match
    for (String key : picklistValues.keySet()) {
      // Compare both the value and label to the search string
      Integer distanceForValue = searchString.getLevenshteinDistance(key);
      Integer distanceForLabel = searchString.getLevenshteinDistance(
        picklistValues.get(key)
      );

      // Update the closest match if this is the closest we've found
      if (minDistance == null || distanceForValue < minDistance) {
        minDistance = distanceForValue;
        closestMatch = key;
      }
      if (distanceForLabel < minDistance) {
        minDistance = distanceForLabel;
        closestMatch = key; // We store the picklist value as the closest match
      }
    }

    return closestMatch;
  }
}
