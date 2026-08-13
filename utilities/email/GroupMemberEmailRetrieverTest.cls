/**
 * @description Test class for GroupMemberEmailRetriever. Pins the authorization acknowledgment
 *              at the public boundary, input trim/validation, the active-user and non-blank-email
 *              member filter, the nested-group depth boundary (inclusive at the max, exclusive
 *              one level deeper), and call-to-call independence of the traversal state.
 *              Note: User.Email is required by the platform, so the non-blank-email member filter
 *              cannot be exercised with a genuinely blank-email user; it is pinned by asserting
 *              the resolved set never carries a null or blank entry.
 * @group Email
 * @see GroupMemberEmailRetriever
 * @author David Wood
 * @since March 2024
 * @last May 2026 — conformance refactor
 * @last 2026-08-13 — pins for use-case acknowledgment, input normalization, inactive-user
 *                    exclusion, depth boundary, and instance-local traversal state
 */
@isTest
public without sharing class GroupMemberEmailRetrieverTest {
  static final String TEST_GROUP_NAME = 'group0';
  static final String TEST_JUNK = 'junk';
  static final String DIRECT_EMAIL = 'other@mailinator.com';
  static final String GROUP_MEMBER_EMAIL_1 = 'groupmember1@mailinator.com';
  static final String GROUP_MEMBER_EMAIL_2 = 'groupmember2@mailinator.com';
  static final String NESTED_MEMBER_EMAIL = 'nestedmember@mailinator.com';
  static final String DEEP_MEMBER_EMAIL = 'deepmember@mailinator.com';
  // Sits in group7, exactly MAX_NESTED_GROUP_DEPTH (5) nesting levels below group0 — included.
  static final String DEPTH_BOUNDARY_EMAIL = 'depthboundarymember@mailinator.com';
  // Sits in group8, six nesting levels below group0 — one past the depth guard, excluded.
  static final String BEYOND_DEPTH_EMAIL = 'beyonddepthmember@mailinator.com';
  // Direct member of group0 deactivated after setup — excluded by the active-user filter.
  static final String INACTIVE_MEMBER_EMAIL = 'inactivemember@mailinator.com';

  @TestSetup
  static void makeData() {
    // User, Group, and GroupMember are setup objects — all of their DML runs under an
    // explicit admin context so the MIXED_DML boundary holds regardless of org automation.
    User adminUser = TestFactory.createTestUser(true, 'System Administrator');

    List<String> memberEmails = new List<String>{
      GROUP_MEMBER_EMAIL_1,
      GROUP_MEMBER_EMAIL_2,
      NESTED_MEMBER_EMAIL,
      DEEP_MEMBER_EMAIL,
      DEPTH_BOUNDARY_EMAIL,
      BEYOND_DEPTH_EMAIL,
      INACTIVE_MEMBER_EMAIL
    };
    List<User> users = new List<User>();
    for (String memberEmail : memberEmails) {
      User newUser = TestFactory.createTestUser(false, 'Standard User');
      newUser.Email = memberEmail;
      users.add(newUser);
    }

    List<Group> groups = new List<Group>();
    for (Integer i = 0; i <= 8; i++) {
      Group newGroup = new Group();
      newGroup.Name = 'group' + i;
      newGroup.DeveloperName = 'group' + i;
      groups.add(newGroup);
    }

    System.runAs(adminUser) {
      insert users;
      TestFactory.createMinAccessUser(true);
      insert groups;
    }

    // User memberships. Nesting chain: group0 -> group3 -> group4 -> group5 -> group6
    // -> group7 -> group8; also group0 -> group1 -> group2 and the revisit edge group3 -> group1.
    List<GroupMember> groupMembers = new List<GroupMember>();
    groupMembers.add(
      new GroupMember(GroupId = groups[0].Id, UserOrGroupId = users[0].Id)
    );
    groupMembers.add(
      new GroupMember(GroupId = groups[0].Id, UserOrGroupId = users[1].Id)
    );
    groupMembers.add(
      new GroupMember(GroupId = groups[1].Id, UserOrGroupId = users[2].Id)
    );
    groupMembers.add(
      new GroupMember(GroupId = groups[2].Id, UserOrGroupId = users[3].Id)
    );
    groupMembers.add(
      new GroupMember(GroupId = groups[7].Id, UserOrGroupId = users[4].Id)
    );
    groupMembers.add(
      new GroupMember(GroupId = groups[8].Id, UserOrGroupId = users[5].Id)
    );
    groupMembers.add(
      new GroupMember(GroupId = groups[0].Id, UserOrGroupId = users[6].Id)
    );

    // Group-in-group memberships.
    groupMembers.add(
      new GroupMember(GroupId = groups[0].Id, UserOrGroupId = groups[1].Id)
    );
    groupMembers.add(
      new GroupMember(GroupId = groups[1].Id, UserOrGroupId = groups[2].Id)
    );
    groupMembers.add(
      new GroupMember(GroupId = groups[0].Id, UserOrGroupId = groups[3].Id)
    );
    groupMembers.add(
      new GroupMember(GroupId = groups[3].Id, UserOrGroupId = groups[4].Id)
    );
    groupMembers.add(
      new GroupMember(GroupId = groups[4].Id, UserOrGroupId = groups[5].Id)
    );
    groupMembers.add(
      new GroupMember(GroupId = groups[5].Id, UserOrGroupId = groups[6].Id)
    );
    groupMembers.add(
      new GroupMember(GroupId = groups[6].Id, UserOrGroupId = groups[7].Id)
    );
    groupMembers.add(
      new GroupMember(GroupId = groups[7].Id, UserOrGroupId = groups[8].Id)
    );
    // Revisit edge: group1 is reachable twice; the visited guard must not double-process it.
    groupMembers.add(
      new GroupMember(GroupId = groups[3].Id, UserOrGroupId = groups[1].Id)
    );

    System.runAs(adminUser) {
      insert groupMembers;
      // Deactivate after membership insert so the membership itself is never in question —
      // this user pins the active-user filter, not GroupMember insert rules.
      users[6].IsActive = false;
      update users[6];
    }
  }

  /**
   * @description Full resolution through nested groups: direct address kept, junk tolerated,
   *              five in-depth active members resolved, and no blank or null entry ever surfaces.
   */
  @isTest
  static void testResolvesNestedGroupMembership() {
    List<String> toAddresses = new List<String>{
      DIRECT_EMAIL,
      TEST_GROUP_NAME,
      TEST_JUNK
    };

    Set<String> emails;
    Test.startTest();
    System.runAs(TestFactory.getMinAccessUser()) {
      emails = GroupMemberEmailRetriever.processMixedInputs(
        toAddresses,
        GroupMemberEmailRetriever.PrivilegedUseCase.SYSTEM_NOTIFICATION
      );
    }
    Test.stopTest();

    Assert.areEqual(
      6,
      emails.size(),
      'Expected the direct address plus the five active, in-depth group members.'
    );
    Assert.isTrue(
      emails.contains(DIRECT_EMAIL),
      'The direct address should pass through to the result.'
    );
    Assert.isTrue(
      emails.contains(GROUP_MEMBER_EMAIL_1) &&
        emails.contains(GROUP_MEMBER_EMAIL_2),
      'Direct group0 members should be resolved.'
    );
    Assert.isTrue(
      emails.contains(NESTED_MEMBER_EMAIL) &&
        emails.contains(DEEP_MEMBER_EMAIL),
      'Members of nested groups within the depth limit should be resolved.'
    );
    Assert.isFalse(
      emails.contains(null) || emails.contains(''),
      'The resolved set must never carry a null or blank email entry.'
    );
  }

  /**
   * @description A deactivated user who is still a group member contributes no address.
   */
  @isTest
  static void testInactiveUserExcluded() {
    Set<String> emails;
    Test.startTest();
    System.runAs(TestFactory.getMinAccessUser()) {
      emails = GroupMemberEmailRetriever.processMixedInputs(
        new List<String>{ TEST_GROUP_NAME },
        GroupMemberEmailRetriever.PrivilegedUseCase.OPERATIONAL_ALERT
      );
    }
    Test.stopTest();

    Assert.isFalse(
      emails.contains(INACTIVE_MEMBER_EMAIL),
      'A deactivated group member must be excluded from the resolved set.'
    );
    Assert.isTrue(
      emails.contains(GROUP_MEMBER_EMAIL_1),
      'Active members of the same group should still be resolved.'
    );
  }

  /**
   * @description Depth boundary is inclusive at MAX_NESTED_GROUP_DEPTH (group7, five nesting
   *              levels down) and exclusive one level deeper (group8).
   */
  @isTest
  static void testDepthBoundaryInclusiveAtMaxExclusiveBeyond() {
    Set<String> emails;
    Test.startTest();
    System.runAs(TestFactory.getMinAccessUser()) {
      emails = GroupMemberEmailRetriever.processMixedInputs(
        new List<String>{ TEST_GROUP_NAME },
        GroupMemberEmailRetriever.PrivilegedUseCase.SYSTEM_NOTIFICATION
      );
    }
    Test.stopTest();

    Assert.isTrue(
      emails.contains(DEPTH_BOUNDARY_EMAIL),
      'A member exactly at the maximum nested depth must be included.'
    );
    Assert.isFalse(
      emails.contains(BEYOND_DEPTH_EMAIL),
      'A member one level past the maximum nested depth must be excluded.'
    );
  }

  /**
   * @description Inputs are trimmed before classification; blank, null, and malformed '@'
   *              entries are dropped; padded group names still resolve.
   */
  @isTest
  static void testInputNormalization() {
    List<String> toAddresses = new List<String>{
      '  ' + DIRECT_EMAIL + '  ',
      '   ',
      null,
      ' ' + TEST_GROUP_NAME + ' ',
      '@',
      'trailingat@'
    };

    Set<String> emails;
    Test.startTest();
    System.runAs(TestFactory.getMinAccessUser()) {
      emails = GroupMemberEmailRetriever.processMixedInputs(
        toAddresses,
        GroupMemberEmailRetriever.PrivilegedUseCase.ADMIN_BROADCAST
      );
    }
    Test.stopTest();

    Assert.isTrue(
      emails.contains(DIRECT_EMAIL),
      'A padded direct address should be trimmed and kept.'
    );
    Assert.isTrue(
      emails.contains(GROUP_MEMBER_EMAIL_1),
      'A padded group developer name should be trimmed and still resolve.'
    );
    Assert.isFalse(
      emails.contains('@') || emails.contains('trailingat@'),
      'Malformed address-shaped entries must be dropped, not forwarded.'
    );
    Assert.areEqual(
      6,
      emails.size(),
      'Only the trimmed direct address and the five active group members should remain.'
    );
  }

  /**
   * @description The privileged path demands an explicit acknowledgment — a null use case
   *              is rejected before any query runs.
   */
  @isTest
  static void testNullUseCaseThrows() {
    Test.startTest();
    System.runAs(TestFactory.getMinAccessUser()) {
      try {
        GroupMemberEmailRetriever.processMixedInputs(
          new List<String>{ TEST_GROUP_NAME },
          null
        );
        Assert.fail(
          'A null PrivilegedUseCase acknowledgment must throw, not resolve.'
        );
      } catch (IllegalArgumentException e) {
        Assert.isTrue(
          e.getMessage().contains('PrivilegedUseCase'),
          'The rejection should name the missing acknowledgment.'
        );
      }
    }
    Test.stopTest();
  }

  /**
   * @description Null and empty input lists resolve to an empty set without error.
   */
  @isTest
  static void testNullAndEmptyInputs() {
    Test.startTest();
    System.runAs(TestFactory.getMinAccessUser()) {
      Set<String> emails = GroupMemberEmailRetriever.processMixedInputs(
        new List<String>(),
        GroupMemberEmailRetriever.PrivilegedUseCase.SYSTEM_NOTIFICATION
      );
      Assert.areEqual(0, emails.size(), 'An empty input list resolves to an empty set.');

      emails = GroupMemberEmailRetriever.processMixedInputs(
        null,
        GroupMemberEmailRetriever.PrivilegedUseCase.SYSTEM_NOTIFICATION
      );
      Assert.areEqual(0, emails.size(), 'A null input list resolves to an empty set.');
    }
    Test.stopTest();
  }

  /**
   * @description Traversal state is instance-local — repeated calls return identical results
   *              with no leakage from the previous traversal.
   */
  @isTest
  static void testRepeatedCallsAreIndependent() {
    Set<String> firstCall;
    Set<String> secondCall;
    Test.startTest();
    System.runAs(TestFactory.getMinAccessUser()) {
      firstCall = GroupMemberEmailRetriever.processMixedInputs(
        new List<String>{ TEST_GROUP_NAME },
        GroupMemberEmailRetriever.PrivilegedUseCase.SYSTEM_NOTIFICATION
      );
      secondCall = GroupMemberEmailRetriever.processMixedInputs(
        new List<String>{ TEST_GROUP_NAME },
        GroupMemberEmailRetriever.PrivilegedUseCase.SYSTEM_NOTIFICATION
      );
    }
    Test.stopTest();

    Assert.areEqual(
      firstCall,
      secondCall,
      'Back-to-back resolutions of the same group must return identical sets.'
    );
  }
}
