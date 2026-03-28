# OceanBase: 字符串类型

> 参考资料:
> - [OceanBase SQL Reference (MySQL Mode)](https://www.oceanbase.com/docs/common-oceanbase-database-cn)
> - [OceanBase SQL Reference (Oracle Mode)](https://www.oceanbase.com/docs/common-oceanbase-database-cn)

**引擎定位**: 分布式关系型数据库，兼容 MySQL/Oracle 双模式。基于 LSM-Tree 存储，Paxos 共识。

## MySQL Mode (same as MySQL)


CHAR(n), VARCHAR(n), TINYTEXT, TEXT, MEDIUMTEXT, LONGTEXT
BINARY(n), VARBINARY(n), TINYBLOB, BLOB, MEDIUMBLOB, LONGBLOB
ENUM, SET

```sql
CREATE TABLE examples (
    code       CHAR(10),
    name       VARCHAR(255),
    content    TEXT,
    big_data   LONGTEXT
);

```

Character sets (same as MySQL)
```sql
CREATE TABLE t (
    name VARCHAR(100) CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci
);

```

Default charset: utf8mb4 (configurable)
Supported collations: utf8mb4_general_ci, utf8mb4_bin, utf8mb4_unicode_ci
Note: utf8mb4_0900_ai_ci may not be available (depends on version)

ENUM and SET (same as MySQL)
```sql
CREATE TABLE t (
    status ENUM('active', 'inactive', 'deleted'),
    tags   SET('tag1', 'tag2', 'tag3')
);

```

## Oracle Mode


VARCHAR2(n): variable-length string (Oracle equivalent of VARCHAR)
CHAR(n): fixed-length string
NVARCHAR2(n): variable-length Unicode string
NCHAR(n): fixed-length Unicode string
CLOB: large text object
NCLOB: large Unicode text object
RAW(n): raw binary data
BLOB: large binary object

```sql
CREATE TABLE examples (
    code       CHAR(10),
    name       VARCHAR2(255),
    content    CLOB,
    raw_data   RAW(256)
);

```

VARCHAR2 vs VARCHAR:
In Oracle mode, VARCHAR2 is the standard type
VARCHAR is an alias but VARCHAR2 is recommended

String length semantics (Oracle mode)
BYTE: length in bytes (default)
CHAR: length in characters
```sql
CREATE TABLE t (
    name_bytes VARCHAR2(100 BYTE),   -- 100 bytes
    name_chars VARCHAR2(100 CHAR)    -- 100 characters
);

```

NVARCHAR2 (national character set, always Unicode)
```sql
CREATE TABLE t (
    intl_name NVARCHAR2(100)
);

```

Character set in Oracle mode:
AL32UTF8 (UTF-8) is the default database character set
AL16UTF16 is the default national character set

Limitations:
MySQL mode: same string types as MySQL
Oracle mode: VARCHAR2, CLOB, NVARCHAR2, RAW types
Oracle mode: LONG type supported but deprecated (use CLOB)
Maximum VARCHAR2 length: 32767 bytes (Oracle extended mode) or 4000 bytes
CLOB can store up to 4GB
