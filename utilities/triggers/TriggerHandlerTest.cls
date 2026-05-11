/**
 * @description Unit tests for the TriggerHandler class. This class tests various trigger contexts
 *              and ensures that the TriggerHandler behaves as expected.
 * @group TriggerHandlerTests
 * @since July 2024
 */
@isTest
private class TriggerHandlerTest {
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

  /**
   * @description Test handler execution in before insert context.
   */
  @isTest
  static void testBeforeInsert() {
    beforeInsertMode();
    handler.run();
    System.assertEquals(
      'beforeInsert',
      lastMethodCalled,
      'Last method should be beforeInsert'
    );
  }

  /**
   * @description Test handler execution in before update context.
   */
  @isTest
  static void testBeforeUpdate() {
    beforeUpdateMode();
    handler.run();
    System.assertEquals(
      'beforeUpdate',
      lastMethodCalled,
      'Last method should be beforeUpdate'
    );
  }

  /**
   * @description Test handler execution in before delete context.
   */
  @isTest
  static void testBeforeDelete() {
    beforeDeleteMode();
    handler.run();
    System.assertEquals(
      'beforeDelete',
      lastMethodCalled,
      'Last method should be beforeDelete'
    );
  }

  /**
   * @description Test handler execution in after insert context.
   */
  @isTest
  static void testAfterInsert() {
    afterInsertMode();
    handler.run();
    System.assertEquals(
      'afterInsert',
      lastMethodCalled,
      'Last method should be afterInsert'
    );
  }

  /**
   * @description Test handler execution in after update context.
   */
  @isTest
  static void testAfterUpdate() {
    afterUpdateMode();
    handler.run();
    System.assertEquals(
      'afterUpdate',
      lastMethodCalled,
      'Last method should be afterUpdate'
    );
  }

  /**
   * @description Test handler execution in after delete context.
   */
  @isTest
  static void testAfterDelete() {
    afterDeleteMode();
    handler.run();
    System.assertEquals(
      'afterDelete',
      lastMethodCalled,
      'Last method should be afterDelete'
    );
  }

  /**
   * @description Test handler execution in after undelete context.
   */
  @isTest
  static void testAfterUndelete() {
    afterUndeleteMode();
    handler.run();
    System.assertEquals(
      'afterUndelete',
      lastMethodCalled,
      'Last method should be afterUndelete'
    );
  }

  /**
   * @description Test handler behavior when run outside of trigger context.
   */
  @isTest
  static void testNonTriggerContext() {
    try {
      handler.run();
      System.assert(false, 'The handler ran but should have thrown');
    } catch (TriggerHandler.TriggerHandlerException te) {
      System.assertEquals(
        TRIGGER_CONTEXT_ERROR,
        te.getMessage(),
        'The exception message should match'
      );
    } catch (Exception e) {
      System.assert(
        false,
        'The exception thrown was not expected: ' +
          e.getTypeName() +
          ': ' +
          e.getMessage()
      );
    }
  }

  // Bypass API Tests

  /**
   * @description Test the bypass API for the TriggerHandler.
   */
  @isTest
  static void testBypassAPI() {
    afterUpdateMode();

    // Test a bypass and run handler
    TriggerHandler.bypass('TestHandler');
    handler.run();
    System.assertEquals(
      null,
      lastMethodCalled,
      'Last method should be null when bypassed'
    );
    System.assertEquals(
      true,
      TriggerHandler.isBypassed('TestHandler'),
      'Test handler should be bypassed'
    );
    resetTest();

    // Clear that bypass and run handler
    TriggerHandler.clearBypass('TestHandler');
    handler.run();
    System.assertEquals(
      'afterUpdate',
      lastMethodCalled,
      'Last method called should be afterUpdate'
    );
    System.assertEquals(
      false,
      TriggerHandler.isBypassed('TestHandler'),
      'Test handler should not be bypassed'
    );
    resetTest();

    // Test a re-bypass and run handler
    TriggerHandler.bypass('TestHandler');
    handler.run();
    System.assertEquals(
      null,
      lastMethodCalled,
      'Last method should be null when bypassed'
    );
    System.assertEquals(
      true,
      TriggerHandler.isBypassed('TestHandler'),
      'Test handler should be bypassed'
    );
    resetTest();

    // Clear all bypasses and run handler
    TriggerHandler.clearAllBypasses();
    handler.run();
    System.assertEquals(
      'afterUpdate',
      lastMethodCalled,
      'Last method called should be afterUpdate'
    );
    System.assertEquals(
      false,
      TriggerHandler.isBypassed('TestHandler'),
      'Test handler should not be bypassed'
    );
    resetTest();
  }

  // Instance Method Tests

  /**
   * @description Test the loop count functionality of the handler.
   */
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
      System.assert(
        false,
        'The handler should throw on the 3rd run when maxLoopCount is 2'
      );
    } catch (TriggerHandler.TriggerHandlerException te) {
      // We're expecting to get here
      System.assertEquals(null, lastMethodCalled, 'Last method should be null');
    } catch (Exception e) {
      System.assert(
        false,
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
      System.assertEquals(
        'beforeInsert',
        lastMethodCalled,
        'Last method should be beforeInsert'
      );
    } catch (TriggerHandler.TriggerHandlerException te) {
      System.assert(
        false,
        'Running the handler after clearing the loop count should not throw'
      );
    } catch (Exception e) {
      System.assert(
        false,
        'The exception thrown was not expected: ' +
          e.getTypeName() +
          ': ' +
          e.getMessage()
      );
    }
  }

  /**
   * @description Test the LoopCount class functionality.
   */
  @isTest
  static void testLoopCountClass() {
    TriggerHandler.LoopCount lc = new TriggerHandler.LoopCount();
    System.assertEquals(5, lc.getMax(), 'Max should be five on init');
    System.assertEquals(0, lc.getCount(), 'Count should be zero on init');

    lc.increment();
    System.assertEquals(1, lc.getCount(), 'Count should be 1');
    System.assertEquals(
      false,
      lc.exceeded(),
      'Should not be exceeded with count of 1'
    );

    lc.increment();
    lc.increment();
    lc.increment();
    lc.increment();
    System.assertEquals(5, lc.getCount(), 'Count should be 5');
    System.assertEquals(
      false,
      lc.exceeded(),
      'Should not be exceeded with count of 5'
    );

    lc.increment();
    System.assertEquals(6, lc.getCount(), 'Count should be 6');
    System.assertEquals(
      true,
      lc.exceeded(),
      'Should be exceeded with count of 6'
    );
  }

  // Private Method Tests

  /**
   * @description Test the getHandlerName method.
   */
  @isTest
  static void testGetHandlerName() {
    System.assertEquals(
      'TestHandler',
      handler.getHandlerName(),
      'Handler name should match class name'
    );
  }

  // Test Virtual Methods

  /**
   * @description Test the virtual methods of the TriggerHandler class.
   */
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
