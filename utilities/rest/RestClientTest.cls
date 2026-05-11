/**
 * @description Test class for RestClient.
 * @group REST
 * @see RestClient
 * @author David Wood
 * @since 2024-03-16
 * @last May 2026 — Wave 6 conformance
 */
@isTest
private without sharing class RestClientTest {
  @TestSetup
  static void makeData() {
    TestFactory.createTestUser();
  }

  @isTest
  static void testConstructorPositive() {
    RestClient rc;
    RestClient rcMin;

    System.runAs(TestFactory.getCreatedTestUser()) {
      Test.startTest();
      rc = new RestClient('dummyNamedCredential');
      rcMin = new RestClient('dummyNamedCredential');
      Test.stopTest();
    }

    Assert.isInstanceOfType(
      rc,
      RestClient.class,
      'Expected the instance to be of type RestClient'
    );
    Assert.isInstanceOfType(
      rcMin,
      RestClient.class,
      'Expected the instance to be of type RestClient'
    );
    Assert.areEqual(
      'dummyNamedCredential',
      rc.namedCredentialName,
      'Expected the name credential to match'
    );
  }

  @isTest
  static void testStaticMakeApiCallFullParamsPositive() {
    HttpCalloutMockFactory mock = new HttpCalloutMockFactory(
      200,
      'OK',
      'OK',
      new Map<String, String>()
    );
    Test.setMock(HttpCalloutMock.class, mock);

    System.runAs(TestFactory.getCreatedTestUser()) {
      Test.startTest();
      HttpResponse response = RestClient.makeApiCall(
        'DummyNamedCredential',
        RestClient.HttpVerb.GET,
        '/',
        '',
        '',
        null
      );
      Test.stopTest();

      Assert.areEqual(
        200,
        response.getStatusCode(),
        'Expected the return status code to be 200'
      );
    }
  }

  @isTest
  static void testStaticMakeApiCallNoHeadersoOrBodyParamsPositive() {
    HttpCalloutMockFactory mock = new HttpCalloutMockFactory(
      200,
      'OK',
      'OK',
      new Map<String, String>()
    );
    Test.setMock(HttpCalloutMock.class, mock);

    System.runAs(TestFactory.getCreatedTestUser()) {
      Test.startTest();
      HttpResponse response = RestClient.makeApiCall(
        'DummyNamedCredential',
        RestClient.HttpVerb.GET,
        '/',
        ''
      );
      Test.stopTest();

      Assert.areEqual(
        200,
        response.getStatusCode(),
        'Expected the return status code to be 200'
      );
    }
  }

  @isTest
  static void testStaticMakeApiCallNoHeadersoOrBodyOrQueryParamsPositive() {
    HttpCalloutMockFactory mock = new HttpCalloutMockFactory(
      200,
      'OK',
      'OK',
      new Map<String, String>()
    );
    Test.setMock(HttpCalloutMock.class, mock);

    System.runAs(TestFactory.getCreatedTestUser()) {
      Test.startTest();
      HttpResponse response = RestClient.makeApiCall(
        'DummyNamedCredential',
        RestClient.HttpVerb.GET,
        '/',
        ''
      );
      Test.stopTest();

      Assert.areEqual(
        200,
        response.getStatusCode(),
        'Expected the return status code to be 200'
      );
    }
  }

  @isTest
  static void testPutWithPathAndBodyPositive() {
    RestClient rc = new RestClient('DummyNamedCredential');
    HttpCalloutMockFactory mock = new HttpCalloutMockFactory(
      201,
      'OK',
      'OK',
      new Map<String, String>()
    );
    Test.setMock(HttpCalloutMock.class, mock);

    System.runAs(TestFactory.getCreatedTestUser()) {
      Test.startTest();
      HttpResponse response = rc.put('/', '{"Id": "003ae3fn12df25k309"}');
      Test.stopTest();

      Assert.areEqual(
        201,
        response.getStatusCode(),
        'Expected to get the 201 response code'
      );
    }
  }

  @isTest
  static void testPutWithPathQueryAndBodyPositive() {
    RestClient rc = new RestClient('DummyNamedCredential');
    HttpCalloutMockFactory mock = new HttpCalloutMockFactory(
      200,
      'OK',
      'OK',
      new Map<String, String>()
    );
    Test.setMock(HttpCalloutMock.class, mock);

    System.runAs(TestFactory.getCreatedTestUser()) {
      Test.startTest();
      HttpResponse response = rc.put(
        '/',
        '?test',
        '{"Id": "003ae3fn12df25k309"}'
      );
      Test.stopTest();

      Assert.areEqual(
        200,
        response.getStatusCode(),
        'Expected to get the 200 response code'
      );
    }
  }

  @isTest
  static void testGetWithPathAndQueryPositive() {
    RestClient rc = new RestClient('DummyNamedCredential');
    HttpCalloutMockFactory mock = new HttpCalloutMockFactory(
      200,
      'OK',
      'OK',
      new Map<String, String>()
    );
    Test.setMock(HttpCalloutMock.class, mock);

    System.runAs(TestFactory.getCreatedTestUser()) {
      Test.startTest();
      HttpResponse response = rc.get('/', '?test');
      Test.stopTest();

      Assert.areEqual(
        200,
        response.getStatusCode(),
        'Expected to get the 200 response code'
      );
    }
  }

  @isTest
  static void testDelWithPathPositive() {
    RestClient rc = new RestClient('DummyNamedCredential');
    HttpCalloutMockFactory mock = new HttpCalloutMockFactory(
      200,
      'OK',
      'OK',
      new Map<String, String>()
    );
    Test.setMock(HttpCalloutMock.class, mock);

    System.runAs(TestFactory.getCreatedTestUser()) {
      Test.startTest();
      HttpResponse response = rc.del('/');
      Test.stopTest();

      Assert.areEqual(
        200,
        response.getStatusCode(),
        'Expected to get the 200 response code'
      );
    }
  }

  @isTest
  static void testDelWithPatandBodyPositive() {
    RestClient rc = new RestClient('DummyNamedCredential');
    HttpCalloutMockFactory mock = new HttpCalloutMockFactory(
      200,
      'OK',
      'OK',
      new Map<String, String>()
    );
    Test.setMock(HttpCalloutMock.class, mock);

    System.runAs(TestFactory.getCreatedTestUser()) {
      Test.startTest();
      HttpResponse response = rc.del('/', 'Delete Body');
      Test.stopTest();

      Assert.areEqual(
        200,
        response.getStatusCode(),
        'Expected to get the 200 response code'
      );
    }
  }

  @isTest
  static void testPostWithPathQueryAndBodyPositive() {
    RestClient rc = new RestClient('DummyNamedCredential');
    HttpCalloutMockFactory mock = new HttpCalloutMockFactory(
      201,
      'OK',
      'OK',
      new Map<String, String>()
    );
    Test.setMock(HttpCalloutMock.class, mock);

    System.runAs(TestFactory.getCreatedTestUser()) {
      Test.startTest();
      HttpResponse response = rc.post(
        '/',
        '?test',
        '{"Id": "003ae3fn12df25k309"}'
      );
      Test.stopTest();

      Assert.areEqual(
        201,
        response.getStatusCode(),
        'Expected to get the 201 response code'
      );
    }
  }

  @isTest
  static void testPostWithPathAndBodyPositive() {
    RestClient rc = new RestClient('DummyNamedCredential');
    HttpCalloutMockFactory mock = new HttpCalloutMockFactory(
      201,
      'OK',
      'OK',
      new Map<String, String>()
    );
    Test.setMock(HttpCalloutMock.class, mock);

    System.runAs(TestFactory.getCreatedTestUser()) {
      Test.startTest();
      HttpResponse response = rc.post('/', '{"Id": "003ae3fn12df25k309"}');
      Test.stopTest();

      Assert.areEqual(
        201,
        response.getStatusCode(),
        'Expected to get the 201 response code'
      );
    }
  }

  @isTest
  static void testPatchWithPathQueryPositive() {
    RestClient rc = new RestClient('DummyNamedCredential');
    HttpCalloutMockFactory mock = new HttpCalloutMockFactory(
      201,
      'OK',
      'OK',
      new Map<String, String>()
    );
    Test.setMock(HttpCalloutMock.class, mock);

    System.runAs(TestFactory.getCreatedTestUser()) {
      Test.startTest();
      HttpResponse response = rc.patch('/', '{"Id": "003ae3fn12df25k309"}');
      Test.stopTest();

      Assert.areEqual(
        201,
        response.getStatusCode(),
        'Expected to get the 201 response code'
      );
    }
  }

  @isTest
  static void testPatchWithPathQueryAndBodyPositive() {
    RestClient rc = new RestClient('DummyNamedCredential');
    HttpCalloutMockFactory mock = new HttpCalloutMockFactory(
      201,
      'OK',
      'OK',
      new Map<String, String>()
    );
    Test.setMock(HttpCalloutMock.class, mock);

    System.runAs(TestFactory.getCreatedTestUser()) {
      Test.startTest();
      HttpResponse response = rc.patch(
        '/',
        '{"Id": "003ae3fn12df25k309"}',
        'Good Body'
      );
      Test.stopTest();

      Assert.areEqual(
        201,
        response.getStatusCode(),
        'Expected to get the 201 response code'
      );
    }
  }

  @isTest
  static void testEnsureStringEndsInSlash() {
    RestClient rc = new RestClient('DummyNamedCredential');

    Test.startTest();
    System.runAs(TestFactory.getCreatedTestUser()) {
      String resource1 = 'example/';
      String result1 = rc.ensureStringEndsInSlash(resource1);
      Assert.areEqual(
        'example/',
        result1,
        'Expected the resource to remain unchanged'
      );

      String resource2 = 'example';
      String result2 = rc.ensureStringEndsInSlash(resource2);
      Assert.areEqual(
        'example/',
        result2,
        'Expected the resource to have a trailing slash'
      );

      rc.addSlash = false;
      String resource3 = 'example';
      String result3 = rc.ensureStringEndsInSlash(resource3);
      Assert.areEqual(
        'example',
        result3,
        'Expected the resource to remain unchanged'
      );
    }
    Test.stopTest();
  }

  @isTest
  static void testRestClientConstructor1() {
    String namedCredential = 'DummyNamedCredential';
    Boolean addSlash = true;
    Test.startTest();
    System.runAs(TestFactory.getCreatedTestUser()) {
      RestClient rc = new RestClient(namedCredential, addSlash);
      Assert.areEqual(
        namedCredential,
        rc.namedCredentialName,
        'Expected named credential to be set correctly'
      );
      Assert.areEqual(
        addSlash,
        rc.addSlash,
        'Expected addSlash to be set correctly'
      );
    }
    Test.stopTest();
  }

  @isTest
  static void testRestClientConstructor3() {
    String namedCredential = 'DummyNamedCredential';
    Map<String, String> headers = new Map<String, String>{
      'Content-Type' => 'application/json',
      'Authorization' => 'Bearer token'
    };
    Boolean addSlash = true;
    Test.startTest();
    System.runAs(TestFactory.getCreatedTestUser()) {
      RestClient rc = new RestClient(namedCredential, headers, addSlash);
      Assert.areEqual(
        namedCredential,
        rc.namedCredentialName,
        'Expected named credential to be set correctly'
      );
      Assert.areEqual(
        addSlash,
        rc.addSlash,
        'Expected addSlash to be set correctly'
      );
    }
    Test.stopTest();
  }

  @isTest
  static void testRestClientConstructor2() {
    String namedCredential = 'DummyNamedCredential';
    Boolean addSlash = true;
    Boolean encodeQuery = false;
    Test.startTest();
    System.runAs(TestFactory.getCreatedTestUser()) {
      RestClient rc = new RestClient(namedCredential, addSlash, encodeQuery);
      Assert.areEqual(
        namedCredential,
        rc.namedCredentialName,
        'Expected named credential to be set correctly'
      );
      Assert.areEqual(
        addSlash,
        rc.addSlash,
        'Expected addSlash to be set correctly'
      );
      Assert.areEqual(
        encodeQuery,
        rc.encodeQuery,
        'Expected encodeQuery to be set correctly'
      );
    }
    Test.stopTest();
  }

  @isTest
  static void testGet() {
    HttpCalloutMockFactory mock = new HttpCalloutMockFactory(
      200,
      'OK',
      'OK',
      new Map<String, String>()
    );
    Test.setMock(HttpCalloutMock.class, mock);

    RestClient rc = new RestClient('DummyNamedCredential');

    String path = '/example';
    HttpResponse response;

    System.runAs(TestFactory.getCreatedTestUser()) {
      Test.startTest();
      response = rc.get(path);
      Test.stopTest();
    }

    Assert.areEqual(
      200,
      response.getStatusCode(),
      'Expected to get the 200 response code'
    );
  }
}
