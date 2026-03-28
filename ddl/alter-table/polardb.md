# PolarDB: ALTER TABLE

PolarDB-X (distributed, MySQL compatible).

> 参考资料:
> - [PolarDB-X SQL Reference](https://help.aliyun.com/zh/polardb/polardb-for-xscale/sql-reference/)
> - [PolarDB MySQL Documentation](https://help.aliyun.com/zh/polardb/polardb-for-mysql/)
> - 添加列

```sql
ALTER TABLE users ADD COLUMN phone VARCHAR(20) AFTER email;
ALTER TABLE users ADD COLUMN status TINYINT NOT NULL DEFAULT 1 FIRST;
```

## 一次添加多列

```sql
ALTER TABLE users
    ADD COLUMN city VARCHAR(64),
    ADD COLUMN country VARCHAR(64);
```

## 修改列类型

```sql
ALTER TABLE users MODIFY COLUMN phone VARCHAR(32) NOT NULL;
```

## 重命名列

```sql
ALTER TABLE users CHANGE COLUMN phone mobile VARCHAR(32);
ALTER TABLE users RENAME COLUMN mobile TO phone;
```

## 删除列

```sql
ALTER TABLE users DROP COLUMN phone;
ALTER TABLE users ADD COLUMN IF NOT EXISTS phone VARCHAR(20);
ALTER TABLE users DROP COLUMN IF EXISTS phone;
```

## 修改默认值

```sql
ALTER TABLE users ALTER COLUMN status SET DEFAULT 0;
ALTER TABLE users ALTER COLUMN status DROP DEFAULT;
```

## 重命名表

```sql
ALTER TABLE users RENAME TO members;
RENAME TABLE users TO members;
```

## 修改表引擎 / 字符集

```sql
ALTER TABLE users ENGINE = InnoDB;
ALTER TABLE users CONVERT TO CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;
```

## 即时列添加（INSTANT）

```sql
ALTER TABLE users ADD COLUMN tag VARCHAR(32), ALGORITHM=INSTANT;
```

## PolarDB-X 分区管理

修改分区数

```sql
ALTER TABLE orders PARTITIONS 32;
```

## 添加分区

```sql
ALTER TABLE logs ADD PARTITION (
    PARTITION p2026 VALUES LESS THAN (2027)
);
```

## 删除分区

```sql
ALTER TABLE logs DROP PARTITION p2023;
```

## 修改广播表为分区表

```sql
ALTER TABLE regions REMOVE PARTITIONING;
ALTER TABLE regions PARTITION BY KEY(id) PARTITIONS 8;
```

## 添加全局索引

```sql
ALTER TABLE orders ADD GLOBAL INDEX idx_amount (amount)
    PARTITION BY HASH(amount) PARTITIONS 4;
```

## 删除全局索引

```sql
ALTER TABLE orders DROP INDEX idx_amount;
```

注意事项：
分布式 DDL 操作会在所有分片上执行
修改分区键不支持在线操作
全局索引的添加/删除会影响所有分片
ALGORITHM=INSTANT 在分布式环境下也适用
