# Angular Core Guidelines

This is a compact, rule-first version of the Angular guidelines. It preserves the intent of the full review guideline set in `angular-review/` while reducing repetition and long examples.

Rule intent in this development file must remain synchronized with the detailed review set, except for rules explicitly labeled as mode-specific. Any material rule change must update both representations in the same change.

## 1. Baseline

- Follow the Angular style guide as the baseline.
- Target Angular 19+.
- Prefer explicit, readable code over clever one-liners.
- Keep components, services, methods, and action flows single-responsibility.
- Use standalone components by default.
- Use strict TypeScript: no `any`, no implicit types.
- Always declare explicit access modifiers and type annotations on class members, method parameters, and return types, except reactive-form member types may be inferred as allowed by §8.
- Use `readonly` for injected dependencies, signals, and values that should not be reassigned.
- Remove `console.log` and debug statements before merge.

## 2. Modern Angular APIs

- Use `inject()` instead of constructor injection unless a base-class constructor requires the dependency, such as passing `DialogRef` to `DialogContentBase`.
- Use `input()` and `output()` signal APIs instead of `@Input()` and `@Output()`.
- Use `@if`, `@else if`, `@else`, `@for`, and `@switch` instead of legacy structural directives.
- Always provide `track` in `@for` loops.
- Do not use `@switch (true)` for boolean branching. Use `@if` / `@else if` / `@else`.
- Prefer lazy-loaded feature routes with `loadComponent`.

## 3. Signals And Reactivity

- Use `signal()` for mutable local state.
- Use `computed()` for derived values that depend on signals.
- Use `linkedSignal()` when writable state must stay synchronized with another signal.
- Use `effect()` only for synchronous side effects that react to signal changes.
- Use `toSignal()` to bridge observables into templates and computed values.
- Use plain `readonly` properties or `const` for static values, fixed labels, fixed options, and configuration.
- Do not wrap static or constant values in `signal()`.
- Do not use `BehaviorSubject` for component-local state.
- Never trigger HTTP or backend calls inside `computed()` or `effect()`. Use `toSignal()` with an observable pipeline instead.

## 4. Observables And RxJS

- Use observables for HTTP, WebSocket, and event streams.
- Avoid `Promise` and `async` / `await`; use RxJS equivalents. Use `firstValueFrom` only as a last resort.
- Prefer `toSignal()` or the `async` pipe for template consumption.
- If a manual subscription is necessary, use `takeUntilDestroyed()` for streams that do not complete on their own.
- Always use `.subscribe({ next, error })` object syntax.
- Always implement a meaningful `error` handler. Empty handlers and `error: () => undefined` are banned.
- Never nest `.subscribe()` inside another `.subscribe()`. Flatten with `switchMap`, `concatMap`, `mergeMap`, or `exhaustMap`.
- Do not nest `.pipe()` calls inside operator callbacks. Extract the inner logic into a named private method or carry the flow in the root pipeline.
- Choose flattening operators by intent:
  - `switchMap`: latest emission wins; cancel in-flight work.
  - `concatMap`: preserve order; process sequentially.
  - `mergeMap`: run independent work in parallel.
  - `exhaustMap`: ignore new emissions while one is in flight.
- Do not default to `switchMap` for every flow.

## 5. Services And State

- Use services with signals as the primary shared state pattern.
- Do not introduce NgRx or another state library unless complexity clearly requires it.
- Services must not contain DOM logic.
- Services with shared state should expose readonly signals.
- Feature-specific services should be provided at the route or component level unless they truly are application-wide.
- Services may wrap generated API clients to add caching, retry behavior, orchestration, or signal conversion.

## 6. Components

- Keep component constructors limited to dependency injection and trivial setup. Move loading, subscriptions, and initialization side effects into lifecycle hooks or reactive fields.
- Components should have one clear reason to exist.
- Split components when they combine orchestration, data fetching, rendering, dialog management, and formatting.
- Treat a component class over roughly 200 lines, a template over roughly 100 lines, or more than five injected dependencies as a decomposition signal.
- Keep public and protected methods around 5-20 lines where practical.
- Use guard clauses and early returns to keep methods flat.
- Keep templates lean. Move non-trivial logic to the component class, a service, a pipe, or a child component.
- Do not put business logic in templates.
- Do not manipulate the DOM directly unless integrating non-Angular code.
- Do not introduce trivial one-line component wrapper methods when the template can call the expression or service directly.
- Do not over-extract tiny single-use private helpers unless extraction improves readability, reuse, or isolates real complexity.

## 7. Action Flows

- Action methods should perform one action, call one endpoint, and handle one response.
- Do not mix unrelated mutations or side effects in one action method.
- Do not expose `Observable<void>` from command-style service methods. If a method primarily performs an action and returns no meaningful data, the owning service should subscribe and return `void`.
- Avoid `Observable<void>` in private command helpers when no meaningful async value is composed.
- Do not pass caller-provided success or error callbacks into services just so callers can react after a command completes.
- Do not force components to call `.subscribe()` only to trigger command execution.
- When a service owns an orchestration flow such as opening a confirmation dialog, calling an API, and showing notifications, keep the full use case in the service and subscribe there.
- If the UI needs follow-up information from a command flow, expose meaningful state as a value stream or signal.
- Do not use `tap` for primary outcome handling such as notifications, refreshes, navigation, or other use-case reactions. Handle final reactions in the owning `subscribe` or receiving consumer.

## 8. Forms

- Use reactive forms for actual forms, validation flows, and multi-field dialogs.
- Allow `ngModel` only for standalone controls and direct grid-cell or row editing that is not part of a form.
- Prefer typed `FormGroup`, `FormControl`, and `FormArray`, but accept bare or inferred form types when they match the local feature pattern.
- Prefer `NonNullableFormBuilder` when all controls should be non-nullable.
- Use `fb.control<Type>(value, { validators: [...] })` with an options object for validators and control config.
- Use `nonNullable: true` only when mixing nullable and non-nullable controls with `FormBuilder`.
- Define form interfaces or types for form models and controls.
- Use custom validators with proper `ValidatorFn` or `AsyncValidatorFn` typing.
- Use Kendo form controls with `formControlName`.
- Use `getRawValue()` for non-nullable forms.
- Do not use `ngModel` or template variables as form state inside an actual form.
- Avoid `form.value` on nullable forms.

## 9. Backend Communication

- Use the generated TypeScript API client for backend communication.
- Import generated clients, DTOs, models, and enums from the generated API package.
- Do not hand-roll `HttpClient` calls for endpoints covered by the generated client.
- Do not duplicate or redefine models that already exist in the generated client.
- Do not cast generated responses to hand-written interfaces.
- When the backend changes, regenerate the client and fix compile errors. Do not patch generated API clients manually.
- Keep transport-layer API contracts distinct from UI view models. Create local models only when they add UI-specific meaning or state.

## 10. Routing

- Use `withComponentInputBinding()` through signal inputs for route parameters, query parameters, and route data.
- Use `input.required()` for mandatory route parameters.
- Provide defaults with `input()` for optional query parameters.
- Type route inputs properly. Route parameters arrive as strings unless transformed.
- For numeric route parameters, use an input transform when direct numeric consumption is appropriate.
- Use `toObservable()` + the correct flattening operator to react to parameter changes when the component owns the data load.
- Prefer route resolvers for detail or child routes that load a single resource by route id before the component renders.
- Redirect from resolver `catchError` when failed data loading should prevent component rendering.
- Match resolver keys to component input names.
- Avoid `ActivatedRoute` unless you need advanced route inspection, parent/child route information, navigation history, or custom route event streams.
- Do not manually parse query strings.
- Do not use resolvers for list pages, search results, or data driven by user interaction after navigation.

## 11. UI Components

- Prefer `@ardis/ngx-kendo-ui` components first, native Kendo components second, and custom implementation only when neither covers the use case.
- Do not use raw HTML controls when an Ardis/Kendo equivalent exists.
- Use Kendo button, form, grid, dropdown, date picker, and dialog primitives for UI interactions.
- Check `@ardis/ngx-kendo-ui` exports before building a custom UI element.
- Use Kendo icons before Font Awesome. Fall back to Font Awesome only when Kendo has no suitable icon.
- Do not create custom data grids, date pickers, dropdowns, or other common controls when Kendo equivalents exist.
- Do not override Kendo component styles with `!important`; use the Kendo theming system.
- Do not add hover or motion effects to cards unless explicitly required.

## 12. Dialogs

- Use Kendo `DialogService` with component rendering.
- Dialog components must extend `DialogContentBase`.
- Dialog templates must include `<kendo-dialog-titlebar>` and `<kendo-dialog-actions>`.
- Pass `DialogRef` to `super()` in dialog components.
- Pass data to dialog components through instance properties after opening.
- Subscribe to `dialogRef.result` with object syntax and meaningful error handling.
- Return typed result objects from dialog components when structured output is needed.
- Prefer an explicit close method in the component class instead of inlining `dialog.close(...)` in the template.
- Do not use declarative `<kendo-dialog>` with `*ngIf`.
- Do not use string `content` or an `actions` array in `dialogService.open()`.
- Do not set `themeColor` on cancel actions. Use theme colors only for affirmative or destructive actions.
- Configure dialog width and dimensions in `DialogService.open(...)`, not in dialog component SCSS.
- Dialog component content should generally use `width: 100%` when needed.
- For grid-based dialogs, configure dimensions in `DialogService.open(...)` and let the grid fill the body. Do not use component-level min-height hacks.
- Render cross-form or dialog-level errors with the shared `ardis-message-box` pattern.
- Aggregate dialog-level error handling to a single shared `ardis-message-box` usage.
- When a Kendo component extends `DialogContentBase`, prefer `...DialogComponent` naming rather than `...PopupComponent`.

## 13. UX Action Availability

- Prefer disabling buttons over hiding them when the restriction is known from local application state.
- Keep buttons enabled when the restriction depends on server-side or business-rule validation; validate on click and show feedback from the API response.
- Derive disabled state from signals, computed values, or form state.
- Do not hide/show buttons based on business rules.
- Do not make an extra API call only to pre-validate a business rule for button state.

## 14. Helpers And Defensive Checks

- Move reusable translation, formatting, and label-resolution helpers into a shared service, utility, or pipe.
- Use pure pipes for stateless template transformations.
- Put utility functions that do not depend on Angular DI in a standalone `*.utils.ts` file.
- Do not duplicate the same helper across components.
- Keep defensive checks proportional to actual risk.
- Trust typed internal values. Use simple fallbacks such as `?? []` or `|| []` for potentially empty arrays.
- Do not create private validation methods to recheck types TypeScript already enforces.
- Do not filter typed ID arrays for integer or positivity checks unless a concrete business rule or unsafe source requires it.
- Apply real validation at boundaries: forms, API responses with loose schema, shared utilities, and business-rule checks.

## 15. Templates And Styling

- Use separate template and style files for rendered components.
- Use `templateUrl` and `styleUrl`; omit `styleUrl` if no custom styles are needed.
- Allow `template: ''` only for abstract, non-rendering base components.
- Never use non-empty inline component templates, inline component styles, or `style="..."`.
- Before adding a root wrapper solely for layout, use component `:host` when it can express the
  layout and direct-child sizing.
- Use BEM naming for custom CSS classes.
- Prefer Kendo UI CSS utilities over custom CSS.
- Use Kendo theme variables for colors, spacing, borders, shadows, typography, and design tokens.
- Use color only when it adds semantic value, status indication, or meaningful emphasis.
- Keep custom styling minimal.
- Delete empty SCSS files.
- Do not hardcode values that exist as Kendo theme variables.
- Do not add custom styling for grids or grid rows unless explicitly requested.
- When styling `ardis-kendo-magic-grid`, use the `ardis-kendo-magic-grid { ... }` element selector directly instead of adding wrapper classes.
- When a component SCSS file uses a block class with BEM elements or modifiers, prefer nesting with `&__...` and `&--...`.

## 16. TypeScript Naming And File Organization

- Component files: `kebab-case.component.ts`.
- Service files: `kebab-case.service.ts`.
- Types/model files: `kebab-case.types.ts` or `kebab-case.model.ts`.
- Route files: `kebab-case.routes.ts`.
- Pipe files: `kebab-case.pipe.ts`.
- Guard files: `kebab-case.guard.ts`.
- Interface names are PascalCase with no `I` prefix.
- Interface properties are camelCase, never PascalCase or snake_case.
- All interfaces and types should live in a `.types.ts` or `.model.ts` file alongside the feature.
- Avoid non-null assertions unless absolutely necessary; use null checks instead.
- Use union types or type-safe enums for constrained values.
- Do not encode implementation types into local member names when a clearer domain or role name exists. Prefer names such as `productIds`, `operationTypes`, or `row` rather than suffixes like `Signal`.

## 17. Performance

- Lazy-load feature routes.
- Use `toSignal()` to avoid unnecessary async-pipe churn where a signal fits the template.
- Use Kendo Grid virtual scrolling for large datasets.
- Avoid manual change detection calls unless integrating non-Angular code.
- Avoid backend calls inside reactive computations.

## 18. Local Project Conventions

- For non-route component inputs that receive numeric attribute text, prefer Angular's `numberAttribute` transform instead of accepting a `string` and casting manually.
- In the `@ardis/ngx-kendo-ui` library and projects that consume it, always wrap `ArdisDataProvider`,
  `ArdisConfigurationProvider`, and `ArdisExpressionConfigurationProvider` in `computed()`.
- In Ardis Angular projects, prefer the `translate` pipe for simple template-rendered text; keep
  component-side translation for non-template consumers such as page titles or notifications.
- In Ardis Angular projects, do not use `ChangeDetectionStrategy.OnPush` for now.
