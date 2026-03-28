# StarRocks: CREATE TABLE

> 参考资料:
> - [1] StarRocks - CREATE TABLE
>   https://docs.starrocks.io/docs/sql-reference/sql-statements/table_bucket_part_index/CREATE_TABLE/
> - [2] StarRocks - Table Design
>   https://docs.starrocks.io/docs/table_design/table_types/


## 1. 数据模型: StarRocks 建表的核心设计决策

 StarRocks 从 Doris 分叉(2020)，保留了四种数据模型但做了关键改进:
   最大差异: StarRocks 有独立的 PRIMARY KEY 语法，Doris 没有。

 设计哲学:
   Doris:     UNIQUE KEY + PROPERTIES("enable_unique_key_merge_on_write") 切换实现
   StarRocks: PRIMARY KEY 是独立模型，语义更清晰，实现也独立优化
   ClickHouse: ENGINE 选择(MergeTree 家族)
   MySQL:     无模型概念，统一 InnoDB 行存

## 2. Duplicate Key 模型 (保留全部行，事实表/日志表)

```sql
CREATE TABLE users (
    id         BIGINT       NOT NULL,
    username   VARCHAR(64)  NOT NULL,
    email      VARCHAR(255) NOT NULL,
    age        INT,
    balance    DECIMAL(10,2) DEFAULT '0.00',
    bio        STRING,
    created_at DATETIME     NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at DATETIME     NOT NULL DEFAULT CURRENT_TIMESTAMP
)
DUPLICATE KEY(id)
DISTRIBUTED BY HASH(id) BUCKETS 16
PROPERTIES ("replication_num" = "3");

```

 与 Doris 完全相同的语法(同源)。Key 列仅用于排序，不强制唯一。

## 3. Aggregate Key 模型 (写入时预聚合)

```sql
CREATE TABLE daily_stats (
    date       DATE         NOT NULL,
    user_id    BIGINT       NOT NULL,
    clicks     BIGINT       SUM      DEFAULT '0',
    revenue    DECIMAL(10,2) SUM     DEFAULT '0',
    last_visit DATETIME     REPLACE
)
AGGREGATE KEY(date, user_id)
DISTRIBUTED BY HASH(user_id) BUCKETS 16
PROPERTIES ("replication_num" = "3");

```

 与 Doris 语法完全一致。Value 列聚合方式: SUM/MIN/MAX/REPLACE/
 REPLACE_IF_NOT_NULL/HLL_UNION/BITMAP_UNION。
 对比 ClickHouse: AggregatingMergeTree + AggregateFunction 列类型更灵活。

## 4. Unique Key 模型 (按主键去重，Merge-on-Read)

```sql
CREATE TABLE users_unique (
    id         BIGINT       NOT NULL,
    username   VARCHAR(64),
    email      VARCHAR(255),
    age        INT,
    updated_at DATETIME
)
UNIQUE KEY(id)
DISTRIBUTED BY HASH(id) BUCKETS 16
PROPERTIES ("replication_num" = "3");

```

 Unique Key = Merge-on-Read，读取时合并相同 Key 的行。
 与 Doris 的 Unique Key 语义相同。读性能不如 Primary Key。

## 5. Primary Key 模型 (1.19+，StarRocks 独有语法)

```sql
CREATE TABLE users_pk (
    id         BIGINT       NOT NULL,
    username   VARCHAR(64),
    email      VARCHAR(255),
    age        INT,
    updated_at DATETIME
)
PRIMARY KEY(id)
DISTRIBUTED BY HASH(id) BUCKETS 16
ORDER BY (username)
PROPERTIES ("replication_num" = "3");

```

 设计分析:
   PRIMARY KEY 是 StarRocks 与 Doris 分叉后最重要的差异化特性。
   实现: Delete + Insert 语义 (Merge-on-Write)。
     写入时通过主键索引定位旧行 → 标记删除 → 插入新行。
     读取时无需合并，点查性能接近 Duplicate Key 模型。

   ORDER BY 子句: 分离排序键与主键(2.0+)。
     PRIMARY KEY 决定去重，ORDER BY 决定存储排序(影响 Zone Map 和扫描效率)。
     这是 StarRocks 独有的设计——Doris 的排序键 = Key 列，无法分离。

 对比:
   Doris:     UNIQUE KEY + "enable_unique_key_merge_on_write"="true" 实现等价功能
              但没有独立语法，也不支持 ORDER BY 分离排序键
   ClickHouse: ReplacingMergeTree(ver)，但去重是后台异步的(不保证实时)
   MySQL:     PRIMARY KEY 原生支持，行级锁 + MVCC

 对引擎开发者的启示:
   StarRocks 的 PRIMARY KEY 设计启示: 在列存引擎上实现行级实时更新，
   核心挑战是主键索引的内存管理。StarRocks 使用 HashIndex + 持久化，
   内存消耗约 = 主键数 × 16 字节。百亿级主键需要 160GB 内存。

## 6. DISTRIBUTED BY HASH: 分桶策略 (必选)

与 Doris 相同，DISTRIBUTED BY HASH 是必选项。

StarRocks 3.0+ 改进: 自动分桶

```sql
CREATE TABLE auto_bucket_table (
    id   BIGINT,
    name VARCHAR(64)
)
DUPLICATE KEY(id)
DISTRIBUTED BY HASH(id);              -- 不指定 BUCKETS，自动推断

```

 设计分析:
   自动分桶根据 BE 节点数和预估数据量自动计算 BUCKETS 数。
   这是 StarRocks 相比 Doris 的体验改进——Doris 仍需手动指定。

 对比:
   Doris:     必须指定 BUCKETS (截至 2.1)
   ClickHouse: 无分桶概念，Distributed 引擎 + sharding_key 分片
   BigQuery:  全自动分布，用户无感知

## 7. 分区表


Range 分区

```sql
CREATE TABLE orders (
    id         BIGINT       NOT NULL,
    user_id    BIGINT       NOT NULL,
    amount     DECIMAL(10,2),
    order_date DATE         NOT NULL
)
DUPLICATE KEY(id)
PARTITION BY RANGE(order_date) (
    PARTITION p2024_01 VALUES LESS THAN ('2024-02-01'),
    PARTITION p2024_02 VALUES LESS THAN ('2024-03-01'),
    PARTITION p2024_03 VALUES LESS THAN ('2024-04-01')
)
DISTRIBUTED BY HASH(user_id) BUCKETS 16;

```

动态分区

```sql
CREATE TABLE orders_dynamic (
    id         BIGINT,
    order_date DATE
)
DUPLICATE KEY(id)
DISTRIBUTED BY HASH(id) BUCKETS 16
PROPERTIES (
    "dynamic_partition.enable"    = "true",
    "dynamic_partition.time_unit" = "DAY",
    "dynamic_partition.start"     = "-30",
    "dynamic_partition.end"       = "3",
    "dynamic_partition.prefix"    = "p"
);

```

 Expression Partition (3.1+，StarRocks 独有):
 PARTITION BY date_trunc('month', order_date)
 自动按表达式创建分区，无需手动定义。
 类似 PostgreSQL 声明式分区，但更简洁。

## 8. CTAS 与外部 Catalog


CTAS (3.0+ 自动推断分布策略)

```sql
CREATE TABLE users_backup AS
SELECT * FROM users WHERE created_at > '2024-01-01';

```

 External Catalog (2.3+)
 CREATE EXTERNAL CATALOG hive_catalog PROPERTIES (
     'type' = 'hive',
     'hive.metastore.uris' = 'thrift://metastore:9083'
 );
 支持: Hive / Iceberg / Hudi / Delta Lake / JDBC / Elasticsearch

 对比:
   Doris:   Multi-Catalog(2.0+)，类似实现。
   Trino:   Connector 架构，最早的多源联邦查询引擎。
   BigQuery: External Table + Federated Query。

## 9. Shared-Data 架构 (3.0+，StarRocks 独有)

 StarRocks 3.0+ 支持存算分离:
   数据持久化在对象存储(S3/OSS/GCS/HDFS)
   BE 节点无状态，本地 SSD 作为缓存层
   可弹性伸缩计算节点，无需数据迁移

 这是 StarRocks 与 Doris 最大的架构差异。
 Doris 也在推进存算分离，但截至 2.1 仍是实验性功能。

 对比:
   Snowflake:  最早的存算分离架构，StarRocks 借鉴了其理念
   BigQuery:   天然存算分离(Serverless)
   ClickHouse: SharedMergeTree(Cloud) 实现存算分离
   Doris:      存算分离仍在开发中

## 10. 版本演进

 StarRocks 1.x:  CBO 优化器(Cascades)，向量化执行引擎
 StarRocks 2.x:  Primary Key 模型，外部表，资源组
 StarRocks 3.0:  存算分离(Shared-Data)，自动分桶，Fast Schema Evolution
 StarRocks 3.1:  Expression Partition，倒排索引
 StarRocks 3.2:  QUALIFY 子句，Pipe 持续加载
 StarRocks 4.0:  ASOF JOIN，JSON 增强

## 11. 横向对比: 建表核心差异

Primary Key 语法:
StarRocks: PRIMARY KEY(cols) — 独立模型，语义清晰
Doris:     UNIQUE KEY + PROPERTIES — 复用 Unique Key，语义模糊
ClickHouse: ReplacingMergeTree(ver) — 异步去重，不保证实时
MySQL:     PRIMARY KEY — 原生唯一约束 + 行级锁

排序键分离:
StarRocks: PRIMARY KEY + ORDER BY 分离(2.0+) — 灵活
Doris:     Key 列 = 排序键，不可分离
ClickHouse: PRIMARY KEY + ORDER BY 分离 — 最早实现此设计

对引擎开发者的参考:
StarRocks 的 CBO 优化器基于 Cascades 框架(Columbia 变体)，
其 Rule 设计和 Cost Model 对自研优化器有直接参考价值。
Primary Key 模型的内存索引设计是实时更新列存表的核心挑战。

