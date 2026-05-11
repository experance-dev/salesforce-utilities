/**
 * @description No-op DML implementation for use in tests or dry-run contexts where real DML must be
 *              suppressed. Extends SimpleDML and overrides every method to log and return immediately
 *              without touching the database.
 *              Uses `inherited sharing` to remain consistent with the DML stack sharing convention,
 *              even though no queries or DML are executed.
 * @group DML
 * @author David Wood
 * @since May 2024
 * @last May 2026 — Wave 2 conformance refactor; corrected copy-paste log messages
 */
public inherited sharing class DMLManagerInert extends DMLManager.SimpleDML {
  public override void dmlDelete(List<SObject> recordsToDelete) {
    Logger.debug(
      'Deleting ' + JSON.serializePretty(recordsToDelete),
      'DMLManager',
      'dmlDelete'
    );
  }

  public override void dmlInsert(List<SObject> recordsToInsert) {
    Logger.debug(
      'Inserting ' + JSON.serializePretty(recordsToInsert),
      'DMLManager',
      'dmlInsert'
    );
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
  }

  public override void dmlUpdate(List<SObject> recordsToUpdate) {
    Logger.debug(
      'Updating ' + JSON.serializePretty(recordsToUpdate),
      'DMLManager',
      'dmlUpdate'
    );
  }

  public override void dmlUpsert(List<SObject> recordsToUpsert) {
    Logger.debug(
      'Upserting ' + JSON.serializePretty(recordsToUpsert),
      'DMLManager',
      'dmlUpsert'
    );
  }
}
