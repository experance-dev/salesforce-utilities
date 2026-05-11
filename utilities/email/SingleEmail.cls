/**
 * @description Represents a single email message that can be sent using the Salesforce Email Messaging API.
 * This class provides methods to set the email properties such as sender, recipient, subject, and body.
 * It also provides methods to send the email and handle any errors that occur during the sending process.
 *
 * Uses `with sharing` so that record-level visibility for Contact/User/Lead lookups honors the
 * running user's sharing rules. Email sending itself is not sharing-sensitive, but keeping sharing
 * enforced is the safe default and consistent with caller expectations.
 *
 * @group   Email
 * @author  David Wood
 * @since   April 2024
 * @last    May 2026 — Wave 5 conformance: explicit sharing, Logger, SingleEmailException, header cleanup
 */
public with sharing class SingleEmail {
  // ─── Inner exception ────────────────────────────────────────────────────────

  /** Custom exception for SingleEmail errors. */
  public class SingleEmailException extends UtilitiesModuleException {}

  // ─── Constants ──────────────────────────────────────────────────────────────

  private static final Integer RECURSION_MAX = 5;
  @TestVisible
  private static final String DEFAULT_SENDER_DISPLAY_NAME = 'Salesforce Support';

  // ─── Public properties ──────────────────────────────────────────────────────

  public List<String> toAddresses;
  public List<String> ccAddresses;
  public List<String> bccAddresses;
  public String senderDisplayName;
  public String replyTo;
  public String subject;
  public String plainBody;
  public String htmlBody;
  public Boolean allOrNone;

  // ─── Constructors ───────────────────────────────────────────────────────────

  public SingleEmail() {
    this.toAddresses = new List<String>();
    this.ccAddresses = new List<String>();
    this.bccAddresses = new List<String>();
    this.allOrNone = false;
  }

  /**
   * @param toAddress The email address of the recipient.
   * @param subject   The subject of the email.
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

  // ─── Public API ─────────────────────────────────────────────────────────────

  /**
   * Sends the email message.
   * @return `true` if the email was sent successfully; `false` if there were no recipients.
   */
  public Boolean sendMail() {
    Integer recipients =
      toAddresses.size() +
      ccAddresses.size() +
      bccAddresses.size();

    if (recipients == 0) {
      return false;
    }

    try {
      Messaging.reserveSingleEmailCapacity(recipients);
      Messaging.SingleEmailMessage mail = new Messaging.SingleEmailMessage();
      mail.setToAddresses(toAddresses);
      mail.setCcAddresses(ccAddresses);
      mail.setBccAddresses(bccAddresses);
      mail.setSenderDisplayName(
        senderDisplayName != null ? senderDisplayName : DEFAULT_SENDER_DISPLAY_NAME
      );
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
        results = Messaging.sendEmail(
          new List<Messaging.SingleEmailMessage>{ mail },
          allOrNone
        );
      } else {
        results = new Messaging.SendEmailResult[0];
      }

      return inspectResults(results);
    } catch (Exception e) {
      Logger.logException(e, 'SingleEmail', 'sendMail');
      throw new SingleEmailException(
        'An error occurred while sending email: '
          + e.getMessage()
          + ' - '
          + e.getStackTraceString()
      );
    }
  }

  // ─── Private helpers ────────────────────────────────────────────────────────

  /**
   * Inspects send results and logs individual failures.
   * @param results Array of SendEmailResult objects from Messaging.sendEmail.
   * @return `true` if all results succeeded (or results is empty).
   */
  @TestVisible
  private static Boolean inspectResults(Messaging.SendEmailResult[] results) {
    if (results == null && Test.isRunningTest()) {
      return true;
    }

    Boolean sendResult = true;
    for (Messaging.SendEmailResult res : results) {
      if (!res.isSuccess()) {
        sendResult = false;
        Logger.warn(
          'SingleEmail.inspectResults: send failure — ' + res.getErrors()
        );
      }
    }
    return sendResult;
  }
}
