/**
 * @description No-op DML implementation for use in tests or dry-run contexts where real DML must be
 *              suppressed. Extends SimpleDML and overrides every method to log and return immediately
 *              without touching the database.
 *              Uses `inherited sharing` to remain consistent with the DML stack sharing convention,
 *              even though no queries or DML are executed.
 * @group DML
 * @author David Wood
 * @since May 2024
 * @last May 2026 — conformance refactor; corrected copy-paste log messages
 * @last August 2026 — ApexDoc completion
 */
public inherited sharing class DMLManagerInert extends DMLManager.SimpleDML {
  /**
   * @description Logs the would-be delete and returns without touching the database.
   * @param recordsToDelete The records the caller asked to delete.
   */
  public override void dmlDelete(List<SObject> recordsToDelete) {
    Logger.debug(
      'Deleting ' + JSON.serializePretty(recordsToDelete),
      'DMLManager',
      'dmlDelete'
    );
  }

  /**
   * @description Logs the would-be insert and returns without touching the database.
   * @param recordsToInsert The records the caller asked to insert.
   */
  public override void dmlInsert(List<SObject> recordsToInsert) {
    Logger.debug(
      'Inserting ' + JSON.serializePretty(recordsToInsert),
      'DMLManager',
      'dmlInsert'
    );
  }

  /**
   * @description Logs the would-be merge and returns without touching the database.
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
  }

  /**
   * @description Logs the would-be update and returns without touching the database.
   * @param recordsToUpdate The records the caller asked to update.
   */
  public override void dmlUpdate(List<SObject> recordsToUpdate) {
    Logger.debug(
      'Updating ' + JSON.serializePretty(recordsToUpdate),
      'DMLManager',
      'dmlUpdate'
    );
  }

  /**
   * @description Logs the would-be upsert and returns without touching the database.
   * @param recordsToUpsert The records the caller asked to upsert.
   */
  public override void dmlUpsert(List<SObject> recordsToUpsert) {
    Logger.debug(
      'Upserting ' + JSON.serializePretty(recordsToUpsert),
      'DMLManager',
      'dmlUpsert'
    );
  }
}
