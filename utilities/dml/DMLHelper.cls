/**
 * @description Helper class for DMLManager — handles FLS inspection, field caching, and record
 *              pre-fetch logic, keeping DMLManager's own methods within complexity budget.
 *              Uses `inherited sharing` so record queries respect the caller's sharing context.
 * @group DML
 * @author David Wood
 * @since May 2024
 * @last May 2026 — Wave 2 USER_MODE migration; conformance refactor
 * @see DMLManager
 */
@SuppressWarnings('PMD.ExcessivePublicCount')
public inherited sharing class DMLHelper {
  /**
   * @param obj The SObject to inspect.
   * @return A map of field names to their populated values (implicit nulls excluded).
   */
  public static Map<String, Object> getFieldMapFromExistingSObject(SObject obj) {
    return obj.getPopulatedFieldsAsMap();
  }

  /**
   * @description Checks FLS for insert — throws FLSException if any restricted field is populated.
   * @param objList The list of SObjects to check.
   */
  public static void checkCreateAction(List<SObject> objList) {
    for (SObject obj : objList) {
      List<String> restrictedFields = DMLManager.cachedRestrictedFields.get(
          DMLManager.Operation.OP_INSERT
        )
        .get(obj.getSObjectType());
      if (restrictedFields == null || restrictedFields.isEmpty()) {
        continue;
      }
      Map<String, Object> fieldsMap = getFieldMapFromExistingSObject(obj);
      for (String fieldName : restrictedFields) {
        if (fieldsMap.get(fieldName) != null) {
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
   * @description Checks FLS for update or upsert — delegates to checkUpdateAction for records
   *              with an Id, and to checkCreateAction for new records in an upsert batch.
   * @param objList The list of SObjects to check.
   * @param existingRecords Pre-fetched existing records keyed by Id.
   * @param dmlOperation The operation being performed.
   */
  public static void checkUpdateOrCreateAction(
    List<SObject> objList,
    Map<Id, SObject> existingRecords,
    DMLManager.Operation dmlOperation
  ) {
    for (SObject obj : objList) {
      if (obj.Id != null) {
        checkUpdateAction(obj, existingRecords.get(obj.Id));
      } else {
        checkCreateAction(new List<SObject>{ obj });
      }
    }
  }

  /**
   * @description Checks FLS for a single record update — throws FLSException if a restricted
   *              field value differs from the stored value.
   * @param obj The SObject being updated.
   * @param existingRecord The current database state of the record.
   */
  public static void checkUpdateAction(SObject obj, SObject existingRecord) {
    List<String> restrictedFields = DMLManager.cachedRestrictedFields.get(
        DMLManager.Operation.OP_UPDATE
      )
      .get(obj.getSObjectType());
    if (restrictedFields == null || restrictedFields.isEmpty()) {
      return;
    }

    if (existingRecord == null) {
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
        throw new DMLManager.FLSException(
          obj.getSObjectType(),
          obj.getSObjectType().getDescribe().fields.getMap().get(fieldName),
          DMLManager.Operation.OP_UPDATE
        );
      }
    }
  }

  /**
   * @description Queries existing records so their field values can be compared during update FLS checks.
   * @param objTypeMap Map of SObject types to lists of record Ids being updated.
   * @return A map of record Ids to their current database state.
   */
  @SuppressWarnings('PMD.OperationWithLimitsInLoop')
  public static Map<Id, SObject> getExistingRecords(
    Map<SObjectType, List<Id>> objTypeMap
  ) {
    Map<Id, SObject> result = new Map<Id, SObject>();
    Map<SObjectType, List<String>> operationRestrictedFields = DMLManager.cachedRestrictedFields.get(
      DMLManager.Operation.OP_UPDATE
    );

    for (SObjectType objType : objTypeMap.keySet()) {
      List<String> restrictedFields = operationRestrictedFields.get(objType);
      if (restrictedFields == null || restrictedFields.isEmpty()) {
        continue;
      }
      List<Id> seenIds = objTypeMap.get(objType);
      if (seenIds.isEmpty()) {
        continue;
      }
      String fieldList = String.join(restrictedFields, ',');
      String query =
        'SELECT ' +
        fieldList +
        ' FROM ' +
        objType.getDescribe().getName() +
        ' WHERE Id IN :seenIds';
      result.putAll(Database.query(String.escapeSingleQuotes(query)));
    }
    return result;
  }

  /**
   * @description Builds (or retrieves from cache) the map of SObject types to Ids and ensures
   *              the restricted-fields cache is populated for the operation.
   * @param objList The list of SObjects about to receive DML.
   * @param dmlOperation The operation being performed.
   * @return A map of SObject types to the list of record Ids present in objList.
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
   * @description Ensures the restricted-fields cache contains entries for both INSERT and UPDATE
   *              when the operation is UPSERT, otherwise ensures it for the single operation.
   * @param obj The SObject whose type needs a cache entry.
   * @param dmlOperation The operation being performed.
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
   * @description Populates the restricted-fields cache for a given SObject type and operation
   *              by inspecting field-level describe metadata.
   * @param obj The SObject whose type is being inspected.
   * @param dmlOperation The operation whose FLS rules are being cached.
   */
  @SuppressWarnings('PMD.CognitiveComplexity, PMD.AvoidDeeplyNestedIfStmts')
  public static void ensureRestrictedFields(
    SObject obj,
    DMLManager.Operation dmlOperation
  ) {
    Map<SObjectType, List<String>> operationRestrictedFields = DMLManager.cachedRestrictedFields.get(
      dmlOperation
    );
    if (operationRestrictedFields == null) {
      operationRestrictedFields = new Map<SObjectType, List<String>>();
      DMLManager.cachedRestrictedFields.put(dmlOperation, operationRestrictedFields);
    }

    if (operationRestrictedFields.containsKey(obj.getSObjectType())) {
      return;
    }

    DescribeSObjectResult describeObject = obj.getSObjectType().getDescribe();
    Map<String, Schema.SObjectField> objectFields = describeObject.fields.getMap();
    List<String> restrictedFields = new List<String>();

    for (String nm : objectFields.keySet()) {
      if (!DMLManager.exceptionValues.contains(nm.toLowerCase())) {
        DescribeFieldResult fr = objectFields.get(nm).getDescribe();
        if (isRestrictedField(fr, dmlOperation)) {
          restrictedFields.add(fr.getName());
        }
      }
    }
    operationRestrictedFields.put(obj.getSObjectType(), restrictedFields);
  }

  /**
   * @description Checks CRUD permission for both the master and merge-target objects before a merge.
   * @param masterObj The record that will survive the merge.
   * @param mergeList The records that will be consumed.
   */
  public static void checkCRUDForMerge(SObject masterObj, List<SObject> mergeList) {
    DMLManager.checkCRUDPermission(
      new Set<SObjectType>{ masterObj.getSObjectType() },
      DMLManager.Operation.OP_UPDATE
    );
    DMLManager.checkCRUDPermission(
      new Set<SObjectType>{ mergeList[0].getSObjectType() },
      DMLManager.Operation.OP_DELETE
    );
  }

  // ─── Private helpers ──────────────────────────────────────────────────────

  private static Boolean isRestrictedField(
    DescribeFieldResult fr,
    DMLManager.Operation dmlOperation
  ) {
    if (fr.isCalculated()) {
      return false;
    }
    if (dmlOperation == DMLManager.Operation.OP_INSERT) {
      return !fr.isCreateable();
    }
    if (dmlOperation == DMLManager.Operation.OP_UPDATE) {
      return !fr.isUpdateable();
    }
    return false;
  }
}
