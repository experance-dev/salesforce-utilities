/**
 * @description Tests for `TestDouble` — proves the overload-matching guard treats
 *              each registered constraint list (param types, param names, args)
 *              independently, plus the name-only, args-only, throwing, and
 *              default-null dispatch paths. Uses `StringBuilder` as the stub
 *              target because it ships with this library and carries the
 *              overloaded instance methods the guard has to disambiguate.
 *              Every path runs as a minimum-access user — stubbing requires
 *              no object or field permissions, and the runAs context proves it.
 * @group Testing
 * @see TestDouble
 * @author David Wood
 * @since August 2026
 * @last August 2026 — initial coverage for the independent-constraint overload guard; runAs contexts (analyzer conformance)
 */
@isTest
public without sharing class TestDoubleTest {
  @TestSetup
  static void makeData() {
    TestFactory.createMinAccessUser(true);
  }

  @isTest
  static void testParamTypesOnlyStubFiresForCallWithArguments() {
    System.runAs(TestFactory.getMinAccessUser()) {
      // A stub constrained ONLY by param types must fire for a call that carries
      // arguments — the unregistered args and names lists place no constraint on
      // the match. Under the old guard this call never matched, because the empty
      // registered args list was compared against the real argument values.
      TestDouble stub = new TestDouble(StringBuilder.class);
      TestDouble.Method addMethod = new TestDouble.Method('add')
        .withParamTypes(new List<Type>{ String.class });
      stub.track(addMethod);
      StringBuilder fake = (StringBuilder) stub.generate();

      fake.add('hello');

      Assert.areEqual(
        1,
        addMethod.hasBeenCalledXTimes,
        'A types-only stub must match a call with arguments; requiring the ' +
          'unregistered args list to match would veto every real invocation.'
      );
    }
  }

  @isTest
  static void testParamTypesDisambiguateOverloads() {
    System.runAs(TestFactory.getMinAccessUser()) {
      TestDouble stub = new TestDouble(StringBuilder.class);
      TestDouble.Method addString = new TestDouble.Method('add')
        .withParamTypes(new List<Type>{ String.class });
      TestDouble.Method addList = new TestDouble.Method('add')
        .withParamTypes(new List<Type>{ List<String>.class });
      stub.track(addString).track(addList);
      StringBuilder fake = (StringBuilder) stub.generate();

      fake.add(new List<String>{ 'a', 'b' });

      Assert.areEqual(
        0,
        addString.hasBeenCalledXTimes,
        'The String overload stub must not fire for the List overload call.'
      );
      Assert.areEqual(
        1,
        addList.hasBeenCalledXTimes,
        'The List overload stub must fire exactly once for the List call.'
      );
    }
  }

  @isTest
  static void testNameOnlyStubMatchesCallWithArgumentsAndReturnsValue() {
    System.runAs(TestFactory.getMinAccessUser()) {
      TestDouble stub = new TestDouble(StringBuilder.class);
      TestDouble.Method addMethod = new TestDouble.Method('add');
      TestDouble.Method getValueMethod = new TestDouble.Method('getStringValue')
        .returning('stubbed value');
      stub.track(addMethod).track(getValueMethod);
      StringBuilder fake = (StringBuilder) stub.generate();

      fake.add('ignored argument');
      String result = fake.getStringValue();

      Assert.areEqual(
        1,
        addMethod.hasBeenCalledXTimes,
        'A name-only stub matches any invocation of that method, arguments included.'
      );
      Assert.areEqual(
        'stubbed value',
        result,
        'The stub must return the value registered via returning().'
      );
    }
  }

  @isTest
  static void testArgsOnlyStubFiresOnMatchingArgumentsOnly() {
    System.runAs(TestFactory.getMinAccessUser()) {
      TestDouble stub = new TestDouble(StringBuilder.class);
      TestDouble.Method addMethod = new TestDouble.Method('add')
        .withArgs(new List<Object>{ 'expected' });
      stub.track(addMethod);
      StringBuilder fake = (StringBuilder) stub.generate();

      fake.add('expected');
      fake.add('unexpected');

      Assert.areEqual(
        1,
        addMethod.hasBeenCalledXTimes,
        'An args-only stub fires for the matching argument list and stays ' +
          'silent for any other.'
      );
    }
  }

  @isTest
  static void testUnregisteredMethodReturnsNull() {
    System.runAs(TestFactory.getMinAccessUser()) {
      TestDouble stub = new TestDouble(StringBuilder.class);
      stub.track(new TestDouble.Method('add'));
      StringBuilder fake = (StringBuilder) stub.generate();

      Assert.isNull(
        fake.getStringValue(),
        'Calls with no registered stub return null by design, so a missing ' +
          'registration surfaces as a downstream failure instead of a silent pass.'
      );
    }
  }

  @isTest
  static void testThrowingStubRaisesTestDoubleException() {
    System.runAs(TestFactory.getMinAccessUser()) {
      TestDouble stub = new TestDouble(StringBuilder.class);
      stub.track(
        new TestDouble.Method('getStringValue').throwing('configured failure')
      );
      StringBuilder fake = (StringBuilder) stub.generate();

      try {
        fake.getStringValue();
        Assert.fail('Expected TestDouble.TestDoubleException to be thrown.');
      } catch (TestDouble.TestDoubleException e) {
        Assert.areEqual(
          'configured failure',
          e.getMessage(),
          'The thrown exception must carry the message registered via throwing().'
        );
      }
    }
  }
}
