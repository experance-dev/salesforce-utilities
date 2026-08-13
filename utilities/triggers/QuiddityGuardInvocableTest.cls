/**
 * @description Unit tests for QuiddityGuardInvocable. Verifies the invocable
 *              API-quiddity check returns a valid single-element boolean list.
 * @group Triggers
 * @see QuiddityGuardInvocable
 * @author David Wood
 * @since June 2024
 * @last May 2026 — conformance refactor
 * @last August 2026 — replaced tautological assert with injected API / non-API verdict checks
 */
@IsTest
private without sharing class QuiddityGuardInvocableTest {
  /**
   * @description Verifies the invocable relays QuiddityGuard's API verdict:
   *              true when the injected quiddity is an API channel (REST),
   *              false when it is not (SYNCHRONOUS).
   */
  @IsTest
  static void testInvocableIsApiQuiddity() {
    User testUser = TestFactory.createMinAccessUser(true);

    System.runAs(testUser) {
      Test.startTest();

      QuiddityGuard.testQuiddityOverride = Quiddity.REST;
      List<Boolean> apiResult = QuiddityGuardInvocable.invocableIsApiQuiddity();

      QuiddityGuard.testQuiddityOverride = Quiddity.SYNCHRONOUS;
      List<Boolean> nonApiResult = QuiddityGuardInvocable.invocableIsApiQuiddity();

      Test.stopTest();

      Assert.areEqual(
        1,
        apiResult.size(),
        'Invocable output should contain exactly one element'
      );
      Assert.isTrue(
        apiResult[0],
        'Expected true when the current quiddity is REST (an API channel)'
      );
      Assert.areEqual(
        1,
        nonApiResult.size(),
        'Invocable output should contain exactly one element'
      );
      Assert.isFalse(
        nonApiResult[0],
        'Expected false when the current quiddity is SYNCHRONOUS (not an API channel)'
      );
    }
  }
}
