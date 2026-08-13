/**
 * @description Tests for `RestClient` — asserts the request actually built on
 *              the wire (endpoint with `callout:` prefix, method, headers,
 *              body) for every verb via HttpCalloutMockFactory's capture
 *              list, value-only query encoding, per-instance header
 *              isolation, and sanitized RestClientException surfacing when a
 *              callout fails.
 * @group REST
 * @see RestClient
 * @author David Wood
 * @since March 2024
 * @last August 2026 — rewrite alongside RestClient: wire-shape assertions via
 *                     request capture, native-PATCH proof, negative paths;
 *                     analyzer conformance.
 */
@isTest
private without sharing class RestClientTest {
  private static final String CREDENTIAL = 'TestCredential';
  private static final String REQUEST_BODY = '{"name":"widget"}';
  private static final String RAW_DETAIL = 'raw remote detail - internal only';

  @TestSetup
  static void makeData() {
    TestFactory.createTestUser();
  }

  // ── Fixtures ─────────────────────────────────────────────────────────────

  private static HttpCalloutMockFactory armMock(Integer statusCode) {
    HttpCalloutMockFactory mock = new HttpCalloutMockFactory(
      statusCode,
      'OK',
      '{"ok":true}',
      new Map<String, String>()
    );
    Test.setMock(HttpCalloutMock.class, mock);
    return mock;
  }

  private static HttpCalloutMockFactory armMultiMock(Integer responseCount) {
    List<HttpResponse> responses = new List<HttpResponse>();
    for (Integer i = 0; i < responseCount; i++) {
      responses.add(
        HttpCalloutMockFactory.generateHttpResponse(
          200,
          'OK',
          '{"ok":true}',
          new Map<String, String>()
        )
      );
    }
    HttpCalloutMockFactory mock = new HttpCalloutMockFactory(responses);
    // Proves the defensive copy: draining the caller's list after
    // construction must not starve the mock's own queue.
    responses.clear();
    Test.setMock(HttpCalloutMock.class, mock);
    return mock;
  }

  @SuppressWarnings('PMD.ExcessiveParameterList')
  private static void assertWireShape(
    HttpRequest sent,
    String expectedMethod,
    String expectedEndpoint,
    String expectedBody
  ) {
    Assert.areEqual(
      expectedMethod,
      sent.getMethod(),
      'Expected the built request to carry the ' + expectedMethod + ' method'
    );
    Assert.areEqual(
      expectedEndpoint,
      sent.getEndpoint(),
      'Expected the built endpoint to match, callout: prefix included'
    );
    Assert.areEqual(
      expectedBody,
      sent.getBody() == null ? '' : sent.getBody(),
      'Expected the built request body to match'
    );
    Assert.areEqual(
      'application/json',
      sent.getHeader('Content-Type'),
      'Expected the instance-default Content-Type header on the wire'
    );
    Assert.areEqual(
      'application/json',
      sent.getHeader('Accept'),
      'Expected the instance-default Accept header on the wire'
    );
  }

  // ── Verb wire-shape tests ────────────────────────────────────────────────

  @isTest
  static void testGetBuildsRequestOnTheWire() {
    HttpCalloutMockFactory mock = armMock(200);
    RestClient client = new RestClient(CREDENTIAL);
    HttpResponse response;

    System.runAs(TestFactory.getCreatedTestUser()) {
      Test.startTest();
      response = client.get('/widgets', 'color=blue');
      Test.stopTest();
    }

    Assert.areEqual(
      200,
      response.getStatusCode(),
      'Expected the mock status to surface on the returned response'
    );
    Assert.areEqual(
      1,
      mock.receivedRequests.size(),
      'Expected exactly one captured request'
    );
    assertWireShape(
      mock.receivedRequests[0],
      'GET',
      'callout:TestCredential/widgets?color=blue',
      ''
    );
  }

  @isTest
  static void testPostBuildsRequestOnTheWire() {
    HttpCalloutMockFactory mock = armMock(201);
    RestClient client = new RestClient(CREDENTIAL);
    HttpResponse response;

    System.runAs(TestFactory.getCreatedTestUser()) {
      Test.startTest();
      response = client.post('/widgets', '', REQUEST_BODY);
      Test.stopTest();
    }

    Assert.areEqual(
      201,
      response.getStatusCode(),
      'Expected the mock status to surface on the returned response'
    );
    assertWireShape(
      mock.receivedRequests[0],
      'POST',
      'callout:TestCredential/widgets',
      REQUEST_BODY
    );
  }

  @isTest
  static void testPutBuildsRequestOnTheWire() {
    HttpCalloutMockFactory mock = armMock(200);
    RestClient client = new RestClient(CREDENTIAL);
    HttpResponse response;

    System.runAs(TestFactory.getCreatedTestUser()) {
      Test.startTest();
      response = client.put('/widgets/1', '', REQUEST_BODY);
      Test.stopTest();
    }

    Assert.areEqual(
      200,
      response.getStatusCode(),
      'Expected the mock status to surface on the returned response'
    );
    assertWireShape(
      mock.receivedRequests[0],
      'PUT',
      'callout:TestCredential/widgets/1',
      REQUEST_BODY
    );
  }

  @isTest
  static void testPatchSendsNativePatchOnTheWire() {
    HttpCalloutMockFactory mock = armMock(200);
    RestClient client = new RestClient(CREDENTIAL);

    System.runAs(TestFactory.getCreatedTestUser()) {
      Test.startTest();
      client.patch('/widgets/1', '', REQUEST_BODY);
      Test.stopTest();
    }

    assertWireShape(
      mock.receivedRequests[0],
      'PATCH',
      'callout:TestCredential/widgets/1',
      REQUEST_BODY
    );
    Assert.isFalse(
      mock.receivedRequests[0].getEndpoint().contains('_HttpMethod'),
      'PATCH must go out natively, not as the POST + _HttpMethod query hack'
    );
  }

  @isTest
  static void testDelSendsHttpDeleteOnTheWire() {
    HttpCalloutMockFactory mock = armMock(204);
    RestClient client = new RestClient(CREDENTIAL).withTimeout(30000);
    HttpResponse response;

    System.runAs(TestFactory.getCreatedTestUser()) {
      Test.startTest();
      response = client.del('/widgets/1', '');
      Test.stopTest();
    }

    Assert.areEqual(
      204,
      response.getStatusCode(),
      'Expected the mock status to surface on the returned response'
    );
    assertWireShape(
      mock.receivedRequests[0],
      'DELETE',
      'callout:TestCredential/widgets/1',
      ''
    );
  }

  // ── Query encoding ───────────────────────────────────────────────────────

  @isTest
  static void testQueryEncodingEncodesValuesOnlyKeepsStructure() {
    HttpCalloutMockFactory mock = armMultiMock(2);
    RestClient client = new RestClient(CREDENTIAL);

    System.runAs(TestFactory.getCreatedTestUser()) {
      Test.startTest();
      client.get(
        '/search',
        'q=blue widget&callback=https://x.example/done?flag=1'
      );
      client.get('/search', '?q=a b');
      Test.stopTest();
    }

    Assert.areEqual(
      'callout:TestCredential/search' +
        '?q=blue+widget&callback=https%3A%2F%2Fx.example%2Fdone%3Fflag%3D1',
      mock.receivedRequests[0].getEndpoint(),
      'Values must be URL-encoded; the ?/=/& structure must survive intact'
    );
    Assert.areEqual(
      'callout:TestCredential/search?q=a+b',
      mock.receivedRequests[1].getEndpoint(),
      'A caller-supplied leading ? must not double up, and the space in the ' +
        'value must be encoded'
    );
  }

  // ── Static wrappers ──────────────────────────────────────────────────────

  @isTest
  static void testStaticMakeApiCallBuildsSameWireShape() {
    HttpCalloutMockFactory mock = armMultiMock(2);
    HttpResponse response;

    System.runAs(TestFactory.getCreatedTestUser()) {
      Test.startTest();
      response = RestClient.makeApiCall(
        CREDENTIAL,
        RestClient.HttpVerb.GET,
        '/widgets'
      );
      RestClient.makeApiCall(
        CREDENTIAL,
        RestClient.HttpVerb.POST,
        '/widgets',
        '',
        REQUEST_BODY,
        new Map<String, String>{ 'X-Trace' => 'abc' }
      );
      Test.stopTest();
    }

    Assert.areEqual(
      200,
      response.getStatusCode(),
      'Expected the mock status to surface through the static wrapper'
    );
    assertWireShape(
      mock.receivedRequests[0],
      'GET',
      'callout:TestCredential/widgets',
      ''
    );
    Assert.areEqual(
      'abc',
      mock.receivedRequests[1].getHeader('X-Trace'),
      'Expected the explicit per-call header map on the wire'
    );
    Assert.isNull(
      mock.receivedRequests[1].getHeader('Content-Type'),
      'An explicit header map replaces the defaults, never merges over them'
    );
  }

  // ── Header isolation ─────────────────────────────────────────────────────

  @isTest
  static void testInstancesDoNotShareCustomHeaders() {
    HttpCalloutMockFactory mock = armMultiMock(2);
    RestClient clientA = new RestClient(
      CREDENTIAL,
      new Map<String, String>{ 'Authorization' => 'Bearer alpha' }
    );
    RestClient clientB = new RestClient(
      CREDENTIAL,
      new Map<String, String>{ 'X-Integration' => 'beta' }
    );

    System.runAs(TestFactory.getCreatedTestUser()) {
      Test.startTest();
      clientA.get('/a', '');
      clientB.get('/b', '');
      Test.stopTest();
    }

    HttpRequest sentByA = mock.receivedRequests[0];
    HttpRequest sentByB = mock.receivedRequests[1];
    Assert.areEqual(
      'Bearer alpha',
      sentByA.getHeader('Authorization'),
      'Expected clientA to carry its own Authorization header'
    );
    Assert.isNull(
      sentByB.getHeader('Authorization'),
      'clientA custom headers must never bleed into clientB requests'
    );
    Assert.areEqual(
      'beta',
      sentByB.getHeader('X-Integration'),
      'Expected clientB to carry its own custom header'
    );
    Assert.isNull(
      sentByA.getHeader('X-Integration'),
      'clientB custom headers must never bleed into clientA requests'
    );
  }

  // ── Negative paths ───────────────────────────────────────────────────────

  @isTest
  static void testServerErrorResponseIsSurfacedNotThrown() {
    armMock(500);
    RestClient client = new RestClient(CREDENTIAL);
    HttpResponse response;

    System.runAs(TestFactory.getCreatedTestUser()) {
      Test.startTest();
      response = client.get('/widgets', '');
      Test.stopTest();
    }

    Assert.areEqual(
      500,
      response.getStatusCode(),
      'A 500 response is a caller decision — it must surface, not throw'
    );
  }

  @isTest
  static void testCalloutFailureWrapsAsSanitizedRestClientException() {
    Test.setMock(HttpCalloutMock.class, new ThrowingCalloutMock());
    RestClient client = new RestClient(CREDENTIAL);
    RestClient.RestClientException caught;

    System.runAs(TestFactory.getCreatedTestUser()) {
      Test.startTest();
      try {
        client.get('/widgets', '');
        Assert.fail('Expected a RestClientException for a failed callout');
      } catch (RestClient.RestClientException e) {
        caught = e;
      }
      Test.stopTest();
    }

    Assert.isTrue(
      caught.getMessage().contains('System.CalloutException'),
      'Expected the exception type name as the operator hint'
    );
    Assert.isTrue(
      caught.getMessage().contains('[txn:'),
      'Expected a correlation id in the sanitized message'
    );
    Assert.isFalse(
      caught.getMessage().contains(RAW_DETAIL),
      'The raw exception message must never surface to the caller'
    );
  }

  private class ThrowingCalloutMock implements HttpCalloutMock {
    /**
     * @description Simulates a transport-level failure by throwing instead of
     *              responding — RAW_DETAIL is the message the client must
     *              never surface.
     * @param request The request being sent; unused.
     * @return Never returns — always throws CalloutException.
     */
    public HttpResponse respond(HttpRequest request) {
      CalloutException failure = new CalloutException();
      failure.setMessage(RAW_DETAIL);
      throw failure;
    }
  }
}
