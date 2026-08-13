/**
 * @description Pins TestFactory's identity-safe user and permission-set resolution: exact-Name
 *              permission-set matching (missing and ambiguous Names throw), the
 *              assignPermSetIfPresent skip-when-absent escape hatch, exactly-one enforcement on
 *              getCreatedTestUser, and precise rediscovery via getTestUserByUsername. These pins
 *              exist because the previous resolution shape (LIKE + first result, most-recent user
 *              by shared LastName) could run a security test under the wrong identity.
 * @group Testing
 * @see TestFactory
 * @author David Wood
 * @since August 2026
 * @last 2026-08-13 — initial pinning coverage for exact-match / missing / ambiguous / if-present / created-identity paths.
 */
@IsTest
private class TestFactoryTest {
  private static final String ADMIN_PROFILE = 'System Administrator';

  @TestSetup
  static void setup() {
    // Setup-object DML boundary: TestFactory.createTestUser wraps its own insert in
    // System.runAs(admin) internally, so no explicit runAs is needed here.
    TestFactory.createTestUser(true, ADMIN_PROFILE);
  }

  // ── assignPermSetToUser ──────────────────────────────────────────────────

  /** @description Exact-Name match resolves the one permission set and assigns it to the user. */
  @IsTest
  static void testAssignPermSetExactMatchAssignsPermissionSet() {
    System.runAs(TestFactory.getTestUser(ADMIN_PROFILE)) {
      PermissionSet permSet = insertUniquePermissionSet();
      User assignee = TestFactory.createMinAccessUser(true);

      TestFactory.assignPermSetToUser(assignee, permSet.Name);

      List<PermissionSetAssignment> assignments = [
        SELECT Id
        FROM PermissionSetAssignment
        WHERE AssigneeId = :assignee.Id AND PermissionSetId = :permSet.Id
      ];
      Assert.areEqual(
        1,
        assignments.size(),
        'Expected exactly one assignment of the exactly-named permission set to the created user.'
      );
    }
  }

  /** @description A permission set Name with no exact match throws a descriptive TestFactoryException instead of no-oping. */
  @IsTest
  static void testAssignPermSetMissingNameThrowsDescriptiveException() {
    System.runAs(TestFactory.getTestUser(ADMIN_PROFILE)) {
      User assignee = TestFactory.createMinAccessUser(true);
      String missingName = 'TFPinMissing' + Utilities.generateRandomCounter();

      try {
        TestFactory.assignPermSetToUser(assignee, missingName);
        Assert.fail(
          'Expected TestFactoryException for a permission set Name with no exact match.'
        );
      } catch (TestFactory.TestFactoryException e) {
        Assert.isTrue(
          e.getMessage().contains(missingName),
          'Expected the exception message to name the missing permission set. Got: ' +
          e.getMessage()
        );
      }
    }
  }

  /** @description A Name matching more than one permission set (namespace collision) throws instead of assigning an arbitrary match. */
  @IsTest
  static void testAssignPermSetAmbiguousNameThrows() {
    System.runAs(TestFactory.getTestUser(ADMIN_PROFILE)) {
      // PermissionSet.Name is unique per namespace, so a real collision can't be fabricated
      // here — inject the ambiguous result through the factory's query seam instead.
      TestFactory.permissionSetQueryOverride = new List<PermissionSet>{
        new PermissionSet(Id = Utilities.getFakeId(PermissionSet.SObjectType)),
        new PermissionSet(Id = Utilities.getFakeId(PermissionSet.SObjectType))
      };
      User assignee = new User(Id = Utilities.getFakeId(User.SObjectType));

      try {
        TestFactory.assignPermSetToUser(assignee, 'TFPinAmbiguous');
        Assert.fail(
          'Expected TestFactoryException when the Name matches more than one permission set.'
        );
      } catch (TestFactory.TestFactoryException e) {
        Assert.isTrue(
          e.getMessage().contains('ambiguous'),
          'Expected the exception message to call out the ambiguity. Got: ' +
          e.getMessage()
        );
      } finally {
        TestFactory.permissionSetQueryOverride = null;
      }
    }
  }

  // ── assignPermSetIfPresent ───────────────────────────────────────────────

  /** @description The if-present variant skips silently — returns false, assigns nothing, throws nothing — when the permission set is absent. */
  @IsTest
  static void testAssignPermSetIfPresentMissingNameSkipsSilently() {
    System.runAs(TestFactory.getTestUser(ADMIN_PROFILE)) {
      User assignee = TestFactory.createMinAccessUser(true);
      String missingName = 'TFPinAbsent' + Utilities.generateRandomCounter();

      Boolean assigned = TestFactory.assignPermSetIfPresent(
        assignee,
        missingName
      );

      Assert.isFalse(
        assigned,
        'Expected assignPermSetIfPresent to report false for an absent permission set.'
      );
      List<PermissionSetAssignment> assignments = [
        SELECT Id
        FROM PermissionSetAssignment
        WHERE AssigneeId = :assignee.Id AND PermissionSet.IsOwnedByProfile = FALSE
      ];
      Assert.areEqual(
        0,
        assignments.size(),
        'Expected no permission set assignment when the named set is absent.'
      );
    }
  }

  /** @description The if-present variant assigns and returns true when the exactly-named permission set exists. */
  @IsTest
  static void testAssignPermSetIfPresentExactMatchAssigns() {
    System.runAs(TestFactory.getTestUser(ADMIN_PROFILE)) {
      PermissionSet permSet = insertUniquePermissionSet();
      User assignee = TestFactory.createMinAccessUser(true);

      Boolean assigned = TestFactory.assignPermSetIfPresent(
        assignee,
        permSet.Name
      );

      Assert.isTrue(
        assigned,
        'Expected assignPermSetIfPresent to report true when the permission set exists.'
      );
      List<PermissionSetAssignment> assignments = [
        SELECT Id
        FROM PermissionSetAssignment
        WHERE AssigneeId = :assignee.Id AND PermissionSetId = :permSet.Id
      ];
      Assert.areEqual(
        1,
        assignments.size(),
        'Expected the if-present variant to create the assignment when the set exists.'
      );
    }
  }

  /** @description The if-present variant still throws on an ambiguous Name — silent skip is only for absence, never for ambiguity. */
  @IsTest
  static void testAssignPermSetIfPresentAmbiguousNameThrows() {
    System.runAs(TestFactory.getTestUser(ADMIN_PROFILE)) {
      TestFactory.permissionSetQueryOverride = new List<PermissionSet>{
        new PermissionSet(Id = Utilities.getFakeId(PermissionSet.SObjectType)),
        new PermissionSet(Id = Utilities.getFakeId(PermissionSet.SObjectType))
      };
      User assignee = new User(Id = Utilities.getFakeId(User.SObjectType));

      try {
        TestFactory.assignPermSetIfPresent(assignee, 'TFPinAmbiguous');
        Assert.fail(
          'Expected TestFactoryException — ambiguity must throw even in the if-present variant.'
        );
      } catch (TestFactory.TestFactoryException e) {
        Assert.isTrue(
          e.getMessage().contains('ambiguous'),
          'Expected the exception message to call out the ambiguity. Got: ' +
          e.getMessage()
        );
      } finally {
        TestFactory.permissionSetQueryOverride = null;
      }
    }
  }

  // ── getCreatedTestUser / getTestUserByUsername ───────────────────────────

  /** @description createTestUser() returns the created identity directly, and getCreatedTestUser() resolves that exact user — not a most-recent guess. */
  @IsTest
  static void testCreateTestUserReturnsCreatedIdentity() {
    User created = TestFactory.createTestUser();

    System.runAs(TestFactory.getTestUser(ADMIN_PROFILE)) {
      User resolved = TestFactory.getCreatedTestUser();
      Assert.areEqual(
        created.Id,
        resolved.Id,
        'Expected getCreatedTestUser to resolve the exact user createTestUser returned.'
      );
    }
  }

  /** @description getCreatedTestUser throws a descriptive exception when no user holds the permission set, instead of returning an arbitrary user. */
  @IsTest
  static void testGetCreatedTestUserNoHolderThrows() {
    System.runAs(TestFactory.getTestUser(ADMIN_PROFILE)) {
      String unheldName = 'TFPinUnheld' + Utilities.generateRandomCounter();

      try {
        TestFactory.getCreatedTestUser(unheldName);
        Assert.fail(
          'Expected TestFactoryException when no user holds the permission set.'
        );
      } catch (TestFactory.TestFactoryException e) {
        Assert.isTrue(
          e.getMessage().contains(unheldName),
          'Expected the exception message to name the unheld permission set. Got: ' +
          e.getMessage()
        );
      }
    }
  }

  /** @description getCreatedTestUser throws when multiple users hold the permission set — an ambiguous identity is never silently picked. */
  @IsTest
  static void testGetCreatedTestUserAmbiguousHoldersThrows() {
    System.runAs(TestFactory.getTestUser(ADMIN_PROFILE)) {
      PermissionSet permSet = insertUniquePermissionSet();
      TestFactory.assignPermSetToUser(
        TestFactory.createMinAccessUser(true),
        permSet.Name
      );
      TestFactory.assignPermSetToUser(
        TestFactory.createMinAccessUser(true),
        permSet.Name
      );

      try {
        TestFactory.getCreatedTestUser(permSet.Name);
        Assert.fail(
          'Expected TestFactoryException when two users hold the permission set.'
        );
      } catch (TestFactory.TestFactoryException e) {
        Assert.isTrue(
          e.getMessage().contains('ambiguous'),
          'Expected the exception message to call out the ambiguous identity. Got: ' +
          e.getMessage()
        );
      }
    }
  }

  /** @description getTestUserByUsername resolves the exact created user through its org-unique Username. */
  @IsTest
  static void testGetTestUserByUsernameResolvesExactUser() {
    System.runAs(TestFactory.getTestUser(ADMIN_PROFILE)) {
      User created = TestFactory.createMinAccessUser(true);

      User resolved = TestFactory.getTestUserByUsername(created.Username);

      Assert.areEqual(
        created.Id,
        resolved.Id,
        'Expected the Username lookup to resolve the exact created user.'
      );
    }
  }

  /** @description getTestUserByUsername throws a descriptive exception for an unknown Username. */
  @IsTest
  static void testGetTestUserByUsernameMissingThrows() {
    System.runAs(TestFactory.getTestUser(ADMIN_PROFILE)) {
      String missingUsername =
        'tfpin.missing.' +
        Utilities.generateRandomCounter() +
        '@test.example.com';

      try {
        TestFactory.getTestUserByUsername(missingUsername);
        Assert.fail('Expected TestFactoryException for an unknown Username.');
      } catch (TestFactory.TestFactoryException e) {
        Assert.isTrue(
          e.getMessage().contains(missingUsername),
          'Expected the exception message to name the missing Username. Got: ' +
          e.getMessage()
        );
      }
    }
  }

  // ── Private helpers ──────────────────────────────────────────────────────

  private static PermissionSet insertUniquePermissionSet() {
    String randomizer = Utilities.generateRandomCounter();
    PermissionSet permSet = new PermissionSet(
      Name = 'TFPin' + randomizer,
      Label = 'TestFactory Pinning ' + randomizer
    );
    Database.insert(permSet, AccessLevel.SYSTEM_MODE);
    return permSet;
  }
}
