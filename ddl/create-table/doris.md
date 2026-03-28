# Apache Doris: CREATE TABLE

 Apache Doris: CREATE TABLE

 参考资料:
   [1] Doris SQL Manual - CREATE TABLE
       https://doris.apache.org/docs/sql-manual/sql-statements/
   [2] Doris Data Model Design
       https://doris.apache.org/docs/table-design/data-model

## 1. 数据模型: Doris 建表的核心设计决策

 Doris 建表必须选择数据模型，这决定了存储布局、写入语义和查询行为。
 这是 Doris/StarRocks 系最独特的设计——将查询优化前置到 DDL 阶段。

 设计哲学:
   传统 RDBMS (MySQL/PG):  建表只定义 schema，存储行为统一
   Doris/StarRocks:        建表时选择模型，不同模型的写入语义完全不同
   ClickHouse:             通过 ENGINE (MergeTree/ReplacingMergeTree) 实现类似效果
   BigQuery:               无需选择模型，统一列存 + 追加写入

 对引擎开发者的启示:
   将数据模型显式暴露给用户，降低了引擎复杂度(不需要通用 MVCC)，
   但增加了用户的学习成本。ClickHouse 的 ENGINE 是更灵活的方案。

## 2. Duplicate Key 模型 (默认，保留全部行)

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

 设计分析:
   DUPLICATE KEY(id) 仅定义排序键(Sort Key)，不强制唯一。
   所有行都保留，即使 Key 相同——适合明细日志、事件流等场景。
   Key 列决定前缀索引(Short Key Index)的构建，直接影响点查性能。

 对比:
   StarRocks: 语法完全相同(同源)。StarRocks 额外支持 ORDER BY 子句分离排序键。
   ClickHouse: MergeTree ENGINE ORDER BY (id) 类似，也保留所有行。
   MySQL:     所有行都保留(INSERT 就是 INSERT)，无需模型选择。

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

 设计分析:
   Value 列必须指定聚合方式: SUM / MIN / MAX / REPLACE / REPLACE_IF_NOT_NULL /
   HLL_UNION / BITMAP_UNION。数据在 Compaction 时按 Key 列聚合。

   这是 Doris 最独特的设计——在存储层完成预聚合，查询时无需再聚合。
   代价: 明细数据丢失，无法还原原始行。

 对比:
   StarRocks:  语法完全相同(同源分叉)。
   ClickHouse: AggregatingMergeTree + AggregateFunction 类型实现类似功能，
               但 ClickHouse 的聚合函数状态存储更灵活(支持 quantile 等)。
   BigQuery:   无预聚合，依赖物化视图 + 查询时聚合。

## 4. Unique Key 模型 (按主键去重，保留最新行)

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

Merge-on-Write (1.2+，推荐，2.1+ 默认启用):

```sql
CREATE TABLE users_mow (
    id         BIGINT       NOT NULL,
    username   VARCHAR(64),
    email      VARCHAR(255),
    age        INT,
    updated_at DATETIME
)
UNIQUE KEY(id)
DISTRIBUTED BY HASH(id) BUCKETS 16
PROPERTIES (
    "replication_num" = "3",
    "enable_unique_key_merge_on_write" = "true"
);

```

 设计分析:
   Unique Key 有两种实现:
     Merge-on-Read (MoR):  写入追加，读取时合并——写快读慢
     Merge-on-Write (MoW): 写入时原地更新——写慢读快(1.2+)

   Doris 没有独立的 PRIMARY KEY 语法(不同于 StarRocks)。
   Unique Key + MoW 本质上等价于 StarRocks 的 Primary Key 模型。

 对比:
   StarRocks:  有独立的 PRIMARY KEY 语法(1.19+)，更清晰
   ClickHouse: ReplacingMergeTree 类似，但去重是最终一致的(后台 Merge 触发)
   MySQL:      PRIMARY KEY 原生唯一约束 + 行级锁
   BigQuery:   不支持 UPSERT 语义，只有 MERGE 语句

## 5. DISTRIBUTED BY HASH: 分桶策略 (必选)

 Doris 的 DISTRIBUTED BY HASH 是必选项，这是与传统数据库最大的语法差异。

 设计分析:
   分桶(Bucket) = 数据在单个分区内的最小分布单元。
   每个 Bucket 对应一个物理 Tablet(数据文件)，分布在不同 BE 节点上。
   BUCKETS 数量 = 并行度上限。过少导致热点，过多导致小文件。

   经验法则: 每个 Bucket 的数据量 100MB ~ 1GB
   10 亿行 × 100 字节/行 = 100GB → BUCKETS 100~1000

 对比:
   StarRocks:  完全相同的语法(同源)。3.0+ 支持自动 BUCKETS(不指定数量)。
   ClickHouse: 无分桶概念，通过 Distributed 引擎 + sharding_key 分片。
   BigQuery:   自动分布(用户无需关心)，可选 CLUSTER BY 控制排序。
   MySQL:      单机无分桶；分库分表中间件(ShardingSphere) 提供类似能力。

 对引擎开发者的启示:
   强制用户指定分桶策略是"正确但不友好"的设计。
   StarRocks 3.0+ 的自动分桶是更好的折中——默认自动，允许手动覆盖。

## 6. 分区表: RANGE / LIST 分区


Range 分区(最常用)

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

List 分区(2.0+)

```sql
CREATE TABLE events_by_region (
    event_id   BIGINT       NOT NULL,
    region     VARCHAR(64)  NOT NULL,
    event_name VARCHAR(128)
)
DUPLICATE KEY(event_id)
PARTITION BY LIST(region) (
    PARTITION p_cn VALUES IN ('cn-beijing', 'cn-shanghai'),
    PARTITION p_us VALUES IN ('us-east', 'us-west')
)
DISTRIBUTED BY HASH(event_id) BUCKETS 8;

```

动态分区(自动创建/删除)

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

 设计分析:
   Doris 采用 PARTITION + BUCKET 两层数据分布:
     第一层 PARTITION: 按时间/枚举裁剪数据(Partition Pruning)
     第二层 BUCKET:    按 Hash 分散负载(并行查询)

   动态分区是 Doris 独有的自动管理机制，类似 Oracle 的 INTERVAL 分区。

 对比:
   StarRocks:  相同的两层分布。3.1+ 新增 Expression Partition(自动按表达式)。
   ClickHouse: PARTITION BY 表达式 + ORDER BY 排序键(无独立分桶)。
   BigQuery:   PARTITION BY DATE/TIMESTAMP/INT + 可选 CLUSTER BY(最多 4 列)。
   MySQL:      PARTITION BY RANGE/LIST/HASH，但无分桶层。

## 7. CTAS 与外部表


CTAS (Create Table As Select)

```sql
CREATE TABLE users_backup AS
SELECT * FROM users WHERE created_at > '2024-01-01';

```

 Multi-Catalog 外部表(2.0+): 直接查询外部数据源
 CREATE CATALOG hive_catalog PROPERTIES (
     'type' = 'hms',
     'hive.metastore.uris' = 'thrift://metastore:9083'
 );
 SELECT * FROM hive_catalog.db.table;

 对比:
   StarRocks: External Catalog(2.3+)，语法和能力类似。
   ClickHouse: 通过 TABLE FUNCTION 查外部源(s3/hdfs/mysql)。
   BigQuery:  External Table + Federated Query。

 对引擎开发者的启示:
   Multi-Catalog 是"计算引擎化"的标志——引擎从存储系统
   演变为查询层，可以查询任意外部存储。
   Trino/Presto 最早实现了这个架构，Doris/StarRocks 借鉴并整合。

## 8. 版本演进

 Doris 1.0:  向量化执行引擎，基础四模型
 Doris 1.2:  Merge-on-Write Unique Key，Light Schema Change，ARRAY 类型
 Doris 2.0:  Nereids 优化器(CBO)，Multi-Catalog，倒排索引，MAP/STRUCT 类型
 Doris 2.1:  AUTO_INCREMENT，递归 CTE，JSONB，Variant 类型，AUTO PARTITION
 Doris 3.0:  存算分离(Cloud-Native)，自动物化视图增强

## 9. 横向对比: 建表核心差异

数据模型:
- **Doris**: 4 种模型(DDL 选择)，UNIQUE KEY 用 PROPERTIES 切换 MoR/MoW
- **StarRocks**: 4 种模型(DDL 选择)，PRIMARY KEY 独立语法，更清晰
- **ClickHouse**: ENGINE 选择(MergeTree/Replacing/Aggregating/...)
- **MySQL**: 无模型概念，统一行存 + MVCC
- **BigQuery**: 无模型概念，统一列存 + 追加写入

分布策略:
- **Doris**: DISTRIBUTED BY HASH (必选) + PARTITION BY RANGE/LIST
- **StarRocks**: 相同(同源)。3.0+ 支持自动 BUCKETS
- **ClickHouse**: PARTITION BY 表达式 + Distributed 引擎分片
- **BigQuery**: 自动分布 + 可选 CLUSTER BY

对引擎开发者的启示:
Doris 建表语法的设计反映了"用户负责数据分布"的理念。
这在性能上是最优的，但用户体验不佳。
- **现代趋势是自动化**: BigQuery 全自动，StarRocks 3.0 半自动。
