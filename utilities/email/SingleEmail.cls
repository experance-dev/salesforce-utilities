/**
 * @description Represents a single email message that can be sent using the Salesforce Email Messaging API.
 * This class provides methods to set the email properties such as sender, recipient, subject, and body.
 * Assembly and dispatch are separate steps: `buildEmail()` returns the fully-populated
 * `Messaging.SingleEmailMessage` without sending it, and `sendMail()` hands that message to an
 * injectable `IEmailDispatcher` seam whose production implementation reserves capacity and calls
 * `Messaging.sendEmail`. Tests inject a capturing fake through the `@TestVisible` dispatcher field,
 * so no test path ever dispatches real email.
 *
 * Sender display name resolution: the per-message `senderDisplayName` property wins when set;
 * otherwise the static `defaultSenderDisplayName` applies (null by default, which leaves the
 * message's sender display name unset so the org default is used).
 *
 * Uses `with sharing` so that record-level visibility for Contact/User/Lead lookups honors the
 * running user's sharing rules. Email sending itself is not sharing-sensitive, but keeping sharing
 * enforced is the safe default and consistent with caller expectations.
 *
 * @group   Email
 * @author  David Wood
 * @since   April 2024
 * @last    May 2026 — conformance refactor: explicit sharing, Logger, SingleEmailException, header cleanup
 * @last    August 2026 — build/dispatch split: buildEmail() returns the message, injectable dispatcher seam
 *                        returning library-owned SendResult, sanitized rethrow, org-default sender fallback
 */
public with sharing class SingleEmail {
  // ─── Inner exception ────────────────────────────────────────────────────────

  /** Custom exception for SingleEmail errors. */
  public class SingleEmailException extends UtilitiesModuleException {}

  // ─── Dispatcher seam ────────────────────────────────────────────────────────

  /**
   * @description Library-owned per-message send outcome. The platform's
   *              `Messaging.SendEmailResult` has no public constructor, so a seam typed
   *              on it can never fabricate a failure in a test; this wrapper is freely
   *              constructible, which is the entire point — fakes can script any reply
   *              (success, partial failure, capacity error) and the failure branch stays
   *              testable.
   */
  public class SendResult {
    /** @description True when the message dispatched successfully. */
    public Boolean success { get; private set; }
    /** @description Error messages for a failed dispatch; empty on success. */
    public List<String> errors { get; private set; }

    /**
     * @description Builds a result.
     * @param success Whether the dispatch succeeded.
     * @param errors  Error messages; null is normalized to an empty list.
     */
    public SendResult(Boolean success, List<String> errors) {
      this.success = success;
      this.errors = errors == null ? new List<String>() : errors;
    }
  }

  /**
   * @description Dispatch seam for outbound email. The production implementation calls
   *              `Messaging.sendEmail`; tests inject a capturing fake so nothing is sent
   *              and any reply can be scripted via `SendResult`.
   */
  public interface IEmailDispatcher {
    /**
     * @description Dispatches the batch and returns one result per message. Must return a
     *              non-null list.
     * @param messages  Fully-assembled messages to dispatch.
     * @param allOrNone When true, any single failure rolls back the whole batch.
     * @return One `SendResult` per dispatched message.
     */
    List<SendResult> send(
      List<Messaging.SingleEmailMessage> messages,
      Boolean allOrNone
    );
  }

  /**
   * @description Production dispatcher — reserves single-email capacity for the batch's
   *              recipients, hands the messages to `Messaging.sendEmail`, and maps the
   *              platform results onto the library-owned `SendResult` type.
   */
  public class EmailDispatcherImpl implements IEmailDispatcher {
    /**
     * @description Reserves capacity for every recipient in the batch, then dispatches.
     * @param messages  Fully-assembled messages to dispatch.
     * @param allOrNone When true, any single failure rolls back the whole batch.
     * @return One `SendResult` per dispatched message.
     */
    public List<SendResult> send(
      List<Messaging.SingleEmailMessage> messages,
      Boolean allOrNone
    ) {
      Integer recipientCount = 0;
      for (Messaging.SingleEmailMessage message : messages) {
        recipientCount += countOf(message.getToAddresses());
        recipientCount += countOf(message.getCcAddresses());
        recipientCount += countOf(message.getBccAddresses());
      }
      Messaging.reserveSingleEmailCapacity(recipientCount);
      List<SendResult> mapped = new List<SendResult>();
      for (Messaging.SendEmailResult platformResult : Messaging.sendEmail(messages, allOrNone)) {
        List<String> errorMessages = new List<String>();
        for (Messaging.SendEmailError err : platformResult.getErrors()) {
          errorMessages.add(err.getMessage());
        }
        mapped.add(new SendResult(platformResult.isSuccess(), errorMessages));
      }
      return mapped;
    }

    private Integer countOf(List<String> addresses) {
      return addresses == null ? 0 : addresses.size();
    }
  }

  @TestVisible
  private static IEmailDispatcher dispatcher = new EmailDispatcherImpl();

  // ─── Defaults ───────────────────────────────────────────────────────────────

  /**
   * Fallback sender display name applied when a message's own `senderDisplayName` is unset.
   * Null (the default) leaves the sender display name off the message entirely, so the org
   * default applies. Set once per org (or per transaction) to brand outbound mail.
   */
  @TestVisible
  private static String defaultSenderDisplayName = null;

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
   * @description Assembles and returns the `Messaging.SingleEmailMessage` from this instance's
   *              properties without sending it. The sender display name is the per-message
   *              `senderDisplayName` when set, else the static `defaultSenderDisplayName`,
   *              else unset (org default).
   * @return The fully-populated message, ready for dispatch.
   */
  public Messaging.SingleEmailMessage buildEmail() {
    Messaging.SingleEmailMessage mail = new Messaging.SingleEmailMessage();
    mail.setToAddresses(toAddresses);
    mail.setCcAddresses(ccAddresses);
    mail.setBccAddresses(bccAddresses);

    String resolvedSenderDisplayName = senderDisplayName != null
      ? senderDisplayName
      : defaultSenderDisplayName;
    if (resolvedSenderDisplayName != null) {
      mail.setSenderDisplayName(resolvedSenderDisplayName);
    }

    mail.setReplyTo(replyTo);
    mail.setSubject(subject);

    if (plainBody != null) {
      mail.setPlainTextBody(plainBody);
    }
    if (htmlBody != null) {
      mail.setHtmlBody(htmlBody);
    }
    return mail;
  }

  /**
   * @description Builds the message via `buildEmail()` and dispatches it through the
   *              `IEmailDispatcher` seam, then inspects the send results.
   * @return `true` if every result succeeded; `false` if there were no recipients or any
   *         result reported failure.
   * @throws SingleEmailException When dispatch throws — the rethrown message carries only the
   *         exception type name and the transaction request ID; full detail goes to the Logger.
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
      List<SendResult> results = dispatcher.send(
        new List<Messaging.SingleEmailMessage>{ buildEmail() },
        allOrNone
      );
      return inspectResults(results);
    } catch (Exception e) {
      Logger.logException(e, 'SingleEmail', 'sendMail');
      throw new SingleEmailException(
        'Email send failed. Contact your administrator. ' +
          e.getTypeName() +
          ' [txn:' +
          System.Request.getCurrent().getRequestId() +
          ']'
      );
    }
  }

  // ─── Private helpers ────────────────────────────────────────────────────────

  /**
   * Inspects send results and logs individual failures.
   * @param results One `SendResult` per dispatched message.
   * @return `true` if all results succeeded (or results is empty).
   */
  @TestVisible
  private static Boolean inspectResults(List<SendResult> results) {
    Boolean sendResult = true;
    for (SendResult res : results) {
      if (!res.success) {
        sendResult = false;
        Logger.warn(
          'SingleEmail.inspectResults: send failure — ' + String.join(res.errors, '; ')
        );
      }
    }
    return sendResult;
  }
}
