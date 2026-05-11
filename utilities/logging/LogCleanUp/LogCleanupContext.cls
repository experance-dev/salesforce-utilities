/**
 * @description This class provides a context for log cleanup.
 * @group Log Management
 * @see LogCleanupBatch.cls
 * @author David Wood
 * @since November 2024
 * @last November 2024 - Created class.
 */

public virtual class LogCleanupContext {
  /**
   * @description Retrieves log retention days from custom metadata.
   * @group Log Management
   * @see LogCleanupContext.cls
   * @since November 2024
   * @last November 2024 - Updated method documentation.
   *
   * @return Map of log object names to their respective retention days.
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
