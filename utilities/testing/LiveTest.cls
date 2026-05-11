// NOT FOR PRODUCTION   ONLY FOR INTERNAL TESTING

@IsTest(SeeAllData=true)
public with sharing class LiveTest {
  @isTest
  public static void TestLive() {
    User user = [
      SELECT Id, LastName, FirstName, Name
      FROM User
      WHERE Name = 'NEX Machine Admin'
      LIMIT 1
    ];
    System.runAs(user) {
      update (new Product2(Id = '01t6A00000422PqQAI', IsActive = false));
    }

  }
}
