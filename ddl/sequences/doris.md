# Apache Doris: 序列与自增

 Apache Doris: 序列与自增

 参考资料:
   [1] Doris Documentation - AUTO_INCREMENT
       https://doris.apache.org/docs/sql-manual/sql-statements/

## 1. 自增设计: 分布式引擎的核心挑战

 全局自增在分布式系统中代价极高(需要全局协调)。
 Doris 2.1+ 通过"段分配"方案实现 AUTO_INCREMENT:
   每个 BE 节点预分配一段 ID(默认 100000 个)
   段内连续，跨段有间隙
   保证全局唯一但不保证全局连续

 对比:
   StarRocks 3.0+: AUTO_INCREMENT，类似的段分配方案
   MySQL:          AUTO_INCREMENT，单机连续，重启可能回退(5.7-)
   ClickHouse:     无自增(分析引擎不需要)
   BigQuery:       无自增(推荐 UUID 或 GENERATE_UUID())
   TiDB:           AUTO_INCREMENT(兼容) + AUTO_RANDOM(推荐，防热点)

 对引擎开发者的启示:
   分布式自增的三种方案:
   A. 段分配(Doris/StarRocks/TiDB): 每节点预分配一段，低延迟但有间隙
   B. 全局协调(ZooKeeper/etcd): 严格连续但延迟高
   C. 不支持(BigQuery/ClickHouse): 推荐 UUID，最简单

## 2. AUTO_INCREMENT (2.1+)

```sql
CREATE TABLE users (
    id       BIGINT       NOT NULL AUTO_INCREMENT,
    username VARCHAR(64)  NOT NULL,
    email    VARCHAR(255) NOT NULL
) UNIQUE KEY(id)
DISTRIBUTED BY HASH(id) BUCKETS 8
PROPERTIES ("replication_num" = "3");

```

插入时不指定自增列

```sql
INSERT INTO users (username, email) VALUES ('alice', 'alice@example.com');

```

 特点:
1. 保证唯一但不保证连续(跨 BE 有间隙)

2. 每个 BE 预分配 100000 个 ID(可配置)

3. AUTO_INCREMENT 列必须是 Key 列

4. 仅 Unique Key 的 Merge-on-Write 模型支持


## 3. SEQUENCE 列 (Doris 特有，版本控制)

```sql
CREATE TABLE orders (
    user_id     BIGINT,
    order_id    BIGINT,
    amount      DECIMAL(10,2),
    update_time DATETIME
) UNIQUE KEY(user_id, order_id)
DISTRIBUTED BY HASH(user_id) BUCKETS 8
PROPERTIES (
    "replication_num" = "3",
    "function_column.sequence_col" = "update_time"
);

```

 设计分析:
   SEQUENCE 列不是 SQL 标准的 SEQUENCE，而是 Doris 特有的版本控制机制。
   用于确定相同 Key 的多行中哪条是"最新的"。
   Unique Key 表默认用 REPLACE 语义(后写入的覆盖)。
   指定 sequence_col 后，按该列的值决定哪条记录保留。

   场景: 多数据源写入同一个 Key，只想保留时间戳最新的那条。

 对比:
   StarRocks: 不支持 sequence_col(Primary Key 按写入顺序覆盖)
   ClickHouse: ReplacingMergeTree(ver) 支持 version 列(类似概念)

## 4. UUID 生成

```sql
SELECT uuid();
```

结果: '7f1b7e42-3a1c-4b5d-8f2e-9c0d1e2f3a4b'


```sql
SELECT uuid_numeric();
```

 返回 LARGEINT 类型的 UUID 数值

## 5. 自增策略选择 (对引擎开发者)

AUTO_INCREMENT(2.1+):  简单，分布式唯一，适合主键
uuid():               全局唯一，128 位，无排序性
uuid_numeric():       LARGEINT 类型，可用于 Key 列
应用层生成 ID:         Snowflake ID 等，可控性最强
SEQUENCE 列:           版本控制(不是自增)

限制:
不支持 CREATE SEQUENCE(SQL 标准的独立序列对象)
不支持 IDENTITY / SERIAL(PostgreSQL 语法)
AUTO_INCREMENT 需要 Doris 2.1+
AUTO_INCREMENT 列必须是 Key 列的一部分

