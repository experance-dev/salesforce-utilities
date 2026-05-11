/**
 * @description Test-only DML implementation that always throws a DMLException. Use this with
 *              DMLManager.setDMLImplementation(new DMLManagerError()) to force DML-failure paths
 *              in unit tests without touching the database.
 * @group DML
 * @author David Wood
 * @since September 2024
 * @last May 2026 — Wave 2 conformance refactor
 */
@isTest
public with sharing class DMLManagerError extends DMLManager.SimpleDML {
  public override void dmlDelete(List<SObject> recordsToDelete) {
    Logger.debug(
      'Deleting ' + JSON.serializePretty(recordsToDelete),
      'DMLManager',
      'dmlDelete'
    );
    throw new DMLException('DML Delete Error');
  }

  public override void dmlInsert(List<SObject> recordsToInsert) {
    Logger.debug(
      'Inserting ' + JSON.serializePretty(recordsToInsert),
      'DMLManager',
      'dmlInsert'
    );
    throw new DMLException('DML Insert Error');
  }

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

  public override void dmlUpdate(List<SObject> recordsToUpdate) {
    Logger.debug(
      'Updating ' + JSON.serializePretty(recordsToUpdate),
      'DMLManager',
      'dmlUpdate'
    );
    throw new DMLException('DML Update Error');
  }

  public override void dmlUpsert(List<SObject> recordsToUpsert) {
    Logger.debug(
      'Upserting ' + JSON.serializePretty(recordsToUpsert),
      'DMLManager',
      'dmlUpsert'
    );
    throw new DMLException('DML Upsert Error');
  }
}
