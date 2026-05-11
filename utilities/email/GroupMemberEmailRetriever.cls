/**
 * @description This class is responsible for retrieving the email addresses of group members.
 * It provides methods to query the group members and retrieve their email addresses.
 *
 * This class processes a mixed list of email addresses and group developer names,
 * retrieves group IDs based on developer names, and fetches email addresses of group members,
 * including handling nested groups up to a defined recursion depth.
 *
 * @group Email Retrieval
 * @since July 2024
 * @see TestFactory
 */
public without sharing class GroupMemberEmailRetriever {
  // Sets the maximum recursion depth to 5 to prevent excessive recursion.
  private static final Integer MAX_RECURSION_DEPTH = 5;

  // Keeps track of processed group IDs to avoid reprocessing.
  private static Set<Id> processedGroupIds = new Set<Id>();

  // Collects user IDs to fetch their email addresses later.
  private static Set<Id> userIds = new Set<Id>();

  /**
   * @description Processes a mixed list of input strings, identifying email addresses and group names for email retrieval.
   *
   * @param inputs List of strings that may contain email addresses or group developer names.
   * @return Set<String> A set of unique email addresses collected.
   */
  public static Set<String> processMixedInputs(List<String> inputs) {
    Set<String> emails = new Set<String>();

    // Early exit for null or empty input.
    if (inputs == null || inputs.isEmpty()) {
      return emails;
    }

    // Reset static variables for a fresh execution.
    processedGroupIds.clear();
    userIds.clear();

    // Separate group names and direct email addresses.
    Set<String> groupNames = new Set<String>();
    for (String input : inputs) {
      if (input.contains('@')) {
        emails.add(input); // Assumed to be an email address.
      } else {
        groupNames.add(input); // Assumed to be a group name.
      }
    }

    // Process each group name if any.
    if (!groupNames.isEmpty()) {
      Set<Id> groupIds = getGroupIdsByDeveloperNames(groupNames);
      retrieveEmailsFromGroups(groupIds, 0);
    }

    // Fetch the email addresses from the collected user IDs.
    if (!userIds.isEmpty()) {
      Set<String> userEmails = getUserEmailsByIds(userIds);
      emails.addAll(userEmails);
    }

    return emails;
  }

  /**
   * @description Retrieves the IDs of the Groups based on their Developer Names.
   *
   * @param groupNames A set of Developer Names of the Groups.
   * @return Set<Id> A set of IDs of the Groups that match the provided Developer Names.
   */
  private static Set<Id> getGroupIdsByDeveloperNames(Set<String> groupNames) {
    Set<Id> groupIds = new Set<Id>();
    for (Group nextGroup : [
      SELECT Id
      FROM Group
      WHERE DeveloperName IN :groupNames
      WITH SECURITY_ENFORCED
    ]) {
      groupIds.add(nextGroup.Id);
    }
    return groupIds;
  }

  /**
   * @description Retrieves the Emails of the Users based on their IDs.
   *
   * @param userIds A set of IDs of the Users.
   * @return Set<String> A set of Emails of the Users that match the provided IDs.
   */
  private static Set<String> getUserEmailsByIds(Set<Id> userIds) {
    Set<String> userEmails = new Set<String>();
    for (User user : [
      SELECT Id, Email
      FROM User
      WHERE Id IN :userIds
      WITH SECURITY_ENFORCED
    ]) {
      userEmails.add(user.Email);
    }
    return userEmails;
  }

  /**
   * @description Recursively retrieves email addresses from a set of groups identified by their developer names.
   *
   * @param groupIds The set of group IDs to process.
   * @param currentDepth The current recursion depth.
   */
  private static void retrieveEmailsFromGroups(
    Set<Id> groupIds,
    Integer currentDepth
  ) {
    // Prevent excessive recursion by checking against the maximum depth.
    if (currentDepth > MAX_RECURSION_DEPTH) {
      return;
    }

    // Mark these groups as processed to avoid reprocessing.
    processedGroupIds.addAll(groupIds);

    Set<Id> newGroupIds = new Set<Id>();
    for (GroupMember gm : [
      SELECT UserOrGroupId
      FROM GroupMember
      WHERE GroupId IN :groupIds
      WITH SECURITY_ENFORCED
    ]) {
      // Check if the member is a User or another Group.
      if (gm.UserOrGroupId.getSObjectType() == User.sObjectType) {
        userIds.add(gm.UserOrGroupId);
      } else if (
        gm.UserOrGroupId.getSObjectType() == Group.sObjectType &&
        !processedGroupIds.contains(gm.UserOrGroupId)
      ) {
        newGroupIds.add(gm.UserOrGroupId);
      }
    }

    // Recurse for nested groups, if any.
    if (!newGroupIds.isEmpty()) {
      retrieveEmailsFromGroups(newGroupIds, currentDepth + 1);
    }
  }
}
