/**
 * @description This class contains test methods for the SingleEmail class.
 */
@isTest
public class SingleEmailTest {
  /**
   * @description This method is used to set up test data before running the test methods.
   */
  @TestSetup
  static void makeData() {
    TestFactory.createTestUser();
  }

  /**
   * @description Positive test for sending an email with minimum required fields.
   */
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
      System.assertEquals(true, result, 'sendMail() should return true');
    }
    Test.stopTest();
  }

  /**
   * @description Positive test for sending an email with all fields filled.
   */
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

      System.assertEquals(true, result, 'sendMail() should return true');
    }
    Test.stopTest();
  }

  /**
   * @description Negative test for sending an email without recipients.
   */
  @isTest
  static void testSendEmailNoRecipients() {
    Test.startTest();
    System.runAs(TestFactory.getCreatedTestUser()) {
      SingleEmail email = new SingleEmail();
      email.subject = 'No Recipients';
      email.plainBody = 'This email has no recipients';

      Boolean result = email.sendMail();

      // No recipients should lead to sendMail returning false
      System.assertEquals(
        false,
        result,
        'No recipients should lead to sendMail returning false'
      );
    }
    Test.stopTest();
  }

  /**
   * @description Test for the constructor that takes parameters.
   */
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
      System.assertEquals(
        1,
        email.toAddresses.size(),
        'The email should have one recipient'
      );

      // Verify that the recipient is 'test@example.com'
      System.assertEquals(
        'test@example.com',
        email.toAddresses[0],
        'The recipient should be test@example.com'
      );

      // Verify that the subject of the email is 'Subject'
      System.assertEquals(
        'Subject',
        email.subject,
        'The subject should be Subject'
      );

      // Verify that the plain body of the email is 'Body'
      System.assertEquals(
        'Body',
        email.plainBody,
        'The plain body should be Body'
      );
    }
    Test.stopTest();
  }
}
