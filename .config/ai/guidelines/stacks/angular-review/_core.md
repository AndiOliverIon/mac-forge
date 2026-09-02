# Angular Review Guidelines — Core

Always load this file for Angular / TypeScript / frontend work in **review mode**. It contains
cross-cutting rules plus the topic-file router. Section numbers remain non-contiguous so references
to the original guideline sections stay valid.

Keep rule intent synchronized with `../angular-development.md` unless a rule is explicitly
mode-specific.

## Topic Files

Build the selection corpus from every changed path, the complete diff including removed lines, and
the complete current contents of every changed file that still exists. Without a diff, treat every
file in the explicit review scope as changed.

Load every topic file whose trigger appears anywhere in that corpus. Match mechanically; do not
decide what the change is "about". Paths are relative to
`~/.config/ai/guidelines/stacks/angular-review/`.

| File | § | Load when the selection corpus contains |
| ---- | - | ---------------------------------------- |
| `rxjs.md` | 4 | `rxjs`, `Observable`, `Subject`, `BehaviorSubject`, `.pipe(`, `.subscribe(`, `switchMap`, `concatMap`, `mergeMap`, `exhaustMap`, `catchError`, `toSignal`, `toObservable`, `takeUntilDestroyed`, `firstValueFrom`, `Promise`, `async`/`await`, `valueChanges` |
| `forms.md` | 8 | `@angular/forms`, `<form`, `ngSubmit`, `form.`, `formControl`, `formGroup`, `.valid`, `.invalid`, `.errors`, `required`, `AbstractControl`, `FormGroup`, `FormControl`, `FormArray`, `FormBuilder`, `NonNullableFormBuilder`, `Validators`, `ValidatorFn`, `AsyncValidatorFn`, `ControlValueAccessor`, `NG_VALUE_ACCESSOR`, `ReactiveFormsModule`, `getRawValue`, `FormsModule`, `ngModel`, `valueChanges` |
| `routing.md` | 11 | `*.routes.ts`, `@angular/router`, `Routes`, `Router`, `RouterModule`, `provideRouter`, `ActivatedRoute`, `RouterLink`, `RouterOutlet`, `ResolveFn`, `CanActivate`, `CanMatch`, `withComponentInputBinding`, `paramMap`, `queryParams`, `toObservable` |
| `ui-kendo.md` | 12 | any `.html` path; `kendo-`, `kendoButton`, `KENDO_`, `@progress/kendo-`, `@ardis/ngx-kendo-ui`, `DialogService`, `DialogRef`, `DialogContentBase`, `.k-`, `::ng-deep`, `!important`, `<table`, `<select`, `<input`, `<textarea`, `<button`, `<a `, `<form`, `<label` |
| `templates-styling.md` | 16 | any `.html`, `.scss`, `.sass`, `.less` or `.css` path; or in a `.ts`: `templateUrl`, `styleUrl`, `template:`, `styles:`; or `style="` / `class="` in a template |

Selection rules:

- This table is the only topic-selection authority. Topic files must not duplicate its triggers.
- Triggers include restricted tokens so the applicable conditional rule is always loaded.
- If the corpus cannot be built completely, load all topic files.
- Default to loading when unsure.
- If a finding reaches an unloaded topic, load that topic before writing the finding.
- Each detailed rule has one review-mode home; do not copy it between core and topic files.

## 1. General Principles

- Follow the Angular style guide as the baseline.
- Prefer explicit, readable code over clever one-liners.
- Keep components, services, methods, and action flows single-responsibility.
- Use strict TypeScript: no `any` and no implicit types.
- Declare explicit access modifiers on all class members.
- Declare explicit types on properties, parameters, and returns, except reactive-form member types may
  be inferred as allowed by §8.
- Use `readonly` for injected dependencies, signals, and values that should not be reassigned.
- Use standalone components by default. Keep NgModules only for legacy or third-party integration.
- Keep `strict: true` enabled in `tsconfig.json`.
- Remove `console.log` and other debug statements before merge; use a logging service for necessary
  runtime diagnostics.

## 2. Angular Version And Features

- Target Angular 19+.
- Use `@if`, `@else if`, `@else`, `@for`, and `@switch` instead of legacy structural directives.
- Always provide `track` in `@for` loops.
- Use `input()` and `output()` instead of `@Input()` and `@Output()`.
- Prefer lazy-loaded feature routes with `loadComponent`.
- Use `inject()` instead of constructor injection unless a base-class constructor requires the
  dependency. For `DialogContentBase`, accept `DialogRef` and pass it to `super(dialog)`.

## 3. Signals And Reactivity

- Use signals as the default primitive for local and shared component state.
- Use `signal()` for mutable state and `computed()` for derived values.
- Use `linkedSignal()` when writable state must remain synchronized with another signal.
- Use `effect()` only for synchronous side effects reacting to signal changes.
- Use `toSignal()` to expose observable values to templates or computed state.
- Use plain `readonly` properties or `const` for static configuration, labels, options, and lookup
  values. Do not wrap constants in signals.
- Do not use `BehaviorSubject` for component-local state.
- Never trigger HTTP or backend calls inside `computed()` or `effect()`; use an observable pipeline
  bridged with `toSignal()`.

## 5. State Management

- Use services with signals as the primary shared-state pattern.
- Do not introduce NgRx or another state library unless the complexity clearly requires it.
- Expose shared service state through readonly signals.
- Provide feature-specific services at route or component scope unless they are genuinely
  application-wide.

## 6. Components

- Keep templates lean; move non-trivial logic to the component, a service, a pipe, or a focused child.
- Do not put business logic in templates.
- Do not manipulate the DOM directly unless integrating non-Angular code; use Angular abstractions.
- Keep constructors limited to dependency injection and trivial setup. Put loading, subscriptions,
  and initialization side effects in lifecycle hooks or reactive fields.
- Do not add trivial one-line wrappers when the template can call the expression or service directly.
- Do not extract tiny single-use helpers unless they improve reuse, isolate substantial complexity,
  or give an important concept a clearer name.

## 7. Component Size And Responsibility

- A component should have one clearly stateable responsibility.
- Split components that combine orchestration, data fetching, rendering, dialog management, and
  formatting.
- Treat a class over roughly 200 lines, a template over roughly 100 lines, or more than five injected
  dependencies as a decomposition signal, not a hard limit.
- Keep public and protected methods around 5–20 lines where practical.
- Use guard clauses and early returns to avoid deep nesting.
- Extract presentation components for meaningful visual sections and container components for
  non-trivial state or data ownership. Do not extract solely to satisfy a line count.
- Action methods should perform one action, call one endpoint, and handle one response.
- Do not mix unrelated mutations or side effects in one action method. Compose genuinely sequential
  operations explicitly.

## 9. Services

- Services must not contain UI or DOM logic.
- Services holding shared state should expose readonly signals.
- Feature-specific services should be route- or component-scoped unless genuinely global.
- Services may wrap generated API clients for caching, retry behavior, orchestration, or signal
  conversion.

## 10. Backend Communication

- Use the generated TypeScript API client for backend communication.
- Import generated clients, DTOs, models, and enums from the generated API package.
- Do not hand-roll `HttpClient` calls for covered endpoints.
- Do not duplicate generated models or cast generated responses to handwritten interfaces.
- Regenerate the client after backend-contract changes and fix resulting compile errors; never patch
  generated clients manually.
- Keep transport contracts distinct from UI view models. Add local models only when they carry
  UI-specific meaning or state.

## 13. UX — Action Availability

- Keep actions visible and disable them when a restriction is fully known from local application or
  form state.
- Keep actions enabled when permission depends on server-side or business-rule validation; validate on
  click and display the API feedback.
- Derive disabled state from signals, computed values, or form state.
- Do not hide actions based on business rules or make an extra API call only to pre-validate their
  availability.

## 14. Shared Helpers

- Move reusable translation, formatting, and label-resolution logic to a shared service, utility, or
  pipe.
- Use pure pipes for stateless template transformations.
- Put utilities without Angular DI dependencies in `*.utils.ts` files.
- Keep a helper on a component only when it depends on component-specific state.
- Do not duplicate the same helper across components.

## 15. Defensive Coding

- Keep defensive checks proportional to actual risk and trust typed internal values.
- Use simple fallbacks such as `?? []` or `|| []` for potentially empty collections.
- Exit early when an empty collection makes further work unnecessary.
- Do not create private validation methods that only recheck TypeScript types.
- Do not filter typed ID arrays for integer or positivity checks unless an unsafe source or concrete
  business rule requires it.
- Validate at boundaries: forms, loosely typed API responses, shared utilities, and business rules.

## 17. TypeScript Standards

- Use `public` for externally consumed members, `protected` for template-only members, and `private`
  for internal implementation details.
- Use `readonly` for injected dependencies and values that should not be reassigned.
- Name interfaces in PascalCase without an `I` prefix.
- Name interface properties in camelCase, never PascalCase or snake_case.
- Keep interfaces and types in a feature-adjacent `.types.ts` or `.model.ts` file.
- Avoid non-null assertions unless no safer narrowing is practical.
- Use union types or type-safe enums for constrained values.

## 18. Naming Conventions

- Components: `kebab-case.component.ts`.
- Services: `kebab-case.service.ts`.
- Types/models: `kebab-case.types.ts` or `kebab-case.model.ts`.
- Routes: `kebab-case.routes.ts`.
- Pipes: `kebab-case.pipe.ts`.
- Guards: `kebab-case.guard.ts`.
- Directives: `kebab-case.directive.ts`.
- Do not encode implementation types into local names when a domain or role name is clearer; prefer
  `productIds`, `operationTypes`, or `row` over suffixes such as `Signal`.

## 19. Performance

- Lazy-load feature routes.
- Always provide `track` in `@for` loops.
- Use `toSignal()` where it avoids unnecessary async-pipe churn.
- Use Kendo Grid virtual scrolling for large datasets.
- Avoid manual `markForCheck()` or `detectChanges()` unless integrating non-Angular code.
- Never perform backend calls inside reactive computations.
