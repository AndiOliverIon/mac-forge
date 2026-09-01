# Angular Review Guidelines — Core

Always loaded for Angular / TypeScript / frontend work in **review mode**. This file carries every rule
that can apply regardless of what the diff touches, plus the index of topic files.

Section numbers are the original ones and are deliberately non-contiguous. A gap means that section
lives in a topic file — see the table below. Nothing was renumbered, so existing references such as
"§8 Forms" still resolve.

Rule intent in this detailed review set must remain synchronized with the compact development rules in
`../angular-development.md`, except for rules explicitly labeled as mode-specific.

## Topic Files

Enumerate the changed files first. Build the selection corpus from all of the following: every changed
path, the complete diff (including removed lines and deleted files), and the complete current contents
of every changed file that still exists. For a review without a diff, treat every file in the explicit
review scope as changed and read its complete contents for selection.

Load every topic file whose trigger appears anywhere in that corpus. Selection is mechanical — match
on file extension and on the literal tokens listed. Do not decide by judgment what a change is "about";
that is how a rule goes missing. Topic paths are relative to
`~/.config/ai/guidelines/stacks/angular-review/`.

| File | § | Load when the selection corpus contains |
| ---- | - | ---------------------------------------- |
| `rxjs.md` | 4 | `rxjs`, `Observable`, `Subject`, `BehaviorSubject`, `.pipe(`, `.subscribe(`, `switchMap`, `concatMap`, `mergeMap`, `exhaustMap`, `catchError`, `toSignal`, `toObservable`, `takeUntilDestroyed`, `firstValueFrom`, `Promise`, `async`/`await`, `valueChanges` |
| `forms.md` | 8 | `@angular/forms`, `<form`, `ngSubmit`, `form.`, `formControl`, `formGroup`, `.valid`, `.invalid`, `.errors`, `required`, `AbstractControl`, `FormGroup`, `FormControl`, `FormArray`, `FormBuilder`, `NonNullableFormBuilder`, `Validators`, `ValidatorFn`, `AsyncValidatorFn`, `ControlValueAccessor`, `NG_VALUE_ACCESSOR`, `ReactiveFormsModule`, `getRawValue`, `FormsModule`, `ngModel`, `valueChanges` |
| `routing.md` | 11 | `*.routes.ts`, `@angular/router`, `Routes`, `Router`, `RouterModule`, `provideRouter`, `ActivatedRoute`, `RouterLink`, `RouterOutlet`, `ResolveFn`, `CanActivate`, `CanMatch`, `withComponentInputBinding`, `paramMap`, `queryParams`, `toObservable` |
| `ui-kendo.md` | 12 | any `.html` path; `kendo-`, `kendoButton`, `KENDO_`, `@progress/kendo-`, `@ardis/ngx-kendo-ui`, `DialogService`, `DialogRef`, `DialogContentBase`, `.k-`, `::ng-deep`, `!important`, `<table`, `<select`, `<input`, `<textarea`, `<button`, `<a `, `<form`, `<label` |
| `templates-styling.md` | 16 | any `.html`, `.scss`, `.sass`, `.less` or `.css` path; or in a `.ts`: `templateUrl`, `styleUrl`, `template:`, `styles:`; or `style="` / `class="` in a template |

Selection rules:

* **This table is the only authority for topic selection.** Topic files must not duplicate trigger
  lists or redefine how they are selected.
* **Triggers include banned tokens, not only approved ones.** A change that introduces `ngModel` contains
  no reactive-forms token, yet the ban must still fire. Each trigger list therefore carries the
  identifiers its section *prohibits* as well as the ones it endorses.
* **If the selection corpus cannot be built completely, load all topic files.** Missing context must
  increase guideline coverage, never reduce it.
* **Default to loading when unsure.** An unneeded topic file costs seconds; a missing one costs the review.
* **If you reach a finding in an area whose topic file you have not loaded, stop and load it before
  writing findings.**
* **Section 20 (*What to Avoid*) stays here as a broad baseline.** It summarizes common prohibitions,
  but it does not replace the topic files or restate every detailed topic rule.
* Each rule has exactly one detailed home. Do not copy rule text between files.

---

## 1. General Principles

* Follow the [Angular Style Guide](https://angular.dev/style-guide) as the baseline for all conventions.
* Prefer **explicit, readable code** over clever one-liners.
* Keep components and services **single-responsibility**.
* All new code must be written in **strict TypeScript** — no `any`, no implicit types.
* **Always use explicit access modifiers** (`public`, `protected`, `private`) on all class members.
* **Always use explicit type annotations** on all properties, parameters, and return types.
* Use **standalone components** by default. NgModules should only be used when integrating legacy code or third-party libraries that require them.
* **No `console.log` in committed code.** Debug statements must be removed before merging. Use a proper logging service for any runtime diagnostics that genuinely need to persist.

---

## 2. Angular Version & Features

Target: **Angular 19+**

### Use Modern Angular APIs

```typescript
// ✅ Standalone component (default)
@Component({
    selector: 'app-user-card',
    standalone: true,
    imports: [CommonModule, UserAvatarComponent],
    templateUrl: './user-card.component.html',
})
export class UserCardComponent {}
```

### Control Flow — Use the New Syntax

Always use `@if`, `@for`, `@switch` instead of `*ngIf`, `*ngFor`, `*ngSwitch`.

```html
<!-- ✅ Modern control flow -->
@if (user()) {
<app-user-card [user]="user()" />
} @else {
<p>No user found.</p>
} @for (item of items(); track item.id) {
<li>{{ item.name }}</li>
}
```

```html
<!-- ❌ Legacy structural directives — do not use for new code -->
<div *ngIf="user">...</div>
<li *ngFor="let item of items">...</li>
```

### Dependency Injection

Use `inject()` instead of constructor injection.

```typescript
// ✅
export class UserService {
  private readonly router: Router = inject(Router);
  private readonly activatedRoute: ActivatedRoute = inject(ActivatedRoute);
}

// ❌ Avoid
constructor(private http: HttpClient, private router: Router) {}
```

---

## 3. Signals & Reactivity

**Signals are the preferred reactivity primitive.** Use them for all local and shared component state.

### Basic Signal Usage

```typescript
import { signal, computed, effect, linkedSignal } from '@angular/core';

export type ShippingOption = 'Standard' | 'Express' | 'Overnight';

export class ProductComponent {
    // Current product and its shipping options
    public product: WritableSignal<string> = signal('A');
    public availableShipping: WritableSignal<ShippingOption[]> = signal<ShippingOption[]>(['Standard', 'Express', 'Overnight']);

    public quantity: WritableSignal<number> = signal(1);
    public price: WritableSignal<number> = signal(50);
    public total: Signal<number> = computed(() => this.quantity() * this.price());

    // Default shipping cost: 5% of total
    public defaultShippingCost: WritableSignal<number> = linkedSignal(() => this.total() * 0.05);

    // Shipping option: keeps previous selection if still available, otherwise defaults
    public shippingOption: WritableSignal<ShippingOption> = linkedSignal({
        source: this.availableShipping,
        compute: (available: ShippingOption[], prev?: ShippingOption): ShippingOption => (prev && available.includes(prev) ? prev : available[0]),
    });

    constructor() {
        effect(() => console.log('Total:', this.total()));
        effect(() => console.log('Default shipping cost:', this.defaultShippingCost()));
        effect(() => console.log('Selected shipping option:', this.shippingOption()));
    }

    public incrementQuantity(): void {
        this.quantity.update((q: number) => q + 1);
    }

    public chooseShipping(option: ShippingOption): void {
        this.shippingOption.set(option); // user selects shipping
    }

    public switchProduct(productId: string, shippingOptions: ShippingOption[]): void {
        this.product.set(productId);
        this.availableShipping.set(shippingOptions);
        // shippingOption automatically updates via linkedSignal logic
    }
}
```

### Signal Inputs & Outputs (Angular 17.1+)

```typescript
// ✅ Use signal-based inputs
export class UserCardComponent {
    public user: InputSignal<User> = input.required<User>();
    public size: InputSignal<'sm' | 'md' | 'lg'> = input<'sm' | 'md' | 'lg'>('md');

    // Signal-based output
    public selected: OutputEmitterRef<User> = output<User>();

    public select(): void {
        this.selected.emit(this.user());
    }
}
```

### `toSignal` — Bridging Observables to Signals

When you need to consume an Observable in the template or computed values, convert it with `toSignal`.

```typescript
import { toSignal } from '@angular/core/rxjs-interop';

export class DashboardComponent {
    private readonly userService: UserService = inject(UserService);

    public users: Signal<User[]> = toSignal(this.userService.getUsers(), { initialValue: [] });
}
```

### Signals for Mutable State Only

Use signals only for values that **change at runtime**. Static or constant values — configuration, lookup tables, labels, fixed options — should be plain `readonly` properties or `const` variables. Wrapping them in signals adds reactive overhead with no benefit and misleads readers into expecting change.

```typescript
// ✅ Signal — value changes at runtime
protected selectedTab: WritableSignal<string> = signal('overview');
protected isLoading: WritableSignal<boolean> = signal(false);

// ✅ Plain readonly — value never changes
protected readonly tabs: string[] = ['overview', 'details', 'history'];
protected readonly maxPageSize: number = 100;
protected readonly statusLabels: Record<string, string> = {
    active: 'Active',
    inactive: 'Inactive',
};

// ❌ Signal wrapping a static value — unnecessary
protected readonly tabs: Signal<string[]> = signal(['overview', 'details', 'history']);
protected readonly maxPageSize: Signal<number> = signal(100);
```

### No Backend Calls in computed() or effect()

**Never trigger HTTP calls or backend requests inside `computed()` or `effect()` blocks.** Computed signals are re-evaluated eagerly whenever their dependencies change — placing API calls inside them causes uncontrolled, repeated requests and creates serious performance penalties. The same applies to `effect()`: it is meant for synchronous side effects (DOM updates, logging), not async I/O.

Use `toSignal()` with a proper observable pipeline instead.

```typescript
// ❌ Backend call inside computed — triggers on every dependency change
protected invoice: Signal<Invoice | undefined> = computed(() => {
    const id = this.selectedId();
    return this.invoiceService.getById(id); // ❌ This returns an Observable, not a value
                                             //    and triggers a new HTTP call on every recompute
});

// ❌ Backend call inside effect — uncontrolled side effects
constructor() {
    effect(() => {
        this.invoiceService.getById(this.selectedId()).subscribe(...); // ❌
    });
}

// ✅ Use toSignal() with an observable pipeline
protected invoice: Signal<Invoice | undefined> = toSignal(
    toObservable(this.selectedId).pipe(
        switchMap((id: string) => this.invoiceService.getById(id))
    )
);
```

### Rules

* ✅ Use `signal()` for mutable local state.
* ✅ Use `computed()` for derived values — never recalculate manually.
* ✅ Use `linkedSignal()` when you need to derive writable state that stays in sync with another signal.
* ✅ Use `effect()` for side effects that react to signal changes.
* ✅ Use `toSignal()` to bridge Observables into the signal world.
* ✅ Use plain `readonly` properties or `const` for static, never-changing values — not signals.
* ❌ Do not use `BehaviorSubject` for component-local state — use `signal()` instead.
* ❌ Do not wrap static/constant values in `signal()` — reserve signals for values that actually change.
* ❌ Never trigger HTTP or backend calls inside `computed()` or `effect()` — use `toSignal()` with an observable pipeline instead.

---

## 5. State Management

Use **services with signals** as the primary state management pattern. Do not introduce NgRx or other external state libraries unless complexity clearly demands it.

### Service with Signals Pattern

```typescript
@Injectable({ providedIn: 'root' })
export class CartService {
    // Private writable signals
    private readonly _items: WritableSignal<CartItem[]> = signal<CartItem[]>([]);

    // Public read-only signals
    public readonly items: Signal<CartItem[]> = this._items.asReadonly();
    public readonly count: Signal<number> = computed(() => this._items().length);
    public readonly total: Signal<number> = computed(() => this._items().reduce((sum: number, item: CartItem) => sum + item.price * item.qty, 0));

    public addItem(item: CartItem): void {
        this._items.update((items: CartItem[]) => [...items, item]);
    }

    public removeItem(id: string): void {
        this._items.update((items: CartItem[]) => items.filter((i: CartItem) => i.id !== id));
    }
}
```

### Consuming State in Components

```typescript
export class CartComponent {
    private readonly cartService: CartService = inject(CartService);

    protected readonly items: Signal<CartItem[]> = this.cartService.items;
    protected readonly total: Signal<number> = this.cartService.total;
}
```

```html
<p>{{ total() | currency }}</p>

@for (item of items(); track item.id) {
  <app-cart-item [item]="item" />
}
```

---

## 6. Components

### Anatomy of a Component

```typescript
@Component({
    selector: 'app-invoice-list',
    standalone: true,
    imports: [CurrencyPipe, InvoiceRowComponent, KendoGridModule],
    templateUrl: './invoice-list.component.html',
    styleUrl: './invoice-list.component.scss',
})
export class InvoiceListComponent {
    // 1. Injected dependencies
    private readonly invoiceService: InvoiceService = inject(InvoiceService);

    // 2. Inputs / Outputs
    public filter: InputSignal<InvoiceFilter> = input<InvoiceFilter>();
    public invoiceSelected: OutputEmitterRef<Invoice> = output<Invoice>();

    // 3. Local state
    protected selectedId: WritableSignal<string | null> = signal<string | null>(null);

    // 4. Derived / computed
    protected invoices: Signal<Invoice[]> = toSignal(this.invoiceService.getAll(), { initialValue: [] });
    protected filtered: Signal<Invoice[]> = computed(() => this.invoices().filter((i: Invoice) => i.status === this.filter()?.status));
}
```

### Rules

* ✅ Use `input()` / `output()` signal-based APIs, not `@Input()` / `@Output()`.
* ✅ Keep templates lean — move logic to the component class or services.
* ❌ No business logic in templates.
* ❌ No direct DOM manipulation — use Angular renderer or reactive patterns.

---

## 7. Component Size & Responsibility

**Components should be small, focused, and single-responsibility.** A component that tries to do too much — render a list, manage selection state, handle pagination, open dialogs, and format data — is harder to test, reuse, and maintain. Decompose early.

### Single Responsibility

Each component should have **one primary reason to exist**. Ask: *"What is the one thing this component does?"* If the answer contains "and", it should likely be split.

```
// ❌ One component doing too much
InvoicePageComponent
  ├── Fetches invoices from service
  ├── Manages filter form state
  ├── Handles row selection
  ├── Opens create/edit dialog
  ├── Renders the data grid
  ├── Renders filter toolbar
  └── Formats currency and dates inline

// ✅ Decomposed by responsibility
InvoicePageComponent          — page shell, composes children
InvoiceFilterComponent        — filter form state and UI
InvoiceGridComponent          — grid rendering and row selection
InvoiceEditDialogComponent    — create/edit form inside a dialog
```

### Component Size Guidelines

There are no hard line-count limits, but treat these as signals to decompose:

* A component class exceeding **~200 lines** likely has more than one responsibility.
* A template exceeding **~100 lines** likely contains UI that belongs in a child component.
* More than **~5 injected dependencies** in one component suggests too much orchestration.
* Methods that only exist to support an isolated section of the template are candidates for extraction into a child component.

### Method Size

Public and protected methods should be short and focused. A method that requires scrolling to read is doing too much.

* **Aim for ~5–20 lines** per method. A method body that fits on one screen is readable at a glance.
* If a method has more than one level of indented logic, extract private helpers.
* Use **guard clauses and early returns** to avoid deep nesting — don't wrap the happy path in `if` blocks.
* A method name should describe its full intent. If you can't name it without using "and", split it.

```typescript
// ❌ Long method doing multiple things
public loadAndFilterAndSort(): void {
    this.invoiceService.getAll().subscribe((invoices: Invoice[]) => {
        const filtered = invoices.filter((i: Invoice) => {
            if (i.status === 'active') {
                if (i.amount > 0) {
                    return true;
                }
            }
            return false;
        });
        const sorted = filtered.sort((a: Invoice, b: Invoice) => {
            return a.dueDate < b.dueDate ? -1 : 1;
        });
        this.invoices.set(sorted);
    });
}

// ✅ Each method does one thing
private readonly invoices$: Observable<Invoice[]> = this.invoiceService.getAll();

protected readonly invoices: Signal<Invoice[]> = toSignal(
    this.invoices$.pipe(map((items: Invoice[]) => this.sortByDueDate(this.filterActive(items)))),
    { initialValue: [] }
);

private filterActive(invoices: Invoice[]): Invoice[] {
    return invoices.filter((i: Invoice) => i.status === 'active' && i.amount > 0);
}

private sortByDueDate(invoices: Invoice[]): Invoice[] {
    return [...invoices].sort((a: Invoice, b: Invoice) => (a.dueDate < b.dueDate ? -1 : 1));
}
```

### SOLID Action Methods

**Action methods must be single-responsibility.** Each method should perform one action, call one endpoint, and handle one response. Do not mix unrelated mutations — for example, saving a record and simultaneously refreshing an unrelated list — inside the same method.

If a user action genuinely requires multiple sequential operations, chain them explicitly in the observable pipeline so intent and error handling remain clear.

```typescript
// ❌ Mixed concerns in one action method
public saveAndRefresh(): void {
    this.invoiceService.save(this.invoice()).subscribe({
        next: () => {
            this.loadInvoices();       // ❌ mixing save + list refresh + notification
            this.loadCustomers();      // ❌ unrelated side effect
            this.notify('Saved');
        },
        error: (err: HttpErrorResponse) => this.notificationService.showError('Save failed', err),
    });
}

// ✅ One action, one endpoint, one response
public save(): void {
    this.invoiceService.save(this.invoice()).subscribe({
        next: (saved: Invoice) => this.onSaveSuccess(saved),
        error: (err: HttpErrorResponse) => this.notificationService.showError('Save failed', err),
    });
}

private onSaveSuccess(saved: Invoice): void {
    this.invoices.update((list: Invoice[]) => [...list, saved]);
    this.notificationService.showSuccess('Invoice saved');
}
```

### Decomposition Patterns

**Extract presentation sub-components** when a section of the template:
- Has its own visual boundary or layout concern
- Could be reused elsewhere
- Contains enough elements that it obscures the parent template's intent

**Extract container/smart components** when:
- A child needs to fetch its own data or manage non-trivial local state
- Multiple siblings share state that currently lives in a parent that doesn't otherwise need it

```typescript
// ✅ Parent delegates rendering to focused children
// invoice-page.component.html
<invoice-filter [filter]="filter()" (filterChange)="filter.set($event)" />
<invoice-grid [invoices]="invoices()" (invoiceSelect)="openEditDialog($event)" />
```

### Rules

* ✅ Each component has a single, clearly stateable responsibility.
* ✅ Decompose large components into smaller, focused child components.
* ✅ Keep component classes to ~200 lines or fewer — split when they grow beyond this.
* ✅ Keep templates to ~100 lines or fewer — extract child components when templates grow.
* ✅ Keep public/protected methods to ~5–20 lines — extract private helpers when they grow.
* ✅ Use guard clauses and early returns to keep methods flat — avoid deep nesting.
* ✅ **Action methods must be single-responsibility** — one action, one endpoint, one response.
* ✅ Use `input()` / `output()` signal-based APIs, not `@Input()` / `@Output()`.
* ✅ Keep templates lean — move logic to the component class or services.
* ❌ No business logic in templates.
* ❌ No direct DOM manipulation — use Angular renderer or reactive patterns.
* ❌ Do not put orchestration, data fetching, UI rendering, and dialog management all in one component.
* ❌ Do not mix unrelated mutations or side effects inside a single action method.

---

## 9. Services

```typescript
// ✅ Provided in root by default unless feature-scoped
@Injectable({ providedIn: 'root' })
export class UserService {
    private readonly http: HttpClient = inject(HttpClient);
    private readonly baseUrl: string = '/api/users';

    public getAll(): Observable<User[]> {
        return this.http.get<User[]>(this.baseUrl);
    }

    public getById(id: string): Observable<User> {
        return this.http.get<User>(`${this.baseUrl}/${id}`);
    }

    public save(user: User): Observable<User> {
        return user.id ? this.http.put<User>(`${this.baseUrl}/${user.id}`, user) : this.http.post<User>(this.baseUrl, user);
    }
}
```

* Services must not contain UI logic or reference DOM APIs.
* Services that hold shared state should expose signals as `readonly`.
* Feature-specific services should be provided at the route or component level, not globally.

---

## 10. Backend Communication — Generated API Clients

**All backend communication must use the generated TypeScript client** produced from the backend's Swagger/OpenAPI specification. Do not hand-roll `HttpClient` calls, do not manually define request/response interfaces that already exist in the generated client.

The generated client is the single source of truth for API contracts. Writing your own models or HTTP wrappers alongside it creates drift, duplication, and type mismatches when the API changes.

### Why

* The generated client is always in sync with the backend contract.
* Models, enums, and request/response shapes are typed automatically.
* Endpoint URLs, HTTP verbs, and parameter serialisation are handled for you.
* A change in the backend schema is caught immediately at compile time.

### Usage

```typescript
// ✅ Use the generated client and its models
import { InvoicesClient, InvoiceForCreate, Invoice } from '@generated/api';

@Injectable({ providedIn: 'root' })
export class InvoiceService {
    private readonly invoicesClient: InvoicesClient = inject(InvoicesClient);

    public getAll(): Observable<Invoice[]> {
        return this.invoicesClient.getAll();
    }

    public create(request: InvoiceForCreate): Observable<Invoice> {
        return this.invoicesClient.create(request);
    }
}

// ❌ Manual HttpClient call — do not do this
@Injectable({ providedIn: 'root' })
export class InvoiceService {
    private readonly http: HttpClient = inject(HttpClient);

    public getAll(): Observable<Invoice[]> {
        return this.http.get<Invoice[]>('/api/v1/invoices'); // ❌ bypasses the generated client
    }
}

// ❌ Manually defined model that mirrors a generated type — do not do this
interface Invoice {        // ❌ already exists in the generated client
    id: number;
    reference: string;
    amount: number;
}
```

### Rules

* ✅ **Always import models and clients from the generated API package.**
* ✅ Use the generated client as a dependency in Angular services — wrap it if you need to add caching, retry logic, or signal conversion.
* ✅ When the backend changes, regenerate the client and fix compile errors — do not patch manually.
* ❌ Do not write manual `HttpClient` calls for endpoints covered by the generated client.
* ❌ Do not duplicate or redefine models that already exist in the generated client.
* ❌ Do not cast responses to hand-written interfaces — use the generated types directly.

> **Warning:** If you find yourself writing `this.http.get<SomeType>('/api/...')` or defining a new interface that looks like a backend DTO, stop and check whether the generated client already covers this. If it does not, regenerate the client from the latest Swagger spec before proceeding.

---

## 13. UX — Action Button Behaviour

**Prefer disabling buttons over hiding them.** Show/hide behaviour causes layout shifts and structural reflows that degrade the user experience. Buttons should remain visible and stable in the UI — their enabled/disabled state communicates availability without moving other content around.

### Application-Level Restrictions → Disable the Button

When a restriction is determined entirely by the application state — for example, a selection count, a required precondition, or a UI-level rule — disable the button upfront. No API call is needed to determine the disabled state; it is derived from local state.

```typescript
// ✅ Disable based on application state (selection count)
protected readonly canDelete: Signal<boolean> = computed(
    () => this.selectedIds().length === 1
);
```

```html
<!-- ✅ Button is always visible; disabled when selection is invalid -->
<button
    kendoButton
    themeColor="error"
    [disabled]="!canDelete()"
    (click)="deleteSelected()"
>
    Delete
</button>

<!-- ❌ Button appears and disappears — causes layout shift -->
@if (canDelete()) {
    <button kendoButton themeColor="error" (click)="deleteSelected()">Delete</button>
}
```

### Business-Level Restrictions → Enable the Button, Validate on Click

When a restriction depends on business rules, server-side state, or data that requires an API call to evaluate — enable the button and perform the validation at action time. The user should be able to attempt the action; feedback is returned from the server if it is not permitted.

```typescript
// ✅ Button is always enabled; validation happens on click via the API
public submitOrder(): void {
    this.orderClient.submit(this.orderId()).subscribe({
        next: () => this.notificationService.showSuccess('Order submitted'),
        error: (err: HttpErrorResponse) => this.notificationService.showError('Submission failed', err),
    });
}
```

```html
<!-- ✅ Always enabled — business validation fires on click -->
<button
    kendoButton
    themeColor="primary"
    (click)="submitOrder()"
>
    Submit Order
</button>
```

### Summary

| Restriction type | Source of truth | Button state |
| ---------------------------------- | ------------------------- | --------------------- |
| Application rule (selection, form) | Local signal / form state | Disabled when invalid |
| Business rule (server state, workflow) | API response | Always enabled; validate on click |

### Rules

* ✅ **Disable buttons** when the restriction is known from local/application state.
* ✅ **Keep buttons enabled** when the restriction requires a server call — validate on click.
* ✅ Derive disabled state from signals or computed values, not show/hide logic.
* ❌ Do not hide/show buttons based on business rules — use disabled state instead.
* ❌ Do not pre-validate business rules with an extra API call just to set button state.

---

## 14. Shared Helper Functions

**Helper functions and utilities must be shared, not duplicated per component.** If a method does not depend on component-specific state — for example, a translation helper, a date formatter, a label resolver — it does not belong on the component class. Place it in a shared service, a utility function, or a pipe so it can be reused consistently across the application.

A helper that appears in more than one component is a signal that it should already be shared.

```typescript
// ❌ Translation helper defined on the component — cannot be reused
export class InvoiceListComponent {
    protected getStatusLabel(status: InvoiceStatus): string {
        const labels: Record<InvoiceStatus, string> = {
            draft: 'Draft',
            sent: 'Sent',
            paid: 'Paid',
            overdue: 'Overdue',
        };
        return labels[status] ?? status;
    }
}

// ✅ Shared via a service — available to any component that needs it
@Injectable({ providedIn: 'root' })
export class InvoiceLabelService {
    public getStatusLabel(status: InvoiceStatus): string {
        const labels: Record<InvoiceStatus, string> = {
            draft: 'Draft',
            sent: 'Sent',
            paid: 'Paid',
            overdue: 'Overdue',
        };
        return labels[status] ?? status;
    }
}

// ✅ Or as a pure pipe for template use
@Pipe({ name: 'invoiceStatus', standalone: true, pure: true })
export class InvoiceStatusPipe implements PipeTransform {
    public transform(status: InvoiceStatus): string {
        const labels: Record<InvoiceStatus, string> = {
            draft: 'Draft',
            sent: 'Sent',
            paid: 'Paid',
            overdue: 'Overdue',
        };
        return labels[status] ?? status;
    }
}
```

### Rules

* ✅ Move translation, formatting, and label-resolution helpers to a shared service or pipe.
* ✅ Use `pure: true` pipes for stateless template transformations.
* ✅ Place utility functions that do not depend on Angular DI in a standalone `*.utils.ts` file.
* ❌ Do not define helper methods on a component class when the logic is not component-specific.
* ❌ Do not duplicate the same helper across multiple components — extract and share it.

---

## 15. Defensive Coding — Avoid Overkill Validations

**Keep defensive checks proportional to the actual risk.** Over-validating simple, well-typed values adds noise, obscures intent, and suggests distrust of the type system. Use straightforward fallbacks instead of dedicated validation methods for trivial cases.

### Array Fallbacks

Do not write a private validation method to check whether an array of IDs contains only positive integers. The type system already enforces `number[]`. A simple `|| []` fallback is sufficient to guard against `null` or `undefined` inputs.

```typescript
// ❌ Overkill — a private method to validate array contents
private validateIds(ids: number[]): number[] {
    if (!ids || !Array.isArray(ids)) return [];
    return ids.filter((id: number) => Number.isInteger(id) && id > 0);
}

public deleteSelected(): void {
    const ids: number[] = this.validateIds(this.selectedIds());
    // ...
}

// ✅ Simple fallback — trust the type, guard only against empty
public deleteSelected(): void {
    const ids: number[] = this.selectedIds() || [];
    if (!ids.length) return;
    // ...
}
```

### When Validation Is Appropriate

Defensive validation makes sense when:
- The input comes from an **untrusted external source** (user input, API response with a loose schema).
- The domain genuinely has **business constraints** that the type system cannot express (e.g. a value must be within a specific range for a business reason).
- You are writing a **shared utility or service** consumed by multiple callers with different guarantees.

For typed, internal data flow within a component or service, trust the types and keep guards minimal.

### Rules

* ✅ Use `|| []` (or `?? []`) as a simple fallback for potentially empty arrays.
* ✅ Use guard clauses (`if (!ids.length) return;`) to exit early on empty collections.
* ✅ Apply real validation at the boundary where data enters the system (forms, API responses).
* ❌ Do not create private validation methods to recheck types that TypeScript already enforces.
* ❌ Do not filter arrays of typed IDs for integer checks or positivity inside a component.

---

## 17. TypeScript Standards

### Access Modifiers & Type Annotations

**All class members MUST have explicit access modifiers and type annotations.**

```typescript
// ✅ Explicit access modifiers and types
export class UserComponent {
    private readonly userService: UserService = inject(UserService);
    public userName: InputSignal<string> = input.required<string>();
    protected userDetails: Signal<UserDetails | undefined> = signal(undefined);
}

// ❌ Missing access modifiers and type annotations
export class UserComponent {
    userService = inject(UserService);
    userName = input.required<string>();
    userDetails = signal(undefined);
}
```

**Access Modifier Guidelines:**

* Use `public` for members accessed in templates or by external components
* Use `protected` for members accessed only in templates (not external)
* Use `private` for internal implementation details
* Always use `readonly` for injected dependencies and signals that aren't reassigned

### Interface Naming

**Interfaces are named in PascalCase. All properties and fields inside an interface are named in camelCase.**

Do not prefix interface names with `I` — unlike the backend C# convention, TypeScript interfaces are not prefixed.

```typescript
// ✅ PascalCase interface name, camelCase properties
interface InvoiceFilter {
    customerId: number;
    statusCode: string;
    dateFrom: Date | null;
    dateTo: Date | null;
}

interface UserFormModel {
    firstName: string;
    lastName: string;
    emailAddress: string;
    isActive: boolean;
}

// ❌ Wrong — prefixed with I (C# style)
interface IInvoiceFilter { ... }

// ❌ Wrong — PascalCase properties
interface InvoiceFilter {
    CustomerId: number;
    StatusCode: string;
}

// ❌ Wrong — snake_case or mixed case properties
interface InvoiceFilter {
    customer_id: number;
    statuscode: string;
}
```

### Code Standards

```typescript
// ✅ Explicit return types on public methods
public getUser(id: string): Observable<User> { ... }

// ✅ Readonly interfaces for data models
interface User {
  readonly id: string;
  readonly email: string;
  name: string;
}

// ✅ Use type-safe enums or union types
type InvoiceStatus = 'draft' | 'sent' | 'paid' | 'overdue';

// ✅ Null handling
public getUserName(user: User | null): string {
  return user?.name ?? 'Unknown';
}

// ❌ Never use `any`
const data: any = response; // ❌

// ❌ Avoid non-null assertion operator unless absolutely necessary
const el: HTMLElement = document.getElementById('app')!; // ❌ — wrap in null check instead
```

### Rules

* ✅ **Always use explicit access modifiers** (`public`, `protected`, `private`) on all class members.
* ✅ **Always use explicit type annotations** on all properties, parameters, and return types.
* ✅ Use `readonly` for dependencies and values that should not be reassigned.
* ✅ Enable `strict: true` in `tsconfig.json`.
* ✅ All interfaces and types should live in a `.types.ts` or `.model.ts` file alongside the feature.
* ✅ **Interface names are PascalCase** — no `I` prefix (e.g. `InvoiceFilter`, not `IInvoiceFilter`).
* ✅ **Interface properties are camelCase** — never PascalCase or snake_case.
* ❌ Never use `any` — always provide explicit types.
* ❌ Avoid non-null assertion operator (`!`) unless absolutely necessary.
* ❌ Do not use the `I` prefix on TypeScript interfaces — that is a C# convention, not a TypeScript one.
* ❌ Do not use PascalCase or snake_case for interface properties.

---

## 18. Naming Conventions

|   Artifact   |        Convention         |          Example          |
| ------------ | ------------------------- | ------------------------- |
|  Component   | `kebab-case.component.ts` | `user-card.component.ts`  |
|   Service    |  `kebab-case.service.ts`  |   `invoice.service.ts`    |
| Types/Models |   `kebab-case.types.ts`   |    `invoice.types.ts`     |
|    Routes    |  `kebab-case.routes.ts`   |    `invoice.routes.ts`    |
|     Pipe     |   `kebab-case.pipe.ts`    | `currency-format.pipe.ts` |
|    Guard     |   `kebab-case.guard.ts`   |      `auth.guard.ts`      |
|  Directive   | `kebab-case.directive.ts` | `auto-focus.directive.ts` |
|  Interface (name)   | PascalCase, no `I` prefix | `InvoiceFilter`, `UserFormModel` |
|  Interface (properties) | camelCase | `customerId`, `isActive`, `dateFrom` |

---

## 19. Performance

* ✅ Use `trackBy` equivalent — always provide `track` in `@for` loops.
* ✅ Lazy-load all feature routes.
* ✅ Use `toSignal()` to avoid unnecessary re-renders from async pipes.
* ✅ Use Kendo Grid's virtual scrolling for large datasets.
* ❌ Avoid triggering change detection manually (`markForCheck`, `detectChanges`) unless integrating non-Angular code.
* ❌ Never trigger HTTP or backend calls inside `computed()` or `effect()` — use `toSignal()` with an observable pipeline.

---

## 20. What to Avoid

|                    ❌ Avoid                                   |                 ✅ Prefer Instead                              |
| ------------------------------------------------------------- | -------------------------------------------------------------- |
|           `Promise`/ `async-await`                            |                `Observable`/ RxJS                              |
|      `BehaviorSubject`for local state                         |                    `signal()`                                  |
|             `*ngIf`, `*ngFor`                                 |                  `@if`, `@for`                                 |
|   Template-driven forms (`ngModel`)                           |  Reactive forms (`FormGroup`/`FormControl`)                    |
|           Untyped `FormGroup`                                 |           Typed `FormGroup<{...}>`                             |
|    `@Input()`/ `@Output()` decorators                         |         `input()`/ `output()` functions                        |
|           Constructor injection                                |                   `inject()`                                   |
|         `NgModule`for new features                            |              Standalone components                             |
|        Custom data grids / pickers                            |         `@ardis/ngx-kendo-ui`equivalents                       |
|   Raw HTML elements when Kendo equivalents exist              |   Kendo/Ardis component equivalents                           |
|                 `any`type                                     |            Explicit types / generics                           |
|       Missing access modifiers/types                          |      `public`/`protected`/`private` + types                    |
|    Manual subscriptions without cleanup                       |       `toSignal()`/ `takeUntilDestroyed()`                     |
|    `.subscribe()` with positional callbacks or empty `error`  |    `{ next, error }` object syntax with real error handler     |
|     Hardcoded values (colors, spacing)                        |              Kendo theme variables                             |
|         Inline templates or styles                            |        Separate `.html` and `.scss` files                      |
|          Non-BEM CSS class names                              |              BEM naming convention                             |
|    `signal()` wrapping static/constant values                 |     Plain `readonly` property or `const`                       |
|     Backend calls inside `computed()` or `effect()`          |     `toSignal()` with observable pipeline                      |
|     Manual `HttpClient` calls / hand-rolled API models        |     Generated API client and its models                        |
|     Components with multiple responsibilities                 |  Decompose into focused single-purpose components              |
|     Methods longer than ~20 lines                             |   Extract private helpers; guard-clause early exit             |
|     Large component classes (200+ lines)                      |       Split by responsibility into smaller units               |
|     Large templates (100+ lines)                              |        Extract sections into child components                  |
|     Nested `.subscribe()` calls                               |    Flatten with `switchMap` / `concatMap` etc.                 |
|     Nested `.pipe()` calls                                    |    Extract inner logic to a private method                     |
|     `switchMap` for everything                                |    Match operator to concurrency intent                        |
|     Mixed concerns in a single action method                  |    One action, one endpoint, one response                      |
|     Component-specific helper/translation methods             |    Shared service, utility, or pipe                            |
|     Overkill array validation in private methods              |    Simple `\|\| []` fallback; trust the type system             |
|     Show/hide buttons based on business rules                 |    Disabled state; validate on click for business rules        |
|     `console.log` in committed code                           |    Remove before merge or use a logging service                |
|     Component fetching route-param data via `toObservable()`  |    Route resolver (`ResolveFn`) for detail/child routes        |
|     `I`-prefixed interface names (`IInvoiceFilter`)           |    PascalCase without prefix (`InvoiceFilter`)                 |
|     PascalCase or snake_case interface properties             |    camelCase interface properties                              |
