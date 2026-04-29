# 分区智能连接 (Partition-Wise Join)

两张事实表都按 `customer_id` 分区，且分区数与边界完全一致——这种"对齐"让 JOIN 可以**分区对分区独立执行**：每个分区的 JOIN 互相独立、可并行、不需要任何跨节点数据移动。这就是 **分区智能连接 (Partition-Wise Join, PWJ)**，分布式数据库里成本最低的等值 JOIN 形态，它把一次 N×M 的全局 JOIN 拆成 P 次小 JOIN（P = 分区数）。

本文聚焦 PWJ：**完全分区智能连接 (full PWJ)** 与 **部分分区智能连接 (partial PWJ)** 的区别、各引擎的支持现状、与广播 JOIN / 重分布 JOIN / 协同分布 JOIN 的关系，以及 Greenplum `DISTRIBUTED BY`、Spark bucketing、PostgreSQL `enable_partitionwise_join` 三个代表性实现的细节。**关于分区策略本身（Range/List/Hash/Composite）请见 [partition-strategy-comparison.md](./partition-strategy-comparison.md)；关于运行时分区裁剪（DPP/Runtime Filter）请见 [partition-pruning.md](./partition-pruning.md)；关于广播/重分布/协同分布等分布式 JOIN 总览请见 [distributed-join-strategies.md](./distributed-join-strategies.md)。**

## 核心概念：full vs partial

```
两表 A、B 按相同列、相同方法、相同分区数对齐分区:

  A:  ┌──p0──┐ ┌──p1──┐ ┌──p2──┐ ┌──p3──┐
  B:  ┌──p0──┐ ┌──p1──┐ ┌──p2──┐ ┌──p3──┐

完全分区智能连接 (Full Partition-Wise Join):
  A.p0 ⋈ B.p0      A.p1 ⋈ B.p1      A.p2 ⋈ B.p2      A.p3 ⋈ B.p3
  全部并行执行, 各分区结果直接 UNION ALL, 零网络数据移动 (单机内存)
  零 shuffle 流量 (分布式)

部分分区智能连接 (Partial Partition-Wise Join):
  A 已分区, B 未分区/分区不对齐
  -> 只重分布 B (按 A 的分区方式), 不动 A
  -> 也叫单边重分布 (one-sided shuffle)

  A:  ┌──p0──┐ ┌──p1──┐ ┌──p2──┐ ┌──p3──┐    (固定不动)
  B:  ╭──any──╮ ╭──any──╮ ╭──any──╮          (按 A.分区方式重新分布)
       └─────┴─────┴─────┘  →  对齐到 p0..p3
```

PWJ 的三大收益：
- **零/单边网络流量**：full PWJ 完全不 shuffle；partial PWJ 只 shuffle 一侧
- **完美并行度**：每个分区独立 JOIN，可并发到 CPU 核数或节点数
- **更小的 hash 表内存**：每个 worker 只构建一个分区的 hash 表，内存峰值远低于全局 JOIN

代价：要求建表时就把 JOIN key 选为分区键。一旦有多个 JOIN key，最多只能为其中一个对齐。

## 无 SQL 标准

ISO/IEC 9075（SQL:2016 / SQL:2023）**没有** "partition-wise join" 这个概念。它和分区裁剪一样，纯粹是优化器层面的实现特性。各厂商把它命名为：

- Oracle：**Partition-Wise Join** (PWJ)（首创该术语，1999 年 8i）
- PostgreSQL：**Partition-wise Join**（GUC: `enable_partitionwise_join`）
- SQL Server：**Collocated Join** / **Partition-aligned Join**
- Greenplum / Cloudberry：**Co-located Join**（基于 `DISTRIBUTED BY`）
- StarRocks / Doris：**Colocate Join**（基于 `colocate_with` 属性）
- TiDB：**Partition-aligned Join** / **MPP local join**
- OceanBase：**Partition-wise Join** / **本地 JOIN**
- Spark SQL：**Bucketed Join** / **storage-partitioned join**
- Trino / Presto：**Partitioned Join**（自动从 connector 元数据推导）
- CockroachDB：**Locality-optimized Join** / **partitioned hash join**
- BigQuery：（无 SQL 概念，依赖底层 colossus 自动 colocate）
- Snowflake：（micro-partition 自动管理，用户不可控）

由于不在标准里，**同一查询在不同引擎可能完全不同**：有些引擎会自动检测分区对齐并启用 PWJ，有些必须显式声明。判断是否真的走了 PWJ 唯一可靠的方法是 `EXPLAIN`。

## 支持矩阵（45+ 引擎）

### 完全分区智能连接（Full Partition-Wise Join）

| 引擎 | 支持 | 起始版本 | 触发方式 | EXPLAIN 体现 |
|------|------|---------|---------|-------------|
| Oracle | 是 | 8i (1999) | 两表分区方式相同（自动） | `PARTITION HASH ALL` 包住 `HASH JOIN` |
| PostgreSQL | 是 | 11 (2018) | `enable_partitionwise_join = on` | `Append` 下若干 `Hash Join` |
| MySQL | 否 | -- | 无 MPP 概念 | -- |
| MariaDB | 否 | -- | -- | -- |
| SQLite | 否 | -- | -- | -- |
| SQL Server | 是 | 2008 | 相同 PARTITION SCHEME | `Constant Scan + Nested Loops + Filter` per partition |
| DB2 | 是 | DPF / pureScale | 相同 distribution key | `Co-located Join` |
| Snowflake | 不适用 | -- | 无用户分区，micro-partition 自动 | -- |
| BigQuery | 不适用 | -- | 无用户控制的物理分布 | -- |
| Redshift | 是 | GA | DISTSTYLE KEY + 相同 DISTKEY | `DS_DIST_NONE` |
| DuckDB | 部分 | 0.10+ | Hive 分区目录 | -- |
| ClickHouse | 否 | -- | 无传统 JOIN 分区对齐 | -- |
| Trino | 是 | 早期 | Connector 暴露 partitioning + 相同 bucket count | `Partitioned (LOCAL)` |
| Presto | 是 | 0.230+ | 同 Trino | `LOCAL` exchange |
| Spark SQL | 是 | 2.0 (2016) | 两表 bucketed by 相同列且 bucket 数相同 | `BucketedScan` 无 Exchange |
| Hive | 是 | 0.6+ | Bucketed Map Join (SMB) | `Sort Merge Bucket Join` |
| Flink SQL | 部分 | 1.16+ | Lookup join + partitioned source | -- |
| Databricks | 是 | GA | Spark bucketing / Liquid Clustering | 同 Spark |
| Teradata | 是 | V2R5+ | 相同 PI（Primary Index） | `Direct Join` (本地) |
| Greenplum | 是 | 4+ | `DISTRIBUTED BY` 相同列 | `Hash Join` 无 Motion |
| CockroachDB | 是 | 19.x+ | 相同 PARTITION BY + LOCALITY | `partitioned hash joiner` |
| TiDB | 是 | 6.1+ | TiFlash MPP + 分区表 hash 一致 | `MppExchange (PassThrough)` |
| OceanBase | 是 | 1.0+ | 相同分区方式（`tablegroup`） | `本地 JOIN` |
| YugabyteDB | 是 | 继承 PG 11+ | 同 PG | 同 PG |
| SingleStore | 是 | GA | 相同 SHARD KEY | `LocalJoin` |
| Vertica | 是 | GA | 相同 segmentation expression | `JOIN ... INNER (LOCAL)` |
| Impala | 是 | 2.x+ | 相同 Kudu/HDFS partitioning | -- |
| StarRocks | 是 | GA | `colocate_with` group | `Colocate Join` |
| Doris | 是 | GA | `colocate_with` group | `COLOCATE JOIN` |
| MaxCompute | 是 | GA | `CLUSTERED BY` + `BUCKETED INTO` | -- |
| MonetDB | 部分 | -- | MERGE TABLE 分区对齐 | -- |
| CrateDB | 部分 | -- | -- | -- |
| TimescaleDB | 是 | 继承 PG | Hypertable + space partitioning 对齐 | -- |
| QuestDB | 不适用 | -- | 单时间序列 | -- |
| Exasol | 自动 | -- | 自动 colocation（用户无可见分区） | -- |
| SAP HANA | 是 | GA | 相同 partition spec | `LOCAL JOIN` |
| Informix | 是 | 早期 | 相同 fragmentation 策略 | -- |
| Firebird | 否 | -- | 无原生分区 | -- |
| H2 | 否 | -- | 无 MPP | -- |
| HSQLDB | 否 | -- | -- | -- |
| Derby | 否 | -- | -- | -- |
| Amazon Athena | 是 | GA | 继承 Trino | 同 Trino |
| Azure Synapse | 是 | GA | 相同 DISTRIBUTION = HASH(col) | `DistributionMoveOperation = None` |
| Google Spanner | 是 | GA | Interleaved tables 父子表 | `local_join` |
| Materialize | 部分 | -- | dataflow 内部对齐 | -- |
| RisingWave | 部分 | -- | 流处理 keyed shuffle | -- |
| InfluxDB IOx | 不适用 | -- | 时间序列模型 | -- |
| DatabendDB | 部分 | -- | -- | -- |
| Yellowbrick | 是 | GA | 相同 distribution | -- |
| Firebolt | 部分 | -- | -- | -- |

> 约 30 个引擎支持某种形式的 full PWJ。不支持的基本是单机引擎（SQLite、H2、Derby、Firebird、HSQLDB）、流处理引擎（部分 Materialize/RisingWave 行为）或不暴露物理分区的云数仓（Snowflake、BigQuery，由内部自动 colocate）。

### 部分分区智能连接（Partial Partition-Wise Join）

| 引擎 | 支持 | 起始版本 | 备注 |
|------|------|---------|------|
| Oracle | 是 | 8i (1999) | 单边 redistribute |
| PostgreSQL | 否 | -- | 11 起仅 full PWJ；partial 需手工 CTE |
| SQL Server | 是 | 2008 | Repartition Streams + Parallelism |
| Greenplum | 是 | 4+ | `Redistribute Motion` 单侧 |
| Trino | 是 | 早期 | Source 已分区时只 shuffle 另一侧 |
| Spark SQL | 是 | 3.x+ | AQE 触发动态 repartition；bucketing 单侧 |
| Hive | 部分 | 0.6+ | Bucketed Map Join 仅一侧已分桶 |
| Vertica | 是 | GA | 单边 segmentation broadcast |
| Teradata | 是 | V2R5+ | RowHash redistribution |
| Redshift | 是 | GA | `DS_DIST_INNER` / `DS_DIST_OUTER` |
| Azure Synapse | 是 | GA | `Shuffle Move` 单侧 |
| StarRocks | 是 | GA | Bucket Shuffle Join（单侧 shuffle） |
| Doris | 是 | GA | Bucket Shuffle Join |
| TiDB | 是 | 6.1+ | TiFlash MPP single-side partition |
| OceanBase | 是 | 2.0+ | 部分 PWJ |
| SingleStore | 是 | GA | `Reshuffle` 单侧 |
| CockroachDB | 是 | 19.x+ | 单侧 distSQL re-streaming |
| DB2 | 是 | DPF | 单侧 directed redistribute |
| SAP HANA | 是 | GA | -- |
| 其他单机引擎 | 不适用 | -- | 无分布式 |

> 部分 PWJ 的本质是 **"只 shuffle 一侧"**：当大表已经按 JOIN key 分区，但小表（或第二大表）没有时，只重分布小表。流量约等于较小一侧的大小，比双边 shuffle 节省一半网络。

### 协同分布连接（Co-located Join，分布式专属）

co-located join 是 PWJ 在分布式系统的工业实现：建表时声明同一 distribution group，相同 key 落到同一节点。

| 引擎 | 关键字 | 是否需要显式分组 | 节点级 colocate | 桶级 colocate |
|------|-------|----------------|----------------|--------------|
| Greenplum | `DISTRIBUTED BY (col)` | 否（推断同 key 即对齐） | 是 | 否 |
| Cloudberry / HAWQ | `DISTRIBUTED BY` | 同 GP | 是 | 否 |
| StarRocks | `PROPERTIES("colocate_with"="g1")` | 是 | 是 | 是（按桶） |
| Doris | `PROPERTIES("colocate_with"="g1")` | 是 | 是 | 是 |
| Vertica | `SEGMENTED BY HASH(col)` + 一致 projection | 否 | 是 | -- |
| Teradata | Primary Index 相同 | 否 | 是 (AMP) | -- |
| Redshift | `DISTSTYLE KEY DISTKEY(col)` | 否 | 是 | -- |
| Synapse | `WITH (DISTRIBUTION = HASH(col))` | 否 | 是 | -- |
| SingleStore | `SHARD KEY (col)` | 否 | 是 | -- |
| Spanner | `INTERLEAVE IN PARENT` | 是（声明父子关系） | 是（同 split） | -- |
| CockroachDB | `LOCALITY REGIONAL BY ROW` + `PARTITION BY` | 是 | 是 | -- |
| OceanBase | `tablegroup` + 相同分区方式 | 是 | 是 | 是 |
| TiDB | 自动 hash + `tiflash_replica` | 否（自动） | 是 | 是 |
| BigQuery | 隐式 | 否 | 自动 | -- |
| Snowflake | 隐式 micro-partition | 否 | 自动 | -- |

### 与广播 JOIN、重分布的对比

| 策略 | 网络流量 | 内存峰值 | 何时优于 PWJ |
|------|---------|---------|-------------|
| **Full PWJ** | 0 | 1 个分区的 hash 表 | 总是首选（如可达成） |
| **Partial PWJ** | 单侧 ~\|B\| | 1 个分区 | 只有大表已分区 |
| **Broadcast** | \|small\| × N | 整个小表 | 一侧 < 几 GB |
| **Hash Repartition (Shuffle)** | \|A\| + \|B\| | 1 个分区 | 都不大 / 都未分区 |
| **Replicated table** | 0 | 全表 | 维度表很小 |

### 分区交换 (Partition Exchange)

部分引擎支持把一张表与另一张表的某个分区做"原子交换"，是 PWJ 的运维姊妹：批量 ETL 时先在 staging 表上做完聚合/索引，再 EXCHANGE 进事实表。

| 引擎 | 语法 | 备注 |
|------|------|------|
| Oracle | `ALTER TABLE ... EXCHANGE PARTITION` | 8i+，零数据移动 |
| PostgreSQL | `ALTER TABLE DETACH/ATTACH PARTITION` | 12+，等价交换 |
| MySQL | `ALTER TABLE ... EXCHANGE PARTITION` | 5.6+ |
| SQL Server | `ALTER TABLE ... SWITCH PARTITION` | 2005+ |
| DB2 | `ALTER TABLE ... ATTACH/DETACH` | LUW 9.7+ |
| MariaDB | `ALTER TABLE ... EXCHANGE PARTITION` | 同 MySQL |
| OceanBase | `ALTER TABLE ... EXCHANGE` | -- |
| TiDB | `ALTER TABLE ... EXCHANGE PARTITION` | 6.x+ |

虽然不直接是 JOIN 优化，但分区交换确保了 PWJ 所依赖的"分区对齐"在 ETL 周期内可以零成本维持。

## 各引擎 PWJ 触发条件与语法

### Oracle：分区智能连接的鼻祖

Oracle 8i (1999) 首发 PWJ，提出 full / partial 两种模式术语，并通过自动检测决定是否启用。

```sql
-- Full PWJ 的前提：两表按相同方式分区（HASH 或 RANGE 同类型同列同数）
CREATE TABLE sales (
    sale_id    NUMBER,
    cust_id    NUMBER,
    sale_date  DATE,
    amount     NUMBER
)
PARTITION BY HASH(cust_id) PARTITIONS 16;

CREATE TABLE customers (
    cust_id   NUMBER,
    name      VARCHAR2(100),
    region    VARCHAR2(20)
)
PARTITION BY HASH(cust_id) PARTITIONS 16;

-- 等值 JOIN，自动启用 Full PWJ
SELECT s.sale_id, c.name
FROM   sales s
JOIN   customers c ON s.cust_id = c.cust_id;

/*
执行计划:
| Id  | Operation                | Name      | Pstart | Pstop |
| --- | ------------------------ | --------- | ------ | ----- |
| 0   | SELECT STATEMENT         |           |        |       |
| 1   |  PARTITION HASH ALL      |           |   1    | 16    |
| 2   |   HASH JOIN              |           |        |       |
| 3   |    PARTITION HASH ITER   |           |   1    | 16    |
| 4   |     TABLE ACCESS FULL    | CUSTOMERS |   1    | 16    |
| 5   |    TABLE ACCESS FULL     | SALES     |   1    | 16    |

关键: PARTITION HASH ALL 包住 HASH JOIN —— 整个 JOIN 在每个分区内独立执行
*/

-- Partial PWJ：customers 未分区，sales 分区
CREATE TABLE customers_global (
    cust_id   NUMBER,
    name      VARCHAR2(100)
);  -- 未分区

SELECT s.sale_id, c.name
FROM   sales s
JOIN   customers_global c ON s.cust_id = c.cust_id;

/*
| 1 |  PX COORDINATOR              |
| 2 |   PX SEND QC (RANDOM)        |
| 3 |    HASH JOIN                 |
| 4 |     PX RECEIVE               |
| 5 |      PX SEND PARTITION (KEY) |  <- customers_global 按 cust_id 重分布
| 6 |       TABLE ACCESS FULL      | CUSTOMERS_GLOBAL
| 7 |     PX BLOCK ITERATOR        |
| 8 |      TABLE ACCESS FULL       | SALES   <- sales 不动
*/

-- 双层分区（Composite）的 PWJ
CREATE TABLE orders_partitioned (
    order_id   NUMBER,
    cust_id    NUMBER,
    order_date DATE,
    amount     NUMBER
)
PARTITION BY RANGE(order_date)
SUBPARTITION BY HASH(cust_id) SUBPARTITIONS 8 (
    PARTITION p2024 VALUES LESS THAN (DATE '2025-01-01'),
    PARTITION p2025 VALUES LESS THAN (DATE '2026-01-01')
);
-- 与按 cust_id HASH(8) 分区的 customers JOIN 时，
-- Oracle 会启用 SUBPARTITION-WISE JOIN（只在子分区粒度并行）
```

### PostgreSQL：enable_partitionwise_join (11+)

PostgreSQL 11 (2018-09) 引入 PWJ 支持，受控于 GUC `enable_partitionwise_join`（默认 **off**！）。

```sql
-- 必须显式开启
SET enable_partitionwise_join = on;
SET enable_partitionwise_aggregate = on;  -- 同步建议开启 (PG 11+)

-- 两表按相同列做 HASH 或 RANGE 分区
CREATE TABLE sales (
    sale_id   bigint,
    cust_id   bigint,
    sale_date date,
    amount    numeric
) PARTITION BY HASH (cust_id);

CREATE TABLE sales_p0 PARTITION OF sales FOR VALUES WITH (modulus 4, remainder 0);
CREATE TABLE sales_p1 PARTITION OF sales FOR VALUES WITH (modulus 4, remainder 1);
CREATE TABLE sales_p2 PARTITION OF sales FOR VALUES WITH (modulus 4, remainder 2);
CREATE TABLE sales_p3 PARTITION OF sales FOR VALUES WITH (modulus 4, remainder 3);

CREATE TABLE customers (
    cust_id bigint,
    name    text
) PARTITION BY HASH (cust_id);

CREATE TABLE customers_p0 PARTITION OF customers FOR VALUES WITH (modulus 4, remainder 0);
-- ... p1, p2, p3 同样

EXPLAIN (COSTS OFF)
SELECT s.sale_id, c.name
FROM   sales s JOIN customers c USING (cust_id);

/*
 Append
   ->  Hash Join                    <- p0 ⋈ p0
         Hash Cond: (s.cust_id = c.cust_id)
         ->  Seq Scan on sales_p0 s
         ->  Hash
               ->  Seq Scan on customers_p0 c
   ->  Hash Join                    <- p1 ⋈ p1
         ->  Seq Scan on sales_p1 s
         ->  Hash
               ->  Seq Scan on customers_p1 c
   ->  Hash Join                    <- p2 ⋈ p2
         ...
   ->  Hash Join                    <- p3 ⋈ p3
         ...

如果未开 enable_partitionwise_join，会变成:
 Hash Join
   ->  Append (sales 全部分区)
   ->  Hash
         ->  Append (customers 全部分区)
单一全局 Hash Join，丢失了并行 + 分区裁剪机会
*/
```

PostgreSQL 11 PWJ 的限制：
1. 两表的分区方式（PARTITION BY 表达式、类型、操作符族）必须**严格相同**；只要 `modulus` 不同就不会触发
2. 只识别等值 JOIN（`=`）
3. JOIN key 必须是分区列；带函数的 key (`UPPER(cust_id) = UPPER(...)`) 不行
4. 多列分区：所有分区列都要在 JOIN 条件中
5. RANGE 分区的边界必须**完全一致**（10..20 vs 10..15+15..20 不算对齐）

```sql
-- enable_partitionwise_aggregate：分区智能聚合
SET enable_partitionwise_aggregate = on;

EXPLAIN SELECT cust_id, SUM(amount) FROM sales GROUP BY cust_id;
/*
 Append
   ->  HashAggregate                   <- 每分区独立聚合
         ->  Seq Scan on sales_p0
   ->  HashAggregate
         ->  Seq Scan on sales_p1
   ...
*/
-- 默认 off 因为可能在小表上反而慢
-- 与 PWJ 类似，只有当 GROUP BY key 是分区 key 时才能利用
```

PWJ 在 PG 12 / 13 / 14 / 15 / 16 / 17 持续优化：
- PG 12：FOREIGN TABLE 分区也支持 PWJ
- PG 13：增量排序与分区智能 ORDER BY 结合
- PG 14：Outer Join 支持 partitionwise
- PG 17：进一步降低 PWJ 规划阶段开销

### SQL Server：colocated joins since 2008

SQL Server 2005 引入分区表（PARTITION FUNCTION + PARTITION SCHEME），2008 起优化器自动识别"分区对齐"的两个表，避免不必要的并行流交换。

```sql
-- 两表必须使用相同的 PARTITION FUNCTION + PARTITION SCHEME
CREATE PARTITION FUNCTION pf_cust (int) AS RANGE RIGHT
    FOR VALUES (1000, 2000, 3000, 4000);

CREATE PARTITION SCHEME ps_cust AS PARTITION pf_cust
    ALL TO ([PRIMARY]);

CREATE TABLE Sales (
    SaleId   bigint,
    CustId   int NOT NULL,
    Amount   decimal(10,2)
) ON ps_cust(CustId);

CREATE TABLE Customers (
    CustId   int NOT NULL PRIMARY KEY,
    Name     nvarchar(100)
) ON ps_cust(CustId);

-- 等值 JOIN，自动 colocated
SELECT s.SaleId, c.Name
FROM   Sales s INNER JOIN Customers c ON s.CustId = c.CustId;

/*
执行计划在分区列上有 "Constant Scan" + "Nested Loops" + "Filter" 模式
或在并行计划中显示 "DistributeStreams: Hash → Hash" 被消除
关键: Actual Partition Count 显示分区粒度并行
*/

-- Azure Synapse Analytics（基于 SQL Server 引擎，但 MPP 化）
CREATE TABLE Sales
WITH ( DISTRIBUTION = HASH(CustId) )
AS SELECT * FROM source_sales;

CREATE TABLE Customers
WITH ( DISTRIBUTION = HASH(CustId) )
AS SELECT * FROM source_customers;

-- 自动 co-located join，EXPLAIN 中 DistributionMoveOperation = None
SELECT s.SaleId, c.Name FROM Sales s JOIN Customers c ON s.CustId = c.CustId;
```

### CockroachDB：partitioned tables + locality

CockroachDB 19.1 (2019) 引入企业版的 PARTITION BY，支持基于 LOCALITY 的 PWJ。

```sql
-- 多区域部署，按 region 分区
CREATE TABLE users (
    id        UUID PRIMARY KEY,
    region    STRING NOT NULL,
    name      STRING
) LOCALITY REGIONAL BY ROW;
-- 或显式 PARTITION BY

CREATE TABLE orders (
    id          UUID PRIMARY KEY,
    user_id     UUID NOT NULL,
    region      STRING NOT NULL,
    amount      DECIMAL,
    FOREIGN KEY (user_id) REFERENCES users(id)
) LOCALITY REGIONAL BY ROW;

-- 同 region 的 user 与 order 在同一节点
SELECT u.name, o.amount
FROM   users u JOIN orders o ON u.id = o.user_id
WHERE  u.region = 'us-west' AND o.region = 'us-west';

-- EXPLAIN 显示 partitioned hash joiner 而非 distSQL hashJoiner
-- 不需要跨区域 shuffle
```

### TiDB / OceanBase：自动 colocate

TiDB 在 6.1+ 启用 TiFlash MPP 模式，支持 partition-aligned join：

```sql
-- TiDB MPP partition-wise join
SET tidb_enforce_mpp = ON;
SET tidb_partition_prune_mode = 'dynamic';

CREATE TABLE sales (
    id      BIGINT,
    cust_id BIGINT,
    amount  DECIMAL(10,2)
) PARTITION BY HASH(cust_id) PARTITIONS 16;

CREATE TABLE customers (
    cust_id BIGINT,
    name    VARCHAR(100)
) PARTITION BY HASH(cust_id) PARTITIONS 16;

-- 在 TiFlash 上 MPP 执行，PassThrough 而非 Broadcast/HashRepartition
EXPLAIN SELECT s.id, c.name FROM sales s JOIN customers c ON s.cust_id = c.cust_id;
/*
TableFullScan_xx              <- TiFlash MPP local scan
└─ Selection_xx
   └─ HashJoin_xx              <- 本地 join，不需要 Exchange
      ├─ ExchangeReceiver(TiFlash[PassThrough])
      └─ ExchangeReceiver(TiFlash[PassThrough])
*/
```

OceanBase 通过 `tablegroup` 显式声明 colocation：

```sql
-- OceanBase tablegroup 自动 PWJ
CREATE TABLEGROUP tg1
    PARTITION BY HASH(cust_id) PARTITIONS 16;

CREATE TABLE sales (
    sale_id  BIGINT,
    cust_id  BIGINT,
    amount   DECIMAL(10,2)
) TABLEGROUP=tg1
  PARTITION BY HASH(cust_id) PARTITIONS 16;

CREATE TABLE customers (
    cust_id  BIGINT,
    name     VARCHAR(100)
) TABLEGROUP=tg1
  PARTITION BY HASH(cust_id) PARTITIONS 16;

-- JOIN 时自动 colocated, 不产生 EXCHANGE 算子
SELECT * FROM sales s JOIN customers c ON s.cust_id = c.cust_id;
```

### Greenplum：DISTRIBUTED BY co-location

Greenplum 4.x 起，所有表都必须有 `DISTRIBUTED BY` 子句（默认按主键），相同 distribution key 的表在 JOIN 时自动 co-located。这是最早的"自动 PWJ"实现之一。

```sql
-- Greenplum 的核心模型: 表必须 distributed
CREATE TABLE sales (
    sale_id    bigint,
    cust_id    bigint,
    sale_date  date,
    amount     numeric
)
DISTRIBUTED BY (cust_id);

CREATE TABLE customers (
    cust_id    bigint,
    name       text
)
DISTRIBUTED BY (cust_id);

-- 自动 co-located join，无 Motion 节点
EXPLAIN SELECT * FROM sales s JOIN customers c USING (cust_id);
/*
Gather Motion 6:1  (slice1; segments: 6)
  ->  Hash Join                          <- 本地 hash join
        Hash Cond: (s.cust_id = c.cust_id)
        ->  Seq Scan on sales s
        ->  Hash
              ->  Seq Scan on customers c
                                         <- 没有 Redistribute Motion
*/

-- 反例: distribution key 不同 → 触发 Redistribute Motion
CREATE TABLE orders (
    order_id   bigint,
    cust_id    bigint,
    amount     numeric
)
DISTRIBUTED BY (order_id);   -- 不是 cust_id

EXPLAIN SELECT * FROM orders o JOIN customers c USING (cust_id);
/*
Gather Motion 6:1
  ->  Hash Join
        ->  Redistribute Motion 6:6     <- orders 按 cust_id 重分布
              Hash Key: o.cust_id
              ->  Seq Scan on orders o
        ->  Hash
              ->  Seq Scan on customers c

或者: 反向重分布 customers (取决于优化器选择)
*/

-- 三表 PWJ
CREATE TABLE orders (cust_id bigint, ...) DISTRIBUTED BY (cust_id);
CREATE TABLE order_items (cust_id bigint, ...) DISTRIBUTED BY (cust_id);
CREATE TABLE customers (cust_id bigint, ...) DISTRIBUTED BY (cust_id);

-- 三表 JOIN 完全 co-located
SELECT * FROM orders o
  JOIN order_items i USING (cust_id)
  JOIN customers c USING (cust_id);

-- 复合 distribution key
CREATE TABLE events (
    event_id  bigint,
    user_id   bigint,
    event_ts  timestamp
)
DISTRIBUTED BY (user_id, event_id);
-- 注意: DISTRIBUTED BY (a, b) 与 DISTRIBUTED BY (a) 不兼容
-- 因为 hash(a, b) ≠ hash(a)
```

Greenplum 哲学：
- 没有 distribution key 的表用 `DISTRIBUTED RANDOMLY`，几乎不能 PWJ
- `DISTRIBUTED REPLICATED` (5+) 把表全量复制到每个 segment，相当于把任何 JOIN 都变成 co-located（适合维度表 < 几 GB）
- 优化器在两表 distribution key 不同但都很大时，会选择"较小一侧 redistribute" 而非双侧 redistribute

### Spark SQL：bucketing for shuffle elimination

Spark SQL 2.0 (2016) 引入 bucketed table，让两表按相同列、相同 bucket 数预先 hash 分桶，JOIN 时跳过 shuffle。

```sql
-- 创建 bucketed table（Hive metastore 表）
CREATE TABLE sales (
    sale_id  BIGINT,
    cust_id  BIGINT,
    amount   DECIMAL(10,2)
)
USING parquet
CLUSTERED BY (cust_id) INTO 32 BUCKETS;

CREATE TABLE customers (
    cust_id  BIGINT,
    name     STRING
)
USING parquet
CLUSTERED BY (cust_id) INTO 32 BUCKETS;

-- 启用 bucket join 优化
SET spark.sql.sources.bucketing.enabled = true;
SET spark.sql.bucketing.coalesceBucketsInJoin.enabled = true;  -- 3.1+

-- JOIN 自动跳过 Exchange
SELECT s.sale_id, c.name
FROM sales s JOIN customers c ON s.cust_id = c.cust_id;

/*
EXPLAIN 输出:
== Physical Plan ==
*(3) SortMergeJoin [cust_id], [cust_id], Inner
:- *(1) Sort [cust_id ASC NULLS FIRST], false, 0
:  +- *(1) Filter ...
:     +- *(1) FileScan parquet sales[cust_id, ...]
+- *(2) Sort [cust_id ASC NULLS FIRST], false, 0
   +- *(2) Filter ...
      +- *(2) FileScan parquet customers[cust_id, ...]

关键: 没有 Exchange (即 shuffle) 节点
对比未 bucket 版本: 两侧都有 Exchange hashpartitioning(cust_id, 200)
*/
```

Spark bucketing 的限制（与 Hive bucketing 同源）：
1. **bucket 数必须严格相等**：32 vs 64 不行（Spark 3.1 起 `coalesceBucketsInJoin.enabled` 允许 2 倍数关系如 32 vs 64 / 32 vs 16）
2. **bucket 列必须严格匹配**：`cust_id` 与 `customer_id` 不行，即使 JOIN ON 上等价
3. **必须是 managed/external Hive table**：DataFrame API 创建的表无法 bucketed
4. **小文件问题**：每个 bucket 对应一个或多个文件，bucket 太多导致小文件
5. **写入开销**：写入 bucketed 表需要先 shuffle 到 bucket 数

```scala
// DataFrame API 写 bucketed table
df.write
  .bucketBy(32, "cust_id")
  .sortBy("cust_id")
  .saveAsTable("sales")
```

Spark 3.0+ 引入 storage-partitioned join (SPJ)（SPARK-33828）：跳过传统 bucketing 限制，让 connector（Iceberg、Delta）自身暴露 partitioning 信息：

```sql
-- Spark 3.4+: storage-partitioned join (SPJ)
SET spark.sql.iceberg.planning.preserve-data-grouping = true;
SET spark.sql.requireAllClusterKeysForCoPartition = false;

-- Iceberg 的 hidden partitioning 也可以触发 PWJ
-- 不再需要双方 bucket count 严格一致
```

Databricks Photon + Liquid Clustering（2023）进一步弱化了对显式 bucketing 的依赖，按工作负载自适应聚类。

### Hive：Bucketed Map Join 与 Sort-Merge Bucket Join

Hive 0.6 引入 bucketing，0.7 起支持 Bucketed Map Join，0.10+ 引入 Sort-Merge Bucket (SMB) Join——后者是 Spark bucketing 的直接前身。

```sql
-- Bucketed table
CREATE TABLE sales (sale_id BIGINT, cust_id BIGINT, amount DECIMAL)
CLUSTERED BY (cust_id) SORTED BY (cust_id) INTO 32 BUCKETS;

CREATE TABLE customers (cust_id BIGINT, name STRING)
CLUSTERED BY (cust_id) SORTED BY (cust_id) INTO 32 BUCKETS;

-- Sort Merge Bucket Map Join (最优, 0.10+)
SET hive.input.format = org.apache.hadoop.hive.ql.io.BucketizedHiveInputFormat;
SET hive.optimize.bucketmapjoin = true;
SET hive.optimize.bucketmapjoin.sortedmerge = true;
SET hive.auto.convert.sortmerge.join = true;
SET hive.auto.convert.sortmerge.join.noconditionaltask = true;

SELECT /*+ MAPJOIN(c) */ s.sale_id, c.name
FROM sales s JOIN customers c ON s.cust_id = c.cust_id;
-- 直接两端 bucket 对齐 + 已排序 → 流式归并 JOIN
-- Map 端完成，无 Reduce shuffle
```

### Trino / Presto：connector-driven PWJ

Trino / Presto 没有自身的物理分区概念，PWJ 完全依赖底层 connector（Hive、Iceberg、Delta、JDBC）暴露的 partitioning 信息。

```sql
-- Hive connector：基于 bucketed table
SET SESSION hive.bucket_execution_enabled = true;
SET SESSION join_distribution_type = 'AUTOMATIC';

-- 如果两表 Hive 元数据中 bucket 列、bucket 数相同
-- Trino 自动选择 PARTITIONED LOCAL JOIN
EXPLAIN
SELECT s.sale_id, c.name
FROM hive.sales s JOIN hive.customers c ON s.cust_id = c.cust_id;

/*
Local Exchange[REPARTITION] 会被消除
显示 Distribution: PARTITIONED, Local: true
*/

-- Iceberg connector：基于 hidden partitioning
SELECT s.sale_id, c.name
FROM iceberg.sales s JOIN iceberg.customers c ON s.cust_id = c.cust_id;
-- Iceberg 暴露的 partition spec 让 Trino 跳过 shuffle
```

Trino 的 `join_distribution_type` 三种取值：
- `BROADCAST`：强制广播
- `PARTITIONED`：强制 hash redistribute（如果可 colocate 则跳过 shuffle）
- `AUTOMATIC`：CBO 选择（默认）

### StarRocks / Doris：Colocate Join

StarRocks 和 Doris (Apache) 都通过表属性 `colocate_with` 显式建立 colocation group：

```sql
-- StarRocks / Doris colocate join
CREATE TABLE sales (
    sale_id   BIGINT,
    cust_id   BIGINT,
    amount    DECIMAL(10,2)
)
DUPLICATE KEY(sale_id)
DISTRIBUTED BY HASH(cust_id) BUCKETS 32
PROPERTIES (
    "colocate_with" = "group1",
    "replication_num" = "3"
);

CREATE TABLE customers (
    cust_id   BIGINT,
    name      VARCHAR(100)
)
DUPLICATE KEY(cust_id)
DISTRIBUTED BY HASH(cust_id) BUCKETS 32
PROPERTIES (
    "colocate_with" = "group1",
    "replication_num" = "3"
);

-- 同一 group 的表保证: 相同 hash bucket 落在相同 BE 节点
-- JOIN 自动 COLOCATE
EXPLAIN SELECT s.sale_id, c.name
FROM sales s JOIN customers c ON s.cust_id = c.cust_id;
/*
| 4 | HASH JOIN                                        |
|   |   join op: INNER JOIN (COLOCATE)                 |  <- 关键标记
|   |   colocate: true                                 |
*/
```

`colocate_with` 的硬约束：
1. 相同 distribution key 列名、列类型、列数
2. 相同 bucket 数
3. 相同 replication_num
4. 相同 partition 列类型（每个 partition 内 colocate 独立计算）
5. 不能跨 backend 集群

如果约束不满足，会报错 `Colocate tables must have same xxxx`，强制提醒不要错配。

### Bucket Shuffle Join（partial PWJ 的工业实现）

Doris 1.x、StarRocks 都支持 Bucket Shuffle Join：当左表已经按 JOIN key 分桶但右表没有，只需 shuffle 右表（按左表的 bucket 函数 + bucket 数）。这是 partial PWJ 在 MPP 系统的常见称呼。

```sql
-- StarRocks/Doris: bucket shuffle join
SET disable_join_reorder = false;
SET runtime_filter_mode = 'GLOBAL';

-- sales 已 bucketed by cust_id, 但 some_other_table 没有
SELECT * FROM sales s JOIN some_other_table o ON s.cust_id = o.cust_id;
/*
| HASH JOIN                                            |
|   join op: INNER JOIN (BUCKET_SHUFFLE)               |
|   ...
| EXCHANGE BUCKET_SHUFFLE                              |  <- 仅 right 侧重分布
*/
```

### CockroachDB：locality-optimized join

```sql
-- CockroachDB 多区域 PWJ
CREATE TABLE users (
    id          UUID PRIMARY KEY,
    region      STRING NOT NULL CHECK (region IN ('us-west','us-east','eu')),
    name        STRING
) LOCALITY REGIONAL BY ROW;

CREATE TABLE orders (
    id          UUID,
    user_id     UUID NOT NULL,
    region      STRING NOT NULL,
    amount      DECIMAL,
    PRIMARY KEY (region, id),
    FOREIGN KEY (user_id) REFERENCES users(id)
) LOCALITY REGIONAL BY ROW;

-- region-pinned PWJ
SELECT u.name, o.amount
FROM users u JOIN orders o ON u.id = o.user_id
WHERE u.region = 'us-west';

-- EXPLAIN ANALYZE 显示:
-- partitioned hash joiner，规避跨区域 follow-the-workload 流量
```

### Snowflake：micro-partition (无用户分区)

Snowflake 取消了用户级 partition 的概念，改用 micro-partition + clustering keys。PWJ 概念被替换为"clustering pruning + colocate placement"，由引擎自动决定。

```sql
-- Snowflake clustering key (近似 PWJ 的语义)
CREATE TABLE sales (
    sale_id   BIGINT,
    cust_id   BIGINT,
    amount    NUMBER(10,2)
)
CLUSTER BY (cust_id);

CREATE TABLE customers (
    cust_id   BIGINT,
    name      VARCHAR
)
CLUSTER BY (cust_id);

-- Snowflake 自动:
-- 1. 按 cust_id clustering 重组 micro-partition
-- 2. JOIN 时基于 metadata 服务做 partition-aware reduce
-- 3. EXPLAIN 显示 "clustering pruning: X% of micro-partitions scanned"
SELECT s.*, c.name FROM sales s JOIN customers c USING (cust_id);
```

Snowflake 不暴露物理分区是否对齐，**因此用户无法判断是否启用了 PWJ**——只能从查询性能间接观察。

### ClickHouse：SAMPLE join 与无传统 PWJ

ClickHouse 不支持传统意义的"分区对齐 JOIN"。它的 JOIN 模型是：
- 默认右表广播（小表）
- `GLOBAL JOIN` 触发右表 shuffle
- 单分片表 + 相同 sharding key 时退化为本地 JOIN（隐式 colocate）

```sql
-- ClickHouse 分布式表 + 相同 sharding key
CREATE TABLE sales_local ON CLUSTER c (
    sale_id  UInt64,
    cust_id  UInt64,
    amount   Decimal(10,2)
) ENGINE = MergeTree() ORDER BY cust_id;

CREATE TABLE sales ON CLUSTER c AS sales_local
    ENGINE = Distributed(c, default, sales_local, cust_id);

CREATE TABLE customers_local ON CLUSTER c (
    cust_id  UInt64,
    name     String
) ENGINE = MergeTree() ORDER BY cust_id;

CREATE TABLE customers ON CLUSTER c AS customers_local
    ENGINE = Distributed(c, default, customers_local, cust_id);

-- 当两侧 Distributed 表使用相同 sharding key 时
-- 走 LOCAL JOIN（每个 shard 独立 join 自己的本地数据）
SELECT s.sale_id, c.name
FROM sales s JOIN customers c ON s.cust_id = c.cust_id
SETTINGS distributed_product_mode = 'local';

-- SAMPLE join: 基于 SAMPLE BY 的特殊场景（非 PWJ，保留用于对比）
CREATE TABLE events (event_id UInt64, user_id UInt64, ts DateTime)
ENGINE = MergeTree()
ORDER BY (user_id, ts)
SAMPLE BY user_id;

-- 在两表都有相同 SAMPLE BY 的前提下, SAMPLE 按 hash 范围裁剪
SELECT * FROM events SAMPLE 0.1 e
JOIN profiles SAMPLE 0.1 p ON e.user_id = p.user_id;
-- 不是真正的 PWJ, 但结合采样能跳过大部分数据
```

### BigQuery：自动 colocate

BigQuery 不暴露分区策略给用户控制 JOIN colocation，依靠 Colossus 自动 colocate 参与 JOIN 的两表。可以用 `CLUSTER BY` 优化但不保证 PWJ。

```sql
-- BigQuery clustering（不是真正的 partition）
CREATE TABLE sales
PARTITION BY DATE(sale_ts)
CLUSTER BY cust_id
AS SELECT * FROM source;

CREATE TABLE customers
CLUSTER BY cust_id
AS SELECT * FROM source;

-- 查询时 EXPLAIN 中体现的是 "Slot Time" 而非分区对齐
-- BigQuery 内部按 col_id 自动分配 slots，自动 reduce
```

## PostgreSQL enable_partitionwise_join 深入

PostgreSQL 11 PWJ 的核心代码在 `src/backend/optimizer/path/joinrels.c`：

```
try_partitionwise_join():
  1. 检查双方 RelOptInfo 是否都是 PARTITIONED
  2. partitioning scheme 是否匹配 (partitioning_is_compatible)
       - PARTITION BY 表达式相同
       - 数据类型、操作符族相同
       - 分区数量相同
       - 各分区的边界 / hash modulus 相同
  3. JOIN 条件包含分区列等值
  4. 对每对配对分区生成子 JOIN path
  5. 用 Append node 包裹所有子 path
```

### 性能对比示例

```sql
-- 测试场景: 两个 1 亿行表, 16 个 hash 分区
-- PG 16, 默认共享内存 4GB

-- 关闭 PWJ
SET enable_partitionwise_join = off;
EXPLAIN (ANALYZE, BUFFERS)
SELECT s.sale_id, c.name FROM sales s JOIN customers c USING (cust_id);
-- Hash Join (cost=... rows=... time=180s)
--   workmem peak: 8 GB (整个 customers 的 hash table)
--   shared hits: 25M, reads: 5M

-- 开启 PWJ
SET enable_partitionwise_join = on;
EXPLAIN (ANALYZE, BUFFERS)
SELECT s.sale_id, c.name FROM sales s JOIN customers c USING (cust_id);
-- Append (time=22s)
--   每个分区的 Hash Join workmem peak: 512 MB (1/16 的 customers)
--   并行度: 16
--   shared hits: 25M, reads: 5M

-- 速度提升约 8 倍, 内存峰值降低约 16 倍
```

### enable_partitionwise_aggregate 的协同

```sql
SET enable_partitionwise_join = on;
SET enable_partitionwise_aggregate = on;

-- 分区智能聚合: GROUP BY 分区 key 时每分区独立聚合再 Append
EXPLAIN SELECT cust_id, SUM(amount) FROM sales GROUP BY cust_id;
/*
 Append
   ->  HashAggregate
         Group Key: cust_id
         ->  Seq Scan on sales_p0
   ->  HashAggregate
         ->  Seq Scan on sales_p1
   ...
*/

-- PWJ + PWAgg 协同: 分区智能 GROUP BY 后再 JOIN
EXPLAIN
SELECT c.name, total
FROM (SELECT cust_id, SUM(amount) total FROM sales GROUP BY cust_id) t
JOIN customers c USING (cust_id);
-- 每分区: HashAggregate -> HashJoin -> Append
```

### PWJ 与并行度的交互

PG 的 PWJ 默认每个分区是一个独立子 path，并行 worker 由 GUC `max_parallel_workers_per_gather` 控制。

```sql
SET max_parallel_workers_per_gather = 8;
SET enable_partitionwise_join = on;
SET parallel_setup_cost = 0;
SET parallel_tuple_cost = 0;

EXPLAIN (ANALYZE)
SELECT s.sale_id, c.name FROM sales s JOIN customers c USING (cust_id);
/*
 Gather
   Workers Planned: 8
   ->  Parallel Append
         ->  Parallel Hash Join (sales_p0, customers_p0)
         ->  Parallel Hash Join (sales_p1, customers_p1)
         ...
*/
```

## Spark bucketing for shuffle elimination

### bucket spec 的元数据格式

```scala
// Spark 在 Hive metastore 中保存的元数据
case class BucketSpec(
    numBuckets: Int,
    bucketColumnNames: Seq[String],
    sortColumnNames: Seq[String])

// SHOW CREATE TABLE 输出
CREATE TABLE sales (...)
CLUSTERED BY (cust_id)
SORTED BY (cust_id)
INTO 32 BUCKETS
TBLPROPERTIES (...)
```

### 触发条件检查（Spark 源码）

```scala
// EnsureRequirements.scala 中决定是否插入 ShuffleExchangeExec
object EnsureRequirements {
  def reorderJoinKeys(...): Boolean = {
    // 1. left/right 都有 BucketSpec
    // 2. bucketColumnNames 与 JOIN keys 完全匹配
    // 3. numBuckets 完全相等 (3.1+ 允许 2 倍数关系)
    // 4. JOIN type 不是 cross/full outer (full outer 也支持但有约束)
    // 5. spark.sql.sources.bucketing.enabled = true
  }
}
```

### Spark 3.1+ coalesceBucketsInJoin

```sql
SET spark.sql.bucketing.coalesceBucketsInJoin.enabled = true;
SET spark.sql.bucketing.coalesceBucketsInJoin.maxBucketRatio = 4;

-- sales 32 buckets, customers 8 buckets (4:1 比例)
-- Spark 3.1+ 会把 sales 4 个相邻 bucket coalesce 成 1 个
-- 实现 partial bucket alignment
```

### Storage-Partitioned Join (SPJ, 3.4+)

SPJ 解决 bucketing 的诸多限制：

```sql
-- Iceberg / Delta connector 支持
SET spark.sql.iceberg.planning.preserve-data-grouping = true;

CREATE TABLE sales (
    sale_id BIGINT,
    cust_id BIGINT,
    amount DECIMAL(10,2)
) USING iceberg
PARTITIONED BY (bucket(32, cust_id));   -- Iceberg hidden partitioning

CREATE TABLE customers (
    cust_id BIGINT,
    name STRING
) USING iceberg
PARTITIONED BY (bucket(32, cust_id));

-- SPJ: 不需要 Hive bucket spec，依靠 Iceberg metadata
SELECT s.sale_id, c.name
FROM sales s JOIN customers c ON s.cust_id = c.cust_id;
-- EXPLAIN 中看到 Distribution: KeyGroupedPartitioning, no Exchange
```

### 与 Adaptive Query Execution (AQE) 的关系

```sql
SET spark.sql.adaptive.enabled = true;
SET spark.sql.adaptive.coalescePartitions.enabled = true;
SET spark.sql.adaptive.skewJoin.enabled = true;

-- AQE 在运行时:
-- 1. coalescePartitions: 合并小分区减少 task 数
-- 2. skewJoin: 拆分倾斜分区 -> 但会破坏 bucketing!
-- 3. localShuffleReader: 读本地 shuffle output, 等价 partial PWJ
```

注意：AQE 的 skew handling 与 bucketing 互相冲突。Spark 3.x 在 bucket join 上禁用 AQE 的 skew split。

## CockroachDB / Spanner 的多区域 PWJ

```sql
-- Spanner interleaved tables (天然 PWJ)
CREATE TABLE Customers (
    customer_id INT64 NOT NULL,
    name STRING(100)
) PRIMARY KEY (customer_id);

CREATE TABLE Orders (
    customer_id INT64 NOT NULL,
    order_id INT64 NOT NULL,
    amount FLOAT64
) PRIMARY KEY (customer_id, order_id),
  INTERLEAVE IN PARENT Customers ON DELETE CASCADE;

-- Customer X 与其所有 Order 物理上同 split
-- JOIN 不需任何跨 split 流量
SELECT c.name, o.amount FROM Customers c JOIN Orders o USING (customer_id);
```

## 关键发现

### 1. PWJ 是分布式 OLAP 的终极目标

任何分布式 JOIN 优化的目标都是把 shuffle 流量降到 0：
```
Shuffle JOIN     >  Partial PWJ        >  Full PWJ        >  Replicated/Broadcast
|A|+|B| 流量        单侧流量              零流量               |B|×N (N 节点)
                                                              (仅适合极小表)
```

### 2. Oracle 25 年领先

Oracle 8i (1999) 首发 full + partial PWJ，定义了术语和算法范式。所有现代 MPP 引擎（Greenplum、Vertica、Teradata、StarRocks）都在重新发明 Oracle 已有 25 年的轮子。

### 3. PostgreSQL 11 (2018) 的迟到引入

PG 直到 2018 年才有 PWJ，且默认关闭。`enable_partitionwise_join` 默认 `off` 的原因：在小分区数（< 4）或小表上反而慢——规划阶段的成本随分区数线性增加。生产 OLAP 场景应当显式打开。

### 4. Spark / Hive 的 bucketing 是 PWJ 的存储层等价物

bucket = "已经 hash 分布的物理目录布局"，bucketed JOIN 就是 storage-aware PWJ。但 Spark bucketing 因严格匹配要求（bucket 数、列名、metastore 类型）在生产中常被弃用，转向 Iceberg + SPJ。

### 5. 显式 colocate 模式 vs 隐式自动模式

| 模式 | 引擎 | 优点 | 缺点 |
|------|------|------|------|
| **显式 group** (StarRocks/Doris/OB tablegroup) | 用户清晰可知是否 colocate | 强约束，可强制提醒错误 | 维护成本，加列要重建 |
| **隐式同 key** (GP/PG/Oracle) | 用户只需保证 distribution key 相同 | 灵活，无显式声明 | 容易"以为对齐其实没对齐" |
| **完全自动** (Snowflake/BigQuery) | 用户无需操心 | 黑盒，性能不可预测 | 大表 JOIN 仍可能 shuffle |

### 6. 三表 PWJ 的链式约束

```
A JOIN B ON a.x=b.x JOIN C ON b.y=c.y
- 如果 A、B 按 x colocate，且 B、C 按 y colocate
- 由于 B 不能同时按 x 和 y 分布
- 至少有一个 JOIN 需要 shuffle 或 broadcast

最佳实践: 把维度表设计为 Replicated（全量复制到每节点）
- Greenplum: DISTRIBUTED REPLICATED
- StarRocks: 单 bucket + replication
- Spark: BROADCAST hint
```

### 7. PWJ 与数据倾斜的天然冲突

PWJ 的并行度由分区数决定，每个分区是一个独立任务。如果某个分区有热点 key（如某大客户 1000 万订单），它会独占一个 worker 而其他 worker 早完成——退化为单线程 JOIN。

解决方案：
- **加盐 (Salt)**：把热点 key 拆为 (key, salt) 复合键
- **Skew-aware bucketing**：StarRocks 7.x、Spark 3.5+ 支持自动检测倾斜分区并拆分
- **维度表广播 hot key**：把热点 key 的维度数据 broadcast，其余 colocate

### 8. PWJ 验证唯一靠 EXPLAIN

由于不在 SQL 标准里，唯一的验证手段是看执行计划：

| 引擎 | 关键标志 |
|------|---------|
| Oracle | `PARTITION HASH ALL` 包住 `HASH JOIN` |
| PostgreSQL | `Append` 下若干 `Hash Join`（而非顶层一个 `Hash Join`） |
| Greenplum | 没有 `Redistribute Motion` 节点 |
| Spark | 没有 `Exchange hashpartitioning` 节点 |
| StarRocks/Doris | `(COLOCATE)` 标记在 HASH JOIN 后 |
| TiDB | `MppExchange (PassThrough)` 而非 `(HashPartition)` |
| Trino | `Distribution: PARTITIONED` + `Local: true` |
| Synapse | `DistributionMoveOperation = None` |

### 9. PWJ 不是 Free Lunch

PWJ 假设两表的分区"完美对齐"。一旦：
- 加列变更分区方式
- 一表分区数变化（导入新数据后 rehash）
- 数据倾斜导致单分区过大
- 跨集群导入数据未保持 colocate

PWJ 优势瞬间消失。生产实践要求 ETL 流水线始终保证 colocate group 内的所有表"同生共死"。

### 10. PWJ 推动了"宽表反范式化"的回潮

由于 PWJ 仅在 distribution key 相同时生效，把多表合并成一个宽表（denormalized fact table）一直是 OLAP 的最佳实践。但 PWJ 让保留范式（normalized）模型可行：只要相关表都按客户/订单 ID colocate，JOIN 几乎免费。

## 引擎实现建议

### 1. PWJ 检测算法

```
输入: 两侧 Plan 的 Distribution / Partitioning 描述
输出: 是否可以 PWJ，以及生成的物理 plan

is_partitionwise_compatible(left_dist, right_dist, join_keys):
    1. 两侧 Distribution 类型相同（都是 Hash / Range / List）
    2. distribution columns ⊆ join_keys
    3. column types 与 hash function 一致
    4. partition count 相同（或允许 coalesce 比例）
    5. partition boundaries 一致（Range / List 情况）

generate_partitionwise_plan():
    for each partition i in 0..N:
        sub_plan = local_join(
            left_partition_i,
            right_partition_i,
            join_keys
        )
    return UnionAll(sub_plans)
```

### 2. 与 Volcano / Cascades CBO 的整合

```
PWJ 是一种 join enforcer / property requirement:
  - LeftDistribution ⊆ RightDistribution
  - JOIN 物理算子的 input requirement 是 "matching distribution"

Cascades 优化:
  1. 如果两侧 distribution 已匹配 → PWJ 物理 op
  2. 否则 → 插入 Repartition / Broadcast enforcer
  3. 选择最低成本: cost(PWJ) vs cost(Repartition + Join) vs cost(Broadcast + Join)
```

### 3. 三表 / 多表的全局优化

```
A JOIN B ON A.x=B.x JOIN C ON B.y=C.y JOIN D ON D.z=A.z

CBO 应该:
  1. 枚举所有 join order
  2. 对每个 join order，决定每步的 distribution
  3. 选择 shuffle 总流量最小的方案

启发式:
  - 优先把"最大表"作为不动 anchor
  - 中等表广播 vs 小表 colocate trade-off
  - 维度表用 REPLICATED 模式可降低大量 shuffle
```

### 4. 分区数不一致的处理

```
sales: 32 buckets, customers: 16 buckets
方案 A (Spark coalesceBuckets): sales 每 2 个 bucket 合并成 1 个 → 16 vs 16
方案 B (Doris bucket shuffle): sales 不动, customers 重新 hash 到 32 → 16→32
方案 C (传统 shuffle): 两侧都重 hash 到 max(32,16)*k → 完全 shuffle

启发: 选择 max-divides-min 比例时优先 coalesce, 否则 shuffle
```

### 5. partition exchange 的事务保证

```
EXCHANGE PARTITION 是 PWJ 长期有效的运维基石:
  1. 必须保证目标分区与源表 schema、约束、索引完全一致
  2. 元数据变更原子: 字典互换指针即可，零数据移动
  3. 与并发查询的隔离:
       - Oracle: 读端继续读旧 segment, exchange 后下次解析读新
       - PG (DETACH/ATTACH): 类似但需要 access exclusive lock
       - SQL Server SWITCH: 也需要 schema lock
```

### 6. EXPLAIN 输出的最佳实践

引擎应当显式标注 PWJ：
- `(COLOCATE)` / `(LOCAL)` / `(PARTITIONED LOCAL)` 关键字
- 显示 partition pair 数（`PARTITION HASH ALL [16/16]`）
- 在 ANALYZE 模式下显示每分区的实际行数和耗时
- 显示 distribution mismatch 时的"未启用 PWJ 原因"

```
建议输出格式:
  Hash Join [partitionwise=true, partitions=16/16]
    Partition Cond: (sales.cust_id = customers.cust_id)
    Distribution: HASH(cust_id) % 16
    NOT applied because: ...   (如果未启用)
```

### 7. PWJ 与 Vectorization 的协同

```
Vectorized 引擎 (DuckDB / ClickHouse / Velox / Arrow):
  - 每个分区一个 batch pipeline
  - Hash table 限制在 batch 大小，CPU cache 友好
  - SIMD probe 在小 hash table 上效率更高

PWJ + Vectorization 是 OLAP 性能的两个独立优化维度，
可以叠加获得 10-100x 加速。
```

### 8. 规划阶段开销控制

PostgreSQL PWJ 默认关闭的核心原因——规划阶段开销线性于分区数：

```
未开 PWJ: 一个全局 Hash Join 路径
开 PWJ: 每对分区生成一个子 path → N 个 path
当 N=1024 时, planner 时间显著增加

优化:
  1. 限制 partition_pruning + partitionwise 协同：
     先 partition prune 出 K 个 partition，再 PWJ
  2. partitionwise_aggregate 也应类似
  3. 设置 work_mem 上限防止过多 hash table 同时创建
```

### 9. 与 Cloud / Storage 分离架构的兼容

```
存算分离 (Snowflake, Databricks, Trino-on-S3):
  - 计算节点没有持久化分区，无法天然 colocate
  - 用 metadata 服务实现 "logical PWJ":
       1. 按 join key bucket 缓存数据到本地磁盘
       2. 同 bucket 数据被同一 worker 处理
       3. 跨 query 复用缓存

Iceberg / Delta / Hudi 的 partition spec 让 connector 暴露 partitioning，
然后由 Spark / Trino 决定是否走 SPJ。
```

### 10. 测试要点

```
功能测试:
  1. 两表完全对齐 → PWJ 启用
  2. 双方 partition count 不同 → 退化为 shuffle 或 coalesce
  3. JOIN key 不是 partition key → PWJ 不启用
  4. 非等值 JOIN → PWJ 不启用
  5. OUTER JOIN 各方向都正确

性能测试:
  - PWJ vs Shuffle 在 10TB 表上的 shuffle 流量对比 (应当 100% vs 0%)
  - PWJ vs Broadcast 在 100GB 维度表上的延迟对比
  - 数据倾斜场景: 10% 分区占 80% 数据时的 worker 利用率

正确性回归:
  - 启用/关闭 PWJ 结果集必须完全一致
  - 启用/关闭 PWAgg 结果必须一致
  - 边界: NULL 在 partition key 中 (NULL ≠ NULL)
```

## 总结对比矩阵

| 能力 | Oracle | PG | SQL Server | Greenplum | Spark | StarRocks/Doris | TiDB | OceanBase | Trino | Snowflake |
|------|--------|----|-----|----|-------|-----------------|------|-----------|-------|-----------|
| Full PWJ | 是 (8i, 1999) | 是 (11, 2018) | 是 (2008) | 是 (4+) | 是 (2.0, 2016) | 是 (colocate) | 是 (6.1+) | 是 (1.0+) | 是 (connector) | 自动 |
| Partial PWJ | 是 | 否 | 是 | 是 | 是 (3.x) | 是 (bucket shuffle) | 是 | 是 | 是 | 自动 |
| 显式 colocate | -- | -- | PARTITION SCHEME | DISTRIBUTED BY | bucketing | colocate_with | tiflash auto | tablegroup | connector | 自动 |
| 分区交换 | 是 | 是 (12+) | 是 (SWITCH) | 是 | -- | 是 | 是 | 是 | -- | -- |
| 多区域 PWJ | RAC | 否 | 否 | -- | -- | 否 | 否 | 是 (主备) | -- | 否 |
| 数据倾斜处理 | 加盐 | 手工 | 手工 | 手工 | AQE | 加盐 | 手工 | 手工 | -- | 自动 |
| 默认开启 | 是 | **否** | 是 | 是 | 否 (要建 bucket 表) | 是 | 是 | 是 | 是 | 是 |

### 引擎选型建议

| 场景 | 推荐方案 | 原因 |
|------|---------|------|
| TB 级 OLTP+OLAP | Oracle 分区表 + PWJ | 25 年成熟，自动检测 |
| 开源 OLAP 数据仓库 | Greenplum DISTRIBUTED BY | 自动 colocate，零配置 |
| 实时 OLAP（亚秒） | StarRocks/Doris colocate_with | 显式声明 + 强校验 |
| 数据湖 + Spark | Iceberg + SPJ (Spark 3.4+) | 跳过 Hive bucketing 限制 |
| 多区域分布式 | CockroachDB LOCALITY | 区域亲和的 PWJ |
| 父子强关联 | Spanner Interleaved | 物理同 split |
| 极端简化 | BigQuery / Snowflake | 用户无需关心 PWJ |
| PostgreSQL OLAP | 显式 SET enable_partitionwise_join = on | 默认关闭，必须开启 |

## 参考资料

- Oracle: [Partition-Wise Joins](https://docs.oracle.com/en/database/oracle/oracle-database/19/vldbg/partition-wise-operations.html)
- PostgreSQL: [enable_partitionwise_join](https://www.postgresql.org/docs/current/runtime-config-query.html#GUC-ENABLE-PARTITIONWISE-JOIN)
- PostgreSQL Wiki: [Partition-wise join](https://wiki.postgresql.org/wiki/Partitionwise_join)
- SQL Server: [Partitioned Tables and Indexes](https://learn.microsoft.com/en-us/sql/relational-databases/partitions/partitioned-tables-and-indexes)
- Greenplum: [Distribution and Skew](https://docs.greenplum.org/6-21/admin_guide/distribution.html)
- Spark SQL: [Bucketing](https://spark.apache.org/docs/latest/sql-data-sources-load-save-functions.html#bucketing-sorting-and-partitioning)
- Spark SPJ (SPARK-33828): [Storage-Partitioned Join](https://issues.apache.org/jira/browse/SPARK-33828)
- StarRocks: [Colocate Join](https://docs.starrocks.io/docs/using_starrocks/Colocate_join/)
- Doris: [Colocation Join](https://doris.apache.org/docs/query-acceleration/join-optimization/colocation-join)
- TiDB: [Partition-aware MPP Execution](https://docs.pingcap.com/tidb/stable/partitioned-table)
- OceanBase: [Tablegroup](https://en.oceanbase.com/docs/oceanbase-database)
- CockroachDB: [Locality-optimized search](https://www.cockroachlabs.com/docs/stable/locality-optimized-search.html)
- Spanner: [Interleaved Tables](https://cloud.google.com/spanner/docs/schema-and-data-model)
- Hive: [Bucketed Map Join](https://cwiki.apache.org/confluence/display/Hive/LanguageManual+JoinOptimization)
- Trino: [Connector partitioning](https://trino.io/docs/current/optimizer/cost-based-optimizations.html)
- Synapse: [Distributed Tables Design](https://learn.microsoft.com/en-us/azure/synapse-analytics/sql-data-warehouse/sql-data-warehouse-tables-distribute)
- Vertica: [Projection Segmentation](https://www.vertica.com/docs/latest/HTML/Content/Authoring/AnalyzingData/Optimizations/JoinOptimizations.htm)
- Teradata: [Primary Index and Co-located Joins](https://docs.teradata.com/r/Database-Design)
