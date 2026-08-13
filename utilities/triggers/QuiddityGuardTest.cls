/**
 * @description Unit tests for QuiddityGuard. Verifies trusted-quiddity detection,
 *              override mechanics, and AccessException on unacceptable quiddities.
 * @group Triggers
 * @see QuiddityGuard
 * @author David Wood
 * @since July 2024
 * @last May 2026 — conformance refactor
 * @last August 2026 — direct coverage for the SOAP and Bulk API helper checks;
 *       analyzer conformance (TRUSTED_QUIDDITIES rename follow-through)
 */
@isTest
private without sharing class QuiddityGuardTest {
  @TestSetup
  static void makeData() {
    TestFactory.createTestUser();
  }

  @isTest
  static void testQuiddityGuardFindsTestQuiddityPositive() {
    System.runAs(TestFactory.getCreatedTestUser()) {
      Test.startTest();

      // Test with a quiddity that should be in the trusted list
      Assert.isTrue(
        QuiddityGuard.isAcceptableQuiddity(QuiddityGuard.TRUSTED_QUIDDITIES),
        'Expected a current quiddity to be in the Trusted Quiddities list'
      );

      // Override with REST quiddity and test
      QuiddityGuard.testQuiddityOverride = Quiddity.REST;
      Assert.isTrue(
        QuiddityGuard.isRestQuiddity(),
        'Expected REST quiddity to be correctly identified'
      );

      // Override with SOAP quiddity and test
      QuiddityGuard.testQuiddityOverride = Quiddity.SOAP;
      Assert.isTrue(
        QuiddityGuard.isApiQuiddity(),
        'Expected SOAP quiddity to be correctly identified as an API quiddity'
      );

      // Test with a quiddity not in the acceptable list
      QuiddityGuard.testQuiddityOverride = Quiddity.INVOCABLE_ACTION;
      Assert.isTrue(
        QuiddityGuard.isNotAcceptableQuiddity(
          new List<Quiddity>{ Quiddity.SOAP }
        ),
        'Expected Invocable Action quiddity to not be in trusted quiddities list'
      );

      Test.stopTest();
    }
  }

  @isTest
  static void testQuiddityOverrideReturnsFalsePositive() {
    System.runAs(TestFactory.getCreatedTestUser()) {
      QuiddityGuard.testQuiddityOverride = Quiddity.FUTURE;
      Test.startTest();

      // Test with a quiddity that should not be in the trusted list
      Assert.isFalse(
        QuiddityGuard.isAcceptableQuiddity(QuiddityGuard.TRUSTED_QUIDDITIES),
        'Expected Future quiddity to not be in trusted quiddities list'
      );

      Test.stopTest();
    }
  }

  /**
   * @description Positive path for the SOAP and Bulk API helpers: each returns
   *              true when the injected quiddity matches its channel.
   */
  @isTest
  static void testSoapAndBulkApiHelpersIdentifyTheirQuiddities() {
    System.runAs(TestFactory.getCreatedTestUser()) {
      Test.startTest();

      QuiddityGuard.testQuiddityOverride = Quiddity.SOAP;
      Assert.isTrue(
        QuiddityGuard.isSoapQuiddity(),
        'Expected isSoapQuiddity to return true for the SOAP quiddity'
      );

      QuiddityGuard.testQuiddityOverride = Quiddity.BULK_API;
      Assert.isTrue(
        QuiddityGuard.isBulkAPIQuiddity(),
        'Expected isBulkAPIQuiddity to return true for the BULK_API quiddity'
      );
      Assert.isTrue(
        QuiddityGuard.isApiQuiddity(),
        'Expected BULK_API to be classified as an API quiddity'
      );

      Test.stopTest();
    }
  }

  /**
   * @description Negative path for the SOAP and Bulk API helpers: each returns
   *              false when the current quiddity belongs to a different channel.
   */
  @isTest
  static void testSoapAndBulkApiHelpersRejectOtherQuiddities() {
    System.runAs(TestFactory.getCreatedTestUser()) {
      Test.startTest();

      QuiddityGuard.testQuiddityOverride = Quiddity.REST;
      Assert.isFalse(
        QuiddityGuard.isSoapQuiddity(),
        'Expected isSoapQuiddity to return false for the REST quiddity'
      );
      Assert.isFalse(
        QuiddityGuard.isBulkAPIQuiddity(),
        'Expected isBulkAPIQuiddity to return false for the REST quiddity'
      );

      QuiddityGuard.testQuiddityOverride = Quiddity.SYNCHRONOUS;
      Assert.isFalse(
        QuiddityGuard.isSoapQuiddity(),
        'Expected isSoapQuiddity to return false for the SYNCHRONOUS quiddity'
      );
      Assert.isFalse(
        QuiddityGuard.isBulkAPIQuiddity(),
        'Expected isBulkAPIQuiddity to return false for the SYNCHRONOUS quiddity'
      );

      Test.stopTest();
    }
  }

  @isTest
  static void testQuiddityGuardThrowsException() {
    System.runAs(TestFactory.getCreatedTestUser()) {
      QuiddityGuard.testQuiddityOverride = Quiddity.FUTURE;
      Test.startTest();

      try {
        Assert.isTrue(
          QuiddityGuard.isAcceptableQuiddity(
            new List<Quiddity>{ Quiddity.FUTURE },
            true
          ),
          'Expected Future quiddity to be acceptable'
        );
        QuiddityGuard.isAcceptableQuiddity(
          QuiddityGuard.TRUSTED_QUIDDITIES,
          true
        );
        Assert.fail(
          'Expected AccessException to be thrown for unacceptable quiddity'
        );
      } catch (QuiddityGuard.AccessException e) {
        Assert.isTrue(
          e.getMessage().contains('Quiddity not acceptable'),
          'Expected AccessException message'
        );
      }

      Test.stopTest();
    }
  }
}
