# Angular Review Guidelines — Observables & RxJS (§4)

Topic file for Angular **review mode**. `_core.md` owns its routing triggers. Read this file in full
when selected; apply it together with the core rules.

## 4. Observables and RxJS

### Rules

- Use observables for HTTP, WebSocket, and event streams. Avoid `Promise` and `async` / `await`; use
  `firstValueFrom()` only as a last resort at a boundary that cannot consume an observable.
- Prefer `toSignal()` or the `async` pipe for template consumption.
- If a manual subscription is necessary for a stream that does not complete itself, use
  `takeUntilDestroyed()`.
- Every `.subscribe()` must use object syntax with `next` and a meaningful `error` handler. Positional
  callbacks, missing handlers, empty handlers, and `error: () => undefined` are violations.
- Never nest `.subscribe()` calls. Flatten dependent work with the appropriate higher-order operator.
- Do not nest `.pipe()` calls inside operator callbacks. Keep the flow in the root pipeline or move
  the inner operation into a named private method.
- Select concurrency by intent; do not default to `switchMap`.

| Operator | Required behavior |
| --- | --- |
| `switchMap` | Latest emission wins and in-flight work may be cancelled, such as search or navigation. |
| `concatMap` | Preserve order and process one emission at a time. |
| `mergeMap` | Run independent work in parallel; completion order does not matter. |
| `exhaustMap` | Ignore new emissions while the current operation is running, such as login or submit. |

### Canonical stream and subscription

```typescript
protected results: Signal<SearchResult[]> = toSignal(
    this.term$.pipe(
        debounceTime(300),
        distinctUntilChanged(),
        switchMap((term: string) => this.searchService.search(term)),
        catchError((error: HttpErrorResponse): Observable<SearchResult[]> => {
            this.notificationService.showError('Search failed', error);
            return of([]);
        })
    ),
    { initialValue: [] }
);

public save(invoice: Invoice): void {
    this.invoiceService.save(invoice).subscribe({
        next: (saved: Invoice) => this.invoices.update(
            (items: Invoice[]) => [...items, saved]
        ),
        error: (error: HttpErrorResponse) =>
            this.notificationService.showError('Save failed', error),
    });
}
```

For a long-lived manual subscription, combine the same object syntax with lifecycle cleanup:

```typescript
private readonly destroyRef: DestroyRef = inject(DestroyRef);

public ngOnInit(): void {
    this.events.pipe(takeUntilDestroyed(this.destroyRef)).subscribe({
        next: (event: NotificationEvent) => this.handle(event),
        error: (error: unknown) => this.notificationService.showError('Event stream failed', error),
    });
}
```

### Flatten dependent work

Keep the composition in one readable pipeline. A named method may contain its own pipeline when it
encapsulates a coherent operation.

```typescript
protected enrichedResults: Signal<EnrichedResult[] | undefined> = toSignal(
    this.term$.pipe(
        switchMap((term: string) => this.searchService.search(term)),
        switchMap((results: SearchResult[]) => this.enrichAll(results))
    )
);

private enrichAll(results: SearchResult[]): Observable<EnrichedResult[]> {
    return forkJoin(
        results.map((result: SearchResult) => this.enrichService.enrich(result))
    );
}
```
