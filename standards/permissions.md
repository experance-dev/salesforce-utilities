# Permission Architecture

This file governs the org-level permission model: what remains on profiles, how permission sets and permission set groups compose into personas, the per-feature permission-set ladder, custom permissions as feature flags, session-based elevation, and integration-user provisioning. It is the org-level half of a pair — [security-sharing.md](security-sharing.md) governs the code-level half (sharing modifiers, `WITH USER_MODE`, the three-layer UI gate). Read this before designing the access model for a new feature, and before provisioning any inbound integration.

## 1. Profiles carry only what the platform forces onto them

**Rule.** Every internal user is assigned the standard `Minimum Access - Salesforce` profile — unclosed, uncloned. All functional access is granted through permission sets and permission set groups. The only things that stay on the profile are the settings the platform will not put anywhere else:

| Stays on the profile | Lives in permission sets |
| --- | --- |
| Login hours and IP ranges | Object and field permissions |
| Default record types | Apex class and Visualforce page access |
| Page-layout assignment | Tab and app visibility |
| Session settings | System and custom permissions |

**Why.** This is Salesforce's stated direction: profiles shrink to login, session, and defaults; access lives in composable permission sets. Custom-profile sprawl — one cloned profile per role, each drifting independently — is exactly the thing being retired. Drawing the bright line also changes the operational profile of profiles: profile edits become rare, audited events instead of the daily change surface.

## 2. Permission sets are feature-scoped atoms; personas are permission set groups

**Rule.** Build each permission set as a feature-scoped, persona-agnostic atom: the access one feature needs, and nothing about who gets it. Compose personas as permission set groups (PSGs) that bundle the atoms; assign users at the PSG level, not permset-by-permset.

**Why.** Feature atoms are reusable across personas and auditable one capability at a time — "what can a Sales Rep do?" is answered by reading the PSG's member list, and "who can touch Invoices?" by finding every PSG containing the invoice atoms. A permission set granting more than roughly 10–15 distinct permissions is probably two permission sets; split it before it becomes a junk drawer.

## 3. Ship a tiered ladder per feature: View / Power User / Admin

**Rule.** Every feature ships a consistent ladder of permission-set atoms — one per access tier — under one naming convention, e.g. `Additional Permissions - <Feature> <Tier>`:

| Tier | Grants |
| --- | --- |
| View | Read access to the feature's objects and fields; the UI custom permission |
| Power User | View, plus create/edit and the feature's action permissions |
| Admin | Power User, plus `View All Records` / `Modify All Records` and configuration surfaces |

PSGs follow their own convention (`Persona - <Role>`), and a written Description is mandatory on every permission set and PSG — what it grants, which feature owns it.

**Why.** Names are the only index admins get in Setup list views; tiers make least-privilege selectable instead of bespoke. When access is a ladder, "give support read-only visibility" is an assignment, not a design exercise. And an undescribed permission set becomes unremovable, because nobody remembers why it exists.

## 4. Every feature ships its permission-set atoms with the feature

**Rule.** New functionality never widens an existing broad permission set. The feature's ladder atoms are authored as metadata in the same pull request as the feature's code, and deploy with it.

**Why.** Bolting a new object's CRUD onto an existing permset silently grants the new capability to everyone who already holds that permset — an access change nobody reviewed as an access change. Shipping the atoms with the feature keeps the access model reviewable in the same diff as the code it gates, and keeps the feature independently assignable and independently revocable.

## 5. Grant Apex Class Access on the permset for every `@AuraEnabled` entry point

**Rule.** Every Apex class exposing an `@AuraEnabled` method gets an explicit `classAccesses` grant on the feature's permission set — at the tier where its capability belongs. Read methods on the View atom; mutating controllers on Power User or above.

```xml
<!-- Additional_Permissions_Invoicing_View.permissionset-meta.xml -->
<classAccesses>
    <apexClass>InvoiceSummaryController</apexClass>
    <enabled>true</enabled>
</classAccesses>
```

**Why.** An authenticated or guest user can invoke an `@AuraEnabled` method only if their profile or an assigned permission set grants access to the Apex class — with a Minimum Access profile, the permission set is the only place that grant can live. Forgetting it produces the classic symptom: the component renders (UI-layer checks passed) and every server call dies. This grant is also layer three of the defense-in-depth gate in [security-sharing.md §6](security-sharing.md) — the only layer enforced server-side, which is why it is never optional.

## 6. Subtract with muting permission sets; never fork the atom

**Rule.** When a persona needs *most* of a PSG but not some specific permission, add a muting permission set inside the PSG to disable it. Do not clone-and-trim a member permission set, and do not edit the shared atom to suit one persona.

**Why.** Muting keeps the shared atom intact — critical when the atom comes from a managed package and cannot be edited at all — and records the subtraction as explicit, reviewable metadata instead of a divergent copy that drifts. Note the semantics inversion: inside a `MutingPermissionSet`, a flagged permission is *disabled* for the group, not granted.

```xml
<!-- Muting permission set inside the Persona - Sales Rep PSG:
     flags mark what is MUTED, not what is granted. -->
<MutingPermissionSet xmlns="http://soap.sforce.com/2006/04/metadata">
    <label>Sales Rep - Mute Invoice Delete</label>
    <description>Sales reps hold the Invoicing Power User atom but must not delete.</description>
    <objectPermissions>
        <allowDelete>true</allowDelete>
        <object>Invoice__c</object>
    </objectPermissions>
</MutingPermissionSet>
```

## 7. Custom permissions are the feature flag

**Rule.** Gate features and automation bypasses with custom permissions — `Can_<Action>` for capabilities, `Bypass_<Object>_<Automation>` for automation escapes — and house them in the feature's permission-set atoms. Check the same flag at every enforcement surface:

- **Component visibility** — FlexiPage filter `{!$Permission.Can_Recalculate_Invoices}` hides the panel before it loads
- **LWC** — `import canRecalculate from '@salesforce/customPermission/Can_Recalculate_Invoices'`
- **Validation rules / flow entry conditions** — `$Permission.Bypass_Invoice_Validation`
- **Apex** — `FeatureManagement.checkPermission('Can_Recalculate_Invoices')`

```apex
if (!FeatureManagement.checkPermission('Can_Recalculate_Invoices')) {
    throw new InvoiceServiceException('Recalculation requires the Invoicing Power User permission.');
}
```

Scope bypass permissions per object — never one global kill switch.

**Why.** One flag works identically across every automation surface, is assignable and revocable per user in seconds, and survives refactors that profile-name checks do not. Per-object bypass granularity keeps a data-migration bypass from silencing the whole org's validation. And because the custom permission travels inside the permset atom, granting the feature grants its flag — no second provisioning step to forget. The UI checks are convenience layers only; the Apex check and the Apex Class Access grant (§5) are what actually hold — see the layering argument in [security-sharing.md §6](security-sharing.md).

## 8. Use session-based permission sets for elevation that should expire

**Rule.** Access that should exist only while a condition holds — an occasional approval step, a quarterly close task, a hardware-token-gated action — goes in a session-based permission set (or session-based PSG), activated at the point of need via the `Activate Session-Based Permission Set` flow core action. It deactivates with the session.

**Why.** Standing privilege is the risk: an "occasionally needs delete" grant that never expires is a permanent grant with better intentions. Session activation turns "always could" into "can right now, audited, expiring with the session" — the platform-native just-in-time elevation primitive. One platform constraint to design around: a flow that activates a session-based permission set cannot also modify Salesforce data — keep the activation flow to activation, and do the data work after.

## 9. Integration principals: one user per integration, API-only, narrowest grant

**Rule.** Every inbound integration gets its own dedicated user on the Salesforce Integration license with the `Minimum Access - API Only Integrations` profile. Access is extended only through permission sets carrying the Salesforce API Integration permission set license — built to the same atom discipline as §2, scoped to exactly the objects and fields that integration touches. Each integration authenticates through its own connected app using the OAuth client-credentials flow, executing as its dedicated user. Never run an integration as a System Administrator, and never share one integration user across systems.

**Why.** Per-integration users buy two things at once: least privilege (the ERP sync literally cannot touch Cases) and per-system traceability (every record's `CreatedById` names the integration that wrote it, so "which system corrupted this field" is a query, not a forensic project). The API-only license is cheap and cannot log into the UI, which removes an entire credential-theft surface. The per-integration connected app removes password and refresh-token custody from the external system, and pins every API action to a principal you can disable in one click when the vendor relationship ends.

## 10. Tests that assign a PSG must calculate it before asserting

**Rule.** An Apex test that assigns a permission set group and then asserts on the resulting access must check `PermissionSetGroup.Status` and call `Test.calculatePermissionSetGroup()` when the group is not yet `Updated`.

```apex
PermissionSetGroup persona = [
    SELECT Id, Status
    FROM PermissionSetGroup
    WHERE DeveloperName = 'Persona_Sales_Rep'
    LIMIT 1
];
if (persona.Status != 'Updated') {
    Test.calculatePermissionSetGroup(persona.Id);
}
// ...assign, then System.runAs(testUser) { ...assert access... }
```

**Why.** A PSG's aggregate permissions are calculated asynchronously; a test that assigns an `Outdated` group asserts against permissions that haven't materialized yet, and fails intermittently. In a permset-first org this is a classic flaky-test source — the failure reproduces under load and vanishes on re-run, which is exactly the kind of noise that erodes trust in the suite.

---

**Summary of the architecture:** the profile answers "when and how can you log in"; permission-set atoms answer "what can this feature holder do"; PSGs answer "what can this persona do"; muting permission sets subtract without forking; custom permissions carry the feature flag across every enforcement surface; session-based permission sets make elevation expire; integration principals get the same atom discipline with an API-only floor. Each feature's ladder ships with the feature, and the code-level enforcement that backs all of it lives in [security-sharing.md](security-sharing.md).

## Sources

- https://admin.salesforce.com/blog/2026/the-salesforce-admins-guide-to-profiles-and-permissions
- https://salesforcebreak.com/2025/10/30/profiles-and-permissions-in-salesforce-the-simple-guide-for-admins/
- https://www.crmscience.com/single-post/getting-hands-on-with-permission-sets-and-groups
- https://dev.to/dipojjal/salesforce-permission-sets-the-complete-guide-for-2026-49pe
- https://jpaulamaki.substack.com/p/part-2-profiles-and-permission-sets
- https://admin.salesforce.com/blog/2024/use-permission-sets-overcome-access-dilemmas
- https://developer.salesforce.com/docs/atlas.en-us.object_reference.meta/object_reference/sforce_api_objects_mutingpermissionset.htm
- https://www.salesforceben.com/an-admins-guide-to-bypass-logic-for-flows-apex-and-validation-rules/
- https://admin.salesforce.com/blog/2021/allow-certain-users-to-edit-data-using-custom-permissions-in-validation-rules
- https://help.salesforce.com/s/articleView?id=platform.perm_sets_session_use.htm
- https://trailhead.salesforce.com/content/learn/modules/session_based_perms
- https://gearset.com/blog/what-are-salesforce-integration-user-licenses/
- https://admin.salesforce.com/blog/2023/best-practices-for-configuring-your-integration-user
- https://help.salesforce.com/s/articleView?id=release-notes.rn_api_new_user_profile.htm&release=248
- https://developer.salesforce.com/blogs/2024/02/invoke-rest-apis-with-the-salesforce-integration-user-and-oauth-client-credentials
- Lightning Aura Components Developer Guide, Apex Developer Guide, Metadata API Developer Guide, and Automate Your Business Processes — verified via the official-doc mirror at https://github.com/damecek/salesforce-documentation-context (`@AuraEnabled` class access, `MutingPermissionSet` semantics, `Activate Session-Based Permission Set` flow action, `Test.calculatePermissionSetGroup`)
