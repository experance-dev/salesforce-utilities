/**
 * @description This class provides a set of utility methods for various common tasks in Apex.
 * @author David Wood
 * @since June 2024
 * @last May 2026 — conformance refactor
 * @last August 2026 — removed duplicate record-type helpers and dead null handling
 * @last 2026-08-13 — RFC 4122 v4 generateUUID; map builders return plain generic maps with validated
 *                    inputs; getFakeId contract documented; stray license tag removed (repo LICENSE governs)
 * @group Utilities
 */
public inherited sharing class Utilities {
  // Transaction-static fake-Id counter: starts at 1, advances once per getFakeId call,
  // shared across every SObjectType so successive fake Ids never collide in a transaction.
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
   * @description Generates a map of Id to SObject from a list based on a specified key field.
   *              The returned map is a plain generic `Map<Id, SObject>` — it cannot be cast to a
   *              concrete map type such as `Map<Id, Account>`; cast individual values instead.
   * @param key The API name of the key field. Must be an Id or lookup/reference field on the list's
   *            SObject type. Records whose key value is null are skipped.
   * @param sObjectList The list of SObjects to transform. Null or empty lists return an empty map.
   * @return A map where the key is the specified field and the value is the SObject.
   * @throws IllegalArgumentException If the key is blank, is not a field on the list's SObject type,
   *         or is not an Id/reference field.
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
   *              The returned map is a plain generic `Map<String, SObject>` — it cannot be cast to a
   *              concrete map type such as `Map<String, Account>`; cast individual values instead.
   * @param key The API name of the key field. The field's value must be castable to String.
   *            Records whose key value is null are skipped.
   * @param sObjectList The list of SObjects to transform. Null or empty lists return an empty map.
   * @return A map where the key is the specified field and the value is the SObject.
   * @throws IllegalArgumentException If the key is blank or is not a field on the list's SObject type.
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
   *              The returned map and its value lists are plain generic collections
   *              (`Map<Id, List<SObject>>`) — cast individual values instead of the map itself.
   * @param key The API name of the key field. Must be an Id or lookup/reference field on the list's
   *            SObject type. Records whose key value is null are skipped.
   * @param sObjectList The list of SObjects to transform. Null or empty lists return an empty map.
   * @return A map where the key is the specified field and the value is a list of SObjects.
   * @throws IllegalArgumentException If the key is blank, is not a field on the list's SObject type,
   *         or is not an Id/reference field.
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
   * @description Generates an RFC 4122 version 4 (random) UUID. The version and variant bits are
   *              set per the RFC, so the value is a genuine v4 UUID — suitable as a correlation
   *              identifier and safe to hand to any consumer that validates UUID structure.
   * @return A 36-character lowercase UUID string in 8-4-4-4-12 hex format.
   */
  public static String generateUUID() {
    return UUID.randomUUID().toString();
  }

  /**
   * @description Generates a short random token — the first four hex characters of a generated UUID.
   *              Random, not sequential: use it to de-collide test data, not to order anything.
   * @return A 4-character lowercase hex string.
   */
  public static String generateRandomCounter() {
    return generateUUID().substring(0, 4);
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
   * @description Returns a fake record Id for the specified SObject type — for in-memory test
   *              fixtures, never for DML. Format contract: exactly 15 characters — the type's
   *              3-character key prefix followed by a 12-digit zero-padded counter. The counter is
   *              transaction-static: it starts at 1, advances by 1 on every call, and is shared
   *              across all SObject types, so every Id generated within a transaction is distinct.
   *              Assigning the value to an `Id` variable normalizes it to the 18-character form.
   * @param sot The Schema.SObjectType for which a fake ID is needed.
   * @return A 15-character fake Id String (key prefix + zero-padded counter), assignable to Id.
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
