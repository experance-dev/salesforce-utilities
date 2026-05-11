/**
 * @description Helper class for DMLManager to handle complex logic and reduce cognitive complexity.
 *
 * @author David Wood
 * @since May 2024
 *
 * @group   Utilities
 * @group   DMLManager
 * @see     DMLManager
 */
@SuppressWarnings(
  'PMD.CyclomaticComplexity, PMD.ExcessivePublicCount'
) //this class is a utility class
public inherited sharing class DMLHelper {
  /**
   * @description Retrieves a map of populated fields from an existing SObject.
   * @param obj The SObject to retrieve fields from.
   * @return A map of field names to field values.
   */
  public static Map<String, Object> getFieldMapFromExistingSObject(
    SObject obj
  ) {
    // Get actual fields present in the object. The getPopulatedFieldsAsMap method removes implicit nulls.
    return obj.getPopulatedFieldsAsMap();
  }

  /**
   * @description Checks if any restricted fields are present in the list of SObjects for create action.
   * @param objList The list of SObjects to check.
   */
  public static void checkCreateAction(List<SObject> objList) {
    for (SObject obj : objList) {
      List<String> restrictedFields = DMLManager.cachedRestrictedFields.get(
          DMLManager.Operation.OP_INSERT
        )
        .get(obj.getSObjectType());
      if (restrictedFields == null || restrictedFields.isEmpty()) {
        continue; // Skip if there are no restricted fields
      }
      Map<String, Object> fieldsMap = getFieldMapFromExistingSObject(obj);
      for (String fieldName : restrictedFields) {
        if (fieldsMap.get(fieldName) != null) {
          // If any restricted fields are present, throw an exception
          throw new DMLManager.FLSException(
            obj.getSObjectType(),
            obj.getSObjectType().getDescribe().fields.getMap().get(fieldName),
            DMLManager.Operation.OP_INSERT
          );
        }
      }
    }
  }

  /**
   * @description Checks if any restricted fields are present in the list of SObjects for update or upsert action.
   * @param objList The list of SObjects to check.
   * @param existingRecords The map of existing records from the database.
   * @param dmlOperation The DML operation being performed.
   */
  public static void checkUpdateOrCreateAction(
    List<SObject> objList,
    Map<Id, SObject> existingRecords,
    DMLManager.Operation dmlOperation
  ) {
    for (SObject obj : objList) {
      SObject existingRecord = existingRecords.get(obj.Id);
      if (obj.id != null) {
        checkUpdateAction(obj, existingRecord);
      } else {
        checkCreateAction(new List<SObject>{ obj });
      }
    }
  }

  /**
   * @description Checks if any restricted fields are present in the SObject for update action.
   * @param obj The SObject to check.
   * @param existingRecord The existing record from the database.
   */
  public static void checkUpdateAction(SObject obj, SObject existingRecord) {
    List<String> restrictedFields = DMLManager.cachedRestrictedFields.get(
        DMLManager.Operation.OP_UPDATE
      )
      .get(obj.getSObjectType());
    if (restrictedFields == null || restrictedFields.isEmpty()) {
      return; // Skip if there are no restricted fields
    }

    if (existingRecord == null) {
      // Throw an exception if an existing record could not be found
      throw new DMLManager.DMLManagerException(
        'DMLManager ERROR: An existing record could not be found for object with Id = ' +
        obj.Id
      );
    }

    Map<String, Object> fieldsMap = getFieldMapFromExistingSObject(obj);
    for (String fieldName : restrictedFields) {
      if (
        fieldsMap.get(fieldName) != null &&
        fieldsMap.get(fieldName) != existingRecord.get(fieldName)
      ) {
        // If any restricted fields have changed, throw an exception
        throw new DMLManager.FLSException(
          obj.getSObjectType(),
          obj.getSObjectType().getDescribe().fields.getMap().get(fieldName),
          DMLManager.Operation.OP_UPDATE
        );
      }
    }
  }

  /**
   * @description Retrieves a map of existing records from the database for the specified object types and IDs.
   * @param objTypeMap The map of SObject types to lists of IDs.
   * @return A map of IDs to existing SObjects.
   */
  @SuppressWarnings('PMD.OperationWithLimitsInLoop')
  public static Map<Id, SObject> getExistingRecords(
    Map<SObjectType, List<Id>> objTypeMap
  ) {
    Map<ID, SObject> result = new Map<Id, SObject>();
    Map<SObjectType, List<String>> operationRestrictedFields = DMLManager.cachedRestrictedFields.get(
      DMLManager.Operation.OP_UPDATE
    );

    for (SObjectType objType : objTypeMap.keySet()) {
      List<String> restrictedFields = operationRestrictedFields.get(objType);
      if (restrictedFields == null || restrictedFields.isEmpty()) {
        continue; // Skip if there are no restricted fields
      }

      List<Id> seenIds = objTypeMap.get(objType);
      if (seenIds.isEmpty()) {
        continue; // Skip if there are no IDs to query
      }

      String fieldList = String.join(restrictedFields, ',');

      String query =
        'SELECT ' +
        fieldList +
        ' FROM ' +
        objType.getDescribe().getName() +
        ' WHERE Id IN :seenIds';
      String safeQuery = String.escapeSingleQuotes(query);

      result.putAll(Database.query(safeQuery));
    }
    return result;
  }

  /**
   * @description Analyzes the DML collection to create a map of SObject types to lists of IDs.
   * @param objList The list of SObjects to analyze.
   * @param dmlOperation The DML operation being performed.
   * @return A map of SObject types to lists of IDs.
   */
  public static Map<SObjectType, List<Id>> analyzeDMLCollection(
    List<SObject> objList,
    DMLManager.Operation dmlOperation
  ) {
    Map<SObjectType, List<Id>> result = new Map<SObjectType, List<Id>>();
    for (SObject obj : objList) {
      ensureRestrictedFieldsEntry(obj, dmlOperation);
      List<Id> seenIds = result.get(obj.getSObjectType());
      if (seenIds == null) {
        seenIds = new List<Id>();
        result.put(obj.getSObjectType(), seenIds);
      }
      if (obj.Id != null) {
        seenIds.add(obj.Id);
      }
    }
    return result;
  }

  /**
   * @description Ensures that the restricted fields entry exists for the specified SObject and DML operation.
   * @param obj The SObject to check.
   * @param dmlOperation The DML operation being performed.
   */
  public static void ensureRestrictedFieldsEntry(
    SObject obj,
    DMLManager.Operation dmlOperation
  ) {
    if (dmlOperation == DMLManager.Operation.OP_UPSERT) {
      ensureRestrictedFields(obj, DMLManager.Operation.OP_INSERT);
      ensureRestrictedFields(obj, DMLManager.Operation.OP_UPDATE);
    } else {
      ensureRestrictedFields(obj, dmlOperation);
    }
  }

  /**
   * @description Ensures that the restricted fields are cached for the specified SObject and DML operation.
   * @param obj The SObject to check.
   * @param dmlOperation The DML operation being performed.
   */
  @SuppressWarnings(
    'PMD.CognitiveComplexity, PMD.AvoidDeeplyNestedIfStmts'
  ) //this opensourse
  public static void ensureRestrictedFields(
    SObject obj,
    DMLManager.Operation dmlOperation
  ) {
    Map<SObjectType, List<String>> operationRestrictedFields = DMLManager.cachedRestrictedFields.get(
      dmlOperation
    );
    if (operationRestrictedFields == null) {
      operationRestrictedFields = new Map<SObjectType, List<String>>();
      DMLManager.cachedRestrictedFields.put(
        dmlOperation,
        operationRestrictedFields
      );
    }

    if (!operationRestrictedFields.containsKey(obj.getSObjectType())) {
      DescribeSObjectResult describeObject = obj.getSObjectType().getDescribe();
      Map<String, Schema.SObjectField> objectFields = describeObject.fields.getMap();
      List<String> restrictedFields = new List<String>();

      for (String nm : objectFields.keyset()) {
        if (!DMLManager.exceptionValues.contains(nm.toLowerCase())) {
          DescribeFieldResult fr = objectFields.get(nm).getDescribe();
          if (
            (!fr.isCalculated()) &&
            ((dmlOperation == DMLManager.Operation.OP_INSERT &&
            !fr.isCreateable()) ||
            (dmlOperation == DMLManager.Operation.OP_UPDATE &&
            !fr.isUpdateable()))
          ) {
            restrictedFields.add(fr.getName());
          }
        }
      }
      operationRestrictedFields.put(obj.getSObjectType(), restrictedFields);
    }
  }

  /**
   * @description Checks CRUD permissions for the master and merge objects.
   * @param masterObj The master SObject.
   * @param mergeList The list of SObjects to merge.
   */
  public static void checkCRUDForMerge(
    SObject masterObj,
    List<SObject> mergeList
  ) {
    DMLManager.checkCRUDPermission(
      new Set<SObjectType>{ masterObj.getSObjectType() },
      DMLManager.Operation.OP_UPDATE
    );
    DMLManager.checkCRUDPermission(
      new Set<SObjectType>{ mergeList[0].getSObjectType() },
      DMLManager.Operation.OP_DELETE
    );
  }
}
