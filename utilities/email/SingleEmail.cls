/**
 * @description Represents a single email message that can be sent using the Salesforce Email Messaging API.
 * This class provides methods to set the email properties such as sender, recipient, subject, and body.
 * It also provides methods to send the email and handle any errors that occur during the sending process.
 *
 * @group   EmailMessaging
 * @author  David Wood
 * @since   April 2024
 */
public with sharing class SingleEmail {
  private static final Integer RECURSION_MAX = 5; // Maximum recursion depth for preventing infinite loops

  public List<String> toAddresses; // List of recipient email addresses
  public List<String> ccAddresses; // List of CC email addresses
  public List<String> bccAddresses; // List of BCC email addresses
  public String senderDisplayName; // Display name for the email sender
  public String replyTo; // Reply-to email address
  public String subject; // Subject of the email
  public String plainBody; // Plain text body of the email
  public String htmlBody; // HTML body of the email
  public Boolean allOrNone; // Flag to indicate whether the email sending should be all-or-none

  /**
   * @description Default constructor for the SingleEmail class.
   * Initializes the toAddresses, ccAddresses, bccAddresses, and allOrNone properties.
   */
  public SingleEmail() {
    this.toAddresses = new List<String>();
    this.ccAddresses = new List<String>();
    this.bccAddresses = new List<String>();
    this.allOrNone = false;
  }

  /**
   * @description Constructor for the SingleEmail class that allows setting the toAddress, subject, and plainBody properties.
   * Initializes the toAddresses, ccAddresses, bccAddresses, subject, plainBody, and allOrNone properties.
   * @param toAddress The email address of the recipient.
   * @param subject The subject of the email.
   * @param plainBody The plain text body of the email.
   */
  public SingleEmail(String toAddress, String subject, String plainBody) {
    this.toAddresses = new List<String>{ toAddress };
    this.ccAddresses = new List<String>();
    this.bccAddresses = new List<String>();
    this.subject = subject;
    this.plainBody = plainBody;
    this.allOrNone = false;
  }

  /**
   * @description Sends the email message.
   * @return A boolean value indicating whether the email was sent successfully.
   */
  public Boolean sendMail() {
    Integer recipients =
      toAddresses.size() +
      ccAddresses.size() +
      bccAddresses.size();

    if (recipients == 0) {
      // No recipients to send the email to
      return false;
    }

    Messaging.reserveSingleEmailCapacity(recipients);
    Messaging.SingleEmailMessage mail = new Messaging.SingleEmailMessage();
    mail.setToAddresses(toAddresses);
    mail.setCcAddresses(ccAddresses);
    mail.setBccAddresses(bccAddresses);

    if (senderDisplayName != null) {
      mail.setSenderDisplayName(senderDisplayName);
    } else {
      mail.setSenderDisplayName('Salesforce Support');
    }

    mail.setReplyTo(replyTo);
    mail.setSubject(subject);

    if (plainBody != null) {
      mail.setPlainTextBody(plainBody);
    }
    if (htmlBody != null) {
      mail.setHtmlBody(htmlBody);
    }

    Messaging.SendEmailResult[] results;

    if (!Test.isRunningTest()) {
      List<Messaging.SingleEmailMessage> mails = new List<Messaging.SingleEmailMessage>{
        mail
      };
      results = Messaging.sendEmail(mails, allOrNone);
    } else {
      results = new Messaging.SendEmailResult[0]; // Mock results for testing
    }

    return inspectResults(results);
  }

  /**
   * @description Helper method to inspect the results of the email sending operation.
   * @param results An array of SendEmailResult objects representing the results of the email sending operation.
   * @return A boolean value indicating whether the email was sent successfully.
   */
  @TestVisible
  private static Boolean inspectResults(Messaging.SendEmailResult[] results) {
    Boolean sendResult = true;

    if (results == null && Test.isRunningTest()) {
      return true;
    }

    for (Messaging.SendEmailResult res : results) {
      if (!res.isSuccess()) {
        sendResult = false;
        System.debug(
          'The following errors occurred sending email: ' + res.getErrors()
        ); //NOPMD.AvoidDebugStatements
      }
    }
    return sendResult;
  }
}
