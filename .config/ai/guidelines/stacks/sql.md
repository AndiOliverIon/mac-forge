# SQL Server Coding Guidelines

This document defines the coding standards and best practices for all SQL Server development.
Developers are expected to follow these guidelines to ensure consistency, readability, and maintainability across the codebase.

---

## 1. Naming Conventions

### General Rules

- Use **PascalCase** for all identifiers: tables, columns, views, procedures, functions, and indexes.
- Names must be descriptive and unambiguous.
- Avoid abbreviations unless they are universally understood (e.g., `Id`, `Url`).
- Never use reserved SQL keywords as identifiers.
- Never use spaces or special characters in names.

### Tables

- Use **singular** names — a table represents an entity, not a collection.
- Do not use prefixes like `tbl_`.

```sql
-- ✅ Correct
Customer
OrderLine
ProductCategory

-- ❌ Incorrect
Customers
tbl_OrderLines
product_category
```

### Columns

- Use PascalCase for all column names.
- Primary keys should be named `Id`.
- Foreign keys should be named after the referenced table followed by `Id`.

```sql
-- ✅ Correct
Id
Name
FirstName
LastName
CustomerId       -- FK referencing Customer.Id
ProductCategoryId

-- ❌ Incorrect
id
customer_id
FIRST_NAME
fkCustomer
```

### Boolean Fields

Boolean (BIT) columns must use a meaningful prefix to make their intent immediately clear:

| Prefix | Example |
|--------|---------|
| `Is`   | `IsActive`, `IsDeleted`, `IsVerified` |
| `Has`  | `HasDiscount`, `HasChildren` |
| `Can`  | `CanEdit`, `CanLogin` |
| `Allow` | `AllowNotification` |
| `Requires` | `RequiresApproval` |

```sql
-- ✅ Correct
IsActive        BIT NOT NULL DEFAULT 1,
HasDiscount     BIT NOT NULL DEFAULT 0,
CanLogin        BIT NOT NULL DEFAULT 1,

-- ❌ Incorrect
Active          BIT,
Discount        BIT,
LoginFlag       BIT,
```

### Other Object Naming

| Object | Convention | Example |
|--------|-----------|---------|
| View | `vw` prefix | `vwActiveCustomer` |
| Stored Procedure | `usp` prefix | `uspGetCustomerById` |
| Scalar Function | `ufn` prefix | `ufnCalculateTax` |
| Table-Valued Function | `tvf` prefix | `tvfGetOrdersByDate` |
| Index | `IX_Table_Column` | `IX_Order_CustomerId` |
| Unique Index | `UX_Table_Column` | `UX_Customer_Email` |
| Primary Key | `PK_Table` | `PK_Customer` |
| Foreign Key | `FK_Table_RefTable` | `FK_Order_Customer` |
| Default Constraint | `DF_Table_Column` | `DF_Customer_IsActive` |

---

## 2. Formatting & Indentation

### Keywords

All SQL keywords must be written in **UPPERCASE**.

```sql
SELECT, FROM, WHERE, JOIN, ON, AND, OR, NOT, IN,
INSERT, UPDATE, DELETE, CREATE, ALTER, DROP,
GROUP BY, ORDER BY, HAVING, WITH, AS, CASE, WHEN, THEN, END
```

### Indentation

- Use **4 spaces** per indentation level. Do not use tabs.
- Each major clause (`SELECT`, `FROM`, `WHERE`, `JOIN`, `GROUP BY`, etc.) starts on a new line.
- Column lists and conditions are indented one level under their clause.

```sql
-- ✅ Correct
SELECT
    c.Id,
    c.FirstName,
    c.LastName,
    o.Id AS OrderId,
    o.CreatedAt
FROM Customer AS c
INNER JOIN [Order] AS o
    ON o.CustomerId = c.Id
WHERE
    c.IsActive = 1
    AND o.CreatedAt >= '2024-01-01'
ORDER BY
    c.LastName,
    c.FirstName;

-- ❌ Incorrect
select c.Id, c.FirstName, c.LastName, o.Id as OrderId, o.CreatedAt from Customer c inner join [Order] o on o.CustomerId=c.Id where c.IsActive=1 and o.CreatedAt>='2024-01-01'
```

### Commas

Place commas **at the beginning** of each new line in column lists. This makes it easier to comment out individual columns and spot errors.

```sql
-- ✅ Correct
SELECT
    c.Id
    ,c.FirstName
    ,c.LastName
    ,c.Email

-- Also acceptable (trailing commas)
SELECT
    c.Id,
    c.FirstName,
    c.LastName,
    c.Email
```

> Pick one style and apply it **consistently** across the entire project.

### Aliases

- Always use the `AS` keyword when aliasing columns or tables.
- Table aliases should be short but meaningful (typically 1–3 characters based on the table name).

```sql
-- ✅ Correct
SELECT
    c.FirstName AS CustomerFirstName,
    p.Name AS ProductName
FROM Customer AS c
INNER JOIN Product AS p ON p.Id = ol.ProductId

-- ❌ Incorrect
SELECT c.FirstName CustomerFirstName
FROM Customer c
```

### Brackets

- Wrap object names in square brackets `[ ]` only when the name is a reserved word or contains spaces.
- Do not use brackets on regular identifiers — it adds noise.

```sql
-- ✅ Use brackets only when necessary
FROM [Order]       -- 'Order' is a reserved word
FROM Customer      -- no brackets needed

-- ❌ Unnecessary brackets
FROM [Customer]
SELECT [Id], [Name]
```

### Semicolons

Always terminate statements with a semicolon `;`. This is required for CTEs and considered best practice generally.

---

## 3. Data Types

Choose the most appropriate and least storage-consuming data type for each column.

### Recommended Types

| Use Case | Recommended Type | Avoid |
|----------|-----------------|-------|
| Primary / Foreign Keys | `INT` or `BIGINT` | `UNIQUEIDENTIFIER` unless required |
| Short strings (codes, etc.) | `NVARCHAR(n)` | `NCHAR`, `VARCHAR` for multilingual data |
| Long text | `NVARCHAR(MAX)` | `TEXT`, `NTEXT` (deprecated) |
| Boolean flags | `BIT NOT NULL` | `CHAR(1)`, `INT` |
| Dates only | `DATE` | `DATETIME` |
| Date and time | `DATETIME2(7)` | `DATETIME`, `SMALLDATETIME` |
| Money / Currency | `DECIMAL(18, 2)` | `MONEY`, `FLOAT` |
| Identifiers (GUID) | `UNIQUEIDENTIFIER` | `CHAR(36)` |

### Rules

- Always define `NOT NULL` or `NULL` explicitly on every column — never rely on defaults.
- Boolean columns must always be `BIT NOT NULL` with a `DEFAULT` constraint.
- Never use `FLOAT` or `REAL` for financial values — use `DECIMAL`.

```sql
-- ✅ Correct
IsActive        BIT          NOT NULL DEFAULT 1,
Price           DECIMAL(18, 2) NOT NULL DEFAULT 0,
CreatedAt       DATETIME2(7) NOT NULL DEFAULT SYSDATETIME(),
Description     NVARCHAR(MAX) NULL,

-- ❌ Incorrect
IsActive        INT,
Price           FLOAT,
CreatedAt       DATETIME,
Description     TEXT
```

---

## 4. Queries

### SELECT

- Never use `SELECT *`. Always list the columns you need explicitly.
- Always qualify column references with the table alias when joining multiple tables.

```sql
-- ✅ Correct
SELECT
    c.Id,
    c.Name,
    o.CreatedAt
FROM Customer AS c
INNER JOIN [Order] AS o ON o.CustomerId = c.Id;

-- ❌ Incorrect
SELECT * FROM Customer;
```

### JOINs

- Always use explicit `JOIN` syntax — never implicit comma joins.
- Prefer `INNER JOIN` over `JOIN` for clarity.
- Put the `ON` condition on its own indented line.

```sql
-- ✅ Correct
FROM [Order] AS o
INNER JOIN Customer AS c
    ON c.Id = o.CustomerId
LEFT JOIN Address AS a
    ON a.Id = c.AddressId

-- ❌ Incorrect
FROM [Order] o, Customer c WHERE o.CustomerId = c.Id
```

### WHERE Conditions

- Place each condition on its own line.
- Put the `AND` / `OR` operator at the beginning of the line.

```sql
WHERE
    c.IsActive = 1
    AND o.CreatedAt >= '2024-01-01'
    AND o.TotalAmount > 100;
```

### CTEs (Common Table Expressions)

Prefer CTEs over deeply nested subqueries for readability.

```sql
WITH ActiveCustomer AS (
    SELECT
        Id,
        Name,
        Email
    FROM Customer
    WHERE IsActive = 1
)
SELECT
    ac.Name,
    COUNT(o.Id) AS OrderCount
FROM ActiveCustomer AS ac
INNER JOIN [Order] AS o ON o.CustomerId = ac.Id
GROUP BY ac.Name;
```

---

## 5. Stored Procedures & Functions

### General Rules

- Prefix stored procedures with `usp` and functions with `ufn` / `tvf`.
- Always include `SET NOCOUNT ON` at the start of stored procedures.
- Always use `BEGIN` / `END` blocks.
- Always handle errors using `TRY` / `CATCH` with transaction management.
- Never use dynamic SQL unless absolutely necessary. If used, always parameterize with `sp_executesql`.

### Stored Procedure Template

```sql
CREATE PROCEDURE uspGetOrderByCustomerId
    @CustomerId INT,
    @IsActive   BIT = 1
AS
BEGIN
    SET NOCOUNT ON;

    BEGIN TRY
        BEGIN TRANSACTION;

        SELECT
            o.Id,
            o.CreatedAt,
            o.TotalAmount
        FROM [Order] AS o
        WHERE
            o.CustomerId = @CustomerId
            AND o.IsActive = @IsActive;

        COMMIT TRANSACTION;
    END TRY
    BEGIN CATCH
        IF @@TRANCOUNT > 0
            ROLLBACK TRANSACTION;

        THROW;
    END CATCH;
END;
```

### Functions

- **Scalar functions** return a single value. Use sparingly in `WHERE` clauses as they can cause performance issues.
- **Table-valued functions (TVF)** return a result set and should be preferred over scalar functions when returning data.

```sql
-- Scalar function
CREATE FUNCTION ufnCalculateTax
(
    @Amount     DECIMAL(18, 2),
    @TaxRate    DECIMAL(5, 4)
)
RETURNS DECIMAL(18, 2)
AS
BEGIN
    RETURN @Amount * @TaxRate;
END;

-- Table-valued function
CREATE FUNCTION tvfGetOrdersByDateRange
(
    @StartDate  DATE,
    @EndDate    DATE
)
RETURNS TABLE
AS
RETURN
(
    SELECT
        o.Id,
        o.CustomerId,
        o.CreatedAt,
        o.TotalAmount
    FROM [Order] AS o
    WHERE o.CreatedAt BETWEEN @StartDate AND @EndDate
);
```

### Parameters

- Prefix parameter names with `@`.
- Use PascalCase after the `@`: `@CustomerId`, `@IsActive`.
- Always provide sensible defaults where appropriate.
- Place each parameter on its own line.

---

## 6. Indexing Strategies

### Naming

Follow the naming conventions defined in Section 1:

```sql
-- Primary Key
CONSTRAINT PK_Customer PRIMARY KEY (Id)

-- Index
CREATE INDEX IX_Order_CustomerId ON [Order] (CustomerId);

-- Unique Index
CREATE UNIQUE INDEX UX_Customer_Email ON Customer (Email);
```

### Clustered Index

- Every table should have a clustered index, typically on the primary key (`Id`).
- For tables with heavy range queries on a date column, consider the date column as the clustered index.

```sql
-- Default: cluster on primary key
CREATE TABLE [Order] (
    Id          INT          NOT NULL IDENTITY(1,1),
    CustomerId  INT          NOT NULL,
    CreatedAt   DATETIME2(7) NOT NULL DEFAULT SYSDATETIME(),
    IsActive    BIT          NOT NULL DEFAULT 1,
    CONSTRAINT PK_Order PRIMARY KEY CLUSTERED (Id)
);
```

### Non-Clustered Indexes

Create non-clustered indexes on columns that are:
- Frequently used in `WHERE` clauses.
- Foreign key columns used in `JOIN` conditions.
- Columns used in `ORDER BY` or `GROUP BY`.

```sql
-- Index on FK column
CREATE INDEX IX_Order_CustomerId
    ON [Order] (CustomerId);

-- Composite index (leading column = most selective)
CREATE INDEX IX_Order_CustomerIdCreatedAt
    ON [Order] (CustomerId, CreatedAt DESC);
```

### Include Columns

Use `INCLUDE` to add non-key columns to an index when they are frequently selected alongside the indexed column, avoiding key lookups.

```sql
CREATE INDEX IX_Order_CustomerId
    ON [Order] (CustomerId)
    INCLUDE (CreatedAt, TotalAmount, IsActive);
```

### Guidelines

- Do not over-index. Every index has a write overhead — only add indexes that address a real query pattern.
- Regularly review and remove unused indexes using `sys.dm_db_index_usage_stats`.
- Avoid indexing low-cardinality columns (e.g., `BIT` columns) in isolation.
- Consider **filtered indexes** for columns with a dominant null or inactive value.

```sql
-- Filtered index: only index active orders
CREATE INDEX IX_Order_CustomerId_Active
    ON [Order] (CustomerId)
    WHERE IsActive = 1;
```

---

*Last updated: April 2026*