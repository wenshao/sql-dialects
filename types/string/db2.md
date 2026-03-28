# IBM Db2: String Types

> 参考资料:
> - [Db2 SQL Reference](https://www.ibm.com/docs/en/db2/11.5?topic=sql)
> - [Db2 Built-in Functions](https://www.ibm.com/docs/en/db2/11.5?topic=functions-built-in)


CHAR(n) / CHARACTER(n): fixed-length, 1-254 bytes
VARCHAR(n) / CHARACTER VARYING(n): variable-length, max 32672 bytes
CLOB(n): Character Large Object, up to 2GB

```sql
CREATE TABLE examples (
    code    CHAR(10),              -- fixed-length
    name    VARCHAR(255),          -- variable-length
    content CLOB(1M)               -- large text
);
```

Unicode types (GRAPHIC types for double-byte characters)
GRAPHIC(n): fixed-length, double-byte characters
VARGRAPHIC(n): variable-length, double-byte
DBCLOB(n): double-byte CLOB

```sql
CREATE TABLE unicode_example (
    code GRAPHIC(10),
    name VARGRAPHIC(255),
    bio  DBCLOB(1M)
);
```

## NCHAR / NVARCHAR (National character, depends on database codepage)

In Db2 for LUW, these are typically UTF-8 if database is UTF-8

```sql
CREATE TABLE national_chars (
    name NVARCHAR(100)
);
```

LONG VARCHAR (deprecated, use CLOB)
CREATE TABLE old_style (content LONG VARCHAR);
Binary types
CHAR FOR BIT DATA: fixed-length binary
VARCHAR FOR BIT DATA: variable-length binary
BLOB(n): Binary Large Object

```sql
CREATE TABLE binary_data (
    hash   CHAR(32) FOR BIT DATA,
    data   VARCHAR(1000) FOR BIT DATA,
    file   BLOB(10M)
);
```

## XML type

```sql
CREATE TABLE xml_data (
    id  BIGINT NOT NULL,
    doc XML
);
```

## String with inline length (performance)

```sql
CREATE TABLE inline_example (
    short_text VARCHAR(100) INLINE LENGTH 100,  -- store inline in row
    long_text  VARCHAR(10000)                    -- may go to LOB storage
);
```

Collation
Database-level collation set at creation: CREATE DATABASE ... COLLATE USING ...
Db2 11.5+: column-level collation
ALTER TABLE t ALTER COLUMN name SET COLLATION UNICODE;
Note: VARCHAR max is 32672 bytes in row-organized tables
Note: in column-organized tables (BLU), VARCHAR max is 32672
Note: no TEXT type; use CLOB for large text
Note: CLOB columns cannot be indexed directly (use text search)
