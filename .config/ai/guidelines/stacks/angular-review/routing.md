# Angular Review Guidelines — Routing (§11)

Topic file for Angular **review mode**. `_core.md` owns its routing triggers. Read this file in full
when selected; apply it together with the core rules.

## 11. Routing

### Rules

- Lazy-load feature pages with `loadComponent`.
- Because the application uses `withComponentInputBinding()`, consume route parameters, query
  parameters, static route data, and resolved data through signal inputs.
- Input names must exactly match parameter, query, data, and resolver keys.
- Use `input.required()` for mandatory values and `input(defaultValue)` for optional values with a
  default.
- Route parameters initially arrive as strings. Type them accordingly or use an input transform for
  direct numeric consumption.
- When the component owns a parameter-driven load, convert its input with `toObservable()` and use
  the flattening operator that matches the required concurrency.
- Prefer a `ResolveFn` for a detail or child route that loads a single resource by route ID before
  rendering, especially when sibling routes share the data or a missing resource prevents rendering.
- In a resolver, handle failed loading and redirect when the component must not activate.
- Do not use resolvers for list pages, search results, or data driven by interaction after navigation.
- Avoid `ActivatedRoute` for ordinary parameters. Use it only for advanced route inspection,
  snapshots, parent/child route information, navigation history, or custom route-event streams.
- Do not parse query strings manually.

### Component-owned parameter flow

```typescript
// Route: products/:category?page=2
export class ProductListComponent {
    private readonly productsClient: ProductsClient = inject(ProductsClient);

    public category: InputSignal<string> = input.required<string>();
    public page: InputSignalWithTransform<number, string | undefined> =
        input<number, string | undefined>(1, {
            transform: (value: string | undefined): number => Number(value ?? 1),
        });

    protected products: Signal<Product[] | undefined> = toSignal(
        toObservable(this.category).pipe(
            switchMap((category: string) => this.productsClient.getByCategory(category))
        )
    );
}
```

### Resolver and input-binding contract

The resolver key and component input name must match (`invoice` below).

```typescript
export const invoiceResolver: ResolveFn<Invoice> = (
    route: ActivatedRouteSnapshot
): Observable<Invoice> => {
    const invoicesClient: InvoicesClient = inject(InvoicesClient);
    const router: Router = inject(Router);
    const id: number = Number(route.paramMap.get('id'));

    return invoicesClient.getById(id).pipe(
        catchError((): Observable<never> => {
            void router.navigate(['/not-found']);
            return EMPTY;
        })
    );
};

export const invoiceRoutes: Routes = [
    {
        path: ':id',
        resolve: { invoice: invoiceResolver },
        loadComponent: () =>
            import('./invoice-detail.component').then(
                (module: typeof import('./invoice-detail.component')) =>
                    module.InvoiceDetailComponent
            ),
    },
];

export class InvoiceDetailComponent {
    public invoice: InputSignal<Invoice> = input.required<Invoice>();
}
```
