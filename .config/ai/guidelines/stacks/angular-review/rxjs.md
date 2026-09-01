# Angular Review Guidelines — Observables & RxJS (§4)

Topic file for Angular **review mode**. It is selected only by the mechanical routing rules in
`_core.md`, which is the sole authority for the selection corpus and trigger table. This file
intentionally contains no duplicate trigger list. When selected, read it in full; the broad baseline
in `_core.md` does not replace the detailed rules here.

---

## 4. Observables & RxJS

Use Observables for **async data streams**, **HTTP calls**, and **event-driven logic**. Avoid Promises.

### HTTP & Data Fetching

```typescript
// ✅ Return an Observable from services
public getUsers(): Observable<User[]> {
  return this.http.get<User[]>('/api/users').pipe(
    retry(2),
    catchError(this.handleError)
  );
}

// ❌ Do not wrap in Promise
async getUsers(): Promise<User[]> {
  return firstValueFrom(this.http.get<User[]>('/api/users'));
}
```

### Subscription Management

Prefer `toSignal()` or the `async` pipe over manual subscriptions. If you must subscribe manually, use `takeUntilDestroyed`.

```typescript
import { takeUntilDestroyed } from '@angular/core/rxjs-interop';

export class NotificationComponent {
    private readonly destroyRef: DestroyRef = inject(DestroyRef);
    private readonly notificationService: NotificationService = inject(NotificationService);

    constructor() {
        this.notificationService.events$.pipe(takeUntilDestroyed(this.destroyRef)).subscribe((event: NotificationEvent) => this.handleEvent(event));
    }

    private handleEvent(event: NotificationEvent): void {
        // Handle notification event
    }
}
```

### Subscribe Syntax

**Always use the object form `{ next, error }` when calling `.subscribe()`.**  The `error` handler is mandatory and must contain a real implementation — an empty function or `() => undefined` is not acceptable. Silent error swallowing makes debugging impossible and hides broken states from users.

```typescript
// ✅ Object syntax with meaningful error handler
this.invoiceService.save(invoice).subscribe({
    next: (saved: Invoice) => {
        this.invoices.update((list: Invoice[]) => [...list, saved]);
    },
    error: (err: HttpErrorResponse) => {
        this.notificationService.showError('Failed to save invoice', err);
    },
});

// ❌ Positional callbacks — avoid
this.invoiceService.save(invoice).subscribe(
    (saved: Invoice) => { ... },
    (err) => { ... }
);

// ❌ Missing or empty error handler — never do this
this.invoiceService.save(invoice).subscribe({
    next: (saved: Invoice) => { ... },
    error: () => undefined,   // ❌ silently swallows errors
});

// ❌ No error handler at all
this.invoiceService.save(invoice).subscribe({
    next: (saved: Invoice) => { ... },
    // ❌ missing error handler
});
```

### RxJS Operators

```typescript
// ✅ Use pipeable operators
export class SearchComponent {
    private readonly searchService: SearchService = inject(SearchService);
    private readonly searchTerm$: Observable<string> = new Subject<string>();

    public results$: Observable<SearchResult[]> = this.searchTerm$.pipe(
        debounceTime(300),
        distinctUntilChanged(),
        switchMap((term: string) => this.searchService.search(term)),
        catchError(() => of<SearchResult[]>([]))
    );
}
```

### No Nested Subscribes

Never call `.subscribe()` inside another `.subscribe()`. Nested subscribes create memory leak risk, bypass cleanup logic, and make error handling unreliable. Flatten with a higher-order operator instead.

```typescript
// ❌ Nested subscribe — do not do this
this.route.params.subscribe((params: Params) => {
    this.invoiceService.getById(params['id']).subscribe((invoice: Invoice) => {
        this.notificationService.notify(invoice.id).subscribe(() => {
            this.invoice.set(invoice);
        });
    });
});

// ✅ Flat pipeline with switchMap
this.invoice = toSignal(
    this.route.params.pipe(
        switchMap((params: Params) => this.invoiceService.getById(params['id'])),
        switchMap((invoice: Invoice) =>
            this.notificationService.notify(invoice.id).pipe(map((): Invoice => invoice))
        )
    )
);
```

### No Nested Pipes

Do not nest `.pipe()` calls inside operator callbacks. Nested pipes obscure the data flow, make the chain hard to follow, and often indicate the inner logic should be extracted into a named private method or a separate observable.

```typescript
// ❌ Nested pipe inside switchMap callback
public results$: Observable<EnrichedResult[]> = this.term$.pipe(
    switchMap((term: string) =>
        this.searchService.search(term).pipe(
            map((results: SearchResult[]) =>
                results.map((r: SearchResult) =>
                    of(r).pipe(
                        switchMap((item: SearchResult) => this.enrichService.enrich(item))
                    )
                )
            )
        )
    )
);

// ✅ Extract inner logic into a private method
public results$: Observable<EnrichedResult[]> = this.term$.pipe(
    switchMap((term: string) => this.searchService.search(term)),
    switchMap((results: SearchResult[]) => this.enrichAll(results))
);

private enrichAll(results: SearchResult[]): Observable<EnrichedResult[]> {
    return forkJoin(results.map((r: SearchResult) => this.enrichService.enrich(r)));
}
```

### Flattening Operator Choice

Not all higher-order operators are interchangeable. Pick the one that matches the intended behaviour:

| Operator | Use when |
| ------------ | -------------------------------------------- |
| `switchMap` | Only the latest emission matters — cancel in-flight (search, navigation, route params) |
| `concatMap` | Order must be preserved — process one at a time (sequential saves, ordered uploads) |
| `mergeMap` | All emissions run in parallel and order doesn't matter (independent fire-and-forget calls) |
| `exhaustMap` | Ignore new emissions while one is in flight (submit button, login) |

```typescript
// ✅ switchMap — search: cancel previous request when term changes
public results$: Observable<SearchResult[]> = this.term$.pipe(
    debounceTime(300),
    distinctUntilChanged(),
    switchMap((term: string) => this.searchService.search(term))
);

// ✅ concatMap — audit log: preserve submission order
public saveAll(items: Item[]): Observable<Item> {
    return from(items).pipe(
        concatMap((item: Item) => this.itemService.save(item))
    );
}

// ✅ exhaustMap — login button: ignore clicks while request is in flight
public login$: Observable<User> = this.loginClick$.pipe(
    exhaustMap(() => this.authService.login(this.credentials()))
);
```

### Rules

* ✅ Use Observables for HTTP, WebSocket, and event streams.
* ✅ Prefer `toSignal()` or `async` pipe for template consumption.
* ✅ Use `takeUntilDestroyed()` for manual subscriptions.
* ✅ Choose the flattening operator that matches the intended concurrency behaviour.
* ✅ **Always use `{ next, error }` object syntax** for `.subscribe()` calls.
* ✅ **Always implement a meaningful `error` handler** — never leave it empty or as `() => undefined`.
* ❌ Avoid raw `.subscribe()` in components without explicit cleanup.
* ❌ Never nest `.subscribe()` inside another `.subscribe()` — flatten with `switchMap`, `concatMap`, `mergeMap`, or `exhaustMap`.
* ❌ Never nest `.pipe()` calls inside operator callbacks — extract to a private method instead.
* ❌ Do not default to `switchMap` for everything — use `concatMap`, `exhaustMap`, or `mergeMap` where appropriate.
* ❌ Avoid `Promise` / `async-await` — use RxJS equivalents (`switchMap`, `firstValueFrom` only as a last resort).
* ❌ Never use an empty or no-op `error` handler — `error: () => undefined` is banned.

---
