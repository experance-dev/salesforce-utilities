/**
 * @description Unit tests for QuiddityGuardInvocable. Verifies the invocable
 *              API-quiddity check returns a valid single-element boolean list.
 * @group Triggers
 * @see QuiddityGuardInvocable
 * @author David Wood
 * @since June 2024
 * @last May 2026 — Wave 6 conformance
 */
@IsTest
private without sharing class QuiddityGuardInvocableTest {
  @IsTest
  static void testInvocableIsApiQuiddity() {
    // Create a standard user
    User testUser = TestFactory.createMinAccessUser(true);

    // Run test as the standard user
    System.runAs(testUser) {
      // Test the invocable method for API quiddity check
      Test.startTest();
      List<Boolean> result = QuiddityGuardInvocable.invocableIsApiQuiddity();
      Test.stopTest();

      // Assert that the result is not null and contains a boolean value
      Assert.isNotNull(result, 'Result should not be null');
      Assert.areEqual(
        1,
        result.size(),
        'Result list should contain one element'
      );
      Assert.isTrue(
        result[0] == true || result[0] == false,
        'Result should be a boolean value'
      );
    }
  }
}
