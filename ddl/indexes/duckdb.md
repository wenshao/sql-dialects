# DuckDB: 索引

> 参考资料:
> - [DuckDB - SQL Reference](https://duckdb.org/docs/sql/introduction)
> - [DuckDB - Functions](https://duckdb.org/docs/sql/functions/overview)
> - [DuckDB - Data Types](https://duckdb.org/docs/sql/data_types/overview)

**引擎定位**: 嵌入式 OLAP 分析引擎，类似 SQLite 的定位。列式存储 + 向量化执行，PostgreSQL 兼容语法。

```sql
CREATE INDEX idx_age ON users (age);

```

Unique index
```sql
CREATE UNIQUE INDEX uk_email ON users (email);

```

Composite index
```sql
CREATE INDEX idx_city_age ON users (city, age);

```

IF NOT EXISTS
```sql
CREATE INDEX IF NOT EXISTS idx_age ON users (age);

```

Drop index
```sql
DROP INDEX idx_age;
DROP INDEX IF EXISTS idx_age;

```

Note: DuckDB creates indexes primarily for point lookups (equality queries)
For range scans and analytics, DuckDB relies on its columnar storage and
automatic zonemaps (min/max per column chunk) which are more efficient

Expression index (v0.9+)
```sql
CREATE INDEX idx_lower_email ON users (LOWER(email));

```

DuckDB-specific: ART indexes are best for:
## Primary key lookups

## Foreign key joins

## OLTP-like point queries on specific columns


DuckDB does NOT support:
Hash indexes, GIN indexes, GiST indexes, BRIN indexes
Partial indexes (WHERE clause on CREATE INDEX)
INCLUDE columns
Concurrent index creation (CONCURRENTLY)

Pragmas to inspect indexes
```sql
PRAGMA table_info('users');
PRAGMA database_size;

```

DuckDB storage info (alternative to index inspection)
```sql
SELECT * FROM duckdb_indexes();

```

Best practices:
## DuckDB rarely needs explicit indexes for analytical workloads

## Zonemaps handle range scans efficiently on sorted/clustered data

## Use indexes mainly for point lookups on unsorted columns

## For large joins, DuckDB's hash join is typically faster than indexed lookup

## Consider sorting data on insert for natural zonemap efficiency
