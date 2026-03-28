# Firebird: String Types

> 参考资料:
> - [Firebird SQL Reference](https://firebirdsql.org/en/reference-manuals/)
> - [Firebird Release Notes](https://firebirdsql.org/file/documentation/release_notes/html/en/4_0/rlsnotes40.html)


CHAR(n) / CHARACTER(n): fixed-length, max 32767 bytes
VARCHAR(n) / CHARACTER VARYING(n): variable-length, max 32765 bytes
Note: actual max depends on page size and character set

```sql
CREATE TABLE examples (
    code    CHAR(10),              -- fixed-length
    name    VARCHAR(255),          -- variable-length
    content BLOB SUB_TYPE TEXT     -- large text
);
```

## Character sets (specified per column)

```sql
CREATE TABLE charset_example (
    ascii_name    VARCHAR(100) CHARACTER SET ASCII,
    utf8_name     VARCHAR(100) CHARACTER SET UTF8,
    latin_name    VARCHAR(100) CHARACTER SET ISO8859_1,
    win_name      VARCHAR(100) CHARACTER SET WIN1252
);
```

BLOB sub-types for text and binary
BLOB SUB_TYPE TEXT (sub_type 1): text data
BLOB SUB_TYPE BINARY (sub_type 0): binary data (default)

```sql
CREATE TABLE blob_example (
    text_data    BLOB SUB_TYPE TEXT CHARACTER SET UTF8,
    binary_data  BLOB SUB_TYPE BINARY,
    generic_blob BLOB                    -- defaults to SUB_TYPE BINARY
);
```

## BLOB with segment size

```sql
CREATE TABLE segmented (
    data BLOB SUB_TYPE TEXT SEGMENT SIZE 8192
);
```

## Domain (reusable string type definition)

```sql
CREATE DOMAIN d_name AS VARCHAR(100) CHARACTER SET UTF8
    DEFAULT ''
    NOT NULL
    COLLATE UNICODE_CI;  -- 4.0+: case-insensitive collation

CREATE DOMAIN d_email AS VARCHAR(255)
    CHECK (VALUE CONTAINING '@' AND VALUE CONTAINING '.');
```

4.0+: BOOLEAN is available but historically strings were used for flags
Pre-3.0: CHAR(1) CHECK (VALUE IN ('Y', 'N')) was common
Collation

```sql
CREATE TABLE collation_example (
    name_cs VARCHAR(100) CHARACTER SET UTF8 COLLATE UNICODE,           -- case-sensitive
    name_ci VARCHAR(100) CHARACTER SET UTF8 COLLATE UNICODE_CI         -- case-insensitive (4.0+)
);
```

Note: max VARCHAR size depends on page size: page_size / 4 - overhead
Note: page sizes: 4096, 8192, 16384, 32768
Note: for page size 8192: max VARCHAR is about 8160 bytes
Note: no TEXT or CLOB type; use BLOB SUB_TYPE TEXT
Note: BLOB SUB_TYPE TEXT supports character sets and collations
