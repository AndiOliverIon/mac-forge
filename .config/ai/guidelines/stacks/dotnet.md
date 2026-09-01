# Coding Guidelines — ASP.NET Core REST API + Business Layer

> Generic, project-agnostic rules. Intended as a living reference.

---

## 1. General Principles

- **SOLID**: Every class has one reason to change. Split when a second responsibility appears.
- **Small methods**: Public methods should fit on screen (~5–30 lines). Extract private helpers when logic grows.
- **Meaningful, short names**: Names should state intent without abbreviation or redundancy. Avoid `Manager2`, `HandleStuff`, `DoProcess`.
- **No comments for the obvious**: Only comment when the *why* is non-obvious — a hidden constraint, a quirk, a workaround. Never describe what the code already says.
- **No over-engineering**: Don't introduce abstractions for hypothetical future needs. Three similar lines beat a premature helper.
- **Avoid deep nesting**: Deep `if`/`else` chains and nested `foreach` loops are a readability smell. Flatten with early returns, guard clauses, or extracted helper methods.
- **No `static` for injectable concerns**: Don't use `static` helper classes for anything that touches configuration, logging, or external services. Inject an interface instead — keeps code testable and replaceable.

---

## 2. Naming Conventions

### 2.1 C# identifiers

| Concept | Casing | Example |
|---|---|---|
| Class | PascalCase | `OrderManager`, `OrderValidator` |
| Interface | PascalCase with `I` prefix | `IOrderManager` |
| Method | PascalCase | `GetById`, `ValidateCreate` |
| Async method | PascalCase + `Async` suffix | `GetByIdAsync`, `CreateAsync` |
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

### 3.2 Expression-body members

Prefer `=>` for single-expression methods and read-only properties. Use block bodies when more than one statement is needed.

```csharp
public int Total => Items.Sum(i => i.Quantity);
public Order ToDto(OrderEntity e) => mapper.ToDto(e);
```

### 3.3 Pattern matching

Prefer `switch` expressions and `is` type patterns over chains of `if`/`else if` on types or values.

```csharp
// Preferred
var label = status switch
{
    eOrderStatus.Open   => "Open",
    eOrderStatus.Closed => "Closed",
    _                   => "Unknown"
};
```

### 3.4 `using` declarations

Use the no-brace `using var` form for disposable resources. Same deterministic disposal, less indentation.

```csharp
using var stream = File.OpenRead(path);
```

### 3.5 Throw-helper methods

Prefer built-in throw helpers over manual null/range checks:

```csharp
ArgumentNullException.ThrowIfNull(request);
ArgumentOutOfRangeException.ThrowIfNegative(quantity);
ArgumentException.ThrowIfNullOrWhiteSpace(name);
```

---

## 4. REST API Controllers

### 4.1 Structure

- Use **primary constructor** injection (C# 12). Inject one manager interface per controller.
- Declare `[ApiController]`, `[Authorize]`, `[Route("api/v{version}/...")]`, and a `[Tags("...")]` group at class level.
- Group related endpoints into one controller when the resource is cohesive; split when a controller would otherwise exceed ~5–6 endpoints.

```csharp
[Tags("Orders")]
[ApiExplorerSettings(GroupName = "v1")]
[Route("api/v1/orders")]
[Authorize]
public class OrdersApiController(IOrderManager orderManager) : ControllerBase
{
    // endpoints
}
```

### 4.2 REST resource design

- Use **nouns** for resource paths, not verbs: `/orders`, not `/getOrders`.
- Nest sub-resources under their parent: `GET /orders/{orderId}/lines`.
- Use HTTP verbs semantically: `GET` reads, `POST` creates, `PUT` replaces/updates, `DELETE` removes.
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
- Always declare `[ProducesResponseType]` for every possible status code, including 400, 404 and 500.
- Use `[FromRoute]`, `[FromQuery]`, `[FromBody]` explicitly on every parameter.
- Apply type constraints on route segments: `{id:int}`, `{code:guid}`.

```csharp
[HttpGet("{id:int}", Name = GetByIdRoute)]
[ProducesResponseType(typeof(Order), StatusCodes.Status200OK)]
[ProducesResponseType(StatusCodes.Status404NotFound)]
[ProducesResponseType(typeof(ProblemDetails), StatusCodes.Status500InternalServerError)]
public async Task<ActionResult> GetByIdAsync([FromRoute] int id)
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
| DELETE | Deleted | `NoContent()` — 204 |

### 4.6 Async/await *(preference, not a review blocker)*

- Where possible, prefer async endpoints and manager methods when the underlying data access supports it.
- When async, suffix method names with `Async`: `GetByIdAsync`, `CreateAsync`.
- Synchronous implementations are fully acceptable. This preference does not constitute a code review failure.

---

## 5. Business / Manager Layer

### 5.1 One interface per manager

Every manager exposes a focused interface. The interface defines only what callers need — no internal helpers leak through.

```csharp
public interface IOrderManager
{
    Task<Order> GetAsync(int orderId, CancellationToken ct = default);
    Task<Order[]> FilterAsync(OrderFilter filter = null, CancellationToken ct = default);
    Task<PageResult<Order>> FilterAsync(OrderFilter filter, PageRequest paging, CancellationToken ct = default);
    Task<Order> CreateAsync(OrderForCreate request, CancellationToken ct = default);
    Task<Order> UpdateAsync(int orderId, OrderForUpdate request, CancellationToken ct = default);
    Task DeleteAsync(int orderId, CancellationToken ct = default);
}
```

### 5.2 Cancellation tokens *(preference, not a review blocker)*

Where async methods are used, passing `CancellationToken ct = default` as the last parameter is encouraged. Forward it to all downstream I/O calls. The default value keeps callers that don't opt in unaffected. Not required if async is not yet adopted.

### 5.3 Short, focused public methods

Public methods should follow a clear, linear flow:

1. Validate inputs (delegate to validator)
2. Load or create the entity
3. Apply changes (delegate to mapper)
4. Persist and return DTO

```csharp
public async Task<Order> CreateAsync(OrderForCreate request, CancellationToken ct = default)
{
    validator.ValidateCreate(request);

    var entity = BuildEntity(request);
    await SaveAsync(entity, ct);

    return mapper.ToDto(entity);
}
```

Decompose complex orchestration into focused private helpers, each handling one specific step. Private helpers must not be exposed through the interface.

### 5.4 Delegation over inline logic

| Responsibility | Delegate to |
|---|---|
| Input validation | `IXxxValidator` |
| Entity ↔ DTO mapping | `XxxMapper` |
| Complex sub-operations | Private methods with descriptive names |

- **Never map inside a manager**: Mapping between entities and DTOs belongs in a dedicated `XxxMapper` class. Inline mapping in manager methods mixes concerns and makes both harder to test.

### 5.5 Immutable return types for collections

Return `IReadOnlyList<T>` or `T[]` from public methods and interfaces rather than `List<T>`. Signals to callers that the result is not meant to be mutated.

```csharp
Task<Order[]> FilterAsync(OrderFilter filter = null, CancellationToken ct = default);
```

---

## 6. Validation

- Each domain has its own `IXxxValidator` / `XxxValidator`.
- Validators are responsible for **validating incoming request DTOs** — field presence, format, and business constraints on input.
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
- Use nullable types (`int?`, `string?`) for optional fields.
- Flatten: avoid nesting DTOs deeper than one level.
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

- **Use `Dictionary<TKey, TValue>` for repeated key lookups**: Build a dictionary upfront when looking up items by key more than once. Avoid `.FirstOrDefault(x => x.Id == id)` inside loops — that is O(n²).

- **Prefer `TryGetValue` over `ContainsKey` + indexer**: `dict.TryGetValue(key, out var val)` is a single lookup. `ContainsKey` followed by `dict[key]` performs the lookup twice.

- **Avoid LINQ inside tight loops**: LINQ allocates enumerators and closures. For hot paths, prefer `for`/`foreach` with direct indexing.

- **Use `HashSet<T>` for membership tests**: When the question is "does this id exist in a set", use `HashSet<T>` — O(1) — instead of `.Contains()` on a `List<T>` — O(n).

- **Prefer `T[]` over `List<T>` for fixed-size results**: When the size is known at construction time (e.g. `.Select(...).ToArray()`), prefer arrays. `List<T>` carries resize overhead and signals mutability you don't intend.

- **Use `StringBuilder` for string concatenation in loops**: String concatenation with `+` inside a loop allocates a new string per iteration. Use `StringBuilder` or build the string once outside the loop.

- **Avoid unnecessary `ToList()` / `ToArray()`**: Don't materialise a collection just to `foreach` over it once. Operate on `IEnumerable<T>` directly when you don't need random access or multiple iterations.

- **Be explicit about deferred LINQ execution**: LINQ queries are lazy. If a query is consumed more than once, materialise it with `.ToArray()` to avoid re-evaluating it. If consumed once, leave it lazy.

- **Avoid `async void`**: `async void` methods swallow exceptions and cannot be awaited. Use `async Task` even for fire-and-forget scenarios; catch exceptions explicitly inside.

---

## 9. Unit Tests

### 9.1 Coverage expectations

Code coverage is a shared responsibility, not an afterthought.

- **Bug fixes** — by preference and where technically feasible, every bug fix should include a regression test that reproduces the failure before the fix and passes after. This prevents the same bug from silently reappearing.
- **New functionality** — unit tests are strongly expected for all new manager methods, validators, and mappers. A feature is not considered complete without test coverage of its happy path, its validation failures, and its not-found/edge cases.

These are not optional suggestions. PRs for new functionality without tests, or bug fixes without regression tests where a test is clearly feasible, should be flagged in code review.

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

Every test follows strict AAA with blank-line separation:

```csharp
[Fact]
public async Task Update_ChangedName_ShouldReturnUpdatedDto()
{
    // arrange
    var request = new OrderForUpdate { Name = "New" };

    // act
    var result = await manager.UpdateAsync(existingId, request);

    // assert
    result.Name.Should().Be("New");
}
```

### 9.5 Builder pattern for test data

Use a fluent builder for complex test objects. Keep builders internal to the test project.

```csharp
internal class OrderBuilder : AbstractBuilder<Order>
{
    public static OrderBuilder Init(int id, string reference) =>
        new OrderBuilder().WithId(id).WithReference(reference);

    public OrderBuilder WithId(int value) =>
        SetValue<OrderBuilder>(o => o.Id = value);

    public OrderBuilder WithReference(string value) =>
        SetValue<OrderBuilder>(o => o.Reference = value);
}

// Usage
var order = OrderBuilder.Init(1, "REF-001").WithStatus(eOrderStatus.Open).Build();
```

### 9.6 Mocking with Moq

```csharp
private readonly Mock<IOrderValidator> _validatorMock = new();

_validatorMock.Setup(v => v.ValidateCreate(It.IsAny<OrderForCreate>()));
```

### 9.7 Parameterized tests

```csharp
[Theory]
[InlineData(null)]
[InlineData("")]
public async Task Create_InvalidReference_ShouldThrow(string reference)
{
    var request = new OrderForCreate { Reference = reference };
    var act = () => manager.CreateAsync(request);

    await act.Should().ThrowAsync<BusinessException>();
}
```

### 9.8 Fixtures for shared context

When tests share expensive setup (e.g. a DB context), use xUnit `ICollectionFixture<T>` rather than repeating setup in every test:

```csharp
[CollectionDefinition(nameof(DbCollection))]
public class DbCollection : ICollectionFixture<DbFixture> { }

[Collection(nameof(DbCollection))]
public class OrderIntegrationTests(DbFixture fixture) { ... }
```

### 9.9 Test categorization

Use `[Trait("Category", "...")]` to allow selective CI runs:

```csharp
[Trait("Category", "Orders.Manager")]
[Fact]
public async Task Create_ValidRequest_ShouldReturnDto() { ... }
```

---

## 10. Checklist — Before Merging

- [ ] Each public method is ≤ ~30 lines
- [ ] No business logic in controllers — controllers only bind and delegate
- [ ] Validator class covers all mandatory fields and constraints on incoming request DTOs
- [ ] Unit tests cover: happy path, missing required field, not-found scenario
- [ ] Bug fix includes a regression test (where technically feasible)
- [ ] New functionality includes unit tests for happy path, validation failures, and edge cases
- [ ] Test method names follow `Method_Scenario_ShouldExpected`
- [ ] `[ProducesResponseType]` declared for all expected HTTP status codes
- [ ] Request and response DTOs are separate types
- [ ] If async is used: methods carry the `Async` suffix and ideally accept `CancellationToken`
- [ ] No comments that describe *what* — only *why* when non-obvious
- [ ] No deep nesting — guard clauses used instead