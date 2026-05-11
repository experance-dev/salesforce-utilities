/**
 * @description Creates and queues HttpResponse instances for use with Test.setMock.
 *              Supports single-response and ordered multi-response scenarios.
 *              Wave 6 test authors should standardize on this factory instead of
 *              inlining anonymous HttpCalloutMock implementations per test.
 * @group Testing
 * @author David Wood
 * @since March 2024
 * @last May 2026 — Wave 2 conformance
 */
@isTest
public without sharing class HttpCalloutMockFactory implements HttpCalloutMock {
  // Holds an ordered list of HttpResponse objects to return one per callout.
  protected List<HttpResponse> responseQueue = new List<HttpResponse>();

  @SuppressWarnings('PMD.ExcessiveParameterList')
  public HttpCalloutMockFactory(
    Integer code,
    String status,
    String bodyAsString,
    Map<String, String> headers
  ) {
    this.responseQueue.add(
      HttpCalloutMockFactory.generateHttpResponse(
        code,
        status,
        bodyAsString,
        headers
      )
    );
  }

  public HttpCalloutMockFactory(List<HttpResponse> orderedResponses) {
    this.responseQueue = orderedResponses;
  }

  /**
   * @description Pops and returns the next queued response. Required by HttpCalloutMock.
   * @param request Injected by the platform; unused in this mock.
   * @return HttpResponse The next mock response in the queue.
   */
  public HttpResponse respond(HttpRequest request) {
    if (this.responseQueue.size() > 0) {
      return this.responseQueue.remove(0);
    }
    throw new HttpCalloutMockException('Mock response queue is empty.');
  }

  /**
   * @description Assembles a single HttpResponse from its constituent parts.
   * @param code         Response status code — 200, 301, 404, etc.
   * @param status       Response status label — 'OK', 'Server Error', etc.
   * @param bodyAsString Response body as a string.
   * @param headers      Response headers map.
   * @return HttpResponse The assembled response object.
   */
  @SuppressWarnings('PMD.ExcessiveParameterList')
  public static HttpResponse generateHttpResponse(
    Integer code,
    String status,
    String bodyAsString,
    Map<String, String> headers
  ) {
    HttpResponse res = new HttpResponse();
    res.setStatusCode(code);
    res.setStatus(status);
    res.setBody(bodyAsString);
    for (String headerKey : headers.keySet()) {
      res.setHeader(headerKey, headers.get(headerKey));
    }
    return res;
  }

  public class HttpCalloutMockException extends UtilitiesModuleException {}
}
