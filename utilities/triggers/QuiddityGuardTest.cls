@isTest
private class QuiddityGuardTest {
  @TestSetup
  static void makeData() {
    TestFactory.createTestUser();
  }
  /**
   * @description Test to verify that QuiddityGuard identifies trusted quiddities correctly.
   */
  @isTest
  static void testQuiddityGuardFindsTestQuiddityPositive() {
    System.runAs(TestFactory.getCreatedTestUser()) {
      Test.startTest();

      // Test with a quiddity that should be in the trusted list
      Assert.isTrue(
        QuiddityGuard.isAcceptableQuiddity(QuiddityGuard.trustedQuiddities),
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

  /**
   * @description Test to verify that QuiddityGuard correctly identifies quiddities not in the trusted list.
   */
  @isTest
  static void testQuiddityOverrideReturnsFalsePositive() {
    System.runAs(TestFactory.getCreatedTestUser()) {
      QuiddityGuard.testQuiddityOverride = Quiddity.FUTURE;
      Test.startTest();

      // Test with a quiddity that should not be in the trusted list
      Assert.isFalse(
        QuiddityGuard.isAcceptableQuiddity(QuiddityGuard.trustedQuiddities),
        'Expected Future quiddity to not be in trusted quiddities list'
      );

      Test.stopTest();
    }
  }

  /**
   * @description Test to verify that QuiddityGuard throws an exception when throwError is true and quiddity is not acceptable.
   */
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
          QuiddityGuard.trustedQuiddities,
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
