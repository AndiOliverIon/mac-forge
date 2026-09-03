# SQL Server Coding Guidelines

Rule-first standards for consistent, readable, and maintainable SQL Server development.

## 1. Naming Conventions

Apply the target naming conventions in this section to genuinely new database objects. When
altering or enriching an existing object, preserve its established name so current consumers remain
compatible. References to legacy names are not violations. Rename an existing object only when the
requested scope explicitly includes the rename and its consumers have been identified and handled.

### General naming

- Use PascalCase for tables, columns, and the descriptive portion of object names. For views,
  procedures, and functions, use the required lowercase prefix followed by a PascalCase descriptive
  name. Follow the explicit patterns below for indexes and constraints.
- Use descriptive, unambiguous names. Avoid abbreviations unless universally understood, such as
  `Id` and `Url`.
- New identifiers must not use reserved SQL keywords, spaces, or special characters.
- Use singular table names and no prefixes such as `tbl_`.
- Use PascalCase column names. Name primary keys `Id` and foreign keys after the referenced table
  followed by `Id`, such as `CustomerId`.
- Prefix boolean names by intent: `Is`, `Has`, `Can`, `Allow`, or `Requires`.
- Use `BIT NOT NULL` for true two-state values. Use nullable `BIT` only when unknown or not evaluated
  is a real domain state. Add a named default only when the domain defines a safe implicit value.

| Object | Convention | Example |
| --- | --- | --- |
| View | `vw` + PascalCase name | `vwActiveCustomer` |
| Stored procedure | `usp` + PascalCase name | `uspGetCustomerById` |
| Scalar function | `ufn` + PascalCase name | `ufnCalculateTax` |
| Table-valued function | `tvf` + PascalCase name | `tvfGetOrdersByDate` |
| Index | `IX_Table_Column` | `IX_Order_CustomerId` |
| Unique index | `UX_Table_Column` | `UX_Customer_Email` |
| Primary key | `PK_Table` | `PK_Customer` |
| Foreign key | `FK_Table_RefTable` | `FK_Order_Customer` |
| Default constraint | `DF_Table_Column` | `DF_Customer_IsActive` |

## 2. Formatting

- Write SQL keywords in uppercase.
- Indent with 4 spaces, never tabs.
- Start each major clause—`SELECT`, `FROM`, `JOIN`, `WHERE`, `GROUP BY`, `HAVING`, and
  `ORDER BY`—on a new line. Indent column lists and conditions one level below their clause.
- Place commas at the end of lines in multiline column lists.
- Put each `WHERE` condition on its own line with `AND` or `OR` at the beginning.
- Always use `AS` for table and column aliases. Keep table aliases short but meaningful, normally
  one to three characters derived from the table name.
- Use square brackets only for an existing reserved or space-containing name that cannot be changed,
  such as `[Order]`. Do not bracket ordinary identifiers.
- Terminate every statement with a semicolon.

```sql
SELECT
    c.Id,
    c.FirstName,
    c.LastName,
    po.CreatedAt
FROM Customer AS c
INNER JOIN ProductionOrder AS po
    ON po.CustomerId = c.Id
WHERE
    c.IsActive = 1
    AND po.CreatedAt >= '2024-01-01'
ORDER BY
    c.LastName,
    c.FirstName;
```

## 3. Data Types

Choose the appropriate and least storage-consuming type while following these project standards:

| Use case | Use | Avoid |
| --- | --- | --- |
| Primary and foreign keys | `INT` or `BIGINT` | `UNIQUEIDENTIFIER` unless required |
| Short strings | `NVARCHAR(n)` | `NCHAR`; `VARCHAR` for multilingual data |
| Long text | `NVARCHAR(MAX)` | `TEXT`, `NTEXT` (deprecated) |
| Boolean flags | `BIT NOT NULL` | `CHAR(1)`, `INT` |
| Date only | `DATE` | `DATETIME` |
| Date and time | `DATETIME2(7)` | `DATETIME`, `SMALLDATETIME` |
| Money and currency | `DECIMAL(18, 2)` | `MONEY`, `FLOAT` |
| GUID | `UNIQUEIDENTIFIER` | `CHAR(36)` |

- Explicitly declare every column `NULL` or `NOT NULL`.
- Use nullable `BIT` only for a meaningful third state and add a named default only when an implicit
  value is valid for the domain.
- Never use `FLOAT` or `REAL` for financial values; use `DECIMAL(18, 2)`.
- Name defaults with `DF_Table_Column` for genuinely new constraints.

```sql
CREATE TABLE Product
(
    Id INT NOT NULL IDENTITY(1, 1),
    Price DECIMAL(18, 2) NOT NULL
        CONSTRAINT DF_Product_Price DEFAULT (0),
    CreatedAt DATETIME2(7) NOT NULL
        CONSTRAINT DF_Product_CreatedAt DEFAULT (SYSDATETIME()),
    Description NVARCHAR(MAX) NULL,
    CONSTRAINT PK_Product PRIMARY KEY CLUSTERED (Id)
);
```

## 4. Queries

- Never use `SELECT *`; list only the required columns.
- Qualify columns with their table alias when joining multiple tables.
- Use explicit joins, never comma joins. Prefer `INNER JOIN` over bare `JOIN` and put each `ON`
  condition on its own indented line.
- Prefer a CTE over a deeply nested subquery when it improves readability.

```sql
WITH ActiveCustomer AS
(
    SELECT
        c.Id,
        c.Name
    FROM Customer AS c
    WHERE c.IsActive = 1
)
SELECT
    ac.Name,
    COUNT(po.Id) AS OrderCount
FROM ActiveCustomer AS ac
INNER JOIN ProductionOrder AS po
    ON po.CustomerId = ac.Id
GROUP BY
    ac.Name;
```

## 5. Stored Procedures and Functions

- Prefix stored procedures with `usp`, scalar functions with `ufn`, and table-valued functions with
  `tvf`.
- Start stored procedures with `SET NOCOUNT ON` and use `BEGIN` / `END` blocks.
- Prefix parameters with `@`, use PascalCase after it, and place each parameter on its own line.
  Provide sensible defaults where appropriate.
- Use explicit transactions only when multiple operations must commit atomically or deliberate
  concurrency control requires one. Do not wrap read-only procedures in explicit transactions by
  default.
- With an explicit transaction, enable `SET XACT_ABORT ON`, use `TRY` / `CATCH`, roll back when
  `XACT_STATE() <> 0`, and rethrow with `THROW`.
- Use `TRY` / `CATCH` without a transaction only for necessary cleanup or contextual error handling.
- Avoid dynamic SQL unless absolutely necessary. When necessary, parameterize it with
  `sp_executesql`.
- Scalar functions return one value; use them sparingly in `WHERE` clauses because they can harm
  performance. Table-valued functions return a result set and are preferred for that purpose.

```sql
CREATE PROCEDURE uspCompleteOrder
    @OrderId INT,
    @CompletedBy INT
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    BEGIN TRY
        BEGIN TRANSACTION;

        UPDATE ProductionOrder
        SET
            Status = 'Completed',
            CompletedAt = SYSDATETIME()
        WHERE Id = @OrderId;

        INSERT INTO OrderHistory
        (
            OrderId,
            EventType,
            CreatedBy
        )
        VALUES
        (
            @OrderId,
            'Completed',
            @CompletedBy
        );

        COMMIT TRANSACTION;
    END TRY
    BEGIN CATCH
        IF XACT_STATE() <> 0
        BEGIN
            ROLLBACK TRANSACTION;
        END;

        THROW;
    END CATCH;
END;
```

## 6. Indexing

- Every table should have a clustered index, normally on its primary key. Consider a date column
  instead for tables dominated by range queries on that date.
- Create non-clustered indexes for demonstrated query patterns involving `WHERE`, foreign-key joins,
  `ORDER BY`, or `GROUP BY`.
- Order composite keys according to the equality and join predicates, range predicates, and ordering
  of the supported queries. Equality and join keys generally precede range keys. Selectivity matters,
  but must not determine key order alone.
- Use `INCLUDE` for frequently returned non-key columns when it avoids key lookups for the supported
  query.
- Do not over-index; every index adds write overhead. Validate important indexes against
  representative execution plans and workload.
- Use `sys.dm_db_index_usage_stats` only to identify review candidates, never as the sole reason for
  removal. Confirm the observation window, server restart history, representative business cycles,
  execution plans, constraint dependencies, and known application, reporting, migration, and
  maintenance workloads.
- Avoid indexing low-cardinality columns such as `BIT` in isolation.
- Consider filtered indexes for columns with a dominant null or inactive value.

```sql
CREATE INDEX IX_ProductionOrder_CustomerIdCreatedAt
    ON ProductionOrder (CustomerId, CreatedAt DESC)
    INCLUDE (TotalAmount, IsActive);

CREATE INDEX IX_ProductionOrder_CustomerId_Active
    ON ProductionOrder (CustomerId)
    WHERE IsActive = 1;
```
