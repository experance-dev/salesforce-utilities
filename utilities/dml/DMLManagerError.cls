/**
 * @description This class extends DMLManager.SimpleDML and is designed to simulate DML errors.
 *              It overrides the DML methods (Insert, Update, Delete, Merge, Upsert) to throw a DMLException.
 *              It is useful for testing and debugging purposes where forced DML failures are required.
 *
 *              Each method logs the serialized SObject list or record involved before throwing the exception.
 *              All exceptions are wrapped in a custom `DMLException`.
 *
 * @author David Wood
 * @since September 2024
 * @group DMLManager
 */
@isTest
public with sharing class DMLManagerError extends DMLManager.SimpleDML {
  /**
   * @description Simulates a DML delete error. Logs the records intended for deletion and throws a DMLException.
   *
   * @param recordsToDelete The list of SObjects that were intended to be deleted.
   * @throws DMLException Always thrown to simulate a DML Delete failure.
   */
  public override void dmlDelete(List<SObject> recordsToDelete) {
    Logger.debug(
      'Deleting ' + JSON.serializePretty(recordsToDelete),
      'DMLManager',
      'dmlDelete'
    );
    throw new DMLException('DML Delete Error');
  }

  /**
   * @description Simulates a DML insert error. Logs the records intended for insertion and throws a DMLException.
   *
   * @param recordsToInsert The list of SObjects that were intended to be inserted.
   * @throws DMLException Always thrown to simulate a DML Insert failure.
   */
  public override void dmlInsert(List<SObject> recordsToInsert) {
    Logger.debug(
      'Inserting ' + JSON.serializePretty(recordsToInsert),
      'DMLManager',
      'dmlInsert'
    );
    throw new DMLException('DML Insert Error');
  }

  /**
   * @description Simulates a DML merge error. Logs the master and duplicate records involved in the merge and throws a DMLException.
   *
   * @param masterRecord The master SObject to retain after the merge.
   * @param duplicateRecords The list of SObjects to merge into the masterRecord.
   * @throws DMLException Always thrown to simulate a DML Merge failure.
   */
  public override void dmlMerge(
    sObject masterRecord,
    List<SObject> duplicateRecords
  ) {
    Logger.debug(
      'Merging ' +
        JSON.serializePretty(masterRecord) +
        ' to ' +
        JSON.serializePretty(duplicateRecords),
      'DMLManager',
      'dmlMerge'
    );
    throw new DMLException('DML Merge Error');
  }

  /**
   * @description Simulates a DML update error. Logs the records intended for update and throws a DMLException.
   *
   * @param recordsToUpdate The list of SObjects that were intended to be updated.
   * @throws DMLException Always thrown to simulate a DML Update failure.
   */
  public override void dmlUpdate(List<SObject> recordsToUpdate) {
    Logger.debug(
      'Updating ' + JSON.serializePretty(recordsToUpdate),
      'DMLManager',
      'dmlUpdate'
    );
    throw new DMLException('DML Update Error');
  }

  /**
   * @description Simulates a DML upsert error. Logs the records intended for upsert and throws a DMLException.
   *
   * @param recordsToUpsert The list of SObjects that were intended to be upserted.
   * @throws DMLException Always thrown to simulate a DML Upsert failure.
   */
  public override void dmlUpsert(List<SObject> recordsToUpsert) {
    Logger.debug(
      'Upserting ' + JSON.serializePretty(recordsToUpsert),
      'DMLManager',
      'dmlUpsert'
    );
    throw new DMLException('DML Upsert Error');
  }
}
