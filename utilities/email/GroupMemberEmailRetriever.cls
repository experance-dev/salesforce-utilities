/**
 * @description Resolves a mixed list of plain email addresses and Public Group developer names
 *              into a flat set of member email addresses. Traversal covers the directly-addressed
 *              groups plus up to MAX_NESTED_GROUP_DEPTH levels of nested groups beneath them;
 *              memberships nested deeper than that are ignored, not an error. Inputs are trimmed
 *              before classification; blank entries, malformed addresses, and names that resolve
 *              to no group are ignored the same way — resolution is tolerant of junk entries by
 *              design. Only active users with a non-blank email contribute addresses.
 *
 *              AUTHORIZATION CONTRACT — read before calling. This class runs `without sharing`
 *              intentionally: group membership resolution must succeed regardless of the calling
 *              user's record-level visibility, because a sender should not be blocked from
 *              addressing a Public Group simply because they cannot see all of the group's member
 *              records. All SOQL is annotated WITH SYSTEM_MODE to make the elevated access
 *              explicit at the query site. Because the return value is a set of user email
 *              addresses assembled above sharing rules, callers MUST pass a PrivilegedUseCase
 *              acknowledgment naming why they need the privileged path:
 *
 *              - SYSTEM_NOTIFICATION — automation (trigger, flow, platform-event handler)
 *                sending a notification to a Public Group the org configured as an audience.
 *              - OPERATIONAL_ALERT — batch / queueable / scheduled job sending a failure or
 *                completion alert to an operations group.
 *              - ADMIN_BROADCAST — an administrator-initiated announcement to a Public Group.
 *
 *              NOT permitted: returning the resolved addresses to a UI or any user-controlled
 *              surface (address harvesting), or passing through inputs an external caller
 *              controls without validating them first. A null acknowledgment throws — the
 *              privileged path is deliberate, never a default.
 *
 * @group Email
 * @author David Wood
 * @since July 2024
 * @last May 2026 — conformance refactor
 * @last 2026-08-13 — authorization acknowledgment at the public boundary; input trim/validation;
 *                    active-user + non-blank-email filter; instance-local traversal state
 */
public without sharing class GroupMemberEmailRetriever {
  /**
   * @description Caller acknowledgment for the privileged, above-sharing resolution path.
   *              The permitted use case behind each value is documented in the class header.
   */
  public enum PrivilegedUseCase {
    SYSTEM_NOTIFICATION,
    OPERATIONAL_ALERT,
    ADMIN_BROADCAST
  }

  // Nested-group traversal follows membership through at most this many nested-group levels
  // beneath the directly-addressed groups. The directly-addressed groups sit at depth 0 and are
  // always processed; a nested group at depth MAX_NESTED_GROUP_DEPTH is processed, one level
  // deeper is not.
  private static final Integer MAX_NESTED_GROUP_DEPTH = 5;

  // Traversal state is instance-local: every public call resolves on a fresh instance, so no
  // state leaks between calls and re-entrancy costs nothing.
  private Set<Id> processedGroupIds = new Set<Id>();
  private Set<Id> memberUserIds = new Set<Id>();

  /**
   * @description Splits the inputs into direct addresses and group developer names, then resolves
   *              group membership into member email addresses. Entries are trimmed first; blank
   *              entries are dropped. An entry containing '@' with text on both sides is treated
   *              as a direct address; an entry with no '@' is treated as a group developer name;
   *              anything else (a bare or edge '@') is junk and ignored. Group members surface
   *              only when the user is active and has a non-blank email.
   * @param inputs List of strings containing email addresses or group developer names.
   * @param useCase Required acknowledgment of the privileged use case — see the class header for
   *        the permitted values. Null is rejected with an IllegalArgumentException.
   * @return Set<String> Unique email addresses collected from direct entries and group members.
   */
  public static Set<String> processMixedInputs(
    List<String> inputs,
    PrivilegedUseCase useCase
  ) {
    if (useCase == null) {
      throw new IllegalArgumentException(
        'GroupMemberEmailRetriever resolves member emails above sharing rules; callers must ' +
        'acknowledge a PrivilegedUseCase. See the class ApexDoc for the permitted use cases.'
      );
    }
    return new GroupMemberEmailRetriever().resolve(inputs);
  }

  private Set<String> resolve(List<String> inputs) {
    Set<String> emails = new Set<String>();
    if (inputs == null || inputs.isEmpty()) {
      return emails;
    }

    Set<String> groupDeveloperNames = classifyInputs(inputs, emails);

    if (!groupDeveloperNames.isEmpty()) {
      collectMemberUserIds(getGroupIdsByDeveloperNames(groupDeveloperNames), 0);
    }

    if (!memberUserIds.isEmpty()) {
      emails.addAll(getActiveUserEmailsByIds(memberUserIds));
    }

    return emails;
  }

  // Trims every entry, drops blanks, routes email-shaped entries into directEmails, and returns
  // the entries that read as group developer names. Entries containing '@' that aren't
  // email-shaped are junk — ignored by design.
  private static Set<String> classifyInputs(
    List<String> inputs,
    Set<String> directEmails
  ) {
    Set<String> groupDeveloperNames = new Set<String>();
    for (String rawInput : inputs) {
      String input = rawInput == null ? '' : rawInput.trim();
      if (String.isBlank(input)) {
        continue;
      }
      if (isEmailShaped(input)) {
        directEmails.add(input);
      } else if (!input.contains('@')) {
        groupDeveloperNames.add(input);
      }
    }
    return groupDeveloperNames;
  }

  // Minimal shape check for a direct address: '@' present with text on both sides. Full RFC
  // validation is the mail server's job; this only keeps obvious junk out of the recipient set.
  private static Boolean isEmailShaped(String input) {
    Integer atIndex = input.indexOf('@');
    return atIndex > 0 && atIndex < input.length() - 1;
  }

  /**
   * @description Looks up Group IDs by developer name; names with no matching Group are ignored.
   * @param groupDeveloperNames Developer names of the Groups to look up.
   * @return Set<Id> IDs of the matching Groups.
   */
  private static Set<Id> getGroupIdsByDeveloperNames(
    Set<String> groupDeveloperNames
  ) {
    Set<Id> groupIds = new Set<Id>();
    for (Group nextGroup : [
      SELECT Id
      FROM Group
      WHERE DeveloperName IN :groupDeveloperNames
      WITH SYSTEM_MODE
    ]) {
      groupIds.add(nextGroup.Id);
    }
    return groupIds;
  }

  /**
   * @description Fetches emails for the given Users, restricted to active users with a non-blank
   *              email — a resolved recipient set never carries a deactivated user's address.
   * @param userIds IDs of the Users whose emails are needed.
   * @return Set<String> Email addresses for the active, addressable Users among the IDs.
   */
  private static Set<String> getActiveUserEmailsByIds(Set<Id> userIds) {
    Set<String> userEmails = new Set<String>();
    for (User member : [
      SELECT Id, Email
      FROM User
      WHERE Id IN :userIds AND IsActive = TRUE AND Email != NULL
      WITH SYSTEM_MODE
    ]) {
      if (String.isNotBlank(member.Email)) {
        userEmails.add(member.Email);
      }
    }
    return userEmails;
  }

  /**
   * @description Walks one level of group membership — collects User members and recurses into
   *              unvisited nested groups until the depth guard trips.
   * @param groupIds Group IDs to process at this recursion level.
   * @param currentDepth Nested-group depth of this level: 0 for the directly-addressed groups,
   *        MAX_NESTED_GROUP_DEPTH for the deepest nested level still processed.
   */
  private void collectMemberUserIds(Set<Id> groupIds, Integer currentDepth) {
    processedGroupIds.addAll(groupIds);

    Set<Id> nestedGroupIds = new Set<Id>();
    for (GroupMember membership : [
      SELECT UserOrGroupId
      FROM GroupMember
      WHERE GroupId IN :groupIds
      WITH SYSTEM_MODE
    ]) {
      if (membership.UserOrGroupId.getSObjectType() == User.sObjectType) {
        memberUserIds.add(membership.UserOrGroupId);
      } else if (
        membership.UserOrGroupId.getSObjectType() == Group.sObjectType &&
        !processedGroupIds.contains(membership.UserOrGroupId)
      ) {
        nestedGroupIds.add(membership.UserOrGroupId);
      }
    }

    if (!nestedGroupIds.isEmpty() && currentDepth < MAX_NESTED_GROUP_DEPTH) {
      collectMemberUserIds(nestedGroupIds, currentDepth + 1);
    }
  }
}
