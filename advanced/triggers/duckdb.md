# DuckDB: 触发器

> 参考资料:
> - [DuckDB - SQL Reference](https://duckdb.org/docs/sql/introduction)
> - [DuckDB - Functions](https://duckdb.org/docs/sql/functions/overview)
> - [DuckDB - Data Types](https://duckdb.org/docs/sql/data_types/overview)

**引擎定位**: 嵌入式 OLAP 分析引擎，类似 SQLite 的定位。列式存储 + 向量化执行，PostgreSQL 兼容语法。

```sql
CREATE VIEW users_with_age_group AS
SELECT *,
    CASE
        WHEN age < 18 THEN 'minor'
        WHEN age < 65 THEN 'adult'
        ELSE 'senior'
    END AS age_group
FROM users;

```

## Generated columns (instead of trigger-computed values)

```sql
CREATE TABLE products (
    price    DECIMAL(10,2),
    quantity INTEGER,
    total    DECIMAL(10,2) GENERATED ALWAYS AS (price * quantity)
);

```

## CHECK constraints (instead of validation triggers)

```sql
CREATE TABLE users (
    id       BIGINT PRIMARY KEY,
    age      INTEGER CHECK (age >= 0 AND age <= 200),
    email    VARCHAR CHECK (email LIKE '%@%'),
    status   INTEGER CHECK (status IN (0, 1, 2))
);

```

## CTE-based audit pattern (manual, per-operation)

```sql
WITH inserted AS (
    INSERT INTO users (username, email) VALUES ('alice', 'alice@example.com') RETURNING *
)
INSERT INTO audit_log (table_name, action, record_id, timestamp)
SELECT 'users', 'INSERT', id, NOW() FROM inserted;

```

## CREATE OR REPLACE TABLE for bulk transformations

Instead of trigger-based data transformation:
```sql
CREATE OR REPLACE TABLE users AS
SELECT *,
    LOWER(email) AS normalized_email,
    NOW() AS updated_at
FROM users;

```

## Macros for enforcing business rules

```sql
CREATE MACRO safe_insert_user(p_username, p_email, p_age) AS TABLE
    SELECT CASE
        WHEN p_age < 0 OR p_age > 200 THEN error('Invalid age')
        WHEN p_email NOT LIKE '%@%' THEN error('Invalid email')
        ELSE 1
    END;
```

Use before inserting: SELECT * FROM safe_insert_user('alice', 'alice@example.com', 25);

Note: DuckDB has no CREATE TRIGGER statement
Note: DuckDB is designed for analytics, not OLTP with event-driven logic
Note: Use application code for trigger-like behavior
Note: Generated columns and CHECK constraints replace some trigger use cases
Note: For audit logging, use CTE + RETURNING pattern or application middleware
Note: For auto-updated timestamps, handle in the application layer
