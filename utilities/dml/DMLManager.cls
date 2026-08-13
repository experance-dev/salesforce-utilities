/**
 * Copyright (c), PatronManager LLC
 * All rights reserved.
 *
 * Redistribution and use in source and binary forms, with or without modification,
 *   are permitted provided that the following conditions are met:
 *
 * - Redistributions of source code must retain the above copyright notice,
 *      this list of conditions and the following disclaimer.
 * - Redistributions in binary form must reproduce the above copyright notice,
 *      this list of conditions and the following disclaimer in the documentation
 *      and/or other materials provided with the distribution.
 * - Neither the name of the Patron Holdings nor the names of its contributors
 *      may be used to endorse or promote products derived from this software without specific prior written permission.
 *
 *  THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS "AS IS" AND
 *  ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE IMPLIED WARRANTIES
 *  OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE ARE DISCLAIMED. IN NO EVENT SHALL
 *  THE COPYRIGHT HOLDER OR CONTRIBUTORS BE LIABLE FOR ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL,
 *  EXEMPLARY, OR CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS
 *  OR SERVICES; LOSS OF USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER CAUSED AND ON ANY THEORY
 *  OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE)
 *  ARISING IN ANY WAY OUT OF THE USE OF THIS SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.
 **/
/**
 * @description Manages CRUD and FLS-safe DML operations, routing all DML through USER_MODE to enforce
 *              field-level and object-level security at the DML site. Uses `inherited sharing` so the
 *              caller's record-visibility context is respected without re-imposing a fixed sharing model.
 * @group DML
 * @author David Wood
 * @since May 2024
 * @last May 2026 — USER_MODE migration; DMLManagerException now extends UtilitiesModuleException
 * @last August 2026 — per-instance AccessLevel in SimpleDML (AsSystem statics now genuinely elevate);
 *                      explicit AccessLevel on merge; hardened DMLHelper-only cache contract; ApexDoc completion
 */
@SuppressWarnings('PMD.ExcessivePublicCount')
public inherited sharing class DMLManager {
  // Swap this out in tests to inject mock or error-simulation DML behaviour.
  private static IDML dmlOperations = new SimpleDML();
  private static IDML systemDmlOperations = new SimpleDML(AccessLevel.SYSTEM_MODE);

  /**
   * @description Fields excluded from FLS restriction checks (auto-managed by the platform).
   *              Contract: read by DMLHelper only — no other consumer may reference or mutate it.
   *              The reference is final; the set contents are the fixed platform-audit field list.
   */
  public static final Set<String> exceptionValues = new Set<String>{
    'id',
    'isdeleted',
    'createddate',
    'systemmodstamp',
    'lastmodifiedbyid',
    'createdbyid',
    'lastmodifieddate'
  };

  /**
   * @description Per-operation, per-SObjectType cache of fields the running user may not write.
   *              Contract: populated and read by DMLHelper only — no other consumer may touch it.
   *              The reference is final; DMLHelper owns all mutation of the cached contents.
   */
  public static final Map<Operation, Map<SObjectType, List<String>>> cachedRestrictedFields = new Map<Operation, Map<SObjectType, List<String>>>();

  /** @description Supported DML operations. */
  public enum Operation {
    OP_INSERT,
    OP_UPDATE,
    OP_DELETE,
    OP_UPSERT
  }

  // ─── AsUser single-record overloads ───────────────────────────────────────

  /**
   * @description Inserts a single record after CRUD and FLS verification.
   * @param obj The SObject to insert.
   */
  public static void insertAsUser(SObject obj) {
    performDMLOperation(new List<SObject>{ obj }, Operation.OP_INSERT);
  }

  /**
   * @description Updates a single record after CRUD and FLS verification.
   * @param obj The SObject to update.
   */
  public static void updateAsUser(SObject obj) {
    performDMLOperation(new List<SObject>{ obj }, Operation.OP_UPDATE);
  }

  /**
   * @description Upserts a single record after CRUD and FLS verification.
   * @param obj The SObject to upsert.
   */
  public static void upsertAsUser(SObject obj) {
    performDMLOperation(new List<SObject>{ obj }, Operation.OP_UPSERT);
  }

  /**
   * @description Deletes a single record after CRUD verification.
   * @param obj The SObject to delete.
   */
  public static void deleteAsUser(SObject obj) {
    performDMLOperation(new List<SObject>{ obj }, Operation.OP_DELETE);
  }

  /**
   * @description Merges one record into a master record after CRUD verification on both types.
   * @param masterObj The master SObject.
   * @param mergeObj The SObject to merge into masterObj.
   */
  public static void mergeAsUser(SObject masterObj, SObject mergeObj) {
    performDMLMergeOperation(masterObj, new List<SObject>{ mergeObj });
  }

  // ─── AsUser list overloads ────────────────────────────────────────────────

  /**
   * @description Inserts a list of records after CRUD and FLS verification.
   * @param objList The list of SObjects to insert.
   */
  public static void insertAsUser(List<SObject> objList) {
    performDMLOperation(objList, Operation.OP_INSERT);
  }

  /**
   * @description Updates a list of records after CRUD and FLS verification.
   * @param objList The list of SObjects to update.
   */
  public static void updateAsUser(List<SObject> objList) {
    performDMLOperation(objList, Operation.OP_UPDATE);
  }

  /**
   * @description Upserts a list of records after CRUD and FLS verification.
   * @param objList The list of SObjects to upsert.
   */
  public static void upsertAsUser(List<SObject> objList) {
    performDMLOperation(objList, Operation.OP_UPSERT);
  }

  /**
   * @description Deletes a list of records after CRUD verification.
   * @param objList The list of SObjects to delete.
   */
  public static void deleteAsUser(List<SObject> objList) {
    performDMLOperation(objList, Operation.OP_DELETE);
  }

  /**
   * @description Merges a list of records into a master record after CRUD verification on both types.
   * @param masterObj The master SObject.
   * @param mergeList The list of SObjects to merge into masterObj.
   */
  public static void mergeAsUser(SObject masterObj, List<SObject> mergeList) {
    performDMLMergeOperation(masterObj, mergeList);
  }

  // ─── AsSystem single-record overloads ─────────────────────────────────────

  /**
   * @description Inserts a single record without pre-checks, via the configured DML implementation.
   * @param obj The SObject to insert.
   */
  public static void insertAsSystem(SObject obj) {
    systemDmlOperations.dmlInsert(new List<SObject>{ obj });
  }

  /**
   * @description Updates a single record without pre-checks, via the configured DML implementation.
   * @param obj The SObject to update.
   */
  public static void updateAsSystem(SObject obj) {
    systemDmlOperations.dmlUpdate(new List<SObject>{ obj });
  }

  /**
   * @description Upserts a single record without pre-checks, via the configured DML implementation.
   * @param obj The SObject to upsert.
   */
  public static void upsertAsSystem(SObject obj) {
    systemDmlOperations.dmlUpsert(new List<SObject>{ obj });
  }

  /**
   * @description Deletes a single record without pre-checks, via the configured DML implementation.
   * @param obj The SObject to delete.
   */
  public static void deleteAsSystem(SObject obj) {
    systemDmlOperations.dmlDelete(new List<SObject>{ obj });
  }

  /**
   * @description Merges one record into a master record without pre-checks, via the configured DML implementation.
   * @param masterObj The master SObject.
   * @param mergeObj The SObject to merge into masterObj.
   */
  public static void mergeAsSystem(SObject masterObj, SObject mergeObj) {
    systemDmlOperations.dmlMerge(masterObj, new List<SObject>{ mergeObj });
  }

  // ─── AsSystem list overloads ──────────────────────────────────────────────

  /**
   * @description Inserts a list of records without pre-checks, via the configured DML implementation.
   * @param objList The list of SObjects to insert.
   */
  public static void insertAsSystem(List<SObject> objList) {
    systemDmlOperations.dmlInsert(objList);
  }

  /**
   * @description Updates a list of records without pre-checks, via the configured DML implementation.
   * @param objList The list of SObjects to update.
   */
  public static void updateAsSystem(List<SObject> objList) {
    systemDmlOperations.dmlUpdate(objList);
  }

  /**
   * @description Upserts a list of records without pre-checks, via the configured DML implementation.
   * @param objList The list of SObjects to upsert.
   */
  public static void upsertAsSystem(List<SObject> objList) {
    systemDmlOperations.dmlUpsert(objList);
  }

  /**
   * @description Deletes a list of records without pre-checks, via the configured DML implementation.
   * @param objList The list of SObjects to delete.
   */
  public static void deleteAsSystem(List<SObject> objList) {
    systemDmlOperations.dmlDelete(objList);
  }

  /**
   * @description Merges a list of records into a master record without pre-checks, via the configured DML implementation.
   * @param masterObj The master SObject.
   * @param mergeList The list of SObjects to merge into masterObj.
   */
  public static void mergeAsSystem(SObject masterObj, List<SObject> mergeList) {
    systemDmlOperations.dmlMerge(masterObj, mergeList);
  }

  // ─── Custom exception hierarchy ───────────────────────────────────────────

  /**
   * @description Base class for DML Manager exceptions; extends UtilitiesModuleException
   *              so callers can catch the whole utilities layer with one handler.
   */
  public virtual class DMLManagerException extends UtilitiesModuleException {
    public SObjectType objType { get; private set; }
    public Operation op { get; private set; }
  }

  /** @description Thrown when the running user lacks CRUD permission for the requested operation. */
  public class CRUDException extends DMLManagerException {
    /**
     * @description Builds the exception message from the denied operation and object type.
     * @param objType The SObjectType that triggered the violation.
     * @param op The operation that was denied.
     */
    public CRUDException(SObjectType objType, Operation op) {
      this('Access Denied: ' + op + ' on ' + objType);
      this.objType = objType;
      this.op = op;
    }
  }

  /** @description Thrown when the running user lacks FLS permission for a specific field. */
  public class FLSException extends DMLManagerException {
    public SObjectField field { get; private set; }

    /**
     * @description Builds the exception message from the denied operation, object type, and field.
     * @param objType The SObjectType that triggered the violation.
     * @param field The restricted field.
     * @param op The operation that was denied.
     */
    public FLSException(SObjectType objType, SObjectField field, Operation op) {
      this('Access Denied: ' + op + ' on ' + objType + '.' + field);
      this.objType = objType;
      this.op = op;
      this.field = field;
    }
  }

  // ─── Infrastructure ───────────────────────────────────────────────────────

  /** @description Interface that all DML implementations must satisfy. */
  public interface IDML {
    void dmlInsert(List<SObject> objList); //NOPMD
    void dmlUpdate(List<SObject> objList); //NOPMD
    void dmlDelete(List<SObject> objList); //NOPMD
    void dmlMerge(SObject masterRecord, List<SObject> objList); //NOPMD
    void dmlUpsert(List<SObject> objList); //NOPMD
  }

  /**
   * @description Swaps the live DML implementation for an injected one.
   * @param dmlImplementation The implementation to inject (e.g. a mock for tests).
   */
  public static void setDMLImplementation(IDML dmlImplementation) {
    dmlOperations = dmlImplementation;
    systemDmlOperations = dmlImplementation;
  }

  /**
   * @description Live implementation that delegates to the platform Database methods at a
   *              per-instance AccessLevel — USER_MODE by default, so CRUD/FLS are enforced
   *              at the DML site; the AsSystem statics hold a SYSTEM_MODE instance.
   *              `inherited sharing` mirrors the containing class — record visibility
   *              follows the caller's sharing context.
   */
  @SuppressWarnings('PMD.ApexCRUDViolation') // CRUD/FLS is verified before reaching these methods
  public inherited sharing virtual class SimpleDML implements IDML {
    private final AccessLevel dmlAccessLevel;

    /** @description Builds the default implementation, enforcing USER_MODE at every DML site. */
    public SimpleDML() {
      this(AccessLevel.USER_MODE);
    }

    /**
     * @description Builds an implementation pinned to the given access level. The AsSystem
     *              statics hold a SYSTEM_MODE instance; everything else defaults to USER_MODE.
     * @param dmlAccessLevel Access level applied to every verb on this instance.
     */
    public SimpleDML(AccessLevel dmlAccessLevel) {
      this.dmlAccessLevel = dmlAccessLevel;
    }

    /**
     * @description Inserts the records at the configured access level.
     * @param objList The records to insert.
     */
    public virtual void dmlInsert(List<SObject> objList) {
      Logger.debug('Inserting ' + JSON.serializePretty(objList), 'DMLManager', 'dmlInsert');
      Database.insert(objList, dmlAccessLevel);
    }

    /**
     * @description Updates the records at the configured access level.
     * @param objList The records to update.
     */
    public virtual void dmlUpdate(List<SObject> objList) {
      Logger.debug('Updating ' + JSON.serializePretty(objList), 'DMLManager', 'dmlUpdate');
      Database.update(objList, dmlAccessLevel);
    }

    /**
     * @description Deletes the records at the configured access level.
     * @param objList The records to delete.
     */
    public virtual void dmlDelete(List<SObject> objList) {
      Logger.debug('Deleting ' + JSON.serializePretty(objList), 'DMLManager', 'dmlDelete');
      Database.delete(objList, dmlAccessLevel);
    }

    /**
     * @description Merges the records into the master record at the configured access level.
     * @param masterRecord The record that survives the merge.
     * @param objList The records to merge into masterRecord.
     */
    public virtual void dmlMerge(SObject masterRecord, List<SObject> objList) {
      Logger.debug(
        'Merging ' +
          JSON.serializePretty(objList) +
          ' into ' +
          JSON.serializePretty(masterRecord),
        'DMLManager',
        'dmlMerge'
      );
      Database.merge(masterRecord, objList, dmlAccessLevel);
    }

    /**
     * @description Upserts the records at the configured access level.
     * @param objList The records to upsert.
     */
    public virtual void dmlUpsert(List<SObject> objList) {
      Logger.debug('Upserting ' + JSON.serializePretty(objList), 'DMLManager', 'dmlUpsert');
      Database.upsert(objList, dmlAccessLevel);
    }
  }

  // ─── Internal permission-checking helpers ─────────────────────────────────

  /**
   * @description Verifies the running user holds the CRUD permission each SObjectType needs for the operation.
   * @param objTypeList Set of SObjectTypes whose CRUD will be verified.
   * @param dmlOperation The operation being attempted.
   * @throws CRUDException when the running user lacks the required CRUD permission on any listed type.
   */
  public static void checkCRUDPermission(
    Set<SObjectType> objTypeList,
    Operation dmlOperation
  ) {
    for (SObjectType objType : objTypeList) {
      DescribeSObjectResult describeObject = objType.getDescribe();
      if (isCRUDViolation(describeObject, dmlOperation)) {
        throw new CRUDException(objType, dmlOperation);
      }
    }
  }

  private static Boolean isCRUDViolation(
    DescribeSObjectResult dr,
    Operation dmlOperation
  ) {
    if (dmlOperation == Operation.OP_INSERT) {
      return !dr.isCreateable();
    }
    if (dmlOperation == Operation.OP_UPDATE) {
      return !dr.isUpdateable();
    }
    if (dmlOperation == Operation.OP_DELETE) {
      return !dr.isDeletable();
    }
    if (dmlOperation == Operation.OP_UPSERT) {
      return !(dr.isCreateable() && dr.isUpdateable());
    }
    return false;
  }

  private static void performDMLOperation(
    List<SObject> objList,
    Operation dmlOperation
  ) {
    if (objList.isEmpty()) {
      Logger.warn('There were no records to process', 'DMLManager', 'performDMLOperation');
      return;
    }

    Map<SObjectType, List<Id>> objTypeMap = DMLHelper.analyzeDMLCollection(objList, dmlOperation);
    checkCRUDPermission(objTypeMap.keySet(), dmlOperation);
    checkFLSPermissions(objList, objTypeMap, dmlOperation);
    dispatchDML(objList, dmlOperation);
  }

  private static void checkFLSPermissions(
    List<SObject> objList,
    Map<SObjectType, List<Id>> objTypeMap,
    Operation dmlOperation
  ) {
    if (dmlOperation == Operation.OP_INSERT) {
      DMLHelper.checkCreateAction(objList);
    } else if (dmlOperation == Operation.OP_UPDATE || dmlOperation == Operation.OP_UPSERT) {
      Map<Id, SObject> existingRecords = DMLHelper.getExistingRecords(objTypeMap);
      DMLHelper.checkUpdateOrCreateAction(objList, existingRecords, dmlOperation);
    }
  }

  private static void dispatchDML(List<SObject> objList, Operation dmlOperation) {
    if (dmlOperation == Operation.OP_INSERT) {
      dmlOperations.dmlInsert(objList);
    } else if (dmlOperation == Operation.OP_UPDATE) {
      dmlOperations.dmlUpdate(objList);
    } else if (dmlOperation == Operation.OP_UPSERT) {
      dmlOperations.dmlUpsert(objList);
    } else if (dmlOperation == Operation.OP_DELETE) {
      dmlOperations.dmlDelete(objList);
    }
  }

  private static void performDMLMergeOperation(
    SObject masterObj,
    List<SObject> mergeList
  ) {
    DMLHelper.checkCRUDForMerge(masterObj, mergeList);
    dmlOperations.dmlMerge(masterObj, mergeList);
  }
}
