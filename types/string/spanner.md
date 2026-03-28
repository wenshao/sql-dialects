# Spanner: 字符串类型

> 参考资料:
> - [Spanner SQL Reference (GoogleSQL)](https://cloud.google.com/spanner/docs/reference/standard-sql/query-syntax)
> - [Spanner - Functions](https://cloud.google.com/spanner/docs/reference/standard-sql/functions-and-operators)
> - [Spanner - Data Types](https://cloud.google.com/spanner/docs/reference/standard-sql/data-types)

**引擎定位**: Google 全球分布式数据库，TrueTime 外部一致性。基于 Colossus 存储，支持跨洲强一致事务。

```sql
CREATE TABLE Examples (
    Name       STRING(100),                    -- max 100 characters
    ShortCode  STRING(5),                      -- max 5 characters
    Content    STRING(MAX),                    -- up to 2.5 MB
    Data       BYTES(MAX)                      -- binary, up to 10 MB
) PRIMARY KEY (Name);

```

Note: STRING requires length: STRING(N) or STRING(MAX)
Note: No CHAR, VARCHAR, TEXT types
Note: No CLOB/BLOB types
Note: String is always UTF-8 encoded

String literals
```sql
SELECT 'hello world';
SELECT "hello world";                          -- double quotes for strings too
SELECT '''multi
line string''';                                -- triple-quoted multi-line
SELECT r'\n is literal';                       -- raw string (no escapes)
SELECT b'binary data';                         -- BYTES literal
SELECT rb'\x00\x01';                           -- raw BYTES literal

```

Type casting
```sql
SELECT CAST('hello' AS STRING(100));
SELECT CAST(123 AS STRING);
SELECT SAFE_CAST('abc' AS INT64);              -- returns NULL on failure

```

Collation
```sql
SELECT COLLATE('hello', 'und:ci') = COLLATE('HELLO', 'und:ci');  -- TRUE (case-insensitive)
```

und:ci = Unicode default, case-insensitive

Column-level collation
```sql
CREATE TABLE LocalizedData (
    Id    INT64 NOT NULL,
    Name  STRING(100),
    NameCI STRING(100) AS (COLLATE(Name, 'und:ci')) STORED  -- case-insensitive column
) PRIMARY KEY (Id);

```

No ENUM type
Use STRING with CHECK constraint instead:
```sql
CREATE TABLE Users (
    UserId INT64 NOT NULL,
    Status STRING(20),
    CONSTRAINT chk_status CHECK (Status IN ('active', 'inactive', 'deleted'))
) PRIMARY KEY (UserId);

```

Proto and ENUM (Protocol Buffer types, Spanner-specific)
Spanner supports PROTO and ENUM types from Protocol Buffer definitions
CREATE PROTO BUNDLE (mypackage.MyProto);

Note: STRING(N) is required (no default length)
Note: STRING(MAX) for large text (up to 2.5 MB)
Note: SAFE_CAST returns NULL on failure (like BigQuery)
Note: Collation uses ICU locale identifiers (e.g., 'und:ci')
Note: No ENUM; use STRING + CHECK or Protocol Buffer ENUMs
Note: Raw strings (r'...') disable escape processing
