/**
 * @description Generic trigger-dispatcher framework (Kevin O'Hara fork).
 *              Subclass this and override the relevant before/after hook methods;
 *              the trigger body calls `new MyHandler().run()`.
 *
 *              Sharing modifier: `without sharing` is intentional — the dispatcher
 *              itself performs no data access; sharing rules are enforced by the
 *              calling trigger's context and the service/domain layer it invokes.
 *              Using `with sharing` here would incorrectly restrict the dispatcher
 *              when invoked from a system-context trigger.
 *
 *              Platform-cache migration (DEFERRED — Wave 4):
 *              `loopCountMap` and `bypassedHandlers` are static class variables.
 *              Per apex.md, cross-transaction state belongs in session platform cache.
 *              Migration was deferred because: (1) no named cache partition is
 *              confirmed to exist in the org; (2) the existing TriggerHandlerTest
 *              relies on static state persisting across sequential `handler.run()`
 *              calls within a single test method — cache isolation semantics in
 *              test context would require a full test-suite rewrite; (3) trigger
 *              handlers run synchronously so static state is reset between
 *              transactions anyway, reducing the async-correctness risk cited in
 *              apex.md. When a cache partition is provisioned, migrate both fields
 *              and update clearCache() to flush the partition key instead.
 * @group Triggers
 * @author Kevin O'Hara / Zelis Engineering
 * @since July 2024
 * @last May 2026 — Wave 3 conformance: sharing modifier, header, exception hierarchy,
 *                  run() decomposition, @TestVisible capitalisation, clearCache() stub.
 */
public virtual without sharing class TriggerHandler {
  // Static loop-count and bypass registries.
  // DEFERRED: should move to session platform cache (see class header).
  private static Map<String, LoopCount> loopCountMap;
  private static Set<String> bypassedHandlers;

  // The current context of the trigger, overridable in tests.
  @TestVisible
  protected TriggerContext context;

  // Whether this instance was created inside a real trigger execution.
  @TestVisible
  private Boolean isTriggerExecuting;

  static {
    loopCountMap = new Map<String, LoopCount>();
    bypassedHandlers = new Set<String>();
  }

  /**
   * @description Custom exception for TriggerHandler errors; extends the
   *              module-level base so callers can catch at either granularity.
   */
  public class TriggerHandlerException extends UtilitiesModuleException {
  }

  public TriggerHandler() {
    this.setTriggerContext();
  }

  // ─── Public API (frozen) ──────────────────────────────────────────────────────

  /**
   * Main entry point called by the trigger body. Validates context, enforces
   * the loop-count ceiling, dispatches to the appropriate hook method, then
   * calls `andFinally`.
   */
  public virtual void run() {
    if (!validateRun()) {
      return;
    }
    addToLoopCount();
    dispatchToHook();
    this.andFinally();
  }

  /**
   * Prevents infinite trigger recursion by capping the number of times this
   * handler may fire in a single transaction.
   * @param max Maximum allowed executions (use 1 to allow exactly one run).
   */
  public void setMaxLoopCount(Integer max) {
    String handlerName = getHandlerName();
    if (!TriggerHandler.loopCountMap.containsKey(handlerName)) {
      TriggerHandler.loopCountMap.put(handlerName, new LoopCount(max));
    } else {
      TriggerHandler.loopCountMap.get(handlerName).setMax(max);
    }
  }

  /** Removes the loop-count ceiling for this handler. */
  public void clearMaxLoopCount() {
    this.setMaxLoopCount(-1);
  }

  /**
   * Prevents the named handler from firing for the remainder of this transaction.
   * @param handlerName Apex class name of the handler to suppress.
   */
  public static void bypass(String handlerName) {
    TriggerHandler.bypassedHandlers.add(handlerName);
  }

  /**
   * Re-enables a previously bypassed handler.
   * @param handlerName Apex class name to remove from the bypass set.
   */
  public static void clearBypass(String handlerName) {
    TriggerHandler.bypassedHandlers.remove(handlerName);
  }

  /**
   * @param handlerName Apex class name to check.
   * @return `Boolean` — true if the handler is currently suppressed.
   */
  public static Boolean isBypassed(String handlerName) {
    return TriggerHandler.bypassedHandlers.contains(handlerName);
  }

  /** Removes all handlers from the bypass set. */
  public static void clearAllBypasses() {
    TriggerHandler.bypassedHandlers.clear();
  }

  // ─── Test support ─────────────────────────────────────────────────────────────

  /**
   * Resets static state between test methods.
   * NOTE: When platform-cache migration lands (Wave 4), update this method to
   * also flush the relevant cache partition keys.
   */
  @TestVisible
  static void clearCache() {
    loopCountMap = new Map<String, LoopCount>();
    bypassedHandlers = new Set<String>();
  }

  // ─── Private / protected instance helpers ─────────────────────────────────────

  @TestVisible
  private void setTriggerContext() {
    this.setTriggerContext(null, false);
  }

  /**
   * @param ctx      String trigger-context token used in test mode.
   * @param testMode When true, `ctx` drives the context instead of Trigger.*
   */
  @TestVisible
  private void setTriggerContext(String ctx, Boolean testMode) {
    if (!Trigger.isExecuting && !testMode) {
      this.isTriggerExecuting = false;
      return;
    }
    this.isTriggerExecuting = true;

    if (Trigger.isExecuting && !testMode) {
      this.context = contextFromOperationType(Trigger.operationType);
    } else if (ctx != null && testMode) {
      this.context = contextFromString(ctx);
    }
  }

  /** Maps the platform TriggerOperation enum to our TriggerContext enum. */
  private static TriggerContext contextFromOperationType(
    System.TriggerOperation opType
  ) {
    switch on opType {
      when BEFORE_INSERT {
        return TriggerContext.BEFORE_INSERT;
      }
      when BEFORE_UPDATE {
        return TriggerContext.BEFORE_UPDATE;
      }
      when BEFORE_DELETE {
        return TriggerContext.BEFORE_DELETE;
      }
      when AFTER_INSERT {
        return TriggerContext.AFTER_INSERT;
      }
      when AFTER_UPDATE {
        return TriggerContext.AFTER_UPDATE;
      }
      when AFTER_DELETE {
        return TriggerContext.AFTER_DELETE;
      }
      when AFTER_UNDELETE {
        return TriggerContext.AFTER_UNDELETE;
      }
      when else {
        return null;
      }
    }
  }

  /** Maps a test-mode string token to TriggerContext; throws on unrecognised input. */
  private static TriggerContext contextFromString(String ctx) {
    switch on ctx {
      when 'before insert' {
        return TriggerContext.BEFORE_INSERT;
      }
      when 'before update' {
        return TriggerContext.BEFORE_UPDATE;
      }
      when 'before delete' {
        return TriggerContext.BEFORE_DELETE;
      }
      when 'after insert' {
        return TriggerContext.AFTER_INSERT;
      }
      when 'after update' {
        return TriggerContext.AFTER_UPDATE;
      }
      when 'after delete' {
        return TriggerContext.AFTER_DELETE;
      }
      when 'after undelete' {
        return TriggerContext.AFTER_UNDELETE;
      }
      when else {
        throw new TriggerHandler.TriggerHandlerException(
          'Unexpected trigger context set'
        );
      }
    }
  }

  /** Dispatches to the virtual hook matching the current context. */
  private void dispatchToHook() {
    switch on context {
      when BEFORE_INSERT {
        this.beforeInsert();
      }
      when BEFORE_UPDATE {
        this.beforeUpdate();
      }
      when BEFORE_DELETE {
        this.beforeDelete();
      }
      when AFTER_INSERT {
        this.afterInsert();
      }
      when AFTER_UPDATE {
        this.afterUpdate();
      }
      when AFTER_DELETE {
        this.afterDelete();
      }
      when AFTER_UNDELETE {
        this.afterUndelete();
      }
    }
  }

  /**
   * Increments the run counter for this handler and throws if the ceiling is exceeded.
   */
  @TestVisible
  protected void addToLoopCount() {
    String handlerName = getHandlerName();
    if (TriggerHandler.loopCountMap.containsKey(handlerName)) {
      Boolean exceeded = TriggerHandler.loopCountMap.get(handlerName).increment();
      if (exceeded) {
        Integer max = TriggerHandler.loopCountMap.get(handlerName).max;
        throw new TriggerHandlerException(
          'Maximum loop count of ' + max + ' reached in ' + handlerName
        );
      }
    }
  }

  /**
   * @return `Boolean` false when this handler is bypassed; throws when called
   *         outside a trigger execution.
   */
  @TestVisible
  protected Boolean validateRun() {
    if (!this.isTriggerExecuting || this.context == null) {
      throw new TriggerHandlerException(
        'Trigger handler called outside of Trigger execution'
      );
    }
    if (TriggerHandler.bypassedHandlers.contains(getHandlerName())) {
      return false;
    }
    return true;
  }

  /**
   * @return `String` simple class name of the concrete handler subclass.
   */
  @TestVisible
  private String getHandlerName() {
    return String.valueOf(this).substring(0, String.valueOf(this).indexOf(':'));
  }

  // ─── Virtual hook methods (override in subclasses) ────────────────────────────

  @TestVisible
  @SuppressWarnings('PMD.EmptyStatementBlock')
  protected virtual void beforeInsert() {
  }

  @TestVisible
  @SuppressWarnings('PMD.EmptyStatementBlock')
  protected virtual void beforeUpdate() {
  }

  @TestVisible
  @SuppressWarnings('PMD.EmptyStatementBlock')
  protected virtual void beforeDelete() {
  }

  @TestVisible
  @SuppressWarnings('PMD.EmptyStatementBlock')
  protected virtual void afterInsert() {
  }

  @TestVisible
  @SuppressWarnings('PMD.EmptyStatementBlock')
  protected virtual void afterUpdate() {
  }

  @TestVisible
  @SuppressWarnings('PMD.EmptyStatementBlock')
  protected virtual void afterDelete() {
  }

  @TestVisible
  @SuppressWarnings('PMD.EmptyStatementBlock')
  protected virtual void afterUndelete() {
  }

  @TestVisible
  @SuppressWarnings('PMD.EmptyStatementBlock')
  protected virtual void andFinally() {
  }

  // ─── Inner classes ────────────────────────────────────────────────────────────

  /** Tracks per-handler run counts and enforces an optional ceiling. */
  @TestVisible
  private class LoopCount {
    private Integer max;
    private Integer count;

    /** Initialises with a default ceiling of 5. */
    public LoopCount() {
      this.max = 5;
      this.count = 0;
    }

    /**
     * @param max Maximum allowed runs.
     */
    public LoopCount(Integer max) {
      this.max = max;
      this.count = 0;
    }

    /**
     * Increments the counter and returns whether the ceiling has been breached.
     * @return `Boolean`
     */
    public Boolean increment() {
      this.count++;
      return this.exceeded();
    }

    /**
     * @return `Boolean` true when count exceeds max (max < 0 means unlimited).
     */
    public Boolean exceeded() {
      if (this.max < 0) {
        return false;
      }
      return this.count > this.max;
    }

    /** @return `Integer` configured maximum. */
    public Integer getMax() {
      return this.max;
    }

    /** @return `Integer` current run count. */
    public Integer getCount() {
      return this.count;
    }

    /** @param max New ceiling value. */
    public void setMax(Integer max) {
      this.max = max;
    }
  }

  /** Enumerates all valid trigger event contexts. */
  @TestVisible
  public enum TriggerContext {
    BEFORE_INSERT,
    BEFORE_UPDATE,
    BEFORE_DELETE,
    AFTER_INSERT,
    AFTER_UPDATE,
    AFTER_DELETE,
    AFTER_UNDELETE
  }
}
