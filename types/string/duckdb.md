# DuckDB: 字符串类型

> 参考资料:
> - [DuckDB - SQL Reference](https://duckdb.org/docs/sql/introduction)
> - [DuckDB - Functions](https://duckdb.org/docs/sql/functions/overview)
> - [DuckDB - Data Types](https://duckdb.org/docs/sql/data_types/overview)

**引擎定位**: 嵌入式 OLAP 分析引擎，类似 SQLite 的定位。列式存储 + 向量化执行，PostgreSQL 兼容语法。

```sql
CREATE TABLE examples (
    code    CHAR(10),                 -- Fixed-length, padded
    name    VARCHAR(255),             -- Variable-length with limit
    content VARCHAR,                  -- Variable-length, no limit (recommended)
    bio     TEXT                      -- Alias for VARCHAR
);

```

DuckDB recommendation: Use VARCHAR (no length limit) in most cases
Length constraints are enforced but rarely needed in analytics

Binary data
```sql
CREATE TABLE files (
    data BLOB                         -- Binary large object
);

```

ENUM type (predefined set of string values)
```sql
CREATE TYPE status_type AS ENUM ('active', 'inactive', 'deleted');
CREATE TABLE t (status status_type);

```

String literals
```sql
SELECT 'hello world';                -- Single quotes
SELECT 'it''s a test';               -- Escaped single quote
SELECT E'tab\there';                 -- Escape string (C-style escapes)
SELECT $$dollar-quoted string$$;     -- Dollar-quoted (no escaping needed)

```

Unicode
```sql
SELECT '你好世界';                     -- UTF-8 strings are native
SELECT LENGTH('你好');                 -- 2 (character count)
SELECT OCTET_LENGTH('你好');           -- 6 (byte count, UTF-8)

```

String collation
DuckDB uses binary collation by default
ICU collation available with icu extension
INSTALL icu; LOAD icu;
SELECT * FROM t ORDER BY name COLLATE 'en_US';

HUGEINT / UUID string representations
```sql
SELECT uuid()::VARCHAR;               -- UUID as string
SELECT '550e8400-e29b-41d4-a716-446655440000'::UUID;  -- String to UUID

```

Note: VARCHAR and TEXT are identical in DuckDB
Note: No TINYTEXT/MEDIUMTEXT/LONGTEXT (MySQL-specific)
Note: Maximum string size limited by available memory
Note: Strings are stored in a dictionary-compressed columnar format
Note: BLOB stores binary data; use for non-text content
