# DuckDB: 存储过程

> 参考资料:
> - [DuckDB - SQL Reference](https://duckdb.org/docs/sql/introduction)
> - [DuckDB - Functions](https://duckdb.org/docs/sql/functions/overview)
> - [DuckDB - Data Types](https://duckdb.org/docs/sql/data_types/overview)

**引擎定位**: 嵌入式 OLAP 分析引擎，类似 SQLite 的定位。列式存储 + 向量化执行，PostgreSQL 兼容语法。

```sql
CREATE MACRO add(a, b) AS a + b;
SELECT add(3, 5);                                      -- 8

```

Macro with default parameters
```sql
CREATE MACRO greet(name, greeting := 'Hello') AS greeting || ' ' || name;
SELECT greet('Alice');                                  -- 'Hello Alice'
SELECT greet('Alice', 'Hi');                            -- 'Hi Alice'

```

Macro with CASE expression
```sql
CREATE MACRO classify_age(age) AS
    CASE
        WHEN age < 18 THEN 'minor'
        WHEN age < 65 THEN 'adult'
        ELSE 'senior'
    END;
SELECT classify_age(25);                               -- 'adult'

```

## Table macros (return tables, v0.9+)

```sql
CREATE MACRO active_users(min_age) AS TABLE
    SELECT * FROM users WHERE status = 1 AND age >= min_age;
SELECT * FROM active_users(25);

```

Table macro with multiple parameters
```sql
CREATE MACRO user_orders(uid, min_amount := 0) AS TABLE
    SELECT u.username, o.amount
    FROM users u
    JOIN orders o ON u.id = o.user_id
    WHERE u.id = uid AND o.amount >= min_amount;
SELECT * FROM user_orders(1, 100);

```

## CREATE OR REPLACE MACRO

```sql
CREATE OR REPLACE MACRO add(a, b) AS a + b;

```

## Drop macro

```sql
DROP MACRO add;
DROP MACRO IF EXISTS add;
DROP MACRO active_users;

```

## Parameterized queries with PREPARE / EXECUTE

```sql
PREPARE get_user AS SELECT * FROM users WHERE id = $1;
EXECUTE get_user(42);

PREPARE insert_user AS
    INSERT INTO users (username, email) VALUES ($1, $2);
EXECUTE insert_user('alice', 'alice@example.com');

```

Deallocate prepared statement
```sql
DEALLOCATE get_user;

```

## Script-like patterns using CTEs

Instead of procedures with logic, chain CTEs:
```sql
WITH
step1 AS (
    SELECT user_id, SUM(amount) AS total FROM orders GROUP BY user_id
),
step2 AS (
    SELECT u.*, s.total
    FROM users u JOIN step1 s ON u.id = s.user_id
    WHERE s.total > 1000
)
SELECT * FROM step2;

```

## Python UDFs (via DuckDB Python API, not SQL)

In Python:
import duckdb
def my_function(x): return x * 2
duckdb.create_function('double_it', my_function, [int], int)
duckdb.sql("SELECT double_it(21)")  -- 42

## Extensions for additional functionality

DuckDB extensions can add new functions:
INSTALL httpfs; LOAD httpfs;   -- HTTP/S3 file access
INSTALL spatial; LOAD spatial; -- Spatial functions

Note: CREATE FUNCTION is an alias for CREATE MACRO (v0.9+); no CREATE PROCEDURE
Note: Macros are expanded inline (no function call overhead)
Note: Table macros return result sets (like table-valued functions)
Note: For complex logic, use the host language (Python, Java, etc.)
Note: PREPARE/EXECUTE provides parameterized queries (not stored procedures)
Note: No PL/pgSQL, no procedural language support
Note: No CALL statement (no procedures to call)
