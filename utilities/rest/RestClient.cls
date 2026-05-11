/**
 * @description Intelligent abstraction for making REST callouts to external
 *              endpoints via Named Credentials. Designated virtual so that
 *              API Service classes can extend and reuse its methods.
 *              Also exposes static convenience wrappers for one-off callouts
 *              where a full service subclass is unnecessary.
 *
 *              Sharing: declared `with sharing` so that user-initiated callouts
 *              respect the running user's record-visibility context. REST
 *              clients do not issue SOQL/DML directly, but `with sharing`
 *              ensures any future platform-security additions (e.g. ConnectApi)
 *              inherit the correct context by default.
 * @group REST
 * @author David Wood
 * @since June 2024
 * @last May 2026 — Wave 5 conformance: added `with sharing`, RestClientException,
 *                  Logger.logException wrapping, stripped method-level @description,
 *                  removed dead commented-out code.
 */
public with sharing virtual class RestClient {
  /**
   * @description Custom exception for all RestClient callout failures.
   */
  public class RestClientException extends UtilitiesModuleException {}

  /**
   * This property determines whether a trailing slash should be added to the
   * URL prior to query parameters.
   */
  @testVisible
  protected Boolean addSlash;

  /**
   * This property determines whether to encode the query parameters in the URL.
   */
  @testVisible
  protected Boolean encodeQuery;

  /**
   * The name of the Named Credential to use.
   */
  @testVisible
  protected String namedCredentialName { get; set; }

  /**
   * Lists possible HTTP verbs. Note: 'Delete' is an Apex keyword (DML),
   * so the enum value 'DEL' is used for delete operations.
   */
  public enum HttpVerb {
    GET,
    POST,
    PATCH,
    PUT,
    HEAD,
    DEL
  }

  /**
   * The default headers applied when no custom headers are specified.
   */
  @testVisible
  @SuppressWarnings('PMD.FieldDeclarationsShouldBeAtStart')
  private static Map<String, String> defaultHeaders = new Map<String, String>{
    'Content-Type' => 'application/json',
    'Accept' => 'application/json'
  };

  // ─── Constructors ─────────────────────────────────────────────────────────

  /**
   * @param namedCredential Name of the Named Credential to use
   */
  public RestClient(String namedCredential) {
    this.namedCredentialName = namedCredential;
    this.addSlash = true;
    this.encodeQuery = true;
  }

  /**
   * @param namedCredential Name of the Named Credential to use
   * @param addSlash        Whether to add a trailing slash to the URL
   */
  public RestClient(String namedCredential, Boolean addSlash) {
    this.namedCredentialName = namedCredential;
    this.addSlash = addSlash;
    this.encodeQuery = true;
  }

  /**
   * @param namedCredential Name of the Named Credential to use
   * @param addSlash        Whether to add a trailing slash to the URL
   * @param encodeQuery     Whether to encode the query parameters in the URL
   */
  public RestClient(
    String namedCredential,
    Boolean addSlash,
    Boolean encodeQuery
  ) {
    this.namedCredentialName = namedCredential;
    this.addSlash = addSlash;
    this.encodeQuery = encodeQuery;
  }

  /**
   * @param namedCredential Name of the Named Credential to use
   * @param headers         Custom headers to merge into defaults
   * @param addSlash        Whether to add a trailing slash to the URL
   * @param encodeQuery     Whether to encode the query parameters in the URL
   */
  @SuppressWarnings('PMD.ExcessiveParameterList')
  public RestClient(
    String namedCredential,
    Map<String, String> headers,
    Boolean addSlash,
    Boolean encodeQuery
  ) {
    this.namedCredentialName = namedCredential;
    RestClient.defaultHeaders.putAll(headers);
    this.addSlash = addSlash;
    this.encodeQuery = encodeQuery;
  }

  /**
   * @param namedCredential Name of the Named Credential to use
   * @param headers         Custom headers to merge into defaults
   * @param addSlash        Whether to add a trailing slash to the URL
   */
  @SuppressWarnings('PMD.ExcessiveParameterList')
  public RestClient(
    String namedCredential,
    Map<String, String> headers,
    Boolean addSlash
  ) {
    this.namedCredentialName = namedCredential;
    RestClient.defaultHeaders.putAll(headers);
    this.addSlash = addSlash;
    this.encodeQuery = true;
  }

  /**
   * Protected no-arg constructor retained so subclasses that do not need a
   * Named Credential are not forced to forward one. Not intended for direct
   * instantiation outside the class hierarchy.
   */
  @SuppressWarnings('PMD.EmptyStatementBlock')
  protected RestClient() {
  }

  // ─── Core callout ─────────────────────────────────────────────────────────

  /**
   * Omnibus callout method. All convenience wrappers ultimately delegate here.
   * @param method  HTTP verb enum (e.g. GET)
   * @param path    Path component of the URL (e.g. `/services/data/v39.0/SObjects`)
   * @param query   Query string (e.g. `q=SELECT Id FROM Account`)
   * @param body    JSON body for POST/PUT/PATCH calls
   * @param headers Request headers; pass null to use defaults
   * @return        HttpResponse from the remote endpoint
   */
  @testVisible
  @SuppressWarnings('PMD.ExcessiveParameterList')
  protected HttpResponse makeApiCall(
    HttpVerb method,
    String path,
    String query,
    String body,
    Map<String, String> headers
  ) {
    try {
      HttpRequest apiRequest = new HttpRequest();
      path = ensureStringEndsInSlash(path);
      String encodedQuery = encodeQueryIfNeeded(query);
      method = adjustHttpMethodForPatch(method, encodedQuery);
      setHeadersAndBody(apiRequest, headers, method, body);
      apiRequest.setMethod(getHttpMethodString(method));
      apiRequest.setEndpoint(
        'callout:' + this.namedCredentialName + path + encodedQuery
      );
      Http http = new Http();
      return http.send(apiRequest);
    } catch (Exception e) {
      Logger.logException(e, 'RestClient', 'makeApiCall');
      throw new RestClientException(
        'Callout failed [' +
          this.namedCredentialName +
          path +
          ']: ' +
          e.getMessage() +
          ' - ' +
          e.getStackTraceString()
      );
    }
  }

  // ─── Convenience overloads ────────────────────────────────────────────────

  /**
   * Convenience overload — uses default headers.
   * @param method HTTP verb
   * @param path   Path component
   * @param query  Query string
   * @param body   Request body
   * @return       HttpResponse
   */
  @testVisible
  @SuppressWarnings('PMD.ExcessiveParameterList')
  protected HttpResponse makeApiCall(
    HttpVerb method,
    String path,
    String query,
    String body
  ) {
    return this.makeApiCall(
      method,
      path,
      query,
      body,
      RestClient.defaultHeaders
    );
  }

  /**
   * Convenience overload — no body, uses default headers.
   * @param method HTTP verb
   * @param path   Path component
   * @param query  Query string
   * @return       HttpResponse
   */
  @testVisible
  protected HttpResponse makeApiCall(
    HttpVerb method,
    String path,
    String query
  ) {
    return this.makeApiCall(method, path, query, '', RestClient.defaultHeaders);
  }

  /**
   * Convenience overload — no body or query, uses default headers.
   * @param method HTTP verb
   * @param path   Path component
   * @return       HttpResponse
   */
  @testVisible
  protected HttpResponse makeApiCall(HttpVerb method, String path) {
    return this.makeApiCall(method, path, '', '', RestClient.defaultHeaders);
  }

  // ─── Verb shortcuts ───────────────────────────────────────────────────────

  /**
   * @param path Path component of the URL
   * @return     HttpResponse
   */
  @testVisible
  protected HttpResponse get(String path) {
    return this.makeApiCall(HttpVerb.GET, path);
  }

  /**
   * @param path  Path component of the URL
   * @param query Query string
   * @return      HttpResponse
   */
  @testVisible
  protected HttpResponse get(String path, String query) {
    return this.makeApiCall(HttpVerb.GET, path, query);
  }

  /**
   * @param path Path component of the URL
   * @return     HttpResponse
   */
  @testVisible
  protected HttpResponse del(String path) {
    return this.makeApiCall(HttpVerb.DEL, path);
  }

  /**
   * @param path  Path component of the URL
   * @param query Query string
   * @return      HttpResponse
   */
  @testVisible
  protected HttpResponse del(String path, String query) {
    return this.makeApiCall(HttpVerb.DEL, path, query);
  }

  /**
   * @param path Path component of the URL
   * @param body JSON request body
   * @return     HttpResponse
   */
  @testVisible
  protected HttpResponse post(String path, String body) {
    return this.makeApiCall(HttpVerb.POST, path, '', body);
  }

  /**
   * @param path  Path component of the URL
   * @param query Query string
   * @param body  JSON request body
   * @return      HttpResponse
   */
  @testVisible
  protected HttpResponse post(String path, String query, String body) {
    return this.makeApiCall(HttpVerb.POST, path, query, body);
  }

  /**
   * @param path Path component of the URL
   * @param body JSON request body
   * @return     HttpResponse
   */
  @testVisible
  protected HttpResponse put(String path, String body) {
    return this.makeApiCall(HttpVerb.PUT, path, '', body);
  }

  /**
   * @param path  Path component of the URL
   * @param query Query string
   * @param body  JSON request body
   * @return      HttpResponse
   */
  @testVisible
  protected HttpResponse put(String path, String query, String body) {
    return this.makeApiCall(HttpVerb.PUT, path, query, body);
  }

  /**
   * @param path Path component of the URL
   * @param body JSON request body
   * @return     HttpResponse
   */
  @testVisible
  protected HttpResponse patch(String path, String body) {
    return this.makeApiCall(HttpVerb.PATCH, path, '', body);
  }

  /**
   * @param path  Path component of the URL
   * @param query Query string
   * @param body  JSON request body
   * @return      HttpResponse
   */
  @testVisible
  protected HttpResponse patch(String path, String query, String body) {
    return this.makeApiCall(HttpVerb.PATCH, path, query, body);
  }

  // ─── Private helpers ──────────────────────────────────────────────────────

  /**
   * Appends a trailing `/` when `addSlash` is true and the path does not
   * already end in one, making callout URLs more robust against missing slashes.
   * @param resource Path string to normalise
   * @return         Path ending in `/` (or unchanged if already correct)
   */
  @testVisible
  protected String ensureStringEndsInSlash(String resource) {
    if (!this.addSlash || resource.endsWith('/')) {
      return resource;
    }
    return resource + '/';
  }

  /**
   * @param query Raw query string
   * @return      URL-encoded query string, or original when encoding is disabled
   */
  private String encodeQueryIfNeeded(String query) {
    return this.encodeQuery ? EncodingUtil.urlEncode(query, 'UTF-8') : query;
  }

  /**
   * Salesforce's HTTP library does not support PATCH natively. We simulate it
   * by sending POST and appending `?_HttpMethod=PATCH` to the query string.
   * @param method       Incoming HTTP verb
   * @param encodedQuery Mutable query string (PATCH indicator is appended here)
   * @return             POST when original method was PATCH, otherwise unchanged
   */
  private HttpVerb adjustHttpMethodForPatch(
    HttpVerb method,
    String encodedQuery
  ) {
    if (method == HttpVerb.PATCH) {
      encodedQuery += '?_HttpMethod=PATCH';
      return HttpVerb.POST;
    }
    return method;
  }

  /**
   * @param request The HttpRequest to configure
   * @param headers Header map; null falls back to defaultHeaders
   * @param method  HTTP verb (determines whether body is set)
   * @param body    Request body string
   */
  @SuppressWarnings('PMD.ExcessiveParameterList')
  private void setHeadersAndBody(
    HttpRequest request,
    Map<String, String> headers,
    HttpVerb method,
    String body
  ) {
    Map<String, String> functionalHeaders = (headers != null)
      ? headers
      : RestClient.defaultHeaders;
    for (String header : functionalHeaders.keySet()) {
      request.setHeader(header, functionalHeaders.get(header));
    }
    if (
      String.isNotBlank(body) &&
      (method == HttpVerb.POST ||
      method == HttpVerb.PUT ||
      method == HttpVerb.PATCH)
    ) {
      request.setBody(body);
    }
  }

  /**
   * @param method HTTP verb enum value
   * @return       String representation safe for HttpRequest.setMethod()
   */
  private String getHttpMethodString(HttpVerb method) {
    return (method == HttpVerb.DEL) ? 'DELETE' : String.valueOf(method);
  }

  // ─── Static wrappers ──────────────────────────────────────────────────────

  /**
   * Static convenience wrapper — full signature.
   * @param namedCredential Named Credential to use
   * @param method          HTTP verb enum
   * @param path            Path component of the URL
   * @param query           Query string
   * @param body            JSON request body
   * @param headers         Request headers
   * @return                HttpResponse
   * @example
   * HttpResponse res = RestClient.makeApiCall(
   *     'MockBin', RestClient.HttpVerb.GET,
   *     '4cb453a6-a23b-42ea-a6ba-9be1c1f17050', '', '',
   *     new Map<String,String>());
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
   * Static convenience wrapper — no body, uses default headers.
   * @param namedCredential Named Credential to use
   * @param method          HTTP verb enum
   * @param path            Path component of the URL
   * @param query           Query string
   * @return                HttpResponse
   * @example
   * HttpResponse res = RestClient.makeApiCall(
   *     'MockBin', RestClient.HttpVerb.GET,
   *     '4cb453a6-a23b-42ea-a6ba-9be1c1f17050', '');
   */
  @SuppressWarnings('PMD.ExcessiveParameterList')
  public static HttpResponse makeApiCall(
    String namedCredential,
    HttpVerb method,
    String path,
    String query
  ) {
    return new RestClient(namedCredential)
      .makeApiCall(method, path, query, '', RestClient.defaultHeaders);
  }

  /**
   * Static convenience wrapper — path only, uses default headers.
   * @param namedCredential Named Credential to use
   * @param method          HTTP verb enum
   * @param path            Path component of the URL
   * @return                HttpResponse
   * @example
   * HttpResponse res = RestClient.makeApiCall(
   *     'MockBin', RestClient.HttpVerb.GET,
   *     '4cb453a6-a23b-42ea-a6ba-9be1c1f17050');
   */
  public static HttpResponse makeApiCall(
    String namedCredential,
    HttpVerb method,
    String path
  ) {
    return new RestClient(namedCredential)
      .makeApiCall(method, path, '', '', RestClient.defaultHeaders);
  }
}
