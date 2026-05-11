/**
 * @description Test class for SingleEmail.
 * @group Email
 * @see SingleEmail
 * @author David Wood
 * @since March 2024
 * @last May 2026 — Wave 6 conformance
 */
@isTest
public without sharing class SingleEmailTest {
  @TestSetup
  static void makeData() {
    TestFactory.createTestUser();
  }

  @isTest
  static void testSendEmailWithMinimumFields() {
    Test.startTest();
    System.runAs(TestFactory.getCreatedTestUser()) {
      SingleEmail email = new SingleEmail(
        'test@example.com',
        'Test Subject',
        'This is the plain text body'
      );
      Boolean result = email.sendMail();

      // As we are running in a test context, sendMail() should return true
      Assert.areEqual(true, result, 'sendMail() should return true');
    }
    Test.stopTest();
  }

  @isTest
  static void testSendEmailWithAllFields() {
    Test.startTest();
    System.runAs(TestFactory.getCreatedTestUser()) {
      SingleEmail email = new SingleEmail();
      email.toAddresses.add('test@example.com');
      email.ccAddresses.add('cc@example.com');
      email.bccAddresses.add('bcc@example.com');
      email.senderDisplayName = 'Sender Name';
      email.replyTo = 'reply@example.com';
      email.subject = 'Complete Email';
      email.plainBody = 'This is a plain text body';
      email.htmlBody = '<p>This is an HTML body</p>';

      Boolean result = email.sendMail();

      Assert.areEqual(true, result, 'sendMail() should return true');
    }
    Test.stopTest();
  }

  @isTest
  static void testSendEmailNoRecipients() {
    Test.startTest();
    System.runAs(TestFactory.getCreatedTestUser()) {
      SingleEmail email = new SingleEmail();
      email.subject = 'No Recipients';
      email.plainBody = 'This email has no recipients';

      Boolean result = email.sendMail();

      // No recipients should lead to sendMail returning false
      Assert.areEqual(
        false,
        result,
        'No recipients should lead to sendMail returning false'
      );
    }
    Test.stopTest();
  }

  @isTest
  static void testConstructorWithParams() {
    Test.startTest();
    System.runAs(TestFactory.getCreatedTestUser()) {
      SingleEmail email = new SingleEmail(
        'test@example.com',
        'Subject',
        'Body'
      );

      // Verify that the email has one recipient
      Assert.areEqual(
        1,
        email.toAddresses.size(),
        'The email should have one recipient'
      );

      // Verify that the recipient is 'test@example.com'
      Assert.areEqual(
        'test@example.com',
        email.toAddresses[0],
        'The recipient should be test@example.com'
      );

      // Verify that the subject of the email is 'Subject'
      Assert.areEqual(
        'Subject',
        email.subject,
        'The subject should be Subject'
      );

      // Verify that the plain body of the email is 'Body'
      Assert.areEqual(
        'Body',
        email.plainBody,
        'The plain body should be Body'
      );
    }
    Test.stopTest();
  }
}
