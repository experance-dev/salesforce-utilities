/**
 * @description Unit tests for QuiddityGuard. Pins the immutable membership-check
 *              surface (isTrusted / isUntrusted / isTestQuiddity), the current-context
 *              conveniences, override mechanics, channel identifiers, and
 *              AccessException escalation on untrusted or unacceptable quiddities.
 * @group Triggers
 * @see QuiddityGuard
 * @author David Wood
 * @since July 2024
 * @last May 2026 — conformance refactor
 * @last 2026-08-13 — coverage moved onto the membership-check surface after the trust
 *       lists went private; direct pins for isTrusted / isUntrusted / isTestQuiddity
 */
@isTest
private without sharing class QuiddityGuardTest {
  @TestSetup
  static void makeData() {
    TestFactory.createTestUser();
  }

  /**
   * @description A real test run executes under a RUNTEST_* quiddity, so the
   *              current-context check reports trusted without any override.
   */
  @isTest
  static void testCurrentQuiddityIsTrustedInTestContext() {
    System.runAs(TestFactory.getCreatedTestUser()) {
      Test.startTest();

      Assert.isTrue(
        QuiddityGuard.isCurrentQuiddityTrusted(),
        'Expected the test-runner quiddity to be classified as a trusted channel'
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
        'Expected Invocable Action quiddity to not be in the supplied accept list'
      );

      Test.stopTest();
    }
  }

  /**
   * @description Pins the membership verdicts of the three private trust lists
   *              through their public membership-check methods: trusted channels
   *              report trusted, externally reachable entry points report
   *              untrusted, and only RUNTEST_* quiddities report test execution.
   */
  @isTest
  static void testMembershipChecksClassifyChannels() {
    System.runAs(TestFactory.getCreatedTestUser()) {
      Test.startTest();

      Assert.isTrue(
        QuiddityGuard.isTrusted(Quiddity.BATCH_APEX),
        'Expected BATCH_APEX to be a trusted channel'
      );
      Assert.isTrue(
        QuiddityGuard.isTrusted(Quiddity.RUNTEST_SYNC),
        'Expected RUNTEST_SYNC to be a trusted channel'
      );
      Assert.isFalse(
        QuiddityGuard.isTrusted(Quiddity.REST),
        'Expected REST to NOT be a trusted channel'
      );

      Assert.isTrue(
        QuiddityGuard.isUntrusted(Quiddity.REST),
        'Expected REST to be an untrusted, externally reachable channel'
      );
      Assert.isTrue(
        QuiddityGuard.isUntrusted(Quiddity.AURA),
        'Expected AURA to be an untrusted, externally reachable channel'
      );
      Assert.isFalse(
        QuiddityGuard.isUntrusted(Quiddity.QUEUEABLE),
        'Expected QUEUEABLE to NOT be an untrusted channel'
      );

      Assert.isTrue(
        QuiddityGuard.isTestQuiddity(Quiddity.RUNTEST_ASYNC),
        'Expected RUNTEST_ASYNC to be classified as a test execution'
      );
      Assert.isFalse(
        QuiddityGuard.isTestQuiddity(Quiddity.SYNCHRONOUS),
        'Expected SYNCHRONOUS to NOT be classified as a test execution'
      );

      Test.stopTest();
    }
  }

  /**
   * @description Negative path for the current-context trusted check: a quiddity
   *              outside the trusted set (FUTURE) reports untrusted.
   */
  @isTest
  static void testQuiddityOverrideReturnsFalsePositive() {
    System.runAs(TestFactory.getCreatedTestUser()) {
      QuiddityGuard.testQuiddityOverride = Quiddity.FUTURE;
      Test.startTest();

      Assert.isFalse(
        QuiddityGuard.isCurrentQuiddityTrusted(),
        'Expected Future quiddity to not be classified as a trusted channel'
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

  /**
   * @description Caller-supplied accept-list escalation: an accepted quiddity
   *              returns true, and a rejected quiddity with throwError=true
   *              raises AccessException.
   */
  @isTest
  static void testAcceptListEscalatesRejectionToException() {
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
          new List<Quiddity>{ Quiddity.SYNCHRONOUS, Quiddity.BATCH_APEX },
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

  /**
   * @description Trusted-channel escalation: an untrusted quiddity with
   *              throwError=true raises AccessException, while throwError=false
   *              reports false without throwing.
   */
  @isTest
  static void testCurrentQuiddityTrustedEscalatesToException() {
    System.runAs(TestFactory.getCreatedTestUser()) {
      QuiddityGuard.testQuiddityOverride = Quiddity.REST;
      Test.startTest();

      Assert.isFalse(
        QuiddityGuard.isCurrentQuiddityTrusted(false),
        'Expected REST to report untrusted without throwing when throwError is false'
      );

      try {
        QuiddityGuard.isCurrentQuiddityTrusted(true);
        Assert.fail(
          'Expected AccessException to be thrown for an untrusted quiddity'
        );
      } catch (QuiddityGuard.AccessException e) {
        Assert.isTrue(
          e.getMessage().contains('Quiddity not acceptable'),
          'Expected AccessException message to name the rejected quiddity check'
        );
      }

      Test.stopTest();
    }
  }
}
