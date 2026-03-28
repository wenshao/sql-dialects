# Teradata: Numeric Types

> 参考资料:
> - [Teradata SQL Reference](https://docs.teradata.com/r/Teradata-VantageTM-SQL-Functions-Expressions-and-Predicates)
> - [Teradata Database Documentation](https://docs.teradata.com/)


Integer types
BYTEINT:   1 byte, -128 ~ 127
SMALLINT:  2 bytes, -32768 ~ 32767
INTEGER:   4 bytes, -2^31 ~ 2^31-1
BIGINT:    8 bytes, -2^63 ~ 2^63-1

```sql
CREATE TABLE examples (
    tiny_val   BYTEINT,              -- Teradata-specific 1-byte integer
    small_val  SMALLINT,
    int_val    INTEGER,
    big_val    BIGINT
);
```


Decimal / Numeric (exact)
DECIMAL(p,s) / NUMERIC(p,s): precision up to 38, scale up to p
```sql
CREATE TABLE prices (
    price     DECIMAL(10,2),          -- up to 99999999.99
    rate      DECIMAL(18,6),          -- high precision
    any_num   DECIMAL(38,0)           -- max precision
);
```


NUMBER (Teradata 14.10+, variable precision like Oracle)
```sql
CREATE TABLE flexible_nums (
    val NUMBER,                       -- any precision
    val2 NUMBER(10,2)                 -- equivalent to DECIMAL(10,2)
);
```


Floating point
FLOAT / REAL / DOUBLE PRECISION: 8 bytes IEEE 754
Note: Teradata FLOAT is always 8 bytes (no single-precision FLOAT)
```sql
CREATE TABLE measurements (
    approx_val FLOAT,                 -- 8 bytes, ~15 digits precision
    real_val   REAL,                  -- alias for FLOAT
    double_val DOUBLE PRECISION       -- alias for FLOAT
);
```


No native BOOLEAN type (use BYTEINT or CHAR(1))
```sql
CREATE TABLE flags (
    active BYTEINT DEFAULT 1 CHECK (active IN (0, 1))
);
```


Auto-generated identity
Teradata uses GENERATED ALWAYS/BY DEFAULT AS IDENTITY
```sql
CREATE TABLE auto_id (
    id INTEGER GENERATED ALWAYS AS IDENTITY (START WITH 1 INCREMENT BY 1),
    name VARCHAR(100)
);
```


COMPRESS for numeric values
```sql
CREATE TABLE compressed (
    status BYTEINT COMPRESS (0, 1, 2, 3)
);
```


Note: BYTEINT is unique to Teradata (1-byte integer)
Note: no UNSIGNED types
Note: DECIMAL max precision is 38
Note: FLOAT is always 64-bit (no 32-bit option)
Note: no SERIAL/SEQUENCE; use IDENTITY columns
