/**
 * @description This class provides a set of utility methods for various common tasks in Apex.
 * @license Licensed under Creative Commons Attribution 4.0 International. Use, distribute, and modify this code as you see fit.
 * @author David Wood
 * @since June 2024
 * @last May 2026 — conformance refactor
 * @group Utilities
 */
public inherited sharing class Utilities {
  private static Integer segment = 1;
  /**
   * @description Returns the standard pricebook Id. Included for existing classes; prefer PricebookUtil directly.
   * @return The standard pricebook Id.
   */
  public static Id standardPricebookId {
    get {
      return PricebookUtil.standardPricebookId;
    }
  }

  /**
   * @description Returns a map of all the record types for a given sObject.
   * @param sObjectName The name of the sObject.
   * @return A map of all the record types for the given sObject.
   */
  public static Map<String, Schema.RecordTypeInfo> getRecordTypeMap(
    String sObjectName
  ) {
    Schema.DescribeSObjectResult describeResult = Schema.getGlobalDescribe()
      .get(sObjectName)
      .getDescribe();
    return describeResult.getRecordTypeInfosByName();
  }

  /**
   * @description Retrieves record type information for a given sObject. Delegates to getRecordTypeMap.
   * @param sObjectName The API name of the sObject for which to retrieve record type information.
   * @return A map of record type API names to their corresponding Schema.RecordTypeInfo objects.
   */
  public static Map<String, Schema.RecordTypeInfo> getRecordTypes(
    String sObjectName
  ) {
    return getRecordTypeMap(sObjectName);
  }

  /**
   * @description Generates a map of Id to SObject from a list based on a specified key field.
   * @param key The field name to use as the key. This must be of type Id.
   * @param sObjectList The list of SObjects to transform.
   * @return A map where the key is the specified field and the value is the SObject.
   */
  public static Map<Id, SObject> createIdMapFromCollectionByKey(
    String key,
    List<SObject> sObjectList
  ) {
    if (isNullOrEmpty(sObjectList)) {
      return new Map<Id, SObject>();
    }
    String objType = extractSObjectTypeFromList(sObjectList);
    return UtilitiesHelper.createDynamicIdMap(objType, key, sObjectList);
  }

  /**
   * @description Generates a map of String to SObject from a list based on a specified key field.
   * @param key The field name to use as the key. The field's value must be castable to String.
   * @param sObjectList The list of SObjects to transform.
   * @return A map where the key is the specified field and the value is the SObject.
   */
  public static Map<String, SObject> createStringMapFromCollectionByKey(
    String key,
    List<SObject> sObjectList
  ) {
    if (isNullOrEmpty(sObjectList)) {
      return new Map<String, SObject>();
    }
    String objType = extractSObjectTypeFromList(sObjectList);
    return UtilitiesHelper.createDynamicStringMap(objType, key, sObjectList);
  }

  /**
   * @description Generates a map of Id to list of SObjects from a list based on a specified key field.
   * @param key The field name to use as the key. This must be of type Id.
   * @param sObjectList The list of SObjects to transform.
   * @return A map where the key is the specified field and the value is a list of SObjects.
   */
  public static Map<Id, List<SObject>> createMapFromCollectionWithCollectionValues(
    String key,
    List<SObject> sObjectList
  ) {
    if (isNullOrEmpty(sObjectList)) {
      return new Map<Id, List<SObject>>();
    }
    String objType = extractSObjectTypeFromList(sObjectList);
    return UtilitiesHelper.createDynamicIdListMap(objType, key, sObjectList);
  }

  /**
   * @description Converts null values to zero for Double type.
   * @param input The Double value to convert.
   * @return The input value or zero if the input is null.
   */
  public static Double convertNullToZero(Double input) {
    return (input == null) ? 0 : input;
  }

  /**
   * @description Converts null values to zero for Integer type.
   * @param input The Integer value to convert.
   * @return The input value or zero if the input is null.
   */
  public static Integer convertNullToZero(Integer input) {
    return (input == null) ? 0 : input;
  }

  /**
   * @description Converts null values to zero for Decimal type.
   * @param input The Decimal value to convert.
   * @return The input value or zero if the input is null.
   */
  public static Decimal convertNullToZero(Decimal input) {
    return (input == null) ? 0 : input;
  }

  /**
   * @description Returns the SObject type from a list of SObjects.
   * @param sObjectList The list of SObjects.
   * @return The SObject type as a String.
   */
  public static String extractSObjectTypeFromList(List<SObject> sObjectList) {
    return (!sObjectList.isEmpty())
      ? String.valueOf(sObjectList[0]?.getSObjectType())
      : 'SObject';
  }

  /**
   * @description Generates a UUID.
   * @return A randomly generated UUID as a string.
   */
  public static String generateUUID() {
    Blob aesKey = Crypto.generateAesKey(128);
    String hexKey = EncodingUtil.convertToHex(aesKey);
    return hexKey.substring(0, 8) +
      '-' +
      hexKey.substring(8, 12) +
      '-' +
      hexKey.substring(12, 16) +
      '-' +
      hexKey.substring(16, 20) +
      '-' +
      hexKey.substring(20);
  }

  /**
   * @description Generates a random counter value.
   * @return A randomly generated counter value as a string.
   */
  public static String generateRandomCounter() {
    return String.valueOf(generateUUID().substring(0, 4));
  }

  /**
   * @description Filters a list of SObjects by a related SObject's Id.
   * @param idFieldName The field name that contains the Id of the related SObject.
   * @param keyId The Id of the related SObject.
   * @param sObjectList The list of SObjects to filter.
   * @return A list of SObjects that match the related SObject's Id.
   */
  public static List<SObject> filterSObjectListById(
    String idFieldName,
    Id keyId,
    List<SObject> sObjectList
  ) {
    List<SObject> filteredList = new List<SObject>();
    if (sObjectList != null && !sObjectList.isEmpty()) {
      for (SObject sObj : sObjectList) {
        if (sObj?.get(idFieldName) != null && sObj.get(idFieldName) == keyId) {
          filteredList.add(sObj);
        }
      }
    }
    return filteredList;
  }

  /**
   * @description Returns the RecordTypeId for a given object and DeveloperName.
   * @param objectApiName The API name of the object (e.g., 'Account', 'Contact').
   * @param recordTypeDeveloperName The DeveloperName of the record type.
   * @return The RecordTypeId if found, otherwise null.
   */
  public static Id getRecordTypeId(
    String objectApiName,
    String recordTypeDeveloperName
  ) {
    Schema.DescribeSObjectResult describeResult = Schema.getGlobalDescribe()
      .get(objectApiName)
      .getDescribe();
    Map<String, Schema.RecordTypeInfo> recordTypeInfoMap = describeResult.getRecordTypeInfosByDeveloperName();
    if (recordTypeInfoMap.containsKey(recordTypeDeveloperName)) {
      return recordTypeInfoMap.get(recordTypeDeveloperName).getRecordTypeId();
    }
    return null;
  }

  /**
   * @description Returns a set of Id values from the specified field of a list of SObjects.
   * @param sObjectList The list of SObjects from which to retrieve the Id values.
   * @param field The field from which to retrieve the Id values.
   * @return A set of Id values from the specified field.
   */
  public static Set<Id> extractIdSetFromField(
    List<SObject> sObjectList,
    SObjectField field
  ) {
    Set<Id> idSet = new Set<Id>();
    for (SObject sObj : sObjectList) {
      Id value = (Id) sObj.get(field);
      if (value != null) {
        idSet.add(value);
      }
    }
    idSet.remove(null);
    return idSet;
  }

  /**
   * @description Returns a set of String values from the specified field of a list of SObjects.
   * @param sObjectList The list of SObjects from which to retrieve the String values.
   * @param field The field from which to retrieve the String values.
   * @return A set of String values from the specified field.
   */
  public static Set<String> extractStringSetFromField(
    List<SObject> sObjectList,
    SObjectField field
  ) {
    Set<String> stringSet = new Set<String>();
    for (SObject sObj : sObjectList) {
      String value = (String) sObj.get(field);
      if (String.isNotBlank(value)) {
        stringSet.add(value);
      }
    }
    return stringSet;
  }

  /**
   * @description Checks if a list of SObjects is null or empty.
   * @param sObjectList The list of SObjects to check.
   * @return True if the list is null or empty, false otherwise.
   */
  public static Boolean isNullOrEmpty(List<SObject> sObjectList) {
    return sObjectList == null || sObjectList.isEmpty();
  }

  /**
   * @description Returns a fake ID for the specified SObject type.
   * @param sot The Schema.SObjectType for which a fake ID is needed.
   * @return A fake ID as a String.
   */
  public static String getFakeId(Schema.SObjectType sot) {
    String result = String.valueOf(segment++);
    return sot.getDescribe().getKeyPrefix() +
      '0'.repeat(12 - result.length()) +
      result;
  }

  /**
   * @description Creates fake IDs for a list of SObjects.
   * @param sobjList The list of SObjects for which fake IDs need to be created.
   * @return A list of SObjects with fake IDs.
   */
  public static List<SObject> createFakeIdsForList(List<SObject> sobjList) {
    for (SObject sObj : sobjList) {
      sObj.Id = getFakeId(sObj.getSObjectType());
    }
    return sobjList;
  }
}
