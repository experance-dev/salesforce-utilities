/**
 * @description HTTP client for outbound REST callouts through Named
 *              Credentials. Construction requires a Named Credential name —
 *              there is no raw-URL path — so every reachable endpoint is one
 *              an admin deliberately configured, and authentication stays
 *              with the platform instead of Apex string-building. Default
 *              headers are per-instance state: two clients serving two
 *              integrations can never bleed an Authorization header into
 *              each other. PATCH goes out natively via setMethod('PATCH').
 *              Query strings are encoded value-by-value — reserved characters
 *              inside a parameter value are escaped while the ?/=/& structure
 *              survives. Extend this class to build a full API service, or
 *              use the static makeApiCall wrappers for a one-off callout.
 *              Sharing: `with sharing` so user-initiated callouts keep the
 *              running user's record-visibility context in subclasses.
 * @group REST
 * @author David Wood
 * @since June 2024
 * @last May 2026 — conformance refactor: `with sharing`, RestClientException,
 *                  Logger.logException wrapping.
 * @last August 2026 — rewrite: named-credential-only construction,
 *                     per-instance default headers, native PATCH, value-only
 *                     query encoding, configurable timeout, sanitized errors;
 *                     analyzer conformance.
 */
public with sharing virtual class RestClient {
  private static final Integer DEFAULT_TIMEOUT_MILLIS = 120000;

  // Verbs whose requests carry a body; GET/HEAD/DEL never set one.
  private static final Set<HttpVerb> BODY_VERBS = new Set<HttpVerb>{
    HttpVerb.POST,
    HttpVerb.PUT,
    HttpVerb.PATCH
  };

  /**
   * Per-instance default headers, applied when a call site passes none.
   * Instance state on purpose: a static map here once let one integration's
   * Authorization header leak into every other client in the transaction.
   */
  @testVisible
  protected Map<String, String> defaultHeaders = new Map<String, String>{
    'Content-Type' => 'application/json',
    'Accept' => 'application/json'
  };

  /** Callout timeout in milliseconds; 120 seconds unless configured. */
  @testVisible
  protected Integer timeoutMillis = DEFAULT_TIMEOUT_MILLIS;

  /**
   * @description The Named Credential every request on this instance routes
   *              through.
   */
  @testVisible
  protected String namedCredentialName { get; set; }

  /**
   * @description Thrown for every failed callout. The message carries only
   *              the exception type and a correlation id — full detail goes
   *              to Logger, never to the caller-facing string.
   */
  public class RestClientException extends UtilitiesModuleException {}

  /** HTTP verbs. 'Delete' is a DML keyword, so DEL stands in for DELETE. */
  public enum HttpVerb {
    GET,
    POST,
    PATCH,
    PUT,
    HEAD,
    DEL
  }

  /**
   * @description Builds a client that routes every request through the given
   *              Named Credential.
   * @param namedCredential Name of the Named Credential to call through.
   */
  public RestClient(String namedCredential) {
    this.namedCredentialName = namedCredential;
  }

  /**
   * @description Builds a client with extra default headers merged over the
   *              JSON defaults, applied to every request this instance sends.
   * @param namedCredential Name of the Named Credential to call through.
   * @param headers         Headers merged into this instance's defaults.
   */
  public RestClient(String namedCredential, Map<String, String> headers) {
    this(namedCredential);
    if (headers != null) {
      this.defaultHeaders.putAll(headers);
    }
  }

  /**
   * @description Overrides the default 120-second callout timeout.
   * @param timeoutMillis Timeout in milliseconds for subsequent requests.
   * @return This instance, for fluent configuration.
   */
  public RestClient withTimeout(Integer timeoutMillis) {
    this.timeoutMillis = timeoutMillis;
    return this;
  }

  /**
   * @description Omnibus callout method — every verb shortcut and static
   *              wrapper delegates here.
   * @param method  HTTP verb to send.
   * @param path    Path below the Named Credential's URL, e.g. `/orders/v1`.
   * @param query   Query string; values are URL-encoded, structure is kept.
   * @param body    Request body for POST/PUT/PATCH; ignored otherwise.
   * @param headers Headers for this request only; null uses instance defaults.
   * @return        The endpoint's HttpResponse. Non-2xx responses are
   *                returned, not thrown — status handling belongs to callers.
   * @throws RestClientException When the callout itself fails; the message is
   *                             sanitized to exception type + correlation id.
   */
  @SuppressWarnings('PMD.ExcessiveParameterList')
  public virtual HttpResponse makeApiCall(
    HttpVerb method,
    String path,
    String query,
    String body,
    Map<String, String> headers
  ) {
    HttpRequest request = buildRequest(method, path, query, body, headers);
    try {
      return new Http().send(request);
    } catch (CalloutException e) {
      Logger.logException(e, 'RestClient', 'makeApiCall');
      throw new RestClientException(
        'Callout through named credential ' + this.namedCredentialName +
        ' failed. ' + e.getTypeName() +
        ' [txn:' + System.Request.getCurrent().getRequestId() + ']'
      );
    }
  }

  /**
   * @description Sends a GET request with no query string.
   * @param path Path below the Named Credential's URL.
   * @return     The endpoint's HttpResponse.
   */
  public HttpResponse get(String path) {
    return makeApiCall(HttpVerb.GET, path, '', '', null);
  }

  /**
   * @description Sends a GET request.
   * @param path  Path below the Named Credential's URL.
   * @param query Query string; pass an empty string for none.
   * @return      The endpoint's HttpResponse.
   */
  public HttpResponse get(String path, String query) {
    return makeApiCall(HttpVerb.GET, path, query, '', null);
  }

  /**
   * @description Sends an HTTP DELETE request.
   * @param path  Path below the Named Credential's URL.
   * @param query Query string; pass an empty string for none.
   * @return      The endpoint's HttpResponse.
   */
  public HttpResponse del(String path, String query) {
    return makeApiCall(HttpVerb.DEL, path, query, '', null);
  }

  /**
   * @description Sends a POST request.
   * @param path  Path below the Named Credential's URL.
   * @param query Query string; pass an empty string for none.
   * @param body  Request body.
   * @return      The endpoint's HttpResponse.
   */
  public HttpResponse post(String path, String query, String body) {
    return makeApiCall(HttpVerb.POST, path, query, body, null);
  }

  /**
   * @description Sends a PUT request.
   * @param path  Path below the Named Credential's URL.
   * @param query Query string; pass an empty string for none.
   * @param body  Request body.
   * @return      The endpoint's HttpResponse.
   */
  public HttpResponse put(String path, String query, String body) {
    return makeApiCall(HttpVerb.PUT, path, query, body, null);
  }

  /**
   * @description Sends a native PATCH request — no `_HttpMethod` query hack.
   * @param path  Path below the Named Credential's URL.
   * @param query Query string; pass an empty string for none.
   * @param body  Request body.
   * @return      The endpoint's HttpResponse.
   */
  public HttpResponse patch(String path, String query, String body) {
    return makeApiCall(HttpVerb.PATCH, path, query, body, null);
  }

  /**
   * @description One-off callout without constructing a client explicitly.
   * @param namedCredential Named Credential to call through.
   * @param method          HTTP verb to send.
   * @param path            Path below the Named Credential's URL.
   * @param query           Query string; values are URL-encoded.
   * @param body            Request body for POST/PUT/PATCH.
   * @param headers         Request headers; null uses the JSON defaults.
   * @return                The endpoint's HttpResponse.
   */
  @SuppressWarnings('PMD.ExcessiveParameterList')
  public static HttpResponse makeApiCall(
    String namedCredential,
    HttpVerb method,
    String path,
    String query,
    String body,
    Map<String, String> headers
  ) {
    return new RestClient(namedCredential)
      .makeApiCall(method, path, query, body, headers);
  }

  /**
   * @description One-off callout — path only, default headers.
   * @param namedCredential Named Credential to call through.
   * @param method          HTTP verb to send.
   * @param path            Path below the Named Credential's URL.
   * @return                The endpoint's HttpResponse.
   */
  public static HttpResponse makeApiCall(
    String namedCredential,
    HttpVerb method,
    String path
  ) {
    return new RestClient(namedCredential)
      .makeApiCall(method, path, '', '', null);
  }

  // Assembles the unsent HttpRequest; tests assert its shape through the
  // HttpCalloutMockFactory capture list rather than a builder seam here.
  @SuppressWarnings('PMD.ExcessiveParameterList')
  private HttpRequest buildRequest(
    HttpVerb method,
    String path,
    String query,
    String body,
    Map<String, String> headers
  ) {
    HttpRequest request = new HttpRequest();
    request.setMethod(method == HttpVerb.DEL ? 'DELETE' : method.name());
    request.setEndpoint(
      'callout:' + this.namedCredentialName +
      normalizePath(path) + encodeQueryValues(query)
    );
    request.setTimeout(this.timeoutMillis);
    Map<String, String> resolved = headers ?? this.defaultHeaders;
    for (String headerName : resolved.keySet()) {
      request.setHeader(headerName, resolved.get(headerName));
    }
    if (String.isNotBlank(body) && BODY_VERBS.contains(method)) {
      request.setBody(body);
    }
    return request;
  }

  // Prefixes a missing leading slash so concatenation can never silently
  // fuse `callout:Name` with the resource name.
  private String normalizePath(String path) {
    if (String.isBlank(path)) {
      return '/';
    }
    return path.startsWith('/') ? path : '/' + path;
  }

  /**
   * @description URL-encodes query parameter values only — never keys and
   *              never the `?`/`=`/`&` structure — so a space or reserved
   *              character inside a value is escaped while the query string
   *              stays parseable. A value containing `=` (a URL, say) is
   *              encoded whole: only the first `=` in each pair separates
   *              key from value.
   * @param query Query string, with or without a leading `?`.
   * @return      `?key=encodedValue&...`, or an empty string for blank input.
   */
  private String encodeQueryValues(String query) {
    if (String.isBlank(query)) {
      return '';
    }
    String rawQuery = query.startsWith('?') ? query.substring(1) : query;
    List<String> encodedPairs = new List<String>();
    for (String pair : rawQuery.split('&')) {
      Integer separatorAt = pair.indexOf('=');
      if (separatorAt == -1) {
        encodedPairs.add(pair);
      } else {
        encodedPairs.add(
          pair.substring(0, separatorAt) + '=' +
          EncodingUtil.urlEncode(pair.substring(separatorAt + 1), 'UTF-8')
        );
      }
    }
    return '?' + String.join(encodedPairs, '&');
  }
}
