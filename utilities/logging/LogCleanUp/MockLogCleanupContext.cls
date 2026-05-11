/**
 * @description Mock implementation of LogCleanupContext for testing purposes.
 * @group Log Management
 * @author David
 * @since November 2024
 * @last November 2024 - Updated class annotations.
 */
@IsTest
public class MockLogCleanupContext extends LogCleanupContext {
  private Map<String, Integer> mockRetentionDays;

  /**
   * @description Constructor for MockLogCleanupContext.
   *
   * @param mockRetentionDays A map containing retention days for different log types.
   */
  public MockLogCleanupContext(Map<String, Integer> mockRetentionDays) {
    this.mockRetentionDays = mockRetentionDays;
  }

  /**
   * @description Overrides the retention days retrieval to return mock data.
   *
   * @return Map of log object names to their respective mock retention days.
   */
  public override Map<String, Integer> getLogRetentionDays() {
    return mockRetentionDays;
  }
}
