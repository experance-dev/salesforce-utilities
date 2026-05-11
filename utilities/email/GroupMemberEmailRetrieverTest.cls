/**
 * @description Test class for GroupMemberEmailRetriever.
 * @group Email
 * @see GroupMemberEmailRetriever
 * @author David Wood
 * @since March 2024
 * @last May 2026 — Wave 6 conformance
 */
@isTest
public without sharing class GroupMemberEmailRetrieverTest {
  static final String TEST_GROUP_NAME = 'group0';
  static final String TEST_EMAIL = 'other@maininator.com';
  static final String TEST_JUNK = 'junk';

  @TestSetup
  static void makeData() {
    Integer numberUsers = 5;
    List<User> users = new List<User>();
    for (Integer i = 0; i < numberUsers; i++) {
      User newUser = TestFactory.createTestUser(false, 'Standard User');
      newUser.Email = 'user' + (i + 1) + '@maininator.com';
      users.add(newUser);
    }
    insert users;

    TestFactory.createMinAccessUser(true);

    List<Group> groups = new List<Group>();

    for (Integer i = 0; i <= 9; i++) {
      Group newGroup = new Group();
      newGroup.Name = 'group' + i;
      newGroup.DeveloperName = 'group' + i;
      groups.add(newGroup);
    }
    insert groups;

    List<GroupMember> groupMembers = new List<GroupMember>();
    //group 0 members
    groupMembers.add(
      new GroupMember(GroupId = groups[0].Id, UserOrGroupId = users[0].Id)
    );
    groupMembers.add(
      new GroupMember(GroupId = groups[0].Id, UserOrGroupId = users[1].Id)
    );

    //group 1 members
    groupMembers.add(
      new GroupMember(GroupId = groups[1].Id, UserOrGroupId = users[2].Id)
    );

    //group 3 members
    groupMembers.add(
      new GroupMember(GroupId = groups[2].Id, UserOrGroupId = users[3].Id)
    );

    //group 8 members
    groupMembers.add(
      new GroupMember(GroupId = groups[8].Id, UserOrGroupId = users[4].Id)
    );

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

    groupMembers.add(
      new GroupMember(GroupId = groups[3].Id, UserOrGroupId = groups[1].Id)
    );
    insert groupMembers;
  }

  @isTest
  static void testRetrieveEmails() {
    List<String> toAddresses = new List<String>{
      TEST_EMAIL,
      TEST_GROUP_NAME,
      TEST_JUNK
    };

    Set<String> emails;

    Test.startTest();
    System.runAs(TestFactory.getMinAccessUser()) {
      emails = GroupMemberEmailRetriever.processMixedInputs(toAddresses);
    }
    Test.stopTest();

    Assert.areEqual(5, emails.size(), 'Should have 4 emails');
    Assert.isTrue(
      !emails.contains('user4@mailinator.com'),
      'Should not have user4'
    );
  }

  @isTest
  static void testRetrieveEmailsNull() {
    List<String> toAddresses = new List<String>();

    Set<String> emails;

    Test.startTest();
    System.runAs(TestFactory.getMinAccessUser()) {
      emails = GroupMemberEmailRetriever.processMixedInputs(toAddresses);

      Assert.areEqual(0, emails.size(), 'Should have 0 emails');

      emails = GroupMemberEmailRetriever.processMixedInputs(null);
      Assert.areEqual(0, emails.size(), 'Should have 0 emails');
    }
    Test.stopTest();
  }
}
