# Angular Review Guidelines — Routing (§11)

Topic file for Angular **review mode**. It is selected only by the mechanical routing rules in
`_core.md`, which is the sole authority for the selection corpus and trigger table. This file
intentionally contains no duplicate trigger list. When selected, read it in full; the broad baseline
in `_core.md` does not replace the detailed rules here.

---

## 11. Routing

Use **lazy-loaded routes** with `loadComponent` for all feature pages.

```typescript
export const routes: Routes = [
    {
        path: 'invoices',
        loadComponent: () => import('./features/invoices/invoice-list.component').then((m) => m.InvoiceListComponent),
    },
    {
        path: 'invoices/:id',
        loadComponent: () => import('./features/invoices/invoice-detail.component').then((m) => m.InvoiceDetailComponent),
    },
];
```

### Route Parameters with Component Input Binding

**This project uses `withComponentInputBinding()`** — route parameters, query parameters, and route data are automatically available as component inputs. This is the **preferred way** to access route information.

#### Basic Route Parameters

Route parameters become signal inputs automatically:

```typescript
// Route: 'invoices/:id'
export class InvoiceDetailComponent {
    private readonly invoiceService: InvoiceService = inject(InvoiceService);

    // Route parameter 'id' becomes an input signal
    public id: InputSignal<string> = input.required<string>();

    // Use it directly in computed values or effects
    protected invoice: Signal<Invoice | undefined> = toSignal(toObservable(this.id).pipe(switchMap((id: string) => this.invoiceService.getById(id))));
}
```

```html
<h1>Invoice {{ id() }}</h1>
@if (invoice(); as invoice) {
<p>Amount: {{ invoice.amount | currency }}</p>
}
```

#### Query Parameters

Query parameters are also automatically bound:

```typescript
// URL: /products?category=electronics&sort=price
export class ProductListComponent {
    private readonly productService: ProductService = inject(ProductService);

    // Query params become inputs with the exact query param name
    public category: InputSignal<string | undefined> = input<string>(); // optional
    public sort: InputSignal<string> = input<string>('name'); // with default

    protected products: Signal<Product[]> = computed(() => {
        return this.productService
            .getAll()
            .filter((p: Product) => !this.category() || p.category === this.category())
            .sort((a: Product, b: Product) => this.sortProducts(a, b, this.sort()));
    });

    private sortProducts(a: Product, b: Product, sortBy: string): number {
        // Sort logic
        return 0;
    }
}
```

#### Route Data

Static route data is accessible as inputs:

```typescript
// Route configuration
{
  path: 'admin',
  data: { requiresAuth: true, role: 'admin' },
  loadComponent: () => import('./admin.component')
}

// Component
export class AdminComponent {
  public requiresAuth: InputSignal<boolean | undefined> = input<boolean>();
  public role: InputSignal<string | undefined> = input<string>();
}
```

#### Multiple Parameters

Components can receive multiple route parameters simultaneously:

```typescript
// Route: 'projects/:projectId/tasks/:taskId'
export class TaskDetailComponent {
    private readonly taskService: TaskService = inject(TaskService);

    public projectId: InputSignal<string> = input.required<string>();
    public taskId: InputSignal<string> = input.required<string>();

    protected task: Signal<Task | undefined> = toSignal(
        combineLatest([toObservable(this.projectId), toObservable(this.taskId)]).pipe(
            switchMap(([projectId, taskId]: [string, string]) => this.taskService.getTask(projectId, taskId))
        )
    );
}
```

#### Type-Safe Parameters

Always type your route parameters for type safety:

```typescript
// ✅ Type-safe route parameters
export class InvoiceDetailComponent {
    public id: InputSignal<string> = input.required<string>(); // string from route
    protected invoiceId: Signal<number> = computed(() => Number(this.id())); // convert to number
}

// ✅ With transform for direct number conversion (Angular 18+)
export class InvoiceDetailComponent {
    public id: InputSignal<number> = input.required<string, number>({
        transform: (value: string): number => Number(value),
    });
}
```

#### When to Use ActivatedRoute Instead

Use the traditional `ActivatedRoute` approach only when you need:

* Access to full route snapshot
* Navigation history
* Parent/child route information
* Custom observable streams from route events

```typescript
// ❌ Avoid for simple parameter access
export class InvoiceDetailComponent {
    private readonly route: ActivatedRoute = inject(ActivatedRoute);
    protected id: Signal<string | null | undefined> = toSignal(this.route.paramMap.pipe(map((p: ParamMap) => p.get('id'))));
}

// ✅ Use withComponentInputBinding instead
export class InvoiceDetailComponent {
    public id: InputSignal<string> = input.required<string>();
}
```

### Route Data Resolvers

**Prefer route resolvers when a child route needs data that depends on a route parameter.** Resolvers fetch the data before the component activates, so the component receives ready-to-use data via an input signal instead of managing its own loading state and `toObservable()` + `switchMap()` pipeline.

Use a resolver when:
- A detail or child route loads a single resource by ID (e.g. `GET /invoices/:id`).
- The component should not render at all if the resource does not exist (the resolver can redirect on 404).
- Multiple sibling child routes need the same resolved data.

Do **not** use a resolver for list pages, search results, or data that changes based on user interaction after navigation — those belong in the component.

```typescript
// invoice.resolver.ts
export const invoiceResolver: ResolveFn<Invoice> = (route: ActivatedRouteSnapshot): Observable<Invoice> => {
    const invoicesClient: InvoicesClient = inject(InvoicesClient);
    const router: Router = inject(Router);
    const id: number = Number(route.paramMap.get('id'));

    return invoicesClient.getById(id).pipe(
        catchError((): Observable<never> => {
            router.navigate(['/not-found']);
            return EMPTY;
        })
    );
};
```

```typescript
// invoice.routes.ts
export const invoiceRoutes: Routes = [
    {
        path: ':id',
        resolve: { invoice: invoiceResolver },
        loadComponent: () =>
            import('./invoice-detail.component').then((m) => m.InvoiceDetailComponent),
    },
];
```

```typescript
// invoice-detail.component.ts
// Because withComponentInputBinding() is active, resolved data arrives as an input signal.
export class InvoiceDetailComponent {
    // The key 'invoice' matches the resolve map key in the route config.
    public invoice: InputSignal<Invoice> = input.required<Invoice>();
}
```

```html
<!-- invoice-detail.component.html -->
<h1>Invoice {{ invoice().reference }}</h1>
<p>Amount: {{ invoice().amount | currency }}</p>
```

**Compared to the component-managed alternative**, the resolver pattern removes the `toObservable()` + `switchMap()` boilerplate from the component, keeps loading/error handling in one place, and prevents the component from ever rendering with a `undefined` value.

```typescript
// ❌ Component managing its own fetch — avoid when a resolver fits
export class InvoiceDetailComponent {
    private readonly invoicesClient: InvoicesClient = inject(InvoicesClient);
    public id: InputSignal<string> = input.required<string>();

    protected invoice: Signal<Invoice | undefined> = toSignal(
        toObservable(this.id).pipe(
            switchMap((id: string) => this.invoicesClient.getById(Number(id)))
        )
    );
}

// ✅ Component receives resolved data — no loading boilerplate
export class InvoiceDetailComponent {
    public invoice: InputSignal<Invoice> = input.required<Invoice>();
}
```

### Rules

* ✅ Use `input()` for all route parameters, query parameters, and route data.
* ✅ Type your inputs properly — route params are always strings initially.
* ✅ Use `input.required()` for mandatory route parameters.
* ✅ Provide defaults with `input()` for optional query parameters.
* ✅ Use `toObservable()` + `switchMap()` pattern to react to parameter changes.
* ✅ **Use route resolvers** (`ResolveFn`) when a detail/child route needs data fetched by a route ID — prefer over `toObservable() + switchMap()` in the component.
* ✅ Redirect to a not-found route inside the resolver's `catchError` to prevent the component from rendering on a failed fetch.
* ✅ Name the resolver key in the `resolve` map to match the component input name so `withComponentInputBinding()` wires them automatically.
* ❌ Avoid `ActivatedRoute` unless you need advanced route inspection.
* ❌ Do not manually parse query strings — let Angular handle it.
* ❌ Do not use resolvers for list pages, search results, or data driven by post-navigation user interaction.

---
