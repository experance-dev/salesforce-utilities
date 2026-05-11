/**
 * @description Test double for `LogCleanupContext`; returns caller-supplied
 *              retention data so batch tests never touch custom metadata.
 * @group LogCleanup
 * @author David Wood
 * @since November 2024
 * @last May 2026 — conformance refactor: explicit sharing, header cleanup.
 */
@IsTest
public without sharing class MockLogCleanupContext extends LogCleanupContext {
  private Map<String, Integer> mockRetentionDays;

  /**
   * @description Constructs the mock with a fixed retention map.
   *
   * @param mockRetentionDays Map of SObject API names to retention days to return.
   */
  public MockLogCleanupContext(Map<String, Integer> mockRetentionDays) {
    this.mockRetentionDays = mockRetentionDays;
  }

  /** @return The retention map supplied at construction time. */
  public override Map<String, Integer> getLogRetentionDays() {
    return mockRetentionDays;
  }
}
