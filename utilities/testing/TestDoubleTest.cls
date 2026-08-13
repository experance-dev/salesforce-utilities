/**
 * @description Tests for `TestDouble` — proves the overload-matching guard treats
 *              each registered constraint list (param types, param names, args)
 *              independently, that mixed constraints are enforced together, and
 *              that strict dispatch throws `UnexpectedInvocationException` (naming
 *              the method and its arguments) for any unmatched invocation unless
 *              the instance opted into `lenient()` null-return dispatch. Uses
 *              `StringBuilder` as the stub target because it ships with this
 *              library and carries the overloaded instance methods the guard has
 *              to disambiguate. Every path runs as a minimum-access user —
 *              stubbing requires no object or field permissions, and the runAs
 *              context proves it.
 * @group Testing
 * @see TestDouble
 * @author David Wood
 * @since August 2026
 * @last 2026-08-13 — strict-dispatch pin matrix: only-types, only-names, only-args,
 *       mixed constraints, unmatched-throws, lenient-null, nullable-return trap
 */
@isTest
public without sharing class TestDoubleTest {
  @TestSetup
  static void makeData() {
    TestFactory.createMinAccessUser(true);
  }

  /**
   * @description A stub constrained ONLY by param types must fire for a call
   *              that carries arguments — the unregistered args and names lists
   *              place no constraint on the match.
   */
  @isTest
  static void testParamTypesOnlyStubFiresForCallWithArguments() {
    System.runAs(TestFactory.getMinAccessUser()) {
      // Under the all-or-nothing guard this call never matched, because the
      // empty registered args list was compared against the real argument values.
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

  /**
   * @description Param types disambiguate overloads: the String-overload stub
   *              stays silent for the List-overload call and vice versa.
   */
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

  /**
   * @description A stub constrained ONLY by param names must fire when the call
   *              site's declared parameter names match, with types and args
   *              unregistered — and must disambiguate overloads by name alone
   *              (`add(String value)` vs `add(List<String> values)`).
   */
  @isTest
  static void testParamNamesOnlyStubDisambiguatesOverloads() {
    System.runAs(TestFactory.getMinAccessUser()) {
      TestDouble stub = new TestDouble(StringBuilder.class);
      TestDouble.Method addSingle = new TestDouble.Method('add')
        .withParamNames(new List<String>{ 'value' });
      TestDouble.Method addMany = new TestDouble.Method('add')
        .withParamNames(new List<String>{ 'values' });
      stub.track(addSingle).track(addMany);
      StringBuilder fake = (StringBuilder) stub.generate();

      fake.add(new List<String>{ 'a', 'b' });

      Assert.areEqual(
        0,
        addSingle.hasBeenCalledXTimes,
        'A names-only stub for add(value) must not fire for the add(values) overload.'
      );
      Assert.areEqual(
        1,
        addMany.hasBeenCalledXTimes,
        'A names-only stub for add(values) must fire exactly once for the List call.'
      );
    }
  }

  /**
   * @description A name-only stub matches any invocation of that method, and a
   *              matched stub returns the value registered via returning().
   */
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

  /**
   * @description A stub constrained ONLY by argument values fires for the
   *              matching argument list, with types and names unregistered.
   */
  @isTest
  static void testArgsOnlyStubFiresOnMatchingArguments() {
    System.runAs(TestFactory.getMinAccessUser()) {
      TestDouble stub = new TestDouble(StringBuilder.class);
      TestDouble.Method addMethod = new TestDouble.Method('add')
        .withArgs(new List<Object>{ 'expected' });
      stub.track(addMethod);
      StringBuilder fake = (StringBuilder) stub.generate();

      fake.add('expected');

      Assert.areEqual(
        1,
        addMethod.hasBeenCalledXTimes,
        'An args-only stub fires for the matching argument list; the ' +
          'unregistered types and names lists place no constraint on the match.'
      );
    }
  }

  /**
   * @description Mixed constraints are enforced together: a stub registering
   *              both param types and args fires only when BOTH match, and a
   *              call matching the types but not the args is an unmatched
   *              invocation under strict dispatch.
   */
  @isTest
  static void testMixedConstraintsEnforcedTogether() {
    System.runAs(TestFactory.getMinAccessUser()) {
      TestDouble stub = new TestDouble(StringBuilder.class);
      TestDouble.Method addMethod = new TestDouble.Method('add')
        .withParamTypes(new List<Type>{ String.class })
        .withArgs(new List<Object>{ 'expected' });
      stub.track(addMethod);
      StringBuilder fake = (StringBuilder) stub.generate();

      fake.add('expected');
      Assert.areEqual(
        1,
        addMethod.hasBeenCalledXTimes,
        'A mixed types+args stub fires when every registered constraint matches.'
      );

      try {
        fake.add('other');
        Assert.fail(
          'Expected UnexpectedInvocationException: the call matches the ' +
            'registered param types but not the registered args.'
        );
      } catch (TestDouble.UnexpectedInvocationException e) {
        Assert.isTrue(
          e.getMessage().contains('add') && e.getMessage().contains('other'),
          'The strict-dispatch message must name the method and the arguments ' +
            'of the unmatched call. Actual: ' + e.getMessage()
        );
      }
      Assert.areEqual(
        1,
        addMethod.hasBeenCalledXTimes,
        'The stub must not fire for the call whose args did not match.'
      );
    }
  }

  /**
   * @description Strict dispatch (the default): an invocation with no matching
   *              registration throws UnexpectedInvocationException naming the
   *              method and its rendered arguments.
   */
  @isTest
  static void testUnmatchedInvocationThrowsDescriptiveException() {
    System.runAs(TestFactory.getMinAccessUser()) {
      TestDouble stub = new TestDouble(StringBuilder.class);
      stub.track(new TestDouble.Method('getStringValue').returning('built'));
      StringBuilder fake = (StringBuilder) stub.generate();

      try {
        fake.add('surprise');
        Assert.fail(
          'Expected UnexpectedInvocationException for a method with no ' +
            'registered stub.'
        );
      } catch (TestDouble.UnexpectedInvocationException e) {
        Assert.isTrue(
          e.getMessage().contains('add'),
          'The exception message must name the unmatched method. Actual: ' +
            e.getMessage()
        );
        Assert.isTrue(
          e.getMessage().contains('surprise'),
          'The exception message must render the call arguments. Actual: ' +
            e.getMessage()
        );
        Assert.isTrue(
          e.getMessage().contains('StringBuilder'),
          'The exception message must name the stubbed type. Actual: ' +
            e.getMessage()
        );
      }
    }
  }

  /**
   * @description The review's false-positive trap: a method with a nullable
   *              return (getStringValue legitimately returns null on an empty
   *              builder) and NO registration must throw under strict dispatch —
   *              a silent null here would let an Assert.isNull pass against a
   *              stub that was never configured.
   */
  @isTest
  static void testNullableReturnUnregisteredCallThrowsInsteadOfPassing() {
    System.runAs(TestFactory.getMinAccessUser()) {
      TestDouble stub = new TestDouble(StringBuilder.class);
      stub.track(new TestDouble.Method('add'));
      StringBuilder fake = (StringBuilder) stub.generate();

      try {
        String result = fake.getStringValue();
        Assert.fail(
          'Expected UnexpectedInvocationException: an unregistered call on a ' +
            'nullable-return method must throw, not return a null that a test ' +
            'assertion could mistake for real behavior. Got: ' + result
        );
      } catch (TestDouble.UnexpectedInvocationException e) {
        Assert.isTrue(
          e.getMessage().contains('getStringValue'),
          'The exception message must name the unregistered method. Actual: ' +
            e.getMessage()
        );
      }
    }
  }

  /**
   * @description Lenient opt-in restores the old contract: unmatched
   *              invocations return null instead of throwing.
   */
  @isTest
  static void testLenientStubReturnsNullForUnmatchedInvocation() {
    System.runAs(TestFactory.getMinAccessUser()) {
      TestDouble stub = new TestDouble(StringBuilder.class).lenient();
      stub.track(new TestDouble.Method('add'));
      StringBuilder fake = (StringBuilder) stub.generate();

      Assert.isNull(
        fake.getStringValue(),
        'A lenient() stub returns null for unmatched invocations — the ' +
          'explicit opt-in restores the pre-strict null-return dispatch.'
      );
    }
  }

  /**
   * @description A stub configured via throwing() raises TestDoubleException
   *              carrying the registered message.
   */
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
