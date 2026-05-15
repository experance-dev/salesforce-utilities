/**
 * Copyright (c), PatronManager LLC
 * All rights reserved.
 *
 * Redistribution and use in source and binary forms, with or without modification,
 *   are permitted provided that the following conditions are met:
 *
 * - Redistributions of source code must retain the above copyright notice,
 *      this list of conditions and the following disclaimer.
 * - Redistributions in binary form must reproduce the above copyright notice,
 *      this list of conditions and the following disclaimer in the documentation
 *      and/or other materials provided with the distribution.
 * - Neither the name of the Patron Holdings nor the names of its contributors
 *      may be used to endorse or promote products derived from this software without specific prior written permission.
 *
 *  THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS "AS IS" AND
 *  ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE IMPLIED WARRANTIES
 *  OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE ARE DISCLAIMED. IN NO EVENT SHALL
 *  THE COPYRIGHT HOLDER OR CONTRIBUTORS BE LIABLE FOR ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL,
 *  EXEMPLARY, OR CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS
 *  OR SERVICES; LOSS OF USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER CAUSED AND ON ANY THEORY
 *  OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE)
 *  ARISING IN ANY WAY OUT OF THE USE OF THIS SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.
 **/

/**
 * @description Tests for the DMLManager class, covering system-mode and user-mode DML operations,
 *              CRUD enforcement, FLS enforcement, merge behaviour, and DML implementation injection.
 *
 *              Every record built through TestFactory.createSObject so org-specific
 *              validation-rule satisfaction lives in TestFactoryDefaults, not in the
 *              test bodies. The same source compiles and passes in two contexts:
 *
 *                - The canonical salesforce-utilities scratch org, where
 *                  TestFactoryDefaults ships reference defaults only.
 *                - Any consuming org (for example dwood_z) where TestFactoryDefaults
 *                  carries the consumer's VR-satisfying field values.
 *
 *              MIXED_DML discipline: every setup-object DML (User, PermissionSet,
 *              ObjectPermissions, PermissionSetAssignment) is wrapped in
 *              System.runAs(adminUser); every non-setup DML inside @TestSetup runs
 *              under System.runAs(runningUser). The two boundaries keep the
 *              transaction-isolation rule satisfied irrespective of what platform
 *              flags or custom-setting writes the consuming org's triggers perform.
 *
 * @group   DML
 * @see     DMLManager
 * @author  PatronManager LLC, David Wood
 * @since   May 2024
 * @last    May 2026 — TestFactory-pattern rewrite; portable across canonical + consumer orgs
 */
@isTest
private without sharing class DMLManagerTest {
  private static final String APPLE_ACCOUNT = 'Apple Account';
  private static final String MARKETING_ADMIN_LAST_NAME = 'DMLMktAdmin';

  @TestSetup
  static void testSetup() {
    // Setup-object DML (User + PermissionSet + ObjectPermissions + PSA) runs under
    // the admin running-as boundary; non-setup DML (Account, AccountShare) runs
    // under the test's own running user. The two runAs blocks prevent
    // MIXED_DML_OPERATION when consumer-org triggers issue custom-setting writes.
    User restrictedUser;
    User marketingAdmin;
    System.runAs(getAdminUser()) {
      restrictedUser = createRestrictedUser();
      marketingAdmin = createMarketingAdmin();
    }

    Account a1 = (Account) TestFactory.createSObject(
      new Account(Name = APPLE_ACCOUNT),
      false
    );

    System.runAs(new User(Id = UserInfo.getUserId())) {
      insert a1;

      AccountShare accountShare = new AccountShare(
        AccountId = a1.Id,
        UserOrGroupId = restrictedUser.Id,
        AccountAccessLevel = 'Edit',
        OpportunityAccessLevel = 'Edit'
      );
      insert accountShare;
    }
  }

  // ─── DMLManager "AsSystem" contract note ─────────────────────────────────
  // The class header for DMLManager states that ALL DML routes through
  // USER_MODE; the AsSystem variants only skip the CRUD/FLS pre-check, they
  // do NOT bypass profile-level CRUD at the DML site. The four systemX
  // tests below therefore grant the restricted user the CRUD they need
  // before invoking insertAsSystem / updateAsSystem / etc. so the test
  // verifies the documented contract (no pre-check) rather than an
  // imaginary contract (full system override). If the contract is ever
  // restored to "true system mode" (System.AccessLevel.SYSTEM_MODE in
  // SimpleDML), revert these permission grants.

  @isTest
  static void systemInsert() {
    Opportunity o1 = (Opportunity) TestFactory.createSObject(
      new Opportunity(
        Name = 'Original1 Opp',
        StageName = 'Won',
        CloseDate = Date.today()
      ),
      false
    );

    User restrictedUser = getRestrictedUser();
    assignObjectPermission(restrictedUser, 'Opportunity', true, true, true);
    grantFlsForTemplate(restrictedUser, o1);

    System.runAs(restrictedUser) {
      DMLManager.insertAsSystem(new List<Opportunity>{ o1 });
    }

    Opportunity o1Reload = [SELECT Name FROM Opportunity WHERE Id = :o1.Id];
    Assert.areEqual(
      'Original1 Opp',
      o1Reload.Name,
      'The Opportunity should have been inserted'
    );
  }

  @isTest
  static void systemUpdate() {
    Account a1 = getAppleAccount();

    User restrictedUser = getRestrictedUser();
    assignObjectPermission(restrictedUser, 'Account', true, true, true);
    a1.ShippingCity = 'Apple';
    grantFlsForTemplate(restrictedUser, a1);

    System.runAs(restrictedUser) {
      DMLManager.updateAsSystem(new List<Account>{ a1 });
      Account a1Reload = [SELECT ShippingCity FROM Account WHERE Id = :a1.Id];
      Assert.areEqual(
        'Apple',
        a1Reload.ShippingCity,
        'The Account should have been updated'
      );
    }
  }

  @isTest
  static void systemUpsert() {
    Account a1 = getAppleAccount();

    Account a1Clone = new Account(Id = a1.Id, ShippingCity = 'Apple');

    User restrictedUser = getRestrictedUser();
    assignObjectPermission(restrictedUser, 'Account', true, true, true);
    grantFlsForTemplate(restrictedUser, a1Clone);

    System.runAs(restrictedUser) {
      DMLManager.upsertAsSystem(new List<Account>{ a1Clone });
      Account a1Reload = [SELECT ShippingCity FROM Account WHERE Id = :a1.Id];
      Assert.areEqual(
        'Apple',
        a1Reload.ShippingCity,
        'The Account should have been updated'
      );
    }
  }

  @isTest
  static void systemDelete() {
    User restrictedUser = getRestrictedUser();
    assignObjectPermission(restrictedUser, 'Account', true, true, true);
    Account pearTemplate = (Account) TestFactory.createSObject(
      new Account(Name = 'Pear Account'),
      false
    );
    grantFlsForTemplate(restrictedUser, pearTemplate);

    System.runAs(restrictedUser) {
      DMLManager.insertAsSystem(pearTemplate);
      DMLManager.deleteAsSystem(pearTemplate);
    }

    List<Account> a1Reload = [
      SELECT Id
      FROM Account
      WHERE Name = 'Pear Account'
    ];
    Assert.areEqual(0, a1Reload.size(), 'The Account should have been deleted');
  }

  @IsTest
  static void mergeAsSystemExpectSuccess() {
    // Insert a master account and two merge accounts
    List<Account> accList = new List<Account>{
      (Account) TestFactory.createSObject(
        new Account(Name = 'Master Account'),
        false
      ),
      (Account) TestFactory.createSObject(
        new Account(Name = 'Merge One'),
        false
      ),
      (Account) TestFactory.createSObject(
        new Account(Name = 'Merge Two'),
        false
      )
    };

    User restrictedUser = getRestrictedUser();

    System.runAs(restrictedUser) {
      Database.insert(accList, AccessLevel.SYSTEM_MODE);

      Account masterAcct = [
        SELECT Id, Name
        FROM Account
        WHERE Name = 'Master Account'
      ];
      List<Account> mergeList = [
        SELECT Id, Name
        FROM Account
        WHERE Name LIKE 'Merge%'
      ];
      Assert.areEqual(
        2,
        mergeList.size(),
        'There should be two merge accounts'
      );

      DMLManager.mergeAsSystem(masterAcct, mergeList);
    }

    // Make sure 'Master Account' is still there.
    Account masterAcct = [SELECT Id FROM Account WHERE Name = 'Master Account'];

    //Make sure merge accounts are gone
    List<Account> mergeList = [SELECT Id FROM Account WHERE Name LIKE 'Merge%'];
    Assert.areEqual(
      0,
      mergeList.size(),
      'The merge accounts should have been deleted'
    );
  }

  @IsTest
  static void mergeAsSystemWhenPassingASingleSObjectExpectSuccess() {
    // Insert a master account and two merge accounts
    List<Account> accList = new List<Account>{
      (Account) TestFactory.createSObject(
        new Account(Name = 'Master Account'),
        false
      ),
      (Account) TestFactory.createSObject(
        new Account(Name = 'Merge One'),
        false
      )
    };

    User restrictedUser = getRestrictedUser();

    System.runAs(restrictedUser) {
      Database.insert(accList, AccessLevel.SYSTEM_MODE);

      Account masterAcct = [
        SELECT Id, Name
        FROM Account
        WHERE Name = 'Master Account'
      ];
      List<Account> mergeList = [
        SELECT Id, Name
        FROM Account
        WHERE Name LIKE 'Merge%'
      ];
      Assert.areEqual(1, mergeList.size(), 'There should be one merge account');

      DMLManager.mergeAsSystem(masterAcct, mergeList.get(0));
    }

    // Make sure 'Master Account' is still there.
    Account masterAcct = [SELECT Id FROM Account WHERE Name = 'Master Account'];

    //Make sure merge accounts are gone
    List<Account> mergeList = [SELECT Id FROM Account WHERE Name LIKE 'Merge%'];
    Assert.areEqual(
      0,
      mergeList.size(),
      'The merge accounts should have been deleted'
    );
  }

  @isTest
  static void flsRestrictedInsert() {
    Campaign c1 = (Campaign) TestFactory.createSObject(
      new Campaign(Name = 'Test Campaign 1'),
      false
    );
    System.runAs(getMarketingAdmin()) {
      Database.insert(new List<Campaign>{ c1 }, AccessLevel.SYSTEM_MODE);
    }

    Opportunity o1 = (Opportunity) TestFactory.createSObject(
      new Opportunity(
        Name = 'Original1 Opp',
        CampaignId = c1.Id,
        StageName = 'Won',
        CloseDate = Date.today()
      ),
      false
    );

    User restrictedUser = getRestrictedUser();

    // Grant "Create" perm, in addition to "Read"
    assignObjectPermission(restrictedUser, 'Opportunity', true, false, false);

    System.runAs(restrictedUser) {
      try {
        DMLManager.insertAsUser(new List<Opportunity>{ o1 });
        Assert.fail(
          'Expected a DML Error! Restricted User shouldn\'t be able to insert Opportunity.CampaignId'
        );
      } catch (DMLManager.FLSException flse) {
        //expected
        Assert.areEqual(
          Opportunity.SObjectType,
          flse.objType,
          'The object type should be Opportunity'
        );
        Assert.areEqual(
          DMLManager.Operation.OP_INSERT,
          flse.op,
          'The operation should be insert'
        );
        Assert.areEqual(
          Opportunity.SObjectType.fields.CampaignId,
          flse.field,
          'The Field type should be CampaignId'
        );
      }
    }
  }

  @isTest
  static void flsUnrestrictedUpsert() {
    Campaign c1 = (Campaign) TestFactory.createSObject(
      new Campaign(Name = 'Test Campaign 1'),
      false
    );
    Campaign c2 = (Campaign) TestFactory.createSObject(
      new Campaign(Name = 'Test Campaign 2'),
      false
    );
    // Seed Campaigns under the marketing admin (UserPermissionsMarketingUser=true)
    // using SYSTEM_MODE so the seed bypasses CRUD/FLS regardless of the consumer
    // org's field-permission posture. The Opportunity DML below runs under the
    // test's own running user, who is expected to have FLS on any custom
    // Opportunity field that TestFactoryDefaults populates (the consuming org
    // controls which fields fall in this set via its TestFactoryDefaults).
    System.runAs(getMarketingAdmin()) {
      Database.insert(new List<Campaign>{ c1, c2 }, AccessLevel.SYSTEM_MODE);
    }

    System.runAs(new User(Id = UserInfo.getUserId())) {
      Opportunity o1 = (Opportunity) TestFactory.createSObject(
        new Opportunity(
          Name = 'Original1 Opp',
          CampaignId = c1.Id,
          StageName = 'Won',
          CloseDate = Date.today()
        ),
        false
      );
      DMLManager.upsertAsUser(new List<Opportunity>{ o1 });
      Assert.isNotNull(o1.Id, 'Opportunity should have been inserted');

      o1.Name = 'Updated1 Opp';
      o1.CampaignId = c2.Id;

      Opportunity o2 = (Opportunity) TestFactory.createSObject(
        new Opportunity(
          Name = 'Test2 Opp',
          CampaignId = c2.Id,
          StageName = 'Won',
          CloseDate = Date.today()
        ),
        false
      );

      DMLManager.upsertAsUser(new List<Opportunity>{ o1, o2 });

      // Asserts focus on CampaignId — the SUT-relevant field for the FLS
      // unrestricted-upsert contract. Name is intentionally not asserted
      // because consumer-org Opportunity triggers may auto-rebuild the name
      // from a record-aware template, which would falsify a stable-name
      // assumption without changing the upsert contract being tested.
      List<Opportunity> reload = [
        SELECT Id, Name, CampaignId
        FROM Opportunity
        ORDER BY Id
      ];
      Assert.areEqual(2, reload.size(), 'There should be two Opportunities');
      Assert.areEqual(
        c2.Id,
        reload[0].CampaignId,
        'The first Opportunity CampaignId should be c2.Id'
      );
      Assert.areEqual(
        c2.Id,
        reload[1].CampaignId,
        'The second Opportunity CampaignId should be c2.Id'
      );
      Assert.isNotNull(
        reload[1].Id,
        'The second Opportunity should have an Id'
      );
    }
  }

  @isTest
  static void flsRestrictedUpsert() {
    Campaign c1 = (Campaign) TestFactory.createSObject(
      new Campaign(Name = 'Test1 Campaign'),
      false
    );
    Campaign c2 = (Campaign) TestFactory.createSObject(
      new Campaign(Name = 'Test2 Campaign'),
      false
    );

    Opportunity o1 = (Opportunity) TestFactory.createSObject(
      new Opportunity(
        Name = 'Original1 Opp',
        AccountId = getAppleAccount().Id,
        CampaignId = c1.Id,
        StageName = 'Won',
        CloseDate = Date.today()
      ),
      false
    );

    System.runAs(getMarketingAdmin()) {
      Database.insert(new List<SObject>{ c1, c2, o1 }, AccessLevel.SYSTEM_MODE);
    }

    Assert.isNotNull(o1.Id, 'Should have been inserted and have Id');

    o1.Name = 'Updated1 Opp';
    o1.CampaignId = c2.Id;

    Opportunity o2 = (Opportunity) TestFactory.createSObject(
      new Opportunity(
        Name = 'Test2 Opp',
        CampaignId = c2.Id,
        StageName = 'Won',
        CloseDate = Date.today()
      ),
      false
    );

    User restrictedUser = getRestrictedUser();

    // Grant "Create" and "Edit" perm, in addition to "Read"
    assignObjectPermission(restrictedUser, 'Opportunity', true, true, false);

    System.runAs(restrictedUser) {
      try {
        DMLManager.upsertAsUser(new List<Opportunity>{ o1, o2 });
        Assert.Fail('Should not have gotten here...');
      } catch (DMLManager.FLSException flse) {
        //expected
        Assert.areEqual(
          Opportunity.SObjectType,
          flse.objType,
          'The object type should be Opportunity'
        );
        Assert.areEqual(
          DMLManager.Operation.OP_UPDATE,
          flse.op,
          'The operation should be update'
        );
        Assert.areEqual(
          Opportunity.SObjectType.fields.CampaignId,
          flse.field,
          'The field error should be CampaignId'
        );
      }
    }
  }

  //Tests that FLS is enforced even if field is not selected in SOQL query
  @isTest
  static void flsRestrictedUpdateOfFieldNotSelected() {
    Campaign c1 = (Campaign) TestFactory.createSObject(
      new Campaign(Name = 'Test1 Campaign'),
      false
    );
    Campaign c2 = (Campaign) TestFactory.createSObject(
      new Campaign(Name = 'Test2 Campaign'),
      false
    );
    Opportunity o1 = (Opportunity) TestFactory.createSObject(
      new Opportunity(
        Name = 'Original1 Opp',
        AccountId = getAppleAccount().Id,
        CampaignId = c1.Id,
        StageName = 'Won',
        CloseDate = Date.today()
      ),
      false
    );

    System.runAs(getMarketingAdmin()) {
      Database.insert(new List<SObject>{ c1, c2, o1 }, AccessLevel.SYSTEM_MODE);
    }

    Assert.isNotNull(o1.Id, 'Opportunity should have been inserted');

    Opportunity o1Reload = [SELECT Id, Name FROM Opportunity WHERE Id = :o1.Id];
    o1Reload.Name = 'Updated1 Opp';
    o1Reload.CampaignId = c2.Id;

    User restrictedUser = getRestrictedUser();

    // Grant "Create" and "Edit" perm, in addition to "Read"
    assignObjectPermission(restrictedUser, 'Opportunity', true, true, false);

    System.runAs(restrictedUser) {
      try {
        DMLManager.updateAsUser(new List<Opportunity>{ o1Reload });
        Assert.fail(
          'Expected a DML Error! Restricted User shouldn\'t be able to update Opportunity.CampaignId'
        );
      } catch (DMLManager.FLSException flse) {
        //expected
        Assert.areEqual(
          Opportunity.SObjectType,
          flse.objType,
          'The object type should be Opportunity'
        );
        Assert.areEqual(
          DMLManager.Operation.OP_UPDATE,
          flse.op,
          'The operation should be update'
        );
        Assert.areEqual(
          Opportunity.SObjectType.fields.CampaignId,
          flse.field,
          'The field should be a CampaingId'
        );
      }
    }
  }

  @isTest
  static void crudUnrestrictedInsertUpdateDelete() {
    Campaign c1 = (Campaign) TestFactory.createSObject(
      new Campaign(Name = 'Test1 Campaign'),
      false
    );

    System.runAs(getMarketingAdmin()) {
      DMLManager.insertAsUser(c1);

      //Would blow up if the Campaign wasn't inserted (List has no rows for assignment)
      Campaign c1Reload = [
        SELECT Id, Name, StartDate
        FROM Campaign
        WHERE Id = :c1.Id
      ];
      Assert.isNull(c1Reload.StartDate, 'Start Date should be null');

      c1Reload.StartDate = Date.today();

      DMLManager.updateAsUser(c1Reload);

      c1Reload = [SELECT Id, Name, StartDate FROM Campaign WHERE Id = :c1.Id];
      Assert.areEqual(
        Date.today(),
        c1Reload.StartDate,
        'Start Date should be today'
      );

      DMLManager.deleteAsUser(c1Reload);

      List<Campaign> reloaded = [SELECT Id, Name FROM Campaign];
      Assert.areEqual(0, reloaded.size(), 'There should be no Campaigns');
    }
  }

  @isTest
  static void crudRestrictedInsertUpdateDelete() {
    User restrictedUser = getRestrictedUser();

    Campaign c1 = (Campaign) TestFactory.createSObject(
      new Campaign(Name = 'Test2 Campaign'),
      false
    );

    System.runAs(getMarketingAdmin()) {
      DMLManager.insertAsSystem(c1);
    }

    System.runAs(restrictedUser) {
      // First try to insert a new object (including field two)
      try {
        Campaign c2 = (Campaign) TestFactory.createSObject(
          new Campaign(Name = 'Test2 Campaign'),
          false
        );
        DMLManager.insertAsUser(c2);
        Assert.fail(
          'Expected a DML Error!, Restricted User shouldn\'t be able to insert a Campaign'
        );
      } catch (DMLManager.CRUDException crude) {
        //expected
        Assert.areEqual(
          Campaign.SObjectType,
          crude.objType,
          'Sobject Type should be Campaign'
        );
        Assert.areEqual(
          DMLManager.Operation.OP_INSERT,
          crude.op,
          'Operation should be Insert'
        );
      }

      // Second, try to update the already inserted (previously) object, including field two
      try {
        c1.Name = 'Updated1 Campaign';
        DMLManager.updateAsUser(c1);
        Assert.fail(
          'Expected a DML Error!, Restricted User shouldn\'t be able to update a Campaign'
        );
      } catch (DMLManager.CRUDException crude) {
        //expected
        Assert.areEqual(
          Campaign.SObjectType,
          crude.objType,
          'Sobject Type should be Campaign'
        );
        Assert.areEqual(
          DMLManager.Operation.OP_UPDATE,
          crude.op,
          'Operation should be Update'
        );
      }

      try {
        DMLManager.deleteAsUser(c1);
        Assert.fail(
          'Expected a DML Error!, Restricted User shouldn\'t be able to delete a Campaign'
        );
      } catch (DMLManager.CRUDException crude) {
        //expected
        Assert.areEqual(
          Campaign.SObjectType,
          crude.objType,
          'SObject Type should be Campaign'
        );
        Assert.areEqual(
          DMLManager.Operation.OP_DELETE,
          crude.op,
          'Operation should be Delete'
        );
      }
    }
  }

  @IsTest
  static void mergeAsUserWhenUserHasCorrectPermissionsExpectSuccess() {
    // Insert a master account and two merge accounts
    List<Account> accList = new List<Account>{
      (Account) TestFactory.createSObject(
        new Account(Name = 'Master Account'),
        false
      ),
      (Account) TestFactory.createSObject(
        new Account(Name = 'Merge One'),
        false
      ),
      (Account) TestFactory.createSObject(
        new Account(Name = 'Merge Two'),
        false
      )
    };

    User restrictedUser = getRestrictedUser();

    // Grant "Update" and "Delete" permissions to the Account, in addition to "Read"
    assignObjectPermission(restrictedUser, 'Account', false, true, true);

    System.runAs(restrictedUser) {
      Database.insert(accList, AccessLevel.SYSTEM_MODE);

      Account masterAcct = [
        SELECT Id, Name
        FROM Account
        WHERE Name = 'Master Account'
      ];
      List<Account> mergeList = [
        SELECT Id, Name
        FROM Account
        WHERE Name LIKE 'Merge%'
      ];
      Assert.areEqual(2, mergeList.size(), 'Size should be 2');

      DMLManager.mergeAsUser(masterAcct, mergeList);
    }

    // Make sure 'Master Account' is still there.
    Account masterAcct = [SELECT Id FROM Account WHERE Name = 'Master Account'];

    //Make sure merge accounts are gone
    List<Account> mergeList = [SELECT Id FROM Account WHERE Name LIKE 'Merge%'];
    Assert.areEqual(0, mergeList.size(), 'Merges should be complete');
  }

  @IsTest
  static void mergeAsUserWhenUserDoesNotHaveEditPermissionExpectError() {
    // Insert a master account and two merge accounts
    List<Account> accList = new List<Account>{
      (Account) TestFactory.createSObject(
        new Account(Name = 'Master Account'),
        false
      ),
      (Account) TestFactory.createSObject(
        new Account(Name = 'Merge One'),
        false
      ),
      (Account) TestFactory.createSObject(
        new Account(Name = 'Merge Two'),
        false
      )
    };

    User restrictedUser = getRestrictedUser();

    // Grant "Create" perms on Account in addition to "Read", but not "Edit" or "Delete"
    assignObjectPermission(restrictedUser, 'Account', true, false, false);

    System.runAs(restrictedUser) {
      Database.insert(accList, AccessLevel.SYSTEM_MODE);

      Account masterAcct = [
        SELECT Id, Name
        FROM Account
        WHERE Name = 'Master Account'
      ];
      List<Account> mergeList = [
        SELECT Id, Name
        FROM Account
        WHERE Name LIKE 'Merge%'
      ];
      Assert.areEqual(2, mergeList.size(), 'There shoudl be 2 items');

      try {
        DMLManager.mergeAsUser(masterAcct, mergeList);
        Assert.fail(
          'Expected a DML Error, Restricted User shouldn\'t be able to merge Account because they don\'t have EDIT permission'
        );
      } catch (DMLManager.CRUDException crudex) {
        //expected
        Assert.areEqual(
          Account.SObjectType,
          crudex.objType,
          'OBject type should be Account'
        );
        Assert.areEqual(
          DMLManager.Operation.OP_UPDATE,
          crudex.op,
          'Operation should be update'
        );
      }
    }

    // 'Master Account' and merge accounts should still be there.
    accList = [SELECT Id FROM Account WHERE Name != :APPLE_ACCOUNT];
    Assert.areEqual(3, accList.size(), 'There should be 3 Accounts');
  }

  @IsTest
  static void mergeAsUserWhenUserDoesNotHaveDeletePermissionExpectError() {
    // Insert a master account and two merge accounts
    List<Account> accList = new List<Account>{
      (Account) TestFactory.createSObject(
        new Account(Name = 'Master Account'),
        false
      ),
      (Account) TestFactory.createSObject(
        new Account(Name = 'Merge One'),
        false
      ),
      (Account) TestFactory.createSObject(
        new Account(Name = 'Merge Two'),
        false
      )
    };

    User restrictedUser = getRestrictedUser();

    // Grant "Create" and "Edit" perms on Account in addition to "Read", but not "Delete"
    assignObjectPermission(restrictedUser, 'Account', true, true, false);

    System.runAs(restrictedUser) {
      Database.insert(accList, AccessLevel.SYSTEM_MODE);

      Account masterAcct = [
        SELECT Id, Name
        FROM Account
        WHERE Name = 'Master Account'
      ];
      List<Account> mergeList = [
        SELECT Id, Name
        FROM Account
        WHERE Name LIKE 'Merge%'
      ];
      Assert.areEqual(2, mergeList.size(), 'Merge list should be 2');

      try {
        DMLManager.mergeAsUser(masterAcct, mergeList);
        Assert.fail(
          'Expected a DML Error, Restricted User shouldn\'t be able to merge Account because they don\'t have DELETE permission'
        );
      } catch (DMLManager.CRUDException crudex) {
        //expected
        Assert.areEqual(
          Account.SObjectType,
          crudex.objType,
          'SObject should be Account'
        );
        Assert.areEqual(
          DMLManager.Operation.OP_DELETE,
          crudex.op,
          'Operation should be Delete'
        );
      }
    }

    // 'Master Account' and merge accounts should still be there.
    accList = [SELECT Id FROM Account WHERE Name != :APPLE_ACCOUNT];
    Assert.areEqual(3, accList.size(), 'Account size shouild be 3');
  }

  @isTest
  static void testFailedUpdateWithErroneousId() {
    Campaign c1 = (Campaign) TestFactory.createSObject(
      new Campaign(Name = 'Test Campaign 1'),
      false
    );
    System.runAs(getMarketingAdmin()) {
      DMLManager.insertAsSystem(c1);
      Id cId = c1.Id;
      DMLManager.deleteAsSystem(c1);

      try {
        Campaign c1Resurrected = new Campaign(
          Id = cId,
          Name = 'Resurrected Campaign'
        );
        DMLManager.upsertAsUser(c1Resurrected);
        Assert.fail(
          'Expected a DMLManagerException! Attempting to update a record with an erroneous Id should fail'
        );
      } catch (DMLManager.DMLManagerException dmle) {
        //expected
        Assert.isTrue(
          dmle.getMessage().contains('An existing record could not be found'),
          'Record should not be found'
        );
      }
    }
  }

  @IsTest
  static void dmlOperationWhenCustomInertDMLOperationsAreSpecifiedExpectNoChangesWithinServer() {
    Contact ctc = (Contact) TestFactory.createSObject(
      new Contact(FirstName = 'Jeremiah', LastName = 'Matthews'),
      false
    );
    String expectedLastName = ctc.LastName;

    // ------ First let's clearly assert the default DML operation is working ------
    DMLManager.insertAsUser(ctc);

    List<Contact> actualContactList = [
      SELECT Id
      FROM Contact
      WHERE FirstName = :ctc.FirstName AND LastName = :ctc.LastName
    ];
    Assert.areEqual(
      1,
      actualContactList.size(),
      'The Salesforce database should contain the new Contact.'
    );

    // ------ Now let's test the DML Operation injection ------
    ctc.LastName = 'Long';

    // Injecting the inert DML class
    DMLManager.setDMLImplementation(new InertDML());

    DMLManager.updateAsUser(ctc);

    // Since the InertDML does nothing, the DMLManager operation respectively does nothing,
    // therefore the Contact is NOT saved within Salesforce.
    actualContactList = [SELECT LastName FROM Contact WHERE Id = :ctc.Id];
    Assert.areEqual(
      expectedLastName,
      actualContactList.get(0).LastName,
      'The Contact should retain the original data.'
    );
  }

  private class InertDML extends DMLManager.SimpleDML {
    public override void dmlDelete(List<SObject> recordsToDelete) {
      return;
    }

    public override void dmlInsert(List<SObject> recordsToInsert) {
      return;
    }

    public override void dmlMerge(
      sObject masterRecord,
      List<SObject> duplicateRecords
    ) {
      return;
    }

    public override void dmlUpdate(List<SObject> recordsToUpdate) {
      return;
    }

    public override void dmlUpsert(List<SObject> recordsToUpsert) {
      return;
    }
  }

  // ─── Helpers ─────────────────────────────────────────────────────────────

  private static Account getAppleAccount() {
    return [
      SELECT Name, ShippingCity
      FROM Account
      WHERE Name = :APPLE_ACCOUNT
      LIMIT 1
    ];
  }

  /**
   * @description Provisions a permission set + ObjectPermissions row + assignment
   *              that grants the supplied user CRUD on `objectType`. Setup-object
   *              DML happens under System.runAs(adminUser) to avoid MIXED_DML
   *              when callers have already touched non-setup data.
   *
   *              Salesforce enforces ObjectPermissions dependencies WITHIN a
   *              permset: "Read Account" requires "Read Contact" be present on
   *              the same permset; "Read Opportunity" requires "Read Account"
   *              (and therefore "Read Contact"). The dependency-satisfier rows
   *              below grant the upstream READs on this permset alongside the
   *              requested CRUD so the platform's FIELD_INTEGRITY_EXCEPTION
   *              (`Permission Read Account depends on permission(s): Read
   *              Contact`) does not fire at insert time. The dependency rows
   *              are read-only, so they don't widen the test's semantic intent
   *              (which is to grant the caller-specified CRUD on `objectType`
   *              only).
   */
  @SuppressWarnings('PMD.ExcessiveParameterList')
  private static void assignObjectPermission(
    User u,
    String objectType,
    Boolean create,
    Boolean edit,
    Boolean remove
  ) {
    System.runAs(getAdminUser()) {
      PermissionSet ps = new PermissionSet(
        Name = 'Enable' + objectType,
        Label = 'Enable ' + objectType
      );
      DMLManager.insertAsSystem(ps);

      List<ObjectPermissions> perms = new List<ObjectPermissions>{
        new ObjectPermissions(
          ParentId = ps.Id,
          PermissionsRead = true,
          PermissionsCreate = create,
          PermissionsEdit = edit,
          PermissionsDelete = remove,
          SObjectType = objectType
        )
      };
      for (String dependency : getReadDependencies(objectType)) {
        perms.add(
          new ObjectPermissions(
            ParentId = ps.Id,
            PermissionsRead = true,
            SObjectType = dependency
          )
        );
      }
      DMLManager.insertAsSystem(perms);

      PermissionSetAssignment assign = new PermissionSetAssignment(
        AssigneeId = u.Id,
        PermissionSetId = ps.Id
      );
      DMLManager.insertAsSystem(assign);
    }
  }

  /**
   * @description Grants the restricted user FLS Edit on every populated field
   *              of `template` by appending FieldPermissions rows to the
   *              Enable&lt;ObjectType&gt; permset already created by
   *              assignObjectPermission. Salesforce caches FieldPermissions
   *              at a deeper tier than ObjectPermissions — adding FLS via a
   *              separate permset and PSA mid-test doesn't always take
   *              effect on the running user's effective FLS, but appending
   *              to an existing permset the user already holds does.
   *              Per-row insert with allOrNone=false so consumer orgs that
   *              reject FLS on a particular field (read-only customs,
   *              compound sub-components) don't break the whole grant.
   */
  private static void grantFlsForTemplate(User u, SObject template) {
    String objectType = String.valueOf(template.getSObjectType());
    Map<String, Object> populatedFields = template.getPopulatedFieldsAsMap();
    System.runAs(getAdminUser()) {
      PermissionSet ps = [
        SELECT Id
        FROM PermissionSet
        WHERE Name = :('Enable' + objectType)
        LIMIT 1
      ];
      Map<String, Schema.SObjectField> fieldMap = Schema.getGlobalDescribe()
        .get(objectType)
        .getDescribe()
        .fields.getMap();
      List<FieldPermissions> rows = new List<FieldPermissions>();
      for (String fieldName : populatedFields.keySet()) {
        if (!fieldMap.containsKey(fieldName.toLowerCase())) {
          continue;
        }
        Schema.DescribeFieldResult fr = fieldMap.get(fieldName.toLowerCase())
          .getDescribe();
        if (
          !fr.isPermissionable() ||
          fr.isCalculated() ||
          !fr.isUpdateable() ||
          !fr.isCreateable()
        ) {
          continue;
        }
        rows.add(
          new FieldPermissions(
            ParentId = ps.Id,
            SobjectType = objectType,
            Field = objectType + '.' + fr.getName(),
            PermissionsRead = true,
            PermissionsEdit = true
          )
        );
      }
      if (!rows.isEmpty()) {
        Database.insert(rows, false, AccessLevel.SYSTEM_MODE);
      }
    }
  }

  /**
   * @description Returns the upstream SObject reads that must accompany a
   *              `Read <objectType>` grant on the same permset to satisfy the
   *              platform's permission-dependency rules. Currently encodes the
   *              two chains exercised by this suite (Account → Contact;
   *              Opportunity → Account → Contact). Extend as new objects join
   *              the suite.
   */
  private static List<String> getReadDependencies(String objectType) {
    switch on objectType {
      when 'Account' {
        return new List<String>{ 'Contact' };
      }
      when 'Opportunity' {
        return new List<String>{ 'Account', 'Contact' };
      }
      when else {
        return new List<String>{};
      }
    }
  }

  /**
   * @description Creates a User with "Read" access to Accounts, Contacts and Opps.
   *              Caller is responsible for wrapping this in System.runAs(adminUser)
   *              when inside @TestSetup or any test-method context that has already
   *              touched non-setup objects.
   *
   * @return The created restricted user.
   */
  private static User createRestrictedUser() {
    User restrictedUser = TestFactory.createMinAccessUser(true);

    PermissionSet ps = new PermissionSet(
      Label = 'Restricted User',
      Name = 'RestrictedUser'
    );
    DMLManager.insertAsSystem(ps);

    List<ObjectPermissions> objectPerms = new List<ObjectPermissions>{
      createObjectPerms(ps.Id, 'Account', true, false, false, false),
      createObjectPerms(ps.Id, 'Contact', true, false, false, false),
      createObjectPerms(ps.Id, 'Opportunity', true, false, false, false)
    };
    DMLManager.insertAsSystem(objectPerms);

    PermissionSetAssignment psa = new PermissionSetAssignment(
      AssigneeId = restrictedUser.Id,
      PermissionSetId = ps.Id
    );
    DMLManager.insertAsSystem(psa);

    return restrictedUser;
  }

  @SuppressWarnings('PMD.ExcessiveParameterList')
  private static ObjectPermissions createObjectPerms(
    Id parentId,
    String objectType,
    Boolean canRead,
    Boolean canCreate,
    Boolean canEdit,
    Boolean canDelete
  ) {
    return new ObjectPermissions(
      ParentId = parentId,
      SobjectType = objectType,
      PermissionsRead = canRead,
      PermissionsCreate = canCreate,
      PermissionsEdit = canEdit,
      PermissionsDelete = canDelete
    );
  }

  private static User getRestrictedUser() {
    return TestFactory.getMinAccessUser();
  }

  /**
   * @description Provisions a System Administrator user with
   *              UserPermissionsMarketingUser = true so Campaign DML works
   *              independent of the test-running user's profile / feature
   *              licence. Caller is responsible for wrapping in
   *              System.runAs(adminUser) inside @TestSetup.
   */
  private static User createMarketingAdmin() {
    Profile sysAdmin = [
      SELECT Id
      FROM Profile
      WHERE Name = 'System Administrator'
      LIMIT 1
    ];
    User mktAdmin = new User(
      ProfileId = sysAdmin.Id,
      LastName = MARKETING_ADMIN_LAST_NAME,
      Email = 'dml-mkt-admin@test.example.com',
      Username = 'dml-mkt-admin@test.example.com' + Crypto.getRandomInteger(),
      CompanyName = 'TEST',
      Title = 'title',
      Alias = 'dmlmkt',
      TimeZoneSidKey = 'America/Los_Angeles',
      EmailEncodingKey = 'UTF-8',
      LanguageLocaleKey = 'en_US',
      LocaleSidKey = 'en_US',
      UserPermissionsMarketingUser = true
    );
    DMLManager.insertAsSystem(mktAdmin);
    return mktAdmin;
  }

  private static User getMarketingAdmin() {
    return [
      SELECT Id
      FROM User
      WHERE LastName = :MARKETING_ADMIN_LAST_NAME
      ORDER BY CreatedDate DESC
      LIMIT 1
    ];
  }

  private static User getAdminUser() {
    return [
      SELECT Id
      FROM User
      WHERE Profile.Name = 'System Administrator' AND IsActive = TRUE
      LIMIT 1
    ];
  }
}
