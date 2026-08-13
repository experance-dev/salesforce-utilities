# LWC Patterns

This file governs component-level implementation patterns for Lightning Web Components — wire-adapter lifecycle, multi-context reactivity, and permission-gating idioms inside a component's JavaScript controller. It complements [../best-practices/lwc.md](../best-practices/lwc.md), which covers naming, file structure, and the broad conventions every component follows; this file goes one level deeper into three patterns that recur in production components and are easy to get subtly wrong in code review. Read it if you're writing or reviewing an LWC that wires Apex data, renders against more than one record context, or gates its own visibility behind a custom permission.

## 1. Wire-getter pattern: the template never reads `data` / `error` directly

**Rule.** Capture every `@wire` result in a private property (`wiredFoo`), and expose the template's read surface through getters — `get foo()`, `get error()`, `get isLoading()` — that unpack that property. The template binds only to the getters. When a write needs to refresh the view, call `refreshApex(this.wiredFoo)`; never re-invoke the imperative version of the same Apex method just to force a re-render.

**Why.** The `{ data, error }` shape returned by `@wire` is an implementation detail of the wire service, not a contract you want your markup coupled to. Binding a template directly to `wiredFoo.data` means every consumer of that property has to know the wire's internal shape, and it means `refreshApex` — which requires the *original* wired object, not a derived value — has nothing stable to target once you start reassigning or destructuring it. The getter layer also gives you one place to compute `isLoading` correctly: a wire that hasn't replied yet has `data === undefined` and `error === undefined` simultaneously, which is not the same state as "loaded, zero rows."

```js
import { LightningElement, wire } from "lwc";
import { refreshApex } from "@salesforce/apex";
import getInvoices from "@salesforce/apex/InvoicePanelController.getInvoices";

export default class RelatedInvoicesPanel extends LightningElement {
  wiredInvoices;

  @wire(getInvoices, { accountId: "$recordId" })
  wiredGetInvoices(result) {
    this.wiredInvoices = result;
  }

  get invoices() {
    return this.wiredInvoices?.data ?? [];
  }

  get error() {
    return this.wiredInvoices?.error;
  }

  get isLoading() {
    const w = this.wiredInvoices;
    return !!w && w.data === undefined && w.error === undefined;
  }

  async refresh() {
    if (this.wiredInvoices) {
      await refreshApex(this.wiredInvoices);
    }
  }
}
```

The template reads `invoices`, `error`, and `isLoading` — it never touches `wiredInvoices` itself.

## 2. Multi-context components: one `@wire` per context, gated by a reactive null-out

**Rule.** When a component can render against more than one SObject context (for example, the same panel mounted on both an Account and an Opportunity record page), declare **one `@wire` per context**, each parameterized by a reactive getter (`$xIdParam`) that resolves to `undefined` whenever that context isn't the active one. Do not try to collapse this into a single wire with a dynamically-swapped Apex method reference — `@wire` method references are static.

**Why.** The Lightning Data Service wire adapter short-circuits — it does not call the underlying Apex method at all — only when a reactive parameter resolves to `undefined`. `null` is a value like any other to LDS: a parameter gated with `null` still fires the wire, calling the Apex method with a `null` argument instead of skipping it. Gating on `undefined` means both wires can be declared unconditionally and only the active one ever fires, which preserves `cacheable=true` LDS caching for whichever context is live: switching contexts on a subsequent render re-uses the cache instead of forcing a fresh round-trip. A single dynamically-reassigned wire loses that caching entirely, because you're either re-wiring on every context change or routing through an imperative call that LDS can't cache the same way.

```js
const CONTEXT_ACCOUNT = "Account";
const CONTEXT_OPPORTUNITY = "Opportunity";

export default class RelatedInvoicesPanel extends LightningElement {
  @api recordId;
  @api recordContext = CONTEXT_OPPORTUNITY;

  wiredOppResult;
  wiredAccountResult;

  // The non-active scope's param resolves to undefined so its wire short-circuits.
  // (a null default would still fire the wire with a null argument — see the Why note above.)
  get opportunityIdParam() {
    return this.recordContext === CONTEXT_OPPORTUNITY ? this.recordId : undefined;
  }

  get accountIdParam() {
    return this.recordContext === CONTEXT_ACCOUNT ? this.recordId : undefined;
  }

  @wire(getInvoicesForOpportunity, { opportunityId: "$opportunityIdParam" })
  wiredOpportunity(result) {
    this.wiredOppResult = result;
  }

  @wire(getInvoicesForAccount, { accountId: "$accountIdParam" })
  wiredAccount(result) {
    this.wiredAccountResult = result;
  }

  get activeWire() {
    return this.recordContext === CONTEXT_OPPORTUNITY
      ? this.wiredOppResult
      : this.wiredAccountResult;
  }
}
```

Route every template-facing getter (§1's `invoices` / `error` / `isLoading`) through `activeWire`, not through either wire directly — that keeps the context switch to a single point of truth.

## 3. Custom-permission checks: strict `=== true` tolerates the unmocked-import case

**Rule.** `@salesforce/customPermission/<name>` resolves to the boolean `true` when the running user holds the permission, and to `undefined` — not `false` — when they don't. Gate on it with a strict `foo === true` comparison, never a bare truthy check (`if (foo)`) and never `foo !== false`.

**Why.** `undefined` is also what an unmocked `@salesforce/customPermission/*` import resolves to inside a Jest test that hasn't stubbed it. A bare truthy check (`if (!foo)`) happens to treat "not granted" and "not yet mocked" the same way today, but it does so by accident of both being falsy — it doesn't distinguish "explicitly denied" from "value we don't understand." `=== true` makes the intent explicit: only a literal grant renders the gated UI, and any other resolved value — `undefined`, a stray string, a future API change — fails closed. Treat this as defense-in-depth, not the only gate: the permission should already control component visibility at the FlexiPage / App Builder level; this check exists for the case where the component is reachable somewhere that visibility rule doesn't reach (an Aura wrapper, a Flow screen, a unit test).

```js
import hasViewPerm from "@salesforce/customPermission/Invoice_Panel_View";

export default class RelatedInvoicesPanel extends LightningElement {
  get canViewPanel() {
    return hasViewPerm === true;
  }
}
```
