/**
 * @class DMLManagerInert
 * @description This class extends the DMLManager.SimpleDML class and is used to manage DML operations in an inert manner.
 *
 * @see DMLManager.SimpleDML
 */
public with sharing class DMLManagerInert extends DMLManager.SimpleDML {
  public override void dmlDelete(List<SObject> recordsToDelete) {
    Logger.debug(
      'Inserting ' + JSON.serializePretty(recordsToDelete),
      'DMLManager',
      'dmlInsert'
    );
    return;
  }

  public override void dmlInsert(List<SObject> recordsToInsert) {
    Logger.debug(
      'Inserting ' + JSON.serializePretty(recordsToInsert),
      'DMLManager',
      'dmlInsert'
    );
    return;
  }

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
    return;
  }

  public override void dmlUpdate(List<SObject> recordsToUpdate) {
    Logger.debug(
      'Inserting ' + JSON.serializePretty(recordsToUpdate),
      'DMLManager',
      'dmlInsert'
    );
    return;
  }

  public override void dmlUpsert(List<SObject> recordsToUpsert) {
    Logger.debug(
      'Inserting ' + JSON.serializePretty(recordsToUpsert),
      'DMLManager',
      'dmlInsert'
    );
    return;
  }
}
