# OceanBase: 数值类型

> 参考资料:
> - [OceanBase SQL Reference (MySQL Mode)](https://www.oceanbase.com/docs/common-oceanbase-database-cn)
> - [OceanBase SQL Reference (Oracle Mode)](https://www.oceanbase.com/docs/common-oceanbase-database-cn)

**引擎定位**: 分布式关系型数据库，兼容 MySQL/Oracle 双模式。基于 LSM-Tree 存储，Paxos 共识。

## MySQL Mode (same as MySQL)


TINYINT, SMALLINT, MEDIUMINT, INT, BIGINT
FLOAT, DOUBLE
DECIMAL/NUMERIC
BIT(M)
BOOL/BOOLEAN

```sql
CREATE TABLE examples (
    tiny_val   TINYINT,
    small_val  SMALLINT,
    int_val    INT,
    big_val    BIGINT,
    pos_val    INT UNSIGNED,
    flag       TINYINT(1)
);

```

BOOL/BOOLEAN (same as MySQL)
```sql
CREATE TABLE t (active BOOLEAN DEFAULT TRUE);

```

DECIMAL (same as MySQL)
```sql
CREATE TABLE prices (
    price    DECIMAL(10,2),
    rate     DECIMAL(5,4)
);

```

AUTO_INCREMENT (same as MySQL)
```sql
CREATE TABLE t (id BIGINT NOT NULL AUTO_INCREMENT PRIMARY KEY);

```

FLOAT/DOUBLE (same as MySQL)
```sql
CREATE TABLE t (
    val_f FLOAT,
    val_d DOUBLE
);

```

## Oracle Mode


NUMBER(p,s): Oracle's universal numeric type
NUMBER: any precision
NUMBER(p): integer with precision p
NUMBER(p,s): decimal with precision p, scale s
NUMBER(*,0): integer (any precision)

```sql
CREATE TABLE examples (
    id         NUMBER NOT NULL,
    age        NUMBER(3),          -- integer, max 3 digits
    price      NUMBER(10,2),       -- decimal with 2 decimal places
    rate       NUMBER(5,4),        -- decimal with 4 decimal places
    big_num    NUMBER(38)          -- up to 38 digits
);

```

INTEGER / INT: aliases for NUMBER(38,0) in Oracle mode
```sql
CREATE TABLE t (
    val INTEGER,
    cnt INT
);

```

FLOAT in Oracle mode
FLOAT(p): binary precision float (p is binary digits, not decimal)
BINARY_FLOAT: 4-byte IEEE float (Oracle-specific)
BINARY_DOUBLE: 8-byte IEEE double (Oracle-specific)
```sql
CREATE TABLE measurements (
    val_f   FLOAT(53),          -- equivalent to DOUBLE precision
    val_bf  BINARY_FLOAT,       -- 4 bytes
    val_bd  BINARY_DOUBLE       -- 8 bytes
);

```

PLS_INTEGER / SIMPLE_INTEGER (Oracle mode, PL/SQL only)
Used in PL/SQL stored procedures for better performance

Sequences for auto-increment (Oracle mode)
```sql
CREATE SEQUENCE seq_id START WITH 1 INCREMENT BY 1;
```

Use: seq_id.NEXTVAL, seq_id.CURRVAL

BOOLEAN in Oracle mode (PL/SQL only, not in SQL)
Oracle mode does not have BOOLEAN as a column type
Use NUMBER(1) with CHECK constraint instead
```sql
CREATE TABLE t (
    active NUMBER(1) DEFAULT 1 CHECK (active IN (0, 1))
);

```

Limitations:
MySQL mode: same numeric types as MySQL
Oracle mode: NUMBER is the primary numeric type
Oracle mode: no BOOLEAN column type (use NUMBER(1))
Oracle mode: BINARY_FLOAT/BINARY_DOUBLE for IEEE floating point
Oracle mode: PLS_INTEGER only in PL/SQL, not as column type
