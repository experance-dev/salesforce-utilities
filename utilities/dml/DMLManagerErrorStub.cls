/**
 * @description Test-only DML implementation that always throws a DMLException. Use this with
 *              DMLManager.setDMLImplementation(new DMLManagerErrorStub()) to force DML-failure paths
 *              in unit tests without touching the database.
 *              Uses `inherited sharing` to remain consistent with the DML stack sharing convention.
 * @group DML
 * @author David Wood
 * @since September 2024
 * @last May 2026 — conformance refactor
 * @last August 2026 — renamed with the descriptive Stub suffix reserved for test infrastructure; inherited sharing to match the DML stack
 */
@isTest
public inherited sharing class DMLManagerErrorStub extends DMLManager.SimpleDML {
  /**
   * @description Logs the attempted delete, then throws a DMLException instead of executing it.
   * @param recordsToDelete The records the caller asked to delete.
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
   * @description Logs the attempted insert, then throws a DMLException instead of executing it.
   * @param recordsToInsert The records the caller asked to insert.
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
   * @description Logs the attempted merge, then throws a DMLException instead of executing it.
   * @param masterRecord The record that would survive the merge.
   * @param duplicateRecords The records that would be consumed.
   */
  public override void dmlMerge(
    SObject masterRecord,
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
   * @description Logs the attempted update, then throws a DMLException instead of executing it.
   * @param recordsToUpdate The records the caller asked to update.
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
   * @description Logs the attempted upsert, then throws a DMLException instead of executing it.
   * @param recordsToUpsert The records the caller asked to upsert.
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
