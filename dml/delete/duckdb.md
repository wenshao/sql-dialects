# DuckDB: DELETE

> 参考资料:
> - [DuckDB - SQL Reference](https://duckdb.org/docs/sql/introduction)
> - [DuckDB - Functions](https://duckdb.org/docs/sql/functions/overview)
> - [DuckDB - Data Types](https://duckdb.org/docs/sql/data_types/overview)

**引擎定位**: 嵌入式 OLAP 分析引擎，类似 SQLite 的定位。列式存储 + 向量化执行，PostgreSQL 兼容语法。

```sql
DELETE FROM users WHERE username = 'alice';

```

USING clause (multi-table delete, PostgreSQL-compatible)
```sql
DELETE FROM users
USING blacklist
WHERE users.email = blacklist.email;

```

Subquery delete
```sql
DELETE FROM users WHERE id IN (SELECT user_id FROM blacklist);

```

RETURNING (v0.9+)
```sql
DELETE FROM users WHERE status = 0 RETURNING id, username;
DELETE FROM users WHERE age > 100 RETURNING *;

```

CTE + DELETE
```sql
WITH inactive AS (
    SELECT id FROM users WHERE last_login < '2023-01-01'
)
DELETE FROM users WHERE id IN (SELECT id FROM inactive);

```

CTE + DELETE + RETURNING (archive then delete)
```sql
WITH deleted AS (
    DELETE FROM users WHERE status = 0 RETURNING *
)
INSERT INTO users_archive SELECT * FROM deleted;

```

EXISTS subquery
```sql
DELETE FROM users u
WHERE NOT EXISTS (SELECT 1 FROM orders o WHERE o.user_id = u.id);

```

Delete all rows
```sql
DELETE FROM users;

```

TRUNCATE (faster, drops and recreates storage)
```sql
TRUNCATE TABLE users;

```

Drop and recreate (alternative for full clear)
```sql
CREATE OR REPLACE TABLE users AS SELECT * FROM users WHERE false;

```

Note: DuckDB supports full PostgreSQL-compatible DELETE syntax
Note: TRUNCATE is faster than DELETE for removing all rows
Note: No CASCADE option on TRUNCATE
Note: DELETE uses MVCC internally for consistency
Note: For bulk deletions, consider creating a new table without unwanted rows:
      CREATE OR REPLACE TABLE users AS SELECT * FROM users WHERE status != 0;
