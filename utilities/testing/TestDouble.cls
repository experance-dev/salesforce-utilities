/**
 * @description Reusable StubProvider implementation with a fluent builder API.
 *              Wraps `System.StubProvider` so tests can stub collaborator methods
 *              without hand-rolling mocks.  See `TestDouble.Method` for the per-method
 *              builder and `TestDouble.TestDoubleException` for controlled throws.
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
 * @last August 2026 — overload guard rebuilt: each registered constraint list now matches independently,
 *                      so a types-only stub fires for calls with arguments; analyzer conformance
 */
@isTest
public without sharing class TestDouble implements System.StubProvider {
  // Methods the developer has actively registered stubs for.
  List<Method> methods = new List<Method>();

  // The Apex Type being stubbed — required by Test.createStub().
  // Note: system classes, sObjects, and static methods cannot be stubbed.
  Type objectType;

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
   * @return `Object` — the value registered via `Method.returning()`, or null
   *         if no matching stub was found (intentional: unregistered calls break tests).
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
    // Returning null is deliberate: unregistered calls will cause downstream
    // NPEs in tests, immediately revealing missing stub registrations.
    return null;
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
}
