# PolarDB: 数值类型

PolarDB-X (distributed, MySQL compatible).

> 参考资料:
> - [PolarDB-X SQL Reference](https://help.aliyun.com/zh/polardb/polardb-for-xscale/sql-reference/)
> - [PolarDB MySQL Documentation](https://help.aliyun.com/zh/polardb/polardb-for-mysql/)
> - 整数
> - TINYINT:   1 字节，-128 ~ 127
> - SMALLINT:  2 字节，-32768 ~ 32767
> - MEDIUMINT: 3 字节
> - INT:       4 字节
> - BIGINT:    8 字节

```sql
CREATE TABLE examples (
    tiny_val   TINYINT,
    small_val  SMALLINT,
    int_val    INT,
    big_val    BIGINT,
    pos_val    INT UNSIGNED,
    flag       TINYINT(1)             -- 常用作布尔值
);
```

## BOOL / BOOLEAN: TINYINT(1) 的别名

```sql
CREATE TABLE t (active BOOLEAN DEFAULT TRUE);
```

浮点数
FLOAT:  4 字节，约 7 位有效数字
DOUBLE: 8 字节，约 15 位有效数字
定点数（精确）
DECIMAL(M,D) / NUMERIC(M,D)

```sql
CREATE TABLE prices (
    price    DECIMAL(10,2),
    rate     DECIMAL(5,4)
);
```

## BIT(M): 位字段，M 范围 1~64

```sql
CREATE TABLE t (flags BIT(8));
```

## 自增

```sql
CREATE TABLE t (id BIGINT NOT NULL AUTO_INCREMENT PRIMARY KEY);
```

注意事项：
数值类型与 MySQL 完全兼容
AUTO_INCREMENT 在分布式环境下全局唯一但不连续
建议使用 BIGINT 作为主键和分区键
UNSIGNED 在 8.0 中浮点和定点类型上已废弃
