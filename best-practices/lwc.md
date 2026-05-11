# Lightning Web Components

> Most of this file is **proposed** — the seed guidelines didn't cover LWC beyond "use headless LWC actions for scheduling." Review and codify the items below before treating as canon.

## Canonical guidance from existing standards

- Use **headless LWC actions** for scheduling work from the UI tier (carried over from Apex guidelines).

---

## Proposed additions

### File and folder naming

- Folder: camelCase matching the component name (`myComponent/`).
- File: same camelCase, with the framework extensions (`myComponent.js`, `myComponent.html`, `myComponent.css`, `myComponent.js-meta.xml`).
- Markup tag: `c-my-component` (kebab-case with `c-` namespace prefix).

### Class and member naming

- Component class: PascalCase, extends `LightningElement`.
- Public reactive properties: `@api` decorator, camelCase.
- Private reactive state: `@track` only when mutating object/array internals; otherwise prefer reassignment.
- Event names: lowercase, no `on` prefix on the dispatch side — `this.dispatchEvent(new CustomEvent('selected'))`; consumers use `onselected`.

### Wire adapters

- Always wrap the wire response in a getter for the template, so the template never reads `data` / `error` directly:

```js
@wire(getRecords, { accountId: '$recordId' })
wiredRecords;

get records() { return this.wiredRecords?.data ?? []; }
get error() { return this.wiredRecords?.error; }
```

- Refresh with `refreshApex(this.wiredRecords)` after a write — don't re-call the imperative version.

### Apex from LWC

- Reads: `@AuraEnabled(cacheable=true)`. Writes: `@AuraEnabled` (no cache).
- Always handle the promise rejection. Never `catch` and swallow — surface the error to the user.

### Errors and toasts

- User-facing errors via `lightning/platformShowToastEvent` with a user-friendly message. Never display raw exception text.
- Log technical detail via [`Logger`](../utilities/logging/Logger.cls) on the Apex side; the LWC user-facing message is short and actionable.

### Platform events

- Subscribe with the `lightning/empApi` module. Never roll a custom long-polling client.
- Unsubscribe in `disconnectedCallback`.

### Custom labels

- All user-visible strings come from Custom Labels imported via `@salesforce/label/c.<labelName>`. No hardcoded strings in templates or JS.

### Accessibility

- Every interactive element gets a label (`aria-label`, `<label for>`, or visible text).
- Use SLDS utility classes for layout — don't reimplement spacing/typography.

### Testing

- Jest tests for every component. Co-located in `__tests__/` under the component folder.
- Use the `@salesforce/sfdx-lwc-jest` setup. Mock Apex imports with `jest.mock('@salesforce/apex/...')`.
- Test rendering, events emitted, and error states — not implementation details.

### Performance

- Avoid expensive work in getters — getters run on every render.
- Use `lightning-record-form` / `lightning-record-edit-form` for CRUD on a single object before reaching for custom forms.
- Lazy-load heavy components via dynamic imports (`import('c/heavy')`) when they're conditional.
