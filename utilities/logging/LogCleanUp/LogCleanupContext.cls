/**
 * @description Provides log-retention configuration for the log-cleanup pipeline.
 *              Reads `Log_Clean_Up__mdt` custom metadata and returns a map of
 *              SObject API name → retention days; override in tests via
 *              `MockLogCleanupContext`. Malformed rows — blank `Log_Name__c` or
 *              missing `Delete_Logs_After__c` — are logged and skipped so one
 *              bad config row can never stall the whole cleanup run.
 * @group LogCleanup
 * @author David Wood
 * @since November 2024
 * @last May 2026 — conformance refactor: explicit sharing, header, method-level ApexDoc pruned.
 * @last August 2026 — malformed Log_Clean_Up__mdt rows are skipped and logged
 *                      instead of throwing.
 */
public virtual inherited sharing class LogCleanupContext {
  /**
   * @description Retrieves log-retention days from `Log_Clean_Up__mdt` custom metadata.
   *
   * @return Map of SObject API names to their configured retention days;
   *         malformed rows are omitted.
   */
  public virtual Map<String, Integer> getLogRetentionDays() {
    return buildRetentionMap(Log_Clean_Up__mdt.getAll().values());
  }

  /**
   * @description Encodes the row-validity rule: a `Log_Clean_Up__mdt` row is
   *              usable only when `Log_Name__c` is non-blank and
   *              `Delete_Logs_After__c` is populated. Anything else is a
   *              malformed row — logged via `Logger.warn` and skipped, never
   *              thrown on. (`Delete_Logs_After__c` is a Number field, so a
   *              non-numeric value can only manifest as null/blank.)
   *
   * @param rows The CMDT rows to fold into the retention map.
   * @return Map of SObject API names to retention days, malformed rows omitted.
   */
  @TestVisible
  private static Map<String, Integer> buildRetentionMap(
    List<Log_Clean_Up__mdt> rows
  ) {
    Map<String, Integer> logRetentionDays = new Map<String, Integer>();
    for (Log_Clean_Up__mdt row : rows) {
      if (String.isBlank(row.Log_Name__c) || row.Delete_Logs_After__c == null) {
        Logger.warn(
          'Skipping malformed Log_Clean_Up__mdt row "' +
            row.DeveloperName +
            '" — Log_Name__c and Delete_Logs_After__c are both required.',
          'LogCleanupContext',
          'buildRetentionMap'
        );
        continue;
      }
      logRetentionDays.put(
        row.Log_Name__c,
        Integer.valueOf(row.Delete_Logs_After__c)
      );
    }
    return logRetentionDays;
  }
}
