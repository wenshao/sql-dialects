# TiDB: 序列与自增

> 参考资料:
> - [TiDB Documentation - AUTO_INCREMENT](https://docs.pingcap.com/tidb/stable/auto-increment)
> - [TiDB Documentation - AUTO_RANDOM](https://docs.pingcap.com/tidb/stable/auto-random)
> - [TiDB Documentation - CREATE SEQUENCE](https://docs.pingcap.com/tidb/stable/sql-statement-create-sequence)

**引擎定位**: 分布式 HTAP 数据库，兼容 MySQL 协议。基于 TiKV 行存 + TiFlash 列存，Raft 共识。

## AUTO_INCREMENT

```sql
CREATE TABLE users (
    id       BIGINT NOT NULL AUTO_INCREMENT,
    username VARCHAR(64) NOT NULL,
    email    VARCHAR(255) NOT NULL,
    PRIMARY KEY (id)
);

```

TiDB AUTO_INCREMENT 特殊行为：
## 默认使用缓存（每个 TiDB 节点预分配 30000 个 ID）

## 保证唯一但不保证连续（各节点独立分配）

## MySQL 兼容模式：SET @@tidb_allow_remove_auto_inc = 0;


强制 MySQL 兼容行为（性能较差）
SET @@auto_increment_increment = 1;
SET @@auto_increment_offset = 1;

```sql
SELECT LAST_INSERT_ID();

```

## AUTO_RANDOM（TiDB 3.1+ 特有，分布式推荐）

避免写热点
```sql
    id       BIGINT NOT NULL AUTO_RANDOM,
    amount   DECIMAL(10,2),
    PRIMARY KEY (id) CLUSTERED
);

```

AUTO_RANDOM(shard_bits)
```sql
CREATE TABLE events (
    id       BIGINT NOT NULL AUTO_RANDOM(5),  -- 5 位分片 = 32 个分片
    data     JSON,
    PRIMARY KEY (id)
);

```

AUTO_RANDOM vs AUTO_INCREMENT：
AUTO_INCREMENT：集中式分配，可能导致写热点
AUTO_RANDOM：高位随机化，写入分散到多个 Region

## SEQUENCE（TiDB 4.0+）

```sql
CREATE SEQUENCE user_id_seq
    START WITH 1
    INCREMENT BY 1
    MINVALUE 1
    MAXVALUE 9999999999
    CACHE 1000
    NO CYCLE;

```

使用序列（兼容两种语法）
```sql
SELECT NEXT VALUE FOR user_id_seq;           -- SQL 标准
SELECT NEXTVAL(user_id_seq);                 -- 简写
SELECT LAST_VALUE FOR user_id_seq;
SELECT SETVAL(user_id_seq, 1000);

```

在表中使用序列
```sql
CREATE TABLE products (
    id       BIGINT DEFAULT NEXT VALUE FOR user_id_seq,
    name     VARCHAR(64)
);

```

删除序列
```sql
DROP SEQUENCE user_id_seq;
DROP SEQUENCE IF EXISTS user_id_seq;

```

## UUID 生成

```sql
SELECT UUID();

```

## 分布式 ID 策略

## AUTO_RANDOM（推荐）：最适合 TiDB 分布式架构

## AUTO_INCREMENT：兼容 MySQL 但可能有热点

## SEQUENCE：灵活，支持 CACHE 优化性能

## UUID()：全局唯一

## SHARD_ROW_ID_BITS：用于无整数主键的表


## 序列 vs 自增 权衡

## AUTO_RANDOM（推荐分布式）：避免热点，全局唯一

## AUTO_INCREMENT：MySQL 兼容，有热点风险

## SEQUENCE（4.0+）：灵活，可跨表共享

## UUID：全局唯一，无需协调

## AUTO_RANDOM 要求主键为 BIGINT 且 CLUSTERED
