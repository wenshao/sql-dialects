# PolarDB: 字符串类型

PolarDB-X (distributed, MySQL compatible).

> 参考资料:
> - [PolarDB-X SQL Reference](https://help.aliyun.com/zh/polardb/polardb-for-xscale/sql-reference/)
> - [PolarDB MySQL Documentation](https://help.aliyun.com/zh/polardb/polardb-for-mysql/)


CHAR(n): 定长，最大 255 字符
VARCHAR(n): 变长，最大 65535 字节
TINYTEXT: 最大 255 字节
TEXT: 最大 65535 字节
MEDIUMTEXT: 最大 16MB
LONGTEXT: 最大 4GB

```sql
CREATE TABLE examples (
    code       CHAR(10),
    name       VARCHAR(255),
    content    TEXT,
    big_data   LONGTEXT
);
```

二进制字符串
BINARY(n) / VARBINARY(n)
TINYBLOB / BLOB / MEDIUMBLOB / LONGBLOB
字符集和排序规则

```sql
CREATE TABLE t (
    name VARCHAR(100) CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci
);
```

## ENUM

```sql
CREATE TABLE t (status ENUM('active', 'inactive', 'deleted'));
```

## SET

```sql
CREATE TABLE t (tags SET('tag1', 'tag2', 'tag3'));
```

注意事项：
默认字符集 utf8mb4
字符串类型与 MySQL 完全兼容
VARCHAR(n) 中 n 是字符数，不是字节数
分区键建议使用定长类型以提高分片路由效率
