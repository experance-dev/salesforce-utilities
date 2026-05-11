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
 * @description Manages CRUD and FLS-safe DML operations, ensuring permissions of the running user.
 * Supports operations as both user and system.
 * This class has all the callable methods and also the ability to set up Mock for Tests
 *
 * @author David Wood
 * @since May 2024
 *
 * @group   Utilities
 * @group   DMLManager
 */
@SuppressWarnings(
  'PMD.CyclomaticComplexity, PMD.ExcessivePublicCount'
) //this class is a utility class
public inherited sharing class DMLManager {
  private static final Boolean DEBUG_DML = false;
  //normal operations of this class... replace if you want to create complex DML or you want to MOCK for tests
  private static IDML dmlOperations = new SimpleDML();
  // Set of field names that should be excluded from DML operations
  public static Set<String> exceptionValues = new Set<String>{ // Changed to public
    'id',
    'isdeleted',
    'createddate',
    'systemmodstamp',
    'lastmodifiedbyid',
    'createdbyid',
    'lastmodifieddate'
  };

  // Cache to store restricted fields for different operations and SObject types
  public static Map<Operation, Map<SObjectType, List<String>>> cachedRestrictedFields = new Map<Operation, Map<SObjectType, List<String>>>(); // Changed to public

  /**
   * @description Enum representing DML operations.
   */
  public enum Operation {
    OP_INSERT,
    OP_UPDATE,
    OP_DELETE,
    OP_UPSERT
  }

  /**
   * @description Inserts an SObject as the running user, checking CRUD and FLS permissions.
   * @param obj The SObject to insert.
   */
  public static void insertAsUser(SObject obj) {
    performDMLOperation(new List<SObject>{ obj }, Operation.OP_INSERT);
  }

  /**
   * @description Updates an SObject as the running user, checking CRUD and FLS permissions.
   * @param obj The SObject to update.
   */
  public static void updateAsUser(SObject obj) {
    performDMLOperation(new List<SObject>{ obj }, Operation.OP_UPDATE);
  }

  /**
   * @description Upserts an SObject as the running user, checking CRUD and FLS permissions.
   * @param obj The SObject to upsert.
   */
  public static void upsertAsUser(SObject obj) {
    performDMLOperation(new List<SObject>{ obj }, Operation.OP_UPSERT);
  }

  /**
   * @description Deletes an SObject as the running user, checking CRUD permissions.
   * @param obj The SObject to delete.
   */
  public static void deleteAsUser(SObject obj) {
    performDMLOperation(new List<SObject>{ obj }, Operation.OP_DELETE);
  }

  /**
   * @description Merges an SObject into a master record as the running user, checking CRUD permissions.
   * @param masterObj The master SObject.
   * @param mergeObj The SObject to merge.
   */
  public static void mergeAsUser(SObject masterObj, SObject mergeObj) {
    performDMLMergeOperation(masterObj, new List<SObject>{ mergeObj });
  }

  /**
   * @description Inserts a list of SObjects as the running user, checking CRUD and FLS permissions.
   * @param objList The list of SObjects to insert.
   */
  public static void insertAsUser(List<SObject> objList) {
    performDMLOperation(objList, Operation.OP_INSERT);
  }

  /**
   * @description Updates a list of SObjects as the running user, checking CRUD and FLS permissions.
   * @param objList The list of SObjects to update.
   */
  public static void updateAsUser(List<SObject> objList) {
    performDMLOperation(objList, Operation.OP_UPDATE);
  }

  /**
   * @description Upserts a list of SObjects as the running user, checking CRUD and FLS permissions.
   * @param objList The list of SObjects to upsert.
   */
  public static void upsertAsUser(List<SObject> objList) {
    performDMLOperation(objList, Operation.OP_UPSERT);
  }

  /**
   * @description Deletes a list of SObjects as the running user, checking CRUD permissions.
   * @param objList The list of SObjects to delete.
   */
  public static void deleteAsUser(List<SObject> objList) {
    performDMLOperation(objList, Operation.OP_DELETE);
  }

  /**
   * @description Merges a list of SObjects into a master record as the running user, checking CRUD permissions.
   * @param masterObj The master SObject.
   * @param mergeList The list of SObjects to merge.
   */
  public static void mergeAsUser(SObject masterObj, List<SObject> mergeList) {
    performDMLMergeOperation(masterObj, mergeList);
  }

  /**
   * @description Inserts an SObject as the system user, without checking CRUD and FLS permissions.
   * @param obj The SObject to insert.
   */
  public static void insertAsSystem(SObject obj) {
    dmlOperations.dmlInsert(new List<SObject>{ obj });
  }

  /**
   * @description Updates an SObject as the system user, without checking CRUD and FLS permissions.
   * @param obj The SObject to update.
   */
  public static void updateAsSystem(SObject obj) {
    dmlOperations.dmlUpdate(new List<SObject>{ obj });
  }

  /**
   * @description Upserts an SObject as the system user, without checking CRUD and FLS permissions.
   * @param obj The SObject to upsert.
   */
  public static void upsertAsSystem(SObject obj) {
    dmlOperations.dmlUpsert(new List<SObject>{ obj });
  }

  /**
   * @description Deletes an SObject as the system user, without checking CRUD permissions.
   * @param obj The SObject to delete.
   */
  public static void deleteAsSystem(SObject obj) {
    dmlOperations.dmlDelete(new List<SObject>{ obj });
  }

  /**
   * @description Merges an SObject into a master record as the system user, without checking CRUD permissions.
   * @param masterObj The master SObject.
   * @param mergeObj The SObject to merge.
   */
  public static void mergeAsSystem(SObject masterObj, SObject mergeObj) {
    dmlOperations.dmlMerge(masterObj, new List<SObject>{ mergeObj });
  }

  /**
   * @description Inserts a list of SObjects as the system user, without checking CRUD and FLS permissions.
   * @param objList The list of SObjects to insert.
   */
  public static void insertAsSystem(List<SObject> objList) {
    dmlOperations.dmlInsert(objList);
  }

  /**
   * @description Updates a list of SObjects as the system user, without checking CRUD and FLS permissions.
   * @param objList The list of SObjects to update.
   */
  public static void updateAsSystem(List<SObject> objList) {
    dmlOperations.dmlUpdate(objList);
  }

  /**
   * @description Upserts a list of SObjects as the system user, without checking CRUD and FLS permissions.
   * @param objList The list of SObjects to upsert.
   */
  public static void upsertAsSystem(List<SObject> objList) {
    dmlOperations.dmlUpsert(objList);
  }

  /**
   * @description Deletes a list of SObjects as the system user, without checking CRUD permissions.
   * @param objList The list of SObjects to delete.
   */
  public static void deleteAsSystem(List<SObject> objList) {
    dmlOperations.dmlDelete(objList);
  }

  /**
   * @description Merges a list of SObjects into a master record as the system user, without checking CRUD permissions.
   * @param masterObj The master SObject.
   * @param mergeList The list of SObjects to merge.
   */
  public static void mergeAsSystem(SObject masterObj, List<SObject> mergeList) {
    dmlOperations.dmlMerge(masterObj, mergeList);
  }

  // Custom Exception Classes

  /**
   * @description Base class for DML Manager exceptions.
   */
  public virtual class DMLManagerException extends Exception {
    /**
     * @description Represents the SObject type associated with the DMLManager class.
     */
    public SObjectType objType { get; private set; } //NOPDM.ApexDoc

    /**
     * @description Gets or sets the Operation object.
     */
    public Operation op { get; private set; }
  }

  /**
   * @description Exception class for CRUD permission errors.
   */
  public class CRUDException extends DMLManagerException {
    /**
     * @description Constructs a new instance of the CRUDException class with the specified SObjectType and Operation.
     *
     * @param objType The SObjectType associated with the exception.
     * @param op The Operation associated with the exception.
     */
    public CRUDException(SObjectType objType, Operation op) {
      this('Access Denied: ' + op + ' on ' + objType);
      this.objType = objType;
      this.op = op;
    }
  }

  /**
   * @description Exception class for FLS permission errors.
   */
  public class FLSException extends DMLManagerException {
    /**
     * @description Represents a field on a Salesforce object.
     * Provides access to the field's metadata and value.
     */
    public SObjectField field { get; private set; }

    /**
     * @description Exception class for handling Field Level Security (FLS) violations.
     *
     * @param objType The SObjectType of the object being accessed.
     * @param field The SObjectField that is being accessed.
     * @param op The Operation being performed on the field.
     */
    public FLSException(SObjectType objType, SObjectField field, Operation op) {
      this('Access Denied: ' + op + ' on ' + objType + '.' + field);
      this.objType = objType;
      this.op = op;
      this.field = field;
    }
  }

  /**
   * @description Performs the specified DML operation, checking CRUD and FLS permissions.
   * @param objList The list of SObjects to perform the DML operation on.
   * @param dmlOperation The DML operation to perform.
   */
  private static void performDMLOperation(
    List<SObject> objList,
    Operation dmlOperation
  ) {
    // Check to see if there is anything to do
    if (objList.isEmpty()) {
      Logger.warn(
        'There were no records to process',
        'DMLManager',
        'performDMLOperation'
      );
      return;
    }

    // Analyze the DML collection and get a map of object types to IDs
    Map<SObjectType, List<Id>> objTypeMap = DMLHelper.analyzeDMLCollection(
      objList,
      dmlOperation
    );

    // Check CRUD permissions for each object type in the collection
    checkCRUDPermission(objTypeMap.keySet(), dmlOperation);

    // Check FLS permissions for insert operation
    if (dmlOperation == Operation.OP_INSERT) {
      DMLHelper.checkCreateAction(objList);
    } else if (
      dmlOperation == Operation.OP_UPDATE ||
      dmlOperation == Operation.OP_UPSERT
    ) {
      // Check FLS permissions for update or upsert operation
      Map<Id, SObject> existingRecords = DMLHelper.getExistingRecords(
        objTypeMap
      );
      DMLHelper.checkUpdateOrCreateAction(
        objList,
        existingRecords,
        dmlOperation
      );
    }

    // Perform the DML operation if no exceptions have been thrown
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

  /**
   * @description Checks for CRUD on the master & merge objects and throws error if they don't have the proper object permission.
   * If all checks pass, the merge operation is performed.
   * @param masterObj SObject the data will be merged into
   * @param mergeList List of SObjects that will be merged into the masterObj
   */
  private static void performDMLMergeOperation(
    SObject masterObj,
    List<SObject> mergeList
  ) {
    // Check CRUD permissions for the master and merge objects
    DMLHelper.checkCRUDForMerge(masterObj, mergeList);

    // Perform the merge operation if no exceptions have been thrown
    mergeAsSystem(masterObj, mergeList);
  }

  /**
   * @description Checks CRUD permissions for the current user on the object.
   * @param objTypeList Set of SObjectTypes to check.
   * @param dmlOperation The DML operation being performed.
   */
  public static void checkCRUDPermission(
    Set<SObjectType> objTypeList,
    Operation dmlOperation
  ) {
    // Changed to public
    for (SObjectType objType : objTypeList) {
      DescribeSObjectResult describeObject = objType.getDescribe();
      // Check for create, update, delete, and upsert permissions
      if (
        (dmlOperation == Operation.OP_INSERT &&
        !describeObject.isCreateable()) ||
        (dmlOperation == Operation.OP_UPDATE &&
        !describeObject.isUpdateable()) ||
        (dmlOperation == Operation.OP_DELETE &&
        !describeObject.isDeletable()) ||
        (dmlOperation == Operation.OP_UPSERT &&
        !(describeObject.isCreateable() && describeObject.isUpdateable()))
      ) {
        throw new CRUDException(objType, dmlOperation);
      }
    }
  }

  /**
   * @description Sets the DML implementation to be used by DMLManager.
   * @param dmlImplementation The DML implementation to set.
   */
  public static void setDMLImplementation(IDML dmlImplementation) {
    dmlOperations = dmlImplementation;
  }

  /**
   * @description Interface for DML operations.
   */
  public interface IDML {
    void dmlInsert(List<SObject> objList); //NOPMD
    void dmlUpdate(List<SObject> objList); //NOPMD
    void dmlDelete(List<SObject> objList); //NOPMD
    void dmlMerge(SObject masterRecord, List<SObject> objList); //NOPMD
    void dmlUpsert(List<SObject> objList); //NOPMD
  }

  /**
   * @description Default implementation of the IDML interface.
   */
  @SuppressWarnings(
    'PMD.ApexCRUDViolation'
  ) //CRUD is checked before execution here
  public inherited sharing virtual class SimpleDML implements IDML {
    /**
     * @description Performs the insert operation on a list of SObjects.
     * @param objList The list of SObjects to be inserted.
     */
    public virtual void dmlInsert(List<SObject> objList) {
      Logger.debug(
        'Inserting ' + JSON.serializePretty(objList),
        'DMLManager',
        'dmlInsert'
      );
      insert objList;
    }

    /**
     * @description Performs the update operation on a list of SObjects.
     * @param objList The list of SObjects to be updated.
     */
    public virtual void dmlUpdate(List<SObject> objList) {
      Logger.debug(
        'Updating ' + JSON.serializePretty(objList),
        'DMLManager',
        'dmlUpdate'
      );
      update objList;
    }

    /**
     * @description Performs the delete operation on a list of SObjects.
     * @param objList The list of SObjects to be deleted.
     */
    public virtual void dmlDelete(List<SObject> objList) {
      Logger.debug(
        'Deleting ' + JSON.serializePretty(objList),
        'DMLManager',
        'dmlDelete'
      );
      delete objList;
    }

    /**
     * @description Performs the merge operation on a master record and a list of SObjects.
     * @param masterRecord The master record to merge into.
     * @param objList The list of SObjects to be merged.
     */
    public virtual void dmlMerge(SObject masterRecord, List<SObject> objList) {
      Database.merge(masterRecord, objList);
    }

    /**
     * @description Performs the upsert operation on a list of SObjects.
     * @param objList The list of SObjects to be upserted.
     */
    public virtual void dmlUpsert(List<SObject> objList) {
      Logger.debug(
        'Upserting ' + JSON.serializePretty(objList),
        'DMLManager',
        'dmlUpsert'
      );

      upsert objList;
    }
  }
}
