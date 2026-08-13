/**
 * @description Helper for the Utilities collection-to-map builders. Validates the object type, key
 *              field, and list inputs with descriptive errors, then builds plain generic maps in
 *              memory. Earlier versions constructed runtime-concrete map types via Type.forName;
 *              the returned maps are now generic (`Map<Id, SObject>`, `Map<String, SObject>`) and
 *              cannot be cast to concrete SObject map types — cast individual values instead.
 * @author David Wood
 * @since June 2024
 * @last May 2026 — conformance refactor; changed to inherited sharing to match Utilities caller context
 * @last 2026-08-13 — replaced Type.forName dynamic map construction with plain generic map building;
 *                    descriptive validation of object type, key field, and list inputs
 * @group Utilities
 */
public inherited sharing class UtilitiesHelper {
  /**
   * @description Creates a map of Id to SObject based on the specified key field. The returned map
   *              is a plain generic `Map<Id, SObject>` — not castable to a concrete map type such
   *              as `Map<Id, Account>`. Records whose key value is null are skipped.
   * @param objType The SObject API name (e.g. 'Account'); must match the list's actual member type.
   * @param key The API name of the key field; must be an Id or lookup/reference field.
   * @param sObjectList The list of SObjects to transform. An empty list returns an empty map.
   * @return A map where the key is the specified field and the value is the SObject.
   * @throws IllegalArgumentException If any input is blank or null, the object type does not match
   *         the list, the key field does not exist, or the key field is not an Id/reference field.
   */
  public static Map<Id, SObject> createDynamicIdMap(
    String objType,
    String key,
    List<SObject> sObjectList
  ) {
    Schema.SObjectField keyField = resolveValidatedKeyField(
      objType,
      key,
      sObjectList
    );
    Map<Id, SObject> recordsByKeyId = new Map<Id, SObject>();
    if (keyField == null) {
      return recordsByKeyId;
    }
    validateIdKeyField(keyField, key, objType);
    for (SObject sObj : sObjectList) {
      Id keyValue = (Id) sObj.get(keyField);
      if (keyValue != null) {
        recordsByKeyId.put(keyValue, sObj);
      }
    }
    return recordsByKeyId;
  }

  /**
   * @description Creates a map of String to SObject based on the specified key field. The returned
   *              map is a plain generic `Map<String, SObject>` — not castable to a concrete map
   *              type such as `Map<String, Account>`. Records whose key value is null are skipped.
   * @param objType The SObject API name (e.g. 'Account'); must match the list's actual member type.
   * @param key The API name of the key field; its value must be castable to String.
   * @param sObjectList The list of SObjects to transform. An empty list returns an empty map.
   * @return A map where the key is the specified field and the value is the SObject.
   * @throws IllegalArgumentException If any input is blank or null, the object type does not match
   *         the list, or the key field does not exist on the SObject type.
   */
  public static Map<String, SObject> createDynamicStringMap(
    String objType,
    String key,
    List<SObject> sObjectList
  ) {
    Schema.SObjectField keyField = resolveValidatedKeyField(
      objType,
      key,
      sObjectList
    );
    Map<String, SObject> recordsByKey = new Map<String, SObject>();
    if (keyField == null) {
      return recordsByKey;
    }
    for (SObject sObj : sObjectList) {
      String keyValue = (String) sObj.get(keyField);
      if (keyValue != null) {
        recordsByKey.put(keyValue, sObj);
      }
    }
    return recordsByKey;
  }

  /**
   * @description Creates a map of Id to list of SObjects based on the specified key field. The
   *              returned map and its value lists are plain generic collections
   *              (`Map<Id, List<SObject>>`) — cast individual values, never the map itself.
   *              Records whose key value is null are skipped.
   * @param objType The SObject API name (e.g. 'Contact'); must match the list's actual member type.
   * @param key The API name of the key field; must be an Id or lookup/reference field.
   * @param sObjectList The list of SObjects to transform. An empty list returns an empty map.
   * @return A map where the key is the specified field and the value is a list of SObjects.
   * @throws IllegalArgumentException If any input is blank or null, the object type does not match
   *         the list, the key field does not exist, or the key field is not an Id/reference field.
   */
  public static Map<Id, List<SObject>> createDynamicIdListMap(
    String objType,
    String key,
    List<SObject> sObjectList
  ) {
    Schema.SObjectField keyField = resolveValidatedKeyField(
      objType,
      key,
      sObjectList
    );
    Map<Id, List<SObject>> recordsByKeyId = new Map<Id, List<SObject>>();
    if (keyField == null) {
      return recordsByKeyId;
    }
    validateIdKeyField(keyField, key, objType);
    for (SObject sObj : sObjectList) {
      Id keyValue = (Id) sObj.get(keyField);
      if (keyValue == null) {
        continue;
      }
      List<SObject> groupedRecords = recordsByKeyId.get(keyValue);
      if (groupedRecords == null) {
        groupedRecords = new List<SObject>();
        recordsByKeyId.put(keyValue, groupedRecords);
      }
      groupedRecords.add(sObj);
    }
    return recordsByKeyId;
  }

  /**
   * @description Validates the map-builder inputs and resolves the key field token. Field-level
   *              validation needs at least one record to describe against, so an empty list returns
   *              null and the caller returns its empty map without field validation. Id-keyed
   *              builders additionally call validateIdKeyField on the resolved token.
   * @param objType The expected SObject API name.
   * @param key The API name of the key field.
   * @param sObjectList The records to map.
   * @return The resolved key field token, or null when the list is empty.
   * @throws IllegalArgumentException If any input is invalid; the message names the offending input.
   */
  private static Schema.SObjectField resolveValidatedKeyField(
    String objType,
    String key,
    List<SObject> sObjectList
  ) {
    validateRequiredInputs(objType, key, sObjectList);
    if (sObjectList.isEmpty()) {
      return null;
    }
    Schema.SObjectType actualType = sObjectList[0].getSObjectType();
    if (!objType.equalsIgnoreCase(String.valueOf(actualType))) {
      throw new IllegalArgumentException(
        'objType "' +
          objType +
          '" does not match the list\'s actual SObject type "' +
          String.valueOf(actualType) +
          '".'
      );
    }
    Schema.SObjectField keyField = actualType.getDescribe(
        SObjectDescribeOptions.DEFERRED
      )
      .fields.getMap()
      .get(key);
    if (keyField == null) {
      throw new IllegalArgumentException(
        'Field "' + key + '" does not exist on SObject type "' + objType + '".'
      );
    }
    return keyField;
  }

  /**
   * @description Rejects blank or null map-builder inputs with a message naming the offender.
   * @param objType The SObject API name argument.
   * @param key The key field API name argument.
   * @param sObjectList The record list argument.
   * @throws IllegalArgumentException If any argument is blank or null.
   */
  private static void validateRequiredInputs(
    String objType,
    String key,
    List<SObject> sObjectList
  ) {
    if (String.isBlank(objType)) {
      throw new IllegalArgumentException(
        'objType is required — pass the SObject API name, e.g. "Account".'
      );
    }
    if (String.isBlank(key)) {
      throw new IllegalArgumentException(
        'key is required — pass the API name of the field to key the map by, e.g. "Id".'
      );
    }
    if (sObjectList == null) {
      throw new IllegalArgumentException(
        'sObjectList is required — pass the records to map (an empty list is allowed).'
      );
    }
  }

  /**
   * @description Confirms a key field destined for an Id-keyed map is an Id or reference field.
   * @param keyField The resolved key field token.
   * @param key The key field API name, for the error message.
   * @param objType The SObject API name, for the error message.
   * @throws IllegalArgumentException If the field is not an Id or lookup/reference field.
   */
  private static void validateIdKeyField(
    Schema.SObjectField keyField,
    String key,
    String objType
  ) {
    Schema.DisplayType keyFieldType = keyField.getDescribe().getType();
    if (
      keyFieldType != Schema.DisplayType.ID &&
      keyFieldType != Schema.DisplayType.REFERENCE
    ) {
      throw new IllegalArgumentException(
        'Field "' +
          key +
          '" on "' +
          objType +
          '" is of type ' +
          keyFieldType +
          '; an Id-keyed map requires an Id or lookup/reference field.'
      );
    }
  }
}
