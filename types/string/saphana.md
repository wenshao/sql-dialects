# SAP HANA: String Types

> 参考资料:
> - [SAP HANA SQL Reference](https://help.sap.com/docs/SAP_HANA_PLATFORM/4fe29514fd584807ac9f2a04f6754767/)
> - [SAP HANA SQLScript Reference](https://help.sap.com/docs/SAP_HANA_PLATFORM/de2486ee947e43e684d39702027f8a94/)


VARCHAR(n): variable-length, ASCII, max 5000 characters
NVARCHAR(n): variable-length, Unicode (UTF-8), max 5000 characters (recommended)
CHAR(n): fixed-length, ASCII
NCHAR(n): fixed-length, Unicode

```sql
CREATE TABLE examples (
    code    CHAR(10),              -- fixed-length ASCII
    name    NVARCHAR(255),         -- variable-length Unicode (recommended)
    content NCLOB                  -- large Unicode text
);
```

LOB types
CLOB: Character Large Object (ASCII), up to 2GB
NCLOB: National Character Large Object (Unicode), up to 2GB
BLOB: Binary Large Object, up to 2GB

```sql
CREATE TABLE documents (
    ascii_text  CLOB,
    unicode_text NCLOB,
    binary_data BLOB
);
```

## SHORTTEXT(n): optimized for fuzzy search and text analysis

Stored in column store with text analysis capabilities

```sql
CREATE TABLE search_data (
    title   SHORTTEXT(500),
    content NCLOB
);
```

## TEXT type (column store, for full-text search)

Internally similar to NCLOB but with text processing

```sql
CREATE TABLE articles (
    id      BIGINT PRIMARY KEY,
    content TEXT
);
```

## ALPHANUM: alphanumeric string, sortable as numbers when possible

```sql
CREATE TABLE parts (
    part_number ALPHANUM(20)  -- 'A100' sorts between 'A99' and 'A101'
);
```

Binary string types
VARBINARY(n): variable-length binary, max 5000 bytes
BINARY(n): fixed-length binary

```sql
CREATE TABLE binary_data (
    hash BINARY(32),
    data VARBINARY(5000)
);
```

## Collation (at column level)

```sql
CREATE TABLE collation_example (
    name NVARCHAR(100) CS_UNICODE  -- case-sensitive Unicode
);
```

Note: always prefer NVARCHAR over VARCHAR for Unicode support
Note: SHORTTEXT provides built-in fuzzy search capabilities
Note: ALPHANUM is unique to SAP HANA
Note: maximum VARCHAR/NVARCHAR length is 5000 characters
Note: use CLOB/NCLOB for text longer than 5000 characters
