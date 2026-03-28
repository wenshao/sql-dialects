# Spanner: 约束

> 参考资料:
> - [Spanner SQL Reference (GoogleSQL)](https://cloud.google.com/spanner/docs/reference/standard-sql/query-syntax)
> - [Spanner - Functions](https://cloud.google.com/spanner/docs/reference/standard-sql/functions-and-operators)
> - [Spanner - Data Types](https://cloud.google.com/spanner/docs/reference/standard-sql/data-types)

**引擎定位**: Google 全球分布式数据库，TrueTime 外部一致性。基于 Colossus 存储，支持跨洲强一致事务。

## PRIMARY KEY (required on every table)


```sql
CREATE TABLE Users (
    UserId   INT64 NOT NULL,
    Username STRING(100) NOT NULL,
    Email    STRING(255) NOT NULL
) PRIMARY KEY (UserId);

```

Composite primary key
```sql
CREATE TABLE OrderItems (
    OrderId INT64 NOT NULL,
    ItemId  INT64 NOT NULL,
    Amount  NUMERIC
) PRIMARY KEY (OrderId, ItemId);

```

Note: Primary key is defined at table level, not column level
Note: Primary key cannot be changed after table creation
Note: Primary key determines physical data ordering

## NOT NULL


```sql
CREATE TABLE Orders (
    OrderId   INT64 NOT NULL,
    UserId    INT64 NOT NULL,
    Amount    NUMERIC,                         -- nullable by default
    OrderDate DATE NOT NULL
) PRIMARY KEY (OrderId);

```

Add NOT NULL
```sql
ALTER TABLE Users ALTER COLUMN Email STRING(255) NOT NULL;
```

Remove NOT NULL (allow NULL)
```sql
ALTER TABLE Users ALTER COLUMN Email STRING(255);

```

## UNIQUE


Unique constraints via UNIQUE INDEX
```sql
CREATE UNIQUE INDEX idx_users_email ON Users (Email);

```

NULL_FILTERED unique (NULLs are excluded from uniqueness)
```sql
CREATE UNIQUE NULL_FILTERED INDEX idx_users_phone ON Users (Phone);

```

## FOREIGN KEY


```sql
CREATE TABLE Orders2 (
    OrderId INT64 NOT NULL,
    UserId  INT64 NOT NULL,
    Amount  NUMERIC,
    CONSTRAINT fk_orders_user FOREIGN KEY (UserId) REFERENCES Users (UserId)
) PRIMARY KEY (OrderId);

```

ON DELETE CASCADE
```sql
CREATE TABLE OrderItems2 (
    OrderId INT64 NOT NULL,
    ItemId  INT64 NOT NULL,
    CONSTRAINT fk_items_order FOREIGN KEY (OrderId) REFERENCES Orders (OrderId)
        ON DELETE CASCADE
) PRIMARY KEY (OrderId, ItemId);

```

Add foreign key
```sql
ALTER TABLE Orders ADD CONSTRAINT fk_orders_user
    FOREIGN KEY (UserId) REFERENCES Users (UserId);

```

Drop foreign key
```sql
ALTER TABLE Orders DROP CONSTRAINT fk_orders_user;

```

Note: Only ON DELETE CASCADE and ON DELETE NO ACTION are supported
Note: ON UPDATE is not supported
Note: Foreign keys and INTERLEAVE serve different purposes

## CHECK constraints (2022+)


```sql
CREATE TABLE Accounts (
    AccountId INT64 NOT NULL,
    Balance   NUMERIC,
    Age       INT64,
    CONSTRAINT chk_balance CHECK (Balance >= 0),
    CONSTRAINT chk_age CHECK (Age >= 0 AND Age <= 150)
) PRIMARY KEY (AccountId);

ALTER TABLE Users ADD CONSTRAINT chk_status CHECK (Status IN (0, 1, 2));
ALTER TABLE Users DROP CONSTRAINT chk_status;

```

## DEFAULT values (2023+)


```sql
CREATE TABLE Defaults (
    Id        INT64 NOT NULL,
    Status    INT64 NOT NULL DEFAULT (0),
    CreatedAt TIMESTAMP DEFAULT (CURRENT_TIMESTAMP())
) PRIMARY KEY (Id);

ALTER TABLE Users ALTER COLUMN Status SET DEFAULT (1);

```

## INTERLEAVE (parent-child co-location constraint)


Not a traditional constraint but enforces referential integrity
```sql
CREATE TABLE OrderItems3 (
    OrderId INT64 NOT NULL,
    ItemId  INT64 NOT NULL
) PRIMARY KEY (OrderId, ItemId),
  INTERLEAVE IN PARENT Orders ON DELETE CASCADE;
```

ON DELETE CASCADE or ON DELETE NO ACTION

## Not supported


EXCLUDE constraints: not supported
UNIQUE as column-level constraint: use UNIQUE INDEX instead
Partial unique constraints: not supported
Deferrable constraints: not supported

View constraints
```sql
SELECT * FROM INFORMATION_SCHEMA.TABLE_CONSTRAINTS WHERE TABLE_NAME = 'Users';
SELECT * FROM INFORMATION_SCHEMA.REFERENTIAL_CONSTRAINTS;
SELECT * FROM INFORMATION_SCHEMA.CHECK_CONSTRAINTS;

```

Note: PRIMARY KEY is required on every table and cannot be altered
Note: Use UNIQUE INDEX for unique constraints
Note: INTERLEAVE provides both co-location and referential integrity
Note: Foreign key ON UPDATE actions are not supported
Note: All constraints are enforced (no informational-only mode)
