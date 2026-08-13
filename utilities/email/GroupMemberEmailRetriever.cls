/**
 * @description Resolves a mixed list of plain email addresses and Public Group developer names
 *              into a flat set of member email addresses. Traversal covers the directly-addressed
 *              groups plus up to MAX_RECURSION_DEPTH levels of nested groups beneath them (six
 *              group levels in total); memberships nested deeper than that are ignored, not an error.
 *              Inputs that resolve to no group are ignored the same way — resolution is tolerant
 *              of junk entries by design.
 *
 *              Sharing: declared `without sharing` intentionally. Group membership resolution
 *              must succeed regardless of the calling user's record-level visibility — a sender
 *              should not be blocked from addressing a Public Group simply because they do not
 *              own (or cannot see) all of the group's member records. All SOQL is annotated
 *              WITH SYSTEM_MODE to make the elevated access explicit at the query site.
 *
 * @group Email
 * @author David Wood
 * @since July 2024
 * @last May 2026 — conformance refactor
 * @last August 2026 — removed the never-thrown module exception; recursion-depth contract stated precisely; analyzer conformance
 */
public without sharing class GroupMemberEmailRetriever {
  // Nested groups are followed up to this many levels below the directly-addressed
  // groups; the guard in retrieveEmailsFromGroups stops the level after this depth.
  private static final Integer MAX_RECURSION_DEPTH = 5;

  private static Set<Id> processedGroupIds = new Set<Id>();
  private static Set<Id> userIds = new Set<Id>();

  /**
   * @description Splits the inputs into direct addresses (anything containing '@') and group
   *              developer names, then resolves group membership into member email addresses.
   * @param inputs List of strings containing email addresses or group developer names.
   * @return Set<String> Unique email addresses collected from direct entries and group members.
   */
  public static Set<String> processMixedInputs(List<String> inputs) {
    Set<String> emails = new Set<String>();

    if (inputs == null || inputs.isEmpty()) {
      return emails;
    }

    processedGroupIds.clear();
    userIds.clear();

    Set<String> groupNames = new Set<String>();
    for (String input : inputs) {
      if (input.contains('@')) {
        emails.add(input);
      } else {
        groupNames.add(input);
      }
    }

    if (!groupNames.isEmpty()) {
      Set<Id> groupIds = getGroupIdsByDeveloperNames(groupNames);
      retrieveEmailsFromGroups(groupIds, 0);
    }

    if (!userIds.isEmpty()) {
      emails.addAll(getUserEmailsByIds(userIds));
    }

    return emails;
  }

  /**
   * @description Looks up Group IDs by developer name; names with no matching Group are ignored.
   * @param groupNames Developer names of the Groups to look up.
   * @return Set<Id> IDs of the matching Groups.
   */
  private static Set<Id> getGroupIdsByDeveloperNames(Set<String> groupNames) {
    Set<Id> groupIds = new Set<Id>();
    for (Group nextGroup : [
      SELECT Id
      FROM Group
      WHERE DeveloperName IN :groupNames
      WITH SYSTEM_MODE
    ]) {
      groupIds.add(nextGroup.Id);
    }
    return groupIds;
  }

  /**
   * @description Fetches the Email field for the given Users.
   * @param userIds IDs of the Users whose emails are needed.
   * @return Set<String> Email addresses for the provided User IDs.
   */
  private static Set<String> getUserEmailsByIds(Set<Id> userIds) {
    Set<String> userEmails = new Set<String>();
    for (User u : [
      SELECT Id, Email
      FROM User
      WHERE Id IN :userIds
      WITH SYSTEM_MODE
    ]) {
      userEmails.add(u.Email);
    }
    return userEmails;
  }

  /**
   * @description Walks one level of group membership — collects User members and recurses into
   *              unvisited nested groups until the depth guard trips.
   * @param groupIds Group IDs to process at this recursion level.
   * @param currentDepth Current recursion depth — 0 for the directly-addressed groups, so the
   *        guard admits depths 0 through MAX_RECURSION_DEPTH (six group levels in total).
   */
  private static void retrieveEmailsFromGroups(
    Set<Id> groupIds,
    Integer currentDepth
  ) {
    if (currentDepth > MAX_RECURSION_DEPTH) {
      return;
    }

    processedGroupIds.addAll(groupIds);

    Set<Id> nestedGroupIds = new Set<Id>();
    for (GroupMember gm : [
      SELECT UserOrGroupId
      FROM GroupMember
      WHERE GroupId IN :groupIds
      WITH SYSTEM_MODE
    ]) {
      if (gm.UserOrGroupId.getSObjectType() == User.sObjectType) {
        userIds.add(gm.UserOrGroupId);
      } else if (
        gm.UserOrGroupId.getSObjectType() == Group.sObjectType &&
        !processedGroupIds.contains(gm.UserOrGroupId)
      ) {
        nestedGroupIds.add(gm.UserOrGroupId);
      }
    }

    if (!nestedGroupIds.isEmpty()) {
      retrieveEmailsFromGroups(nestedGroupIds, currentDepth + 1);
    }
  }
}
