/**
 * @description Provides log-retention configuration for the log-cleanup pipeline.
 *              Reads `Log_Clean_Up__mdt` custom metadata and returns a map of
 *              SObject API name → retention days; override in tests via
 *              `MockLogCleanupContext`.
 * @group LogCleanup
 * @author David Wood
 * @since November 2024
 * @last May 2026 — conformance refactor: explicit sharing, header, method-level ApexDoc pruned.
 */
public virtual inherited sharing class LogCleanupContext {
  /**
   * @description Retrieves log-retention days from `Log_Clean_Up__mdt` custom metadata.
   *
   * @return Map of SObject API names to their configured retention days.
   */
  public virtual Map<String, Integer> getLogRetentionDays() {
    Map<String, Integer> logRetentionDays = new Map<String, Integer>();
    for (Log_Clean_Up__mdt config : Log_Clean_Up__mdt.getAll().values()) {
      logRetentionDays.put(
        config.Log_Name__c,
        Integer.valueOf(config.Delete_Logs_After__c)
      );
    }
    return logRetentionDays;
  }
}
