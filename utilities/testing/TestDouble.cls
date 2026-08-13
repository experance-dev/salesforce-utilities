/**
 * @description Reusable StubProvider implementation with a fluent builder API.
 *              Wraps `System.StubProvider` so tests can stub collaborator methods
 *              without hand-rolling mocks.  See `TestDouble.Method` for the per-method
 *              builder and `TestDouble.TestDoubleException` for controlled throws.
 *
 *              Dispatch contract: an invocation that matches no registered `Method`
 *              throws `UnexpectedInvocationException` naming the method and its
 *              arguments. Strict-by-default exists because silent null-return hides
 *              missing registrations — a stubbed method with a nullable return can
 *              satisfy an assertion the real collaborator never would. Call
 *              `.lenient()` on the instance to opt back into null-return dispatch.
 *
 *              Typical use:
 *              ```apex
 *              TestDouble stub = new TestDouble(SomeClass.class);
 *              TestDouble.Method m = new TestDouble.Method('methodName')
 *                  .returning(someObject);
 *              stub.track(m);
 *              SomeClass fake = (SomeClass) stub.generate();
 *              ```
 * @group Testing
 * @author David Wood
 * @since June 2024
 * @last May 2026 — conformance refactor
 * @last 2026-08-13 — dispatch contract hardened: independent constraint-list matching
 *                    (types / names / args each enforced only when registered) plus
 *                    strict unmatched-invocation throw with lenient() opt-out
 */
@isTest
public without sharing class TestDouble implements System.StubProvider {
  // Methods the developer has actively registered stubs for.
  List<Method> methods = new List<Method>();

  // The Apex Type being stubbed — required by Test.createStub().
  // Note: system classes, sObjects, and static methods cannot be stubbed.
  Type objectType;

  // When true, unmatched invocations return null instead of throwing.
  Boolean lenientMode = false;

  /**
   * @description Builds a stub provider for the given Apex type.
   * @param objectType The Apex Type to stub (e.g. MyService.class).
   */
  public TestDouble(Type objectType) {
    this.objectType = objectType;
  }

  /**
   * @description Registers a Method stub with this instance for dispatch.
   * @param toTrack A configured `TestDouble.Method` object.
   * @return `TestDouble` — this instance, for chaining.
   */
  public TestDouble track(Method toTrack) {
    this.methods.add(toTrack);

    return this;
  }

  /**
   * @description Opts this instance out of strict dispatch: unmatched invocations
   *              return null instead of throwing `UnexpectedInvocationException`.
   *              Reach for this only when the code under test legitimately calls
   *              collaborator methods the test has no interest in registering.
   * @return `TestDouble` — this instance, for chaining.
   */
  public TestDouble lenient() {
    this.lenientMode = true;

    return this;
  }

  /**
   * @description Materialises the stub object via the platform stub API.
   * @return `Object` — cast back to the stubbed type at the call site.
   */
  public Object generate() {
    return Test.createStub(this.objectType, this);
  }

  /**
   * @description Required `StubProvider` callback.  Matches the incoming call
   *              to a registered `Method` by name, then by whichever constraint
   *              lists the stub registered (param types, param names, args) —
   *              each enforced independently — and delegates to `Method.handleCall()`.
   * @param stubbedObject     The object being stubbed.
   * @param stubbedMethodName The name of the method being called.
   * @param returnType        The declared return type.
   * @param listOfParamTypes  Parameter types (used for overload disambiguation).
   * @param listOfParamNames  Parameter names (used for overload disambiguation).
   * @param listOfArgs        Actual argument values.
   * @return `Object` — the value registered via `Method.returning()`; when no
   *         registered stub matches, null only in lenient mode.
   * @throws UnexpectedInvocationException When no registered stub matches the
   *         invocation and `lenient()` has not been called on this instance.
   */
  @SuppressWarnings('PMD.ExcessiveParameterList')
  public Object handleMethodCall(
    Object stubbedObject,
    String stubbedMethodName,
    Type returnType,
    List<System.Type> listOfParamTypes,
    List<String> listOfParamNames,
    List<Object> listOfArgs
  ) {
    for (Method method : methods) {
      // Case-insensitive name match first; then apply any registered constraints.
      if (method.name.equalsIgnoreCase(stubbedMethodName)) {
        // The three constraint lists are independent — a stub may register any
        // subset of them (types, names, args). Each list is enforced only when
        // the caller registered it; an unregistered (empty) list never vetoes
        // a match, so a types-only stub still fires for calls with arguments.
        Boolean paramTypesMatch =
          method.listOfParamTypes.isEmpty() ||
          method.listOfParamTypes == listOfParamTypes;
        Boolean paramNamesMatch =
          method.listOfParamNames.isEmpty() ||
          method.listOfParamNames == listOfParamNames;
        Boolean argsMatch =
          method.listOfArgs.isEmpty() ||
          method.listOfArgs == listOfArgs;
        if (paramTypesMatch && paramNamesMatch && argsMatch) {
          return method.handleCall();
        }
      }
    }
    if (lenientMode) {
      // Lenient dispatch: the test opted in to null-return for unmatched calls.
      return null;
    }
    // Strict dispatch: surface the missing registration at the call site instead
    // of letting a silent null satisfy an assertion the real collaborator wouldn't.
    throw new UnexpectedInvocationException(
      'Unexpected invocation on ' +
        String.valueOf(objectType) +
        ' stub: ' +
        stubbedMethodName +
        '(' +
        renderArguments(listOfArgs) +
        '). No registered TestDouble.Method matched this call. Register a ' +
        'matching Method via track(), or call lenient() on the TestDouble to ' +
        'restore null-return dispatch.'
    );
  }

  /**
   * @description Renders an argument list for the strict-dispatch exception
   *              message so the failure names the exact call that had no registration.
   * @param arguments The invocation's actual argument values; null-safe.
   * @return `String` — the arguments rendered as a comma-separated list, or empty.
   */
  private static String renderArguments(List<Object> arguments) {
    if (arguments == null || arguments.isEmpty()) {
      return '';
    }
    List<String> rendered = new List<String>();
    for (Object argument : arguments) {
      rendered.add(String.valueOf(argument));
    }
    return String.join(rendered, ', ');
  }

  /**
   * @description Describes a single stubbed method, including its return value,
   *              optional param-list constraints for overload disambiguation,
   *              and call-count tracking.
   */
  public class Method {
    // Name of the method being stubbed.
    String name;
    // Value to return when the stub is invoked.
    Object returnValue;
    // Running tally — assert against this to verify call count.
    public Integer hasBeenCalledXTimes = 0;
    // When true, handleCall() throws TestDoubleException instead of returning.
    Boolean throwsException = false;
    // Message carried by the thrown TestDoubleException.
    String exceptionMessage = '';
    // Overload-disambiguation: each registered (non-empty) list must match for
    // the stub to fire; unregistered lists place no constraint on the call.
    List<Type> listOfParamTypes = new List<Type>();
    List<String> listOfParamNames = new List<String>();
    List<Object> listOfArgs = new List<Object>();

    /**
     * @description Names the method this stub intercepts.
     * @param methodName Name of the method to stub.
     */
    public Method(String methodName) {
      this.name = methodName;
    }

    /**
     * @description Constrains this stub to fire only when param types match.
     * @param paramTypes Expected parameter types.
     * @return `Method` — this instance, for chaining.
     */
    public Method withParamTypes(List<Type> paramTypes) {
      this.listOfParamTypes = paramTypes;

      return this;
    }

    /**
     * @description Constrains this stub to fire only when param names match.
     * @param paramNames Expected parameter names.
     * @return `Method` — this instance, for chaining.
     */
    public Method withParamNames(List<String> paramNames) {
      this.listOfParamNames = paramNames;

      return this;
    }

    /**
     * @description Constrains this stub to fire only when argument values match.
     * @param args Expected argument values.
     * @return `Method` — this instance, for chaining.
     */
    public Method withArgs(List<Object> args) {
      this.listOfArgs = args;

      return this;
    }

    /**
     * @description Registers the value this stub returns when invoked.
     * @param returnValue The value to return.
     * @return `Method` — this instance, for chaining.
     */
    public Method returning(Object returnValue) {
      this.returnValue = returnValue;

      return this;
    }

    /**
     * @description Configures this stub to throw a `TestDoubleException` instead of returning.
     * @param exceptionMessage Message to include in the thrown exception.
     * @return `Method` — this instance, for chaining.
     */
    public Method throwing(String exceptionMessage) {
      this.exceptionMessage = exceptionMessage;
      this.throwsException = true;
      return this;
    }

    /**
     * @description Dispatches the stub — increments the call counter, then either
     *              throws or returns per configuration.
     * @return `Object` — the registered return value, or throws.
     */
    public Object handleCall() {
      hasBeenCalledXTimes++;

      if (throwsException) {
        throw new TestDoubleException(exceptionMessage);
      }
      return returnValue;
    }
  }

  /**
   * @description Thrown by stubs configured via `Method.throwing()`.
   *              Extends `UtilitiesModuleException` so test helpers share the
   *              module-level catch hierarchy.
   */
  public class TestDoubleException extends UtilitiesModuleException {
  }

  /**
   * @description Thrown by strict dispatch when an invocation matches no
   *              registered `Method` — the message names the method and its
   *              rendered arguments so the missing registration is a one-read fix.
   *              Suppressed by calling `lenient()` on the `TestDouble` instance.
   */
  public class UnexpectedInvocationException extends UtilitiesModuleException {
  }
}
