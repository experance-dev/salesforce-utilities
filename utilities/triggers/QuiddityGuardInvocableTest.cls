/**
 * @description Test class for QuiddityGuardInvocable.
 * @group Quiddity Recipes
 * @see QuiddityGuardInvocable
 * @author David Wood
 * @since June 2024
 */
@IsTest
private class QuiddityGuardInvocableTest {
  /**
   * @description Test method for invocableIsApiQuiddity.
   */
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
      System.assertNotEquals(null, result, 'Result should not be null');
      System.assertEquals(
        1,
        result.size(),
        'Result list should contain one element'
      );
      System.assert(
        result[0] == true || result[0] == false,
        'Result should be a boolean value'
      );
    }
  }
}
