/**
 * @description Test class for SingleEmail. Asserts built-message shape from buildEmail(),
 *              dispatch through a capturing fake dispatcher (nothing is ever actually sent —
 *              dispatch tests assert zero email invocations), sender display name fallback
 *              resolution, and the failure path through inspectResults via a fake failed
 *              send result. No test in this class calls Messaging.sendEmail.
 * @group Email
 * @see SingleEmail
 * @author David Wood
 * @since March 2024
 * @last May 2026 — conformance refactor
 * @last August 2026 — rewritten around buildEmail() and the capturing dispatcher fake; no real dispatch anywhere
 */
@isTest
private without sharing class SingleEmailTest {
  static final String TO_ADDRESS = 'recipient@mailinator.com';
  static final String CC_ADDRESS = 'copy@mailinator.com';
  static final String BCC_ADDRESS = 'blindcopy@mailinator.com';
  static final String REPLY_TO_ADDRESS = 'replies@mailinator.com';

  /**
   * Capturing fake for the dispatcher seam: records what sendMail() hands it and returns a
   * configurable result list. Never touches Messaging.sendEmail.
   */
  private class CapturingEmailDispatcher implements SingleEmail.IEmailDispatcher {
    public List<Messaging.SingleEmailMessage> capturedMessages = new List<Messaging.SingleEmailMessage>();
    public Boolean capturedAllOrNone;
    public List<SingleEmail.SendResult> resultsToReturn = new List<SingleEmail.SendResult>();

    public List<SingleEmail.SendResult> send(
      List<Messaging.SingleEmailMessage> messages,
      Boolean allOrNone
    ) {
      this.capturedMessages.addAll(messages);
      this.capturedAllOrNone = allOrNone;
      return resultsToReturn;
    }
  }

  /**
   * Builds a failed send result — the library-owned SendResult is freely constructible,
   * so the failure path needs no platform-type tricks.
   */
  private static SingleEmail.SendResult buildFailedSendResult() {
    return new SingleEmail.SendResult(
      false,
      new List<String>{ 'Simulated send failure' }
    );
  }

  @TestSetup
  static void makeData() {
    TestFactory.createTestUser();
  }

  @isTest
  static void testBuildEmailAssemblesAllFields() {
    System.runAs(TestFactory.getCreatedTestUser()) {
      SingleEmail email = new SingleEmail();
      email.toAddresses.add(TO_ADDRESS);
      email.ccAddresses.add(CC_ADDRESS);
      email.bccAddresses.add(BCC_ADDRESS);
      email.senderDisplayName = 'Sender Name';
      email.replyTo = REPLY_TO_ADDRESS;
      email.subject = 'Complete Email';
      email.plainBody = 'This is a plain text body';
      email.htmlBody = '<p>This is an HTML body</p>';

      Test.startTest();
      Messaging.SingleEmailMessage mail = email.buildEmail();
      Integer emailInvocations = Limits.getEmailInvocations();
      Test.stopTest();

      Assert.areEqual(
        new List<String>{ TO_ADDRESS },
        mail.getToAddresses(),
        'To addresses should carry through to the built message'
      );
      Assert.areEqual(
        new List<String>{ CC_ADDRESS },
        mail.getCcAddresses(),
        'Cc addresses should carry through to the built message'
      );
      Assert.areEqual(
        new List<String>{ BCC_ADDRESS },
        mail.getBccAddresses(),
        'Bcc addresses should carry through to the built message'
      );
      Assert.areEqual(
        'Sender Name',
        mail.getSenderDisplayName(),
        'Per-message sender display name should win when set'
      );
      Assert.areEqual(
        REPLY_TO_ADDRESS,
        mail.getReplyTo(),
        'Reply-to should carry through to the built message'
      );
      Assert.areEqual(
        'Complete Email',
        mail.getSubject(),
        'Subject should carry through to the built message'
      );
      Assert.areEqual(
        'This is a plain text body',
        mail.getPlainTextBody(),
        'Plain text body should carry through to the built message'
      );
      Assert.areEqual(
        '<p>This is an HTML body</p>',
        mail.getHtmlBody(),
        'HTML body should carry through to the built message'
      );
      Assert.areEqual(
        0,
        emailInvocations,
        'buildEmail() must never dispatch email'
      );
    }
  }

  @isTest
  static void testBuildEmailSenderDefaultsToOrgDefault() {
    System.runAs(TestFactory.getCreatedTestUser()) {
      SingleEmail email = new SingleEmail(TO_ADDRESS, 'Subject', 'Body');

      Test.startTest();
      Messaging.SingleEmailMessage mail = email.buildEmail();
      Test.stopTest();

      // Neither the message nor the static fallback set a sender display name,
      // so the built message leaves it unset and the org default applies.
      Assert.isNull(
        mail.getSenderDisplayName(),
        'With no per-message or static sender, the display name should stay unset (org default)'
      );
    }
  }

  @isTest
  static void testBuildEmailAppliesStaticSenderFallback() {
    System.runAs(TestFactory.getCreatedTestUser()) {
      SingleEmail.defaultSenderDisplayName = 'Utilities Notifications';
      SingleEmail email = new SingleEmail(TO_ADDRESS, 'Subject', 'Body');

      Test.startTest();
      Messaging.SingleEmailMessage mail = email.buildEmail();
      Test.stopTest();

      Assert.areEqual(
        'Utilities Notifications',
        mail.getSenderDisplayName(),
        'The static default should apply when the per-message sender is unset'
      );
    }
  }

  @isTest
  static void testSendMailDispatchesThroughSeam() {
    System.runAs(TestFactory.getCreatedTestUser()) {
      CapturingEmailDispatcher fakeDispatcher = new CapturingEmailDispatcher();
      SingleEmail.dispatcher = fakeDispatcher;

      SingleEmail email = new SingleEmail(
        TO_ADDRESS,
        'Test Subject',
        'This is the plain text body'
      );

      Test.startTest();
      Boolean result = email.sendMail();
      Integer emailInvocations = Limits.getEmailInvocations();
      Test.stopTest();

      Assert.areEqual(
        true,
        result,
        'sendMail() should report success when every dispatcher result succeeds'
      );
      Assert.areEqual(
        1,
        fakeDispatcher.capturedMessages.size(),
        'Exactly one message should reach the dispatcher'
      );
      Assert.areEqual(
        new List<String>{ TO_ADDRESS },
        fakeDispatcher.capturedMessages[0].getToAddresses(),
        'The dispatched message should carry the recipient'
      );
      Assert.areEqual(
        false,
        fakeDispatcher.capturedAllOrNone,
        'allOrNone should pass through the seam unchanged'
      );
      Assert.areEqual(
        0,
        emailInvocations,
        'No real email may ever be dispatched from a test'
      );
    }
  }

  @isTest
  static void testSendMailNoRecipientsReturnsFalseWithoutDispatch() {
    System.runAs(TestFactory.getCreatedTestUser()) {
      CapturingEmailDispatcher fakeDispatcher = new CapturingEmailDispatcher();
      SingleEmail.dispatcher = fakeDispatcher;

      SingleEmail email = new SingleEmail();
      email.subject = 'No Recipients';
      email.plainBody = 'This email has no recipients';

      Test.startTest();
      Boolean result = email.sendMail();
      Integer emailInvocations = Limits.getEmailInvocations();
      Test.stopTest();

      Assert.areEqual(
        false,
        result,
        'No recipients should lead to sendMail returning false'
      );
      Assert.areEqual(
        0,
        fakeDispatcher.capturedMessages.size(),
        'The dispatcher must not be invoked when there are no recipients'
      );
      Assert.areEqual(
        0,
        emailInvocations,
        'No real email may ever be dispatched from a test'
      );
    }
  }

  @isTest
  static void testSendMailReportsFailureFromDispatcherResults() {
    System.runAs(TestFactory.getCreatedTestUser()) {
      CapturingEmailDispatcher fakeDispatcher = new CapturingEmailDispatcher();
      fakeDispatcher.resultsToReturn.add(buildFailedSendResult());
      SingleEmail.dispatcher = fakeDispatcher;

      SingleEmail email = new SingleEmail(
        TO_ADDRESS,
        'Test Subject',
        'This is the plain text body'
      );

      Test.startTest();
      Boolean result = email.sendMail();
      Integer emailInvocations = Limits.getEmailInvocations();
      Test.stopTest();

      Assert.areEqual(
        false,
        result,
        'A failed dispatcher result should make sendMail return false through inspectResults'
      );
      Assert.areEqual(
        0,
        emailInvocations,
        'No real email may ever be dispatched from a test'
      );
    }
  }

  @isTest
  static void testConstructorWithParams() {
    System.runAs(TestFactory.getCreatedTestUser()) {
      Test.startTest();
      SingleEmail email = new SingleEmail(TO_ADDRESS, 'Subject', 'Body');
      Test.stopTest();

      Assert.areEqual(
        1,
        email.toAddresses.size(),
        'The email should have one recipient'
      );
      Assert.areEqual(
        TO_ADDRESS,
        email.toAddresses[0],
        'The recipient should match the constructor argument'
      );
      Assert.areEqual(
        'Subject',
        email.subject,
        'The subject should match the constructor argument'
      );
      Assert.areEqual(
        'Body',
        email.plainBody,
        'The plain body should match the constructor argument'
      );
    }
  }
}
