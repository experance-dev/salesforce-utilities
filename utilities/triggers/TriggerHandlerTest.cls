/**
 * @description Unit tests for the TriggerHandler class. Verifies trigger-context dispatch,
 *              bypass API, loop-count enforcement, and virtual-method defaults.
 * @group Triggers
 * @see TriggerHandler
 * @author David Wood
 * @since July 2024
 * @last May 2026 — conformance refactor
 * @last August 2026 — runAs user context on every method; per-hook no-op asserts; method ApexDoc
 */
@isTest
private without sharing class TriggerHandlerTest {
  private static final String TRIGGER_CONTEXT_ERROR = 'Trigger handler called outside of Trigger execution';
  private static String lastMethodCalled;
  private static TriggerHandlerTest.TestHandler handler;

  static {
    handler = new TriggerHandlerTest.TestHandler();
    // Override its internal trigger detection
    handler.isTriggerExecuting = true;
  }

  @TestSetup
  static void makeData() {
    TestFactory.createTestUser();
  }

  /***************************************
   * Unit Tests
   ***************************************/

  // Contexts Tests

  /**
   * @description Verifies run() dispatches to the beforeInsert hook in
   *              before-insert context.
   */
  @isTest
  static void testBeforeInsert() {
    System.runAs(TestFactory.getCreatedTestUser()) {
      beforeInsertMode();
      handler.run();
      Assert.areEqual(
        'beforeInsert',
        lastMethodCalled,
        'Last method should be beforeInsert'
      );
    }
  }

  /**
   * @description Verifies run() dispatches to the beforeUpdate hook in
   *              before-update context.
   */
  @isTest
  static void testBeforeUpdate() {
    System.runAs(TestFactory.getCreatedTestUser()) {
      beforeUpdateMode();
      handler.run();
      Assert.areEqual(
        'beforeUpdate',
        lastMethodCalled,
        'Last method should be beforeUpdate'
      );
    }
  }

  /**
   * @description Verifies run() dispatches to the beforeDelete hook in
   *              before-delete context.
   */
  @isTest
  static void testBeforeDelete() {
    System.runAs(TestFactory.getCreatedTestUser()) {
      beforeDeleteMode();
      handler.run();
      Assert.areEqual(
        'beforeDelete',
        lastMethodCalled,
        'Last method should be beforeDelete'
      );
    }
  }

  /**
   * @description Verifies run() dispatches to the afterInsert hook in
   *              after-insert context.
   */
  @isTest
  static void testAfterInsert() {
    System.runAs(TestFactory.getCreatedTestUser()) {
      afterInsertMode();
      handler.run();
      Assert.areEqual(
        'afterInsert',
        lastMethodCalled,
        'Last method should be afterInsert'
      );
    }
  }

  /**
   * @description Verifies run() dispatches to the afterUpdate hook in
   *              after-update context.
   */
  @isTest
  static void testAfterUpdate() {
    System.runAs(TestFactory.getCreatedTestUser()) {
      afterUpdateMode();
      handler.run();
      Assert.areEqual(
        'afterUpdate',
        lastMethodCalled,
        'Last method should be afterUpdate'
      );
    }
  }

  /**
   * @description Verifies run() dispatches to the afterDelete hook in
   *              after-delete context.
   */
  @isTest
  static void testAfterDelete() {
    System.runAs(TestFactory.getCreatedTestUser()) {
      afterDeleteMode();
      handler.run();
      Assert.areEqual(
        'afterDelete',
        lastMethodCalled,
        'Last method should be afterDelete'
      );
    }
  }

  /**
   * @description Verifies run() dispatches to the afterUndelete hook in
   *              after-undelete context.
   */
  @isTest
  static void testAfterUndelete() {
    System.runAs(TestFactory.getCreatedTestUser()) {
      afterUndeleteMode();
      handler.run();
      Assert.areEqual(
        'afterUndelete',
        lastMethodCalled,
        'Last method should be afterUndelete'
      );
    }
  }

  /**
   * @description Negative path: run() outside any trigger context throws
   *              TriggerHandlerException with the expected message.
   */
  @isTest
  static void testNonTriggerContext() {
    System.runAs(TestFactory.getCreatedTestUser()) {
      try {
        handler.run();
        Assert.fail('The handler ran but should have thrown');
      } catch (TriggerHandler.TriggerHandlerException te) {
        Assert.areEqual(
          TRIGGER_CONTEXT_ERROR,
          te.getMessage(),
          'The exception message should match'
        );
      } catch (Exception e) {
        Assert.fail(
          'The exception thrown was not expected: ' +
            e.getTypeName() +
            ': ' +
            e.getMessage()
        );
      }
    }
  }

  // Bypass API Tests

  /**
   * @description Exercises the full bypass API lifecycle: bypass suppresses the
   *              handler, clearBypass and clearAllBypasses restore it, and
   *              isBypassed reports each state correctly.
   */
  @isTest
  static void testBypassAPI() {
    System.runAs(TestFactory.getCreatedTestUser()) {
      afterUpdateMode();

      // Test a bypass and run handler
      TriggerHandler.bypass('TestHandler');
      handler.run();
      Assert.areEqual(
        null,
        lastMethodCalled,
        'Last method should be null when bypassed'
      );
      Assert.areEqual(
        true,
        TriggerHandler.isBypassed('TestHandler'),
        'Test handler should be bypassed'
      );
      resetTest();

      // Clear that bypass and run handler
      TriggerHandler.clearBypass('TestHandler');
      handler.run();
      Assert.areEqual(
        'afterUpdate',
        lastMethodCalled,
        'Last method called should be afterUpdate'
      );
      Assert.areEqual(
        false,
        TriggerHandler.isBypassed('TestHandler'),
        'Test handler should not be bypassed'
      );
      resetTest();

      // Test a re-bypass and run handler
      TriggerHandler.bypass('TestHandler');
      handler.run();
      Assert.areEqual(
        null,
        lastMethodCalled,
        'Last method should be null when bypassed'
      );
      Assert.areEqual(
        true,
        TriggerHandler.isBypassed('TestHandler'),
        'Test handler should be bypassed'
      );
      resetTest();

      // Clear all bypasses and run handler
      TriggerHandler.clearAllBypasses();
      handler.run();
      Assert.areEqual(
        'afterUpdate',
        lastMethodCalled,
        'Last method called should be afterUpdate'
      );
      Assert.areEqual(
        false,
        TriggerHandler.isBypassed('TestHandler'),
        'Test handler should not be bypassed'
      );
      resetTest();
    }
  }

  // Instance Method Tests

  /**
   * @description Verifies loop-count enforcement: runs beyond the configured
   *              ceiling throw, and clearMaxLoopCount lifts the ceiling.
   */
  @isTest
  static void testLoopCount() {
    System.runAs(TestFactory.getCreatedTestUser()) {
      beforeInsertMode();

      // Set the max loops to 2
      handler.setMaxLoopCount(2);

      // Run the handler twice
      handler.run();
      handler.run();

      // Clear the tests
      resetTest();

      try {
        // Try running it. This should exceed the limit.
        handler.run();
        Assert.fail(
          'The handler should throw on the 3rd run when maxLoopCount is 2'
        );
      } catch (TriggerHandler.TriggerHandlerException te) {
        // We're expecting to get here
        Assert.areEqual(null, lastMethodCalled, 'Last method should be null');
      } catch (Exception e) {
        Assert.fail(
          'The exception thrown was not expected: ' +
            e.getTypeName() +
            ': ' +
            e.getMessage()
        );
      }

      // Clear the tests
      resetTest();

      // Now clear the loop count
      handler.clearMaxLoopCount();

      try {
        // Re-run the handler. We shouldn't throw now.
        handler.run();
        Assert.areEqual(
          'beforeInsert',
          lastMethodCalled,
          'Last method should be beforeInsert'
        );
      } catch (TriggerHandler.TriggerHandlerException te) {
        Assert.fail(
          'Running the handler after clearing the loop count should not throw'
        );
      } catch (Exception e) {
        Assert.fail(
          'The exception thrown was not expected: ' +
            e.getTypeName() +
            ': ' +
            e.getMessage()
        );
      }
    }
  }

  /**
   * @description Verifies the LoopCount inner class: default ceiling of 5,
   *              increment counting, and exceeded() flipping past the ceiling.
   */
  @isTest
  static void testLoopCountClass() {
    System.runAs(TestFactory.getCreatedTestUser()) {
      TriggerHandler.LoopCount lc = new TriggerHandler.LoopCount();
      Assert.areEqual(5, lc.getMax(), 'Max should be five on init');
      Assert.areEqual(0, lc.getCount(), 'Count should be zero on init');

      lc.increment();
      Assert.areEqual(1, lc.getCount(), 'Count should be 1');
      Assert.areEqual(
        false,
        lc.exceeded(),
        'Should not be exceeded with count of 1'
      );

      lc.increment();
      lc.increment();
      lc.increment();
      lc.increment();
      Assert.areEqual(5, lc.getCount(), 'Count should be 5');
      Assert.areEqual(
        false,
        lc.exceeded(),
        'Should not be exceeded with count of 5'
      );

      lc.increment();
      Assert.areEqual(6, lc.getCount(), 'Count should be 6');
      Assert.areEqual(
        true,
        lc.exceeded(),
        'Should be exceeded with count of 6'
      );
    }
  }

  // Private Method Tests

  /**
   * @description Verifies getHandlerName resolves the concrete subclass name,
   *              which keys the loop-count and bypass registries.
   */
  @isTest
  static void testGetHandlerName() {
    System.runAs(TestFactory.getCreatedTestUser()) {
      Assert.areEqual(
        'TestHandler',
        handler.getHandlerName(),
        'Handler name should match class name'
      );
    }
  }

  // Test Virtual Methods

  /**
   * @description Verifies each of the eight default virtual hooks is a safe
   *              no-op — a subclass that overrides nothing must run every
   *              context without throwing.
   */
  @isTest
  static void testVirtualMethodDefaultsAreNoOps() {
    System.runAs(TestFactory.getCreatedTestUser()) {
      TriggerHandler baseHandler = new TriggerHandler();

      try {
        baseHandler.beforeInsert();
      } catch (Exception e) {
        Assert.fail('Default beforeInsert should not throw: ' + e.getMessage());
      }
      try {
        baseHandler.beforeUpdate();
      } catch (Exception e) {
        Assert.fail('Default beforeUpdate should not throw: ' + e.getMessage());
      }
      try {
        baseHandler.beforeDelete();
      } catch (Exception e) {
        Assert.fail('Default beforeDelete should not throw: ' + e.getMessage());
      }
      try {
        baseHandler.afterInsert();
      } catch (Exception e) {
        Assert.fail('Default afterInsert should not throw: ' + e.getMessage());
      }
      try {
        baseHandler.afterUpdate();
      } catch (Exception e) {
        Assert.fail('Default afterUpdate should not throw: ' + e.getMessage());
      }
      try {
        baseHandler.afterDelete();
      } catch (Exception e) {
        Assert.fail('Default afterDelete should not throw: ' + e.getMessage());
      }
      try {
        baseHandler.afterUndelete();
      } catch (Exception e) {
        Assert.fail(
          'Default afterUndelete should not throw: ' + e.getMessage()
        );
      }
      try {
        baseHandler.andFinally();
      } catch (Exception e) {
        Assert.fail('Default andFinally should not throw: ' + e.getMessage());
      }

      Assert.isNull(
        lastMethodCalled,
        'Base-class default hooks must not dispatch into subclass behavior'
      );
    }
  }

  /***************************************
   * Testing Utilities
   ***************************************/

  /**
   * @description Reset the lastMethodCalled variable for clean test execution.
   */
  private static void resetTest() {
    lastMethodCalled = null;
  }

  // Modes for Testing

  /**
   * @description Set the handler to before insert mode.
   */
  private static void beforeInsertMode() {
    handler.setTriggerContext('before insert', true);
  }

  /**
   * @description Set the handler to before update mode.
   */
  private static void beforeUpdateMode() {
    handler.setTriggerContext('before update', true);
  }

  /**
   * @description Set the handler to before delete mode.
   */
  private static void beforeDeleteMode() {
    handler.setTriggerContext('before delete', true);
  }

  /**
   * @description Set the handler to after insert mode.
   */
  private static void afterInsertMode() {
    handler.setTriggerContext('after insert', true);
  }

  /**
   * @description Set the handler to after update mode.
   */
  private static void afterUpdateMode() {
    handler.setTriggerContext('after update', true);
  }

  /**
   * @description Set the handler to after delete mode.
   */
  private static void afterDeleteMode() {
    handler.setTriggerContext('after delete', true);
  }

  /**
   * @description Set the handler to after undelete mode.
   */
  private static void afterUndeleteMode() {
    handler.setTriggerContext('after undelete', true);
  }

  // Test implementation of the TriggerHandler

  /**
   * @description TestHandler class to simulate different trigger contexts.
   */
  private class TestHandler extends TriggerHandler {
    public override void beforeInsert() {
      TriggerHandlerTest.lastMethodCalled = 'beforeInsert';
    }

    public override void beforeUpdate() {
      TriggerHandlerTest.lastMethodCalled = 'beforeUpdate';
    }

    public override void beforeDelete() {
      TriggerHandlerTest.lastMethodCalled = 'beforeDelete';
    }

    public override void afterInsert() {
      TriggerHandlerTest.lastMethodCalled = 'afterInsert';
    }

    public override void afterUpdate() {
      TriggerHandlerTest.lastMethodCalled = 'afterUpdate';
    }

    public override void afterDelete() {
      TriggerHandlerTest.lastMethodCalled = 'afterDelete';
    }

    public override void afterUndelete() {
      TriggerHandlerTest.lastMethodCalled = 'afterUndelete';
    }
  }
}
