/**
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
 * @last May 2026 — Wave 2 USER_MODE migration; DMLManagerException now extends UtilitiesModuleException
 */
@SuppressWarnings('PMD.ExcessivePublicCount')
public inherited sharing class DMLManager {
  // Swap this out in tests to inject mock or error-simulation DML behaviour.
  private static IDML dmlOperations = new SimpleDML();

  // Fields excluded from FLS restriction checks (auto-managed by the platform).
  public static Set<String> exceptionValues = new Set<String>{
    'id',
    'isdeleted',
    'createddate',
    'systemmodstamp',
    'lastmodifiedbyid',
    'createdbyid',
    'lastmodifieddate'
  };

  // Per-operation, per-SObjectType cache of fields the running user may not write.
  public static Map<Operation, Map<SObjectType, List<String>>> cachedRestrictedFields = new Map<Operation, Map<SObjectType, List<String>>>();

  /** @description Supported DML operations. */
  public enum Operation {
    OP_INSERT,
    OP_UPDATE,
    OP_DELETE,
    OP_UPSERT
  }

  // ─── AsUser single-record overloads ───────────────────────────────────────

  /** @param obj The SObject to insert. */
  public static void insertAsUser(SObject obj) {
    performDMLOperation(new List<SObject>{ obj }, Operation.OP_INSERT);
  }

  /** @param obj The SObject to update. */
  public static void updateAsUser(SObject obj) {
    performDMLOperation(new List<SObject>{ obj }, Operation.OP_UPDATE);
  }

  /** @param obj The SObject to upsert. */
  public static void upsertAsUser(SObject obj) {
    performDMLOperation(new List<SObject>{ obj }, Operation.OP_UPSERT);
  }

  /** @param obj The SObject to delete. */
  public static void deleteAsUser(SObject obj) {
    performDMLOperation(new List<SObject>{ obj }, Operation.OP_DELETE);
  }

  /**
   * @param masterObj The master SObject.
   * @param mergeObj The SObject to merge into masterObj.
   */
  public static void mergeAsUser(SObject masterObj, SObject mergeObj) {
    performDMLMergeOperation(masterObj, new List<SObject>{ mergeObj });
  }

  // ─── AsUser list overloads ────────────────────────────────────────────────

  /** @param objList The list of SObjects to insert. */
  public static void insertAsUser(List<SObject> objList) {
    performDMLOperation(objList, Operation.OP_INSERT);
  }

  /** @param objList The list of SObjects to update. */
  public static void updateAsUser(List<SObject> objList) {
    performDMLOperation(objList, Operation.OP_UPDATE);
  }

  /** @param objList The list of SObjects to upsert. */
  public static void upsertAsUser(List<SObject> objList) {
    performDMLOperation(objList, Operation.OP_UPSERT);
  }

  /** @param objList The list of SObjects to delete. */
  public static void deleteAsUser(List<SObject> objList) {
    performDMLOperation(objList, Operation.OP_DELETE);
  }

  /**
   * @param masterObj The master SObject.
   * @param mergeList The list of SObjects to merge into masterObj.
   */
  public static void mergeAsUser(SObject masterObj, List<SObject> mergeList) {
    performDMLMergeOperation(masterObj, mergeList);
  }

  // ─── AsSystem single-record overloads ─────────────────────────────────────

  /** @param obj The SObject to insert. */
  public static void insertAsSystem(SObject obj) {
    dmlOperations.dmlInsert(new List<SObject>{ obj });
  }

  /** @param obj The SObject to update. */
  public static void updateAsSystem(SObject obj) {
    dmlOperations.dmlUpdate(new List<SObject>{ obj });
  }

  /** @param obj The SObject to upsert. */
  public static void upsertAsSystem(SObject obj) {
    dmlOperations.dmlUpsert(new List<SObject>{ obj });
  }

  /** @param obj The SObject to delete. */
  public static void deleteAsSystem(SObject obj) {
    dmlOperations.dmlDelete(new List<SObject>{ obj });
  }

  /**
   * @param masterObj The master SObject.
   * @param mergeObj The SObject to merge into masterObj.
   */
  public static void mergeAsSystem(SObject masterObj, SObject mergeObj) {
    dmlOperations.dmlMerge(masterObj, new List<SObject>{ mergeObj });
  }

  // ─── AsSystem list overloads ──────────────────────────────────────────────

  /** @param objList The list of SObjects to insert. */
  public static void insertAsSystem(List<SObject> objList) {
    dmlOperations.dmlInsert(objList);
  }

  /** @param objList The list of SObjects to update. */
  public static void updateAsSystem(List<SObject> objList) {
    dmlOperations.dmlUpdate(objList);
  }

  /** @param objList The list of SObjects to upsert. */
  public static void upsertAsSystem(List<SObject> objList) {
    dmlOperations.dmlUpsert(objList);
  }

  /** @param objList The list of SObjects to delete. */
  public static void deleteAsSystem(List<SObject> objList) {
    dmlOperations.dmlDelete(objList);
  }

  /**
   * @param masterObj The master SObject.
   * @param mergeList The list of SObjects to merge into masterObj.
   */
  public static void mergeAsSystem(SObject masterObj, List<SObject> mergeList) {
    dmlOperations.dmlMerge(masterObj, mergeList);
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
   * @param dmlImplementation The implementation to inject (e.g. a mock for tests).
   */
  public static void setDMLImplementation(IDML dmlImplementation) {
    dmlOperations = dmlImplementation;
  }

  /**
   * @description Live implementation that delegates to the platform Database methods
   *              with AccessLevel.USER_MODE so CRUD/FLS are enforced at the DML site.
   *              `inherited sharing` mirrors the containing class — record visibility
   *              follows the caller's sharing context.
   */
  @SuppressWarnings('PMD.ApexCRUDViolation') // CRUD/FLS is verified before reaching these methods
  public inherited sharing virtual class SimpleDML implements IDML {
    public virtual void dmlInsert(List<SObject> objList) {
      Logger.debug('Inserting ' + JSON.serializePretty(objList), 'DMLManager', 'dmlInsert');
      Database.insert(objList, AccessLevel.USER_MODE);
    }

    public virtual void dmlUpdate(List<SObject> objList) {
      Logger.debug('Updating ' + JSON.serializePretty(objList), 'DMLManager', 'dmlUpdate');
      Database.update(objList, AccessLevel.USER_MODE);
    }

    public virtual void dmlDelete(List<SObject> objList) {
      Logger.debug('Deleting ' + JSON.serializePretty(objList), 'DMLManager', 'dmlDelete');
      Database.delete(objList, AccessLevel.USER_MODE);
    }

    public virtual void dmlMerge(SObject masterRecord, List<SObject> objList) {
      // Database.merge does not accept AccessLevel; sharing is governed by the class modifier.
      Database.merge(masterRecord, objList);
    }

    public virtual void dmlUpsert(List<SObject> objList) {
      Logger.debug('Upserting ' + JSON.serializePretty(objList), 'DMLManager', 'dmlUpsert');
      Database.upsert(objList, AccessLevel.USER_MODE);
    }
  }

  // ─── Internal permission-checking helpers ─────────────────────────────────

  /**
   * @param objTypeList Set of SObjectTypes whose CRUD will be verified.
   * @param dmlOperation The operation being attempted.
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
      insertAsSystem(objList);
    } else if (dmlOperation == Operation.OP_UPDATE) {
      updateAsSystem(objList);
    } else if (dmlOperation == Operation.OP_UPSERT) {
      upsertAsSystem(objList);
    } else if (dmlOperation == Operation.OP_DELETE) {
      deleteAsSystem(objList);
    }
  }

  private static void performDMLMergeOperation(
    SObject masterObj,
    List<SObject> mergeList
  ) {
    DMLHelper.checkCRUDForMerge(masterObj, mergeList);
    mergeAsSystem(masterObj, mergeList);
  }
}
