/**
 * @description Creates and queues HttpResponse instances for use with Test.setMock.
 *              Supports single-response and ordered multi-response scenarios,
 *              and captures every HttpRequest it receives so tests can assert
 *              the request that was actually built — endpoint, method,
 *              headers, body — instead of only the canned response's status.
 *              New test classes should standardize on this factory instead of
 *              inlining anonymous HttpCalloutMock implementations per test.
 *
 *              The ordered-response constructor copies the supplied list.
 *              Earlier versions aliased the caller's list and consumed it as
 *              responses were served, so the caller's own variable silently
 *              emptied one element per callout — a side effect no test should
 *              inherit. The defensive copy also means changes the caller
 *              makes to their list after construction never reach this mock.
 * @group Testing
 * @author David Wood
 * @since March 2024
 * @last May 2026 — conformance refactor
 * @last August 2026 — request capture list; defensive copy of the
 *                     ordered-response queue; analyzer conformance.
 */
@isTest
public without sharing class HttpCalloutMockFactory implements HttpCalloutMock {
  // Holds an ordered list of HttpResponse objects to return one per callout.
  protected List<HttpResponse> responseQueue = new List<HttpResponse>();

  /**
   * Every request this mock received, in call order. Public on purpose:
   * tests assert the built request (endpoint, method, headers, body) here
   * rather than trusting the canned response as proof of behavior.
   */
  public List<HttpRequest> receivedRequests = new List<HttpRequest>();

  /**
   * @description Queues a single response assembled from its parts.
   * @param code         Response status code — 200, 301, 404, etc.
   * @param status       Response status label — 'OK', 'Server Error', etc.
   * @param bodyAsString Response body as a string.
   * @param headers      Response headers map.
   */
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

  /**
   * @description Queues an ordered list of responses, served one per callout.
   *              The list is copied defensively — serving responses never
   *              mutates the caller's list (see the class header for the
   *              aliasing side effect this replaces).
   * @param orderedResponses Responses to serve, in order.
   */
  public HttpCalloutMockFactory(List<HttpResponse> orderedResponses) {
    this.responseQueue = new List<HttpResponse>(orderedResponses);
  }

  /**
   * @description Captures the incoming request on `receivedRequests`, then
   *              pops and returns the next queued response. Required by
   *              HttpCalloutMock.
   * @param request Injected by the platform; recorded for later assertions.
   * @return HttpResponse The next mock response in the queue.
   */
  public HttpResponse respond(HttpRequest request) {
    this.receivedRequests.add(request);
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

  /** @description Thrown when a callout arrives after the mock's response queue is exhausted. */
  public class HttpCalloutMockException extends UtilitiesModuleException {}
}
