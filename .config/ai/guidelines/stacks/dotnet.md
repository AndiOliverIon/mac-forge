# Coding Guidelines — ASP.NET Core REST API + Business Layer

> Generic, project-agnostic rules. Intended as a living reference.

---

## 1. General Principles

- **SOLID**: Keep each class cohesive around one responsibility or reason to change. Split it when
  concerns evolve independently, require materially different dependencies, or make the class
  difficult to understand—not merely because it contains multiple related operations.
- **Prefer small methods when practical**: A method fitting on screen is a useful readability signal,
  not a strict line limit. Keep one coherent responsibility and extract only when a block is
  reusable, independently meaningful, substantially complex, or represents a separate concern.
- **Meaningful, concise names**: State intent and avoid obscure, ambiguous, or newly invented
  abbreviations. Established domain acronyms and project terminology are valid. Do not rename an
  existing public or broadly consumed identifier solely to expand an accepted abbreviation. Avoid
  names such as `Manager2`, `HandleStuff`, and `DoProcess`.
- **No comments for the obvious**: Only comment when the *why* is non-obvious — a hidden constraint, a quirk, a workaround. Never describe what the code already says.
- **No over-engineering**: Don't introduce abstractions for hypothetical future needs. Three similar lines beat a premature helper.
- **Avoid deep nesting**: Flatten deep branches with early returns, guards, indexing, projection, or
  focused helpers. Avoid nested loops unless they are the clearest way to express a necessary
  hierarchy after considering those alternatives, and verify they do not introduce accidental
  repeated scans.
- **No `static` for injectable concerns**: Don't use `static` helper classes for anything that touches configuration, logging, or external services. Inject an interface instead — keeps code testable and replaceable.

---

## 2. Naming Conventions

### 2.1 C# identifiers

| Concept | Casing | Example |
|---|---|---|
| Class | PascalCase | `OrderManager`, `OrderValidator` |
| Interface | PascalCase with `I` prefix | `IOrderManager` |
| Method | PascalCase | `GetById`, `ValidateCreate` |
| Async service/manager/data method | PascalCase + `Async` suffix | `GetByIdAsync`, `CreateAsync` |
| Property | PascalCase | `TotalCount`, `IsActive` |
| Private field | `_camelCase` | `_orderManager`, `_validator` |
| Local variable | camelCase | `orderId`, `pageResult` |
| Parameter | camelCase | `int orderId`, `OrderForCreate request` |
| Constant | PascalCase | `DefaultPageSize`, `MaxNameLength` |
| Enum type | PascalCase with `e` prefix | `eOrderStatus`, `eCalendarType` |
| Enum value | PascalCase | `eOrderStatus.Open`, `eOrderStatus.Closed` |

### 2.2 Domain type naming

| Concept | Pattern | Example |
|---|---|---|
| Manager interface | `I{Domain}Manager` | `IOrderManager` |
| Manager implementation | `{Domain}Manager` | `OrderManager` |
| Validator interface | `I{Domain}Validator` | `IOrderValidator` |
| Validator implementation | `{Domain}Validator` | `OrderValidator` |
| Mapper (internal) | `{Domain}Mapper` | `OrderMapper` |
| Response DTO | `{Entity}` | `Order`, `OrderSummary` |
| Create/update DTO (same payload) | `{Entity}ForUpsert` | `OrderForUpsert` |
| Create DTO (different payload) | `{Entity}ForCreate` | `OrderForCreate` |
| Update DTO (different payload) | `{Entity}ForUpdate` | `OrderForUpdate` |
| Filter DTO | `{Entity}Filter` | `OrderFilter` |
| Test class | `{Feature}UnitTest` or `{Feature}Tests` | `OrderManagerTests` |
| Test method | `{Method}_{Scenario}_Should{Expected}` | `Create_MissingName_ShouldThrow` |

---

## 3. C# Style

### 3.1 `var` usage

Use `var` when the type is obvious from the right-hand side. Use explicit types when the type is not immediately clear from context.

```csharp
var items = new List<Order>();          // obvious — use var
var result = mapper.ToDto(entity);      // obvious — use var
PageResult<Order> page = GetPage();     // not obvious — use explicit type
```

### 3.2 Other style preferences

- Prefer `=>` for single-expression methods and read-only properties; use a block for multiple
  statements.
- Prefer switch expressions and type patterns over equivalent `if`/`else if` chains.
- Prefer `using var` when end-of-scope disposal is appropriate; use a `using` block for earlier or
  visibly constrained disposal.

### 3.3 Throw-helper methods

Prefer built-in throw helpers when the target framework supports them and nearby code uses them.
Otherwise follow the project's established explicit guard style:

```csharp
ArgumentNullException.ThrowIfNull(request);
ArgumentOutOfRangeException.ThrowIfNegative(quantity);
ArgumentException.ThrowIfNullOrWhiteSpace(name);
```

---

## 4. REST API Controllers

### 4.1 Structure

- Prefer **primary constructor** injection when the project supports it and nearby controllers use it.
- Reuse the established base controller. Ensure `[ApiController]` and other shared metadata are
  declared either on that base or directly on the controller; do not duplicate inherited attributes.
- Follow the project's established authorization, tags, API explorer, and versioned-route shape.
- Prefer one primary manager for a cohesive controller, but allow additional class-level or
  action-scoped dependencies when its use cases require them.
- Group endpoints by resource cohesion and responsibility. Split when responsibilities diverge, not
  because of an arbitrary endpoint count.

```csharp
[Tags("Orders")]
[ApiExplorerSettings(GroupName = "v1")]
[Route("api/v1/orders")]
[Authorize]
public class OrdersApiController(IOrderManager orderManager) : AbstractApiController
{
    // endpoints
}
```

### 4.2 REST resource design

- Use **nouns** for resource paths, not verbs: `/orders`, not `/getOrders`.
- Nest sub-resources under their parent: `GET /orders/{orderId}/lines`.
- Use HTTP verbs semantically: `GET` reads, `POST` creates, `PUT` replaces or performs the project's
  established complete update, `PATCH` modifies part of a resource, and `DELETE` removes.
- Use kebab-case for multi-word path segments: `/order-lines`, not `/orderLines`.
- **Prefer single-resource endpoints**: Design update, delete, and create endpoints to act on one resource at a time. Batch operations are the exception, not the default.

### 4.3 Route name constants

Declare named route constants as private `const string` fields using `nameof()` to avoid stringly-typed references:

```csharp
private const string BaseRoute    = "Order";
private const string GetByIdRoute = $"{BaseRoute}_{nameof(GetById)}";
private const string CreateRoute  = $"{BaseRoute}_{nameof(Create)}";
```

### 4.4 Endpoint methods

- Controller methods are **thin**: binding → manager call → return. No business logic.
- Declare `[ProducesResponseType]` for the success response and every applicable endpoint-specific
  status, including 400, 404, and 500 according to project conventions. Document globally handled
  authentication, authorization, and middleware responses where the project's OpenAPI convention
  requires them.
- Use `[FromRoute]`, `[FromQuery]`, `[FromBody]` explicitly on every parameter.
- Apply type constraints on route segments: `{id:int}`, `{code:guid}`.

```csharp
[HttpGet("{id:int}", Name = GetByIdRoute)]
[ProducesResponseType(typeof(Order), StatusCodes.Status200OK)]
[ProducesResponseType(StatusCodes.Status404NotFound)]
[ProducesResponseType(typeof(ProblemDetails), StatusCodes.Status500InternalServerError)]
public async Task<ActionResult> GetById([FromRoute] int id)
{
    var item = await orderManager.GetAsync(id);
    return Ok(item);
}
```

### 4.5 HTTP verb → return type conventions

| Verb | Scenario | Return |
|---|---|---|
| GET (collection) | Paged list | `Ok(PageResult<T>)` — 200 |
| GET (single) | Found | `Ok(item)` — 200 |
| POST | Created | `CreatedAtRoute(GetByIdRoute, new { id }, item)` — 201 |
| PUT | Updated | `Ok(item)` — 200 |
| PATCH | Partially updated | `Ok(item)` — 200 |
| DELETE | Deleted | `NoContent()` — 204 |

### 4.6 Async/await *(preference, not a review blocker)*

- Where possible, prefer async endpoints and manager methods when the underlying data access supports it.
- Keep controller action names resource-oriented and without an `Async` suffix, even when they return
  `Task`. Suffix async manager, service, and data-access methods with `Async`.
- Synchronous implementations are fully acceptable. This preference does not constitute a code review failure.

---

## 5. Business / Manager Layer

### 5.1 One interface per manager

Every manager exposes a focused interface. The interface defines only what callers need — no internal helpers leak through.

```csharp
public interface IOrderManager
{
    Task<Order> GetAsync(int orderId, CancellationToken cancellationToken = default);
    Task<Order[]> FilterAsync(OrderFilter filter = null, CancellationToken cancellationToken = default);
    Task<PageResult<Order>> FilterAsync(OrderFilter filter, PageRequest paging, CancellationToken cancellationToken = default);
    Task<Order> CreateAsync(OrderForCreate request, CancellationToken cancellationToken = default);
    Task<Order> UpdateAsync(int orderId, OrderForUpdate request, CancellationToken cancellationToken = default);
    Task DeleteAsync(int orderId, CancellationToken cancellationToken = default);
}
```

### 5.2 Cancellation tokens *(preference, not a review blocker)*

Where async methods are used, passing `CancellationToken cancellationToken = default` as the last
parameter is encouraged. Forward it to downstream I/O calls. Follow an existing local signature's
parameter name; do not rename consumed parameters solely for consistency. Not required if async is
not yet adopted.

### 5.3 Short, focused public methods

Keep public methods linear and focused. A command commonly follows these relevant stages:

1. Validate inputs (delegate to validator)
2. Load or create the entity
3. Apply changes (delegate to mapper)
4. Persist and construct its result

Include only the stages the use case needs. Retrieval and computation methods should follow their
simplest coherent flow.

```csharp
public async Task<Order> CreateAsync(OrderForCreate request, CancellationToken cancellationToken = default)
{
    validator.ValidateCreate(request);

    var entity = BuildEntity(request);
    await SaveAsync(entity, cancellationToken);

    return mapper.ToDto(entity);
}
```

Decompose complex orchestration into focused private helpers, each handling one specific step. Private helpers must not be exposed through the interface.

### 5.4 Delegation over inline logic

| Responsibility | Delegate to |
|---|---|
| Input validation | `IXxxValidator` |
| Reusable entity ↔ DTO property mapping | The project's established mapper pattern |
| Complex sub-operations | Private methods with descriptive names |

- Managers own use-case output and may invoke dedicated mappers when constructing responses.
- Do not handwrite routine entity-to-DTO property copying inline in managers. Prefer the project's
  established mapping generator or mapper pattern when it expresses the mapping cleanly.
- Contextual aggregation and response orchestration may remain in the manager when they combine
  results or require business context; extract reusable property mapping.
- Validators validate inputs and business rules; they do not construct response DTOs.

### 5.5 Collection return contracts

Expose the narrowest contract callers need. Use `IReadOnlyList<T>` when callers should only read the
collection, and follow established project conventions such as arrays for materialized result DTOs.
Return `List<T>` only when caller mutation is intentionally part of the API. Arrays are fixed-size,
not immutable.

```csharp
Task<Order[]> FilterAsync(OrderFilter filter = null, CancellationToken cancellationToken = default);
```

---

## 6. Validation

- Each domain has its own `IXxxValidator` / `XxxValidator`.
- Validators enforce input and business preconditions, including relevant loaded domain state or
  prepared validation data. They may expose focused predicates used by that validation.
- Validators do not own persistence, use-case orchestration, or response construction.
- Validators can share a base class for common checks (max length, required, format).
- Throw typed domain exceptions (`BusinessException`, `NotFoundException`) — never embed user-facing message strings inline.

```csharp
public class OrderValidator : IOrderValidator
{
    public void ValidateCreate(OrderForCreate request)
    {
        ArgumentNullException.ThrowIfNull(request);

        if (string.IsNullOrWhiteSpace(request.Reference))
            throw new BusinessException("ORDER_REFERENCE_REQUIRED");

        if (request.Reference.Length > 100)
            throw new BusinessException("ORDER_REFERENCE_TOO_LONG");
    }
}
```

---

## 7. DTOs and Models

- **Separate request and response models**: response models expose what clients read; request models capture only what clients may send.
- Use `[Required]` data annotations on mandatory properties.
- Use `T?` for optional value types. For optional reference types, use `T?` only when the project
  enables nullable reference types; otherwise follow its established plain-reference and `null`
  conventions. Do not introduce `#nullable` or nullable-reference syntax locally without a
  project-level decision.
- Keep DTOs as shallow as the use case permits. Nest when the response is naturally hierarchical and
  every level is required by the consumer; do not expose or mirror a broad entity graph merely
  because those relationships exist.
- **Don't wrap a single value in a response object**: If an endpoint returns only one scalar value, return it directly. A wrapper DTO with a single property adds noise without benefit.

### 7.1 When to use ForUpsert vs ForCreate/ForUpdate

| Scenario | Recommendation |
|---|---|
| Create and update accept identical fields | Single `{Entity}ForUpsert` |
| Create and update differ (e.g. immutable fields on create) | Separate `{Entity}ForCreate` / `{Entity}ForUpdate` |

### 7.2 Paging

Use shared `PageRequest` (in, from query) and `PageResult<T>` (out) types consistently across all paged endpoints. Expose both a paged and an unpaged overload on the manager interface when callers may need either.

---

## 8. Performance

- Prevent algorithmic problems such as repeated linear searches inside loops. Pre-index data with a
  dictionary or lookup for repeated keyed access, and use a set for repeated membership checks.
- Prefer `TryGetValue` over `ContainsKey` followed by the dictionary indexer when one lookup is
  sufficient.
- Keep clear LINQ unless it causes repeated or expensive work, or the path is demonstrably hot.
  Optimize hot paths based on evidence rather than assumed allocation savings.
- Materialize an enumerable when a stable snapshot, multiple enumeration, or a query-execution
  boundary requires it. Avoid materializing solely to enumerate once.
- Use `StringBuilder` for substantial repeated concatenation; do not introduce it mechanically for
  small, simple loops.
- Choose collection types according to the public contract described above, not as an assumed
  micro-optimization.

- **Avoid `async void` except for genuine framework event handlers**: Callers cannot await these
  methods or directly observe their exceptions. Return `Task` for other asynchronous methods. In an
  event handler, catch or deliberately route exceptions through the application's established error
  handling.

---

## 9. Unit Tests

### 9.1 Coverage expectations

- Bug fixes must include a regression test when technically feasible.
- New manager, validator, mapper, and other testable behavior must cover its meaningful happy path,
  validation failures, and relevant not-found or edge cases.
- In review, flag missing required coverage unless a clear technical constraint makes it impractical.

### 9.2 Framework stack

- **xUnit** — test runner
- **Moq** — interface mocking
- **FluentAssertions** — assertions

### 9.3 Test method naming

```
{MethodUnderTest}_{Scenario}_Should{ExpectedOutcome}
```

Examples:
- `Create_MissingReference_ShouldThrowBusinessException`
- `Filter_NoResults_ShouldReturnEmptyPage`
- `Delete_ValidId_ShouldRemoveEntity`

### 9.4 Arrange-Act-Assert

Structure tests as Arrange–Act–Assert, normally separated by blank lines. Do not require phase-label
comments; comment only when a non-obvious setup or boundary needs explanation.

```csharp
[Fact]
public async Task Update_ChangedName_ShouldReturnUpdatedDto()
{
    var request = new OrderForUpdate { Name = "New" };

    var result = await manager.UpdateAsync(existingId, request);

    result.Name.Should().Be("New");
}
```

### 9.5 Builder pattern for test data

Use a builder or factory when repeated complex setup would otherwise obscure the test. Reuse the
project's established test-data pattern, keep helpers internal to the test project, and do not
introduce a builder abstraction for one-off setup.

### 9.6 Parameterized tests

Use `[Theory]` and the project's established data source when one behavior must be checked across
multiple inputs.

### 9.7 Fixtures for shared context

When tests share expensive setup such as a database context, use xUnit `ICollectionFixture<T>` rather
than repeating that setup in every test.

### 9.8 Test categorization

Use `[Trait("Category", "...")]` to allow selective CI runs.
