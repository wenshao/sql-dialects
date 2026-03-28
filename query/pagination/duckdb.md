# DuckDB: 分页查询

> 参考资料:
> - [DuckDB - SQL Reference](https://duckdb.org/docs/sql/introduction)
> - [DuckDB - Functions](https://duckdb.org/docs/sql/functions/overview)
> - [DuckDB - Data Types](https://duckdb.org/docs/sql/data_types/overview)

**引擎定位**: 嵌入式 OLAP 分析引擎，类似 SQLite 的定位。列式存储 + 向量化执行，PostgreSQL 兼容语法。

```sql
SELECT * FROM users ORDER BY id LIMIT 10 OFFSET 20;

```

LIMIT only
```sql
SELECT * FROM users ORDER BY id LIMIT 10;

```

SQL standard syntax (FETCH FIRST)
```sql
SELECT * FROM users ORDER BY id OFFSET 20 ROWS FETCH FIRST 10 ROWS ONLY;

```

FETCH NEXT (same as FETCH FIRST)
```sql
SELECT * FROM users ORDER BY id OFFSET 20 ROWS FETCH NEXT 10 ROWS ONLY;

```

Window function pagination
```sql
SELECT * FROM (
    SELECT *, ROW_NUMBER() OVER (ORDER BY id) AS rn
    FROM users
) t
WHERE rn BETWEEN 21 AND 30;

```

Keyset / cursor pagination (efficient for large offsets)
```sql
SELECT * FROM users WHERE id > 100 ORDER BY id LIMIT 10;

```

Keyset pagination with multiple sort columns
```sql
SELECT * FROM users
WHERE (created_at, id) > ('2024-01-15', 100)
ORDER BY created_at, id
LIMIT 10;

```

SAMPLE clause (DuckDB-specific: random sample instead of pagination)
```sql
SELECT * FROM users USING SAMPLE 10;           -- 10 rows
SELECT * FROM users USING SAMPLE 10%;          -- 10% of rows
SELECT * FROM users USING SAMPLE 10 ROWS;      -- 10 rows (explicit)

```

Sampling methods
```sql
SELECT * FROM users USING SAMPLE reservoir(10);  -- Reservoir sampling
SELECT * FROM users USING SAMPLE system(10%);    -- System sampling (block-level)
SELECT * FROM users USING SAMPLE bernoulli(10%); -- Bernoulli sampling (row-level)

```

TABLESAMPLE (SQL standard syntax)
```sql
SELECT * FROM users TABLESAMPLE reservoir(10 ROWS);

```

ORDER BY ALL (DuckDB-specific: order by all columns left-to-right)
```sql
SELECT * FROM users ORDER BY ALL;
SELECT * FROM users ORDER BY ALL DESC;

```

Note: DuckDB supports both LIMIT/OFFSET and FETCH FIRST syntax
Note: For large tables, keyset pagination is much faster than OFFSET
Note: SAMPLE is useful for analytical exploration (not deterministic pagination)
Note: No server-side cursor-based pagination (DuckDB is embedded)
