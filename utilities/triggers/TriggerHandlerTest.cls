/**
 * @description Unit tests for the TriggerHandler class. Verifies trigger-context dispatch,
 *              bypass API, loop-count enforcement, and virtual-method defaults.
 * @group Triggers
 * @see TriggerHandler
 * @author David Wood
 * @since July 2024
 * @last May 2026 — Wave 6 conformance
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

  /***************************************
   * Unit Tests
   ***************************************/

  // Contexts Tests

  @isTest
  static void testBeforeInsert() {
    beforeInsertMode();
    handler.run();
    Assert.areEqual(
      'beforeInsert',
      lastMethodCalled,
      'Last method should be beforeInsert'
    );
  }

  @isTest
  static void testBeforeUpdate() {
    beforeUpdateMode();
    handler.run();
    Assert.areEqual(
      'beforeUpdate',
      lastMethodCalled,
      'Last method should be beforeUpdate'
    );
  }

  @isTest
  static void testBeforeDelete() {
    beforeDeleteMode();
    handler.run();
    Assert.areEqual(
      'beforeDelete',
      lastMethodCalled,
      'Last method should be beforeDelete'
    );
  }

  @isTest
  static void testAfterInsert() {
    afterInsertMode();
    handler.run();
    Assert.areEqual(
      'afterInsert',
      lastMethodCalled,
      'Last method should be afterInsert'
    );
  }

  @isTest
  static void testAfterUpdate() {
    afterUpdateMode();
    handler.run();
    Assert.areEqual(
      'afterUpdate',
      lastMethodCalled,
      'Last method should be afterUpdate'
    );
  }

  @isTest
  static void testAfterDelete() {
    afterDeleteMode();
    handler.run();
    Assert.areEqual(
      'afterDelete',
      lastMethodCalled,
      'Last method should be afterDelete'
    );
  }

  @isTest
  static void testAfterUndelete() {
    afterUndeleteMode();
    handler.run();
    Assert.areEqual(
      'afterUndelete',
      lastMethodCalled,
      'Last method should be afterUndelete'
    );
  }

  @isTest
  static void testNonTriggerContext() {
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

  // Bypass API Tests

  @isTest
  static void testBypassAPI() {
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

  // Instance Method Tests

  @isTest
  static void testLoopCount() {
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

  @isTest
  static void testLoopCountClass() {
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

  // Private Method Tests

  @isTest
  static void testGetHandlerName() {
    Assert.areEqual(
      'TestHandler',
      handler.getHandlerName(),
      'Handler name should match class name'
    );
  }

  // Test Virtual Methods

  @isTest
  static void testVirtualMethods() {
    TriggerHandler h = new TriggerHandler();
    h.beforeInsert();
    h.beforeUpdate();
    h.beforeDelete();
    h.afterInsert();
    h.afterUpdate();
    h.afterDelete();
    h.afterUndelete();
    Assert.isTrue(true, 'Virtual methods should not throw error');
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
