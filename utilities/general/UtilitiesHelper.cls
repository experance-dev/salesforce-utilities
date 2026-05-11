/**
 * @description This helper class provides methods to create dynamic maps for SObjects based on specified keys.
 * @license Licensed under Creative Commons Attribution 4.0 International. Use, distribute, and modify this code as you see fit.
 * @author David Wood
 * @since June 2024
 * @last May 2026 — conformance refactor; changed to inherited sharing to match Utilities caller context
 * @group Utilities
 */
public inherited sharing class UtilitiesHelper {
  /**
   * @description Creates a dynamic map of Id to SObject based on the specified key.
   * @param objType The type of the SObject.
   * @param key The field name to use as the key.
   * @param sObjectList The list of SObjects to transform.
   * @return A map where the key is the specified field and the value is the SObject.
   */
  public static Map<Id, SObject> createDynamicIdMap(
    String objType,
    String key,
    List<SObject> sObjectList
  ) {
    Type dynamicMapType = Type.forName('Map<Id,' + objType + '>');
    Map<Id, SObject> resultMap = (Map<Id, SObject>) dynamicMapType.newInstance();
    for (SObject sObj : sObjectList) {
      if (sObj.get(key) != null) {
        resultMap.put((Id) sObj.get(key), sObj);
      }
    }
    return resultMap;
  }

  /**
   * @description Creates a dynamic map of String to SObject based on the specified key.
   * @param objType The type of the SObject.
   * @param key The field name to use as the key.
   * @param sObjectList The list of SObjects to transform.
   * @return A map where the key is the specified field and the value is the SObject.
   */
  public static Map<String, SObject> createDynamicStringMap(
    String objType,
    String key,
    List<SObject> sObjectList
  ) {
    Type dynamicMapType = Type.forName('Map<String,' + objType + '>');
    Map<String, SObject> resultMap = (Map<String, SObject>) dynamicMapType.newInstance();
    for (SObject sObj : sObjectList) {
      if (sObj.get(key) != null) {
        resultMap.put((String) sObj.get(key), sObj);
      }
    }
    return resultMap;
  }

  /**
   * @description Creates a dynamic map of Id to list of SObjects based on the specified key.
   * @param objType The type of the SObject.
   * @param key The field name to use as the key.
   * @param sObjectList The list of SObjects to transform.
   * @return A map where the key is the specified field and the value is a list of SObjects.
   */
  public static Map<Id, List<SObject>> createDynamicIdListMap(
    String objType,
    String key,
    List<SObject> sObjectList
  ) {
    Type listObjType = Type.forName('List<' + objType + '>');
    Type dynamicMapType = Type.forName('Map<Id, List<' + objType + '>>');
    Map<Id, List<SObject>> resultMap = (Map<Id, List<SObject>>) dynamicMapType.newInstance();
    for (SObject sObj : sObjectList) {
      if (sObj.get(key) != null) {
        Id fieldId = (Id) sObj.get(key);
        if (resultMap.containsKey(fieldId)) {
          resultMap.get(fieldId).add(sObj);
        } else {
          List<SObject> newList = (List<SObject>) listObjType.newInstance();
          newList.add(sObj);
          resultMap.put(fieldId, newList);
        }
      }
    }
    return resultMap;
  }
}
