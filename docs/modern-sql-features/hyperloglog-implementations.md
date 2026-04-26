# HyperLogLog 实现对比 (HyperLogLog Implementations)

用 12 KB 内存估算 100 亿基数，误差仅 1.6%——HyperLogLog 是过去二十年最成功的概率数据结构之一，几乎被每一个现代分析型数据库采纳为去重计数的标准武器。

## 一篇论文如何重塑分析数据库

2007 年，Philippe Flajolet、Éric Fusy、Olivier Gandouet、Frédéric Meunier 在 AofA (Conference on Analysis of Algorithms) 发表论文《HyperLogLog: the analysis of a near-optimal cardinality estimation algorithm》。这篇论文给出了一个看似不可能的结论：

- 估算 N 个不同元素，所需内存与 N 几乎无关
- m 个寄存器 (每个 5-6 bit) 即可达到 1.04 / sqrt(m) 的相对标准误差
- m = 2^14 (16384 个寄存器，约 12 KB) 时误差约 0.81%
- 算法可分布式合并，无需中心化协调

在大数据时代，这个结论的工程价值难以高估。"30 天独立访问用户" 这类查询，过去要么在 Hadoop 上跑数小时的 shuffle，要么在 OLAP 引擎上耗光内存。HLL 出现后，同样查询变成秒级、几 KB 内存、可任意聚合维度上卷。

2013 年，Stefan Heule、Marc Nunkesser、Alexander Hall 在 EDBT 发表《HyperLogLog in Practice: Algorithmic Engineering of a State of The Art Cardinality Estimation Algorithm》，提出 HLL++ (HyperLogLog Plus Plus)，进一步降低了小基数的偏差和大基数的内存。HLL++ 成为 BigQuery、Spark、Presto 等引擎的事实标准。

2015 年 Yahoo 开源 Apache DataSketches，提供了 Theta、HLL、KLL、Quantiles 等家族的可移植草图格式，让不同引擎之间的草图互操作成为可能。Druid、Pinot 等 OLAP 引擎将 DataSketches 内嵌进引擎层，把 "近似聚合" 提升为一等公民。

到 2020 年代，HLL 已经从 Flajolet 的论文走入几乎每一个主流 SQL 引擎的函数库——从 Snowflake、BigQuery 到 PostgreSQL 扩展 (postgresql-hll)、SQL Server 2019、Oracle 12c 都内置了 APPROX_COUNT_DISTINCT 或类似函数。

## 理论背景：为什么 HLL 能用 12 KB 数清 100 亿

### 概率与前导零的妙用

HyperLogLog 的核心直觉：假设你抛一枚均匀硬币，连续抛出 k 次正面的概率是 2^-k。如果你观察到某次实验中最长的连续正面数是 K，那么 "实验次数" 至少应该在 2^K 量级。

把每个元素 hash 成 64-bit (或 32-bit) 整数，前导零 (leading zero) 个数就是 "硬币正面" 的连续次数。对一个值集合，记录其中所有元素 hash 后前导零的最大值 K，就能粗略估计集合基数为 2^K。

但单个观察的方差极大。HLL 的工程化做法：

1. 用 hash 的前 p bit 作为 "桶号" (bucket index)，把空间划分成 m = 2^p 个桶
2. 每个桶独立记录 "落入该桶的元素中，剩余 hash 位的最大前导零数"
3. 估计基数时，用调和平均 (harmonic mean) 合并所有桶的贡献，再乘以偏差修正常数 alpha_m

公式简化形式：

```
E = alpha_m * m^2 / sum(2^-M[j])

其中:
  m = 寄存器数 (2^p)
  M[j] = 第 j 个寄存器的值 (该桶元素 hash 剩余位的最大前导零 + 1)
  alpha_m ≈ 0.7213 / (1 + 1.079/m)  (大 m 近似)
```

### 精度、寄存器数、内存的关系

| precision (p) | 寄存器数 m = 2^p | 标准误差 (1.04/√m) | 内存 (m × 6 bit) |
|---------------|-----------------|--------------------|-----------------|
| 4 | 16 | 26% | 12 字节 |
| 8 | 256 | 6.5% | 192 字节 |
| 10 | 1024 | 3.25% | 768 字节 |
| 11 | 2048 | 2.30% | 1.5 KB |
| 12 | 4096 | 1.625% | 3 KB |
| 14 | 16384 | 0.81% | 12 KB |
| 16 | 65536 | 0.41% | 48 KB |
| 18 | 262144 | 0.20% | 192 KB |

精度 p 每加 1，标准误差减半，内存翻倍。"sweet spot" 通常在 p=12~14：误差 1-2%、内存 3-12 KB，绝大多数业务可接受。

### 误差的统计学含义

"1.6% 标准误差" 的含义：HLL 估计值是无偏的随机变量，估计值与真实基数的相对差服从渐近正态分布，标准差约为 1.6%。这意味着：

- 约 68% 的估计落在 [真值 × 0.984, 真值 × 1.016] 区间内
- 约 95% 的估计落在 [真值 × 0.968, 真值 × 1.032] 区间内
- 约 99.7% 的估计落在 [真值 × 0.952, 真值 × 1.048] 区间内

这是 "平均误差"，不是 "最大误差"。在尾部，HLL 偶尔会有 5-10% 的偏差，对绝大多数 BI 报表场景仍然可以接受。

### 小基数的偏差与 LinearCounting 修正

原始 HLL 在基数 < 2.5 × m 时偏差较大。Flajolet 等人提出的修正：当估计值 E < 2.5m 且存在空寄存器时，切换到 LinearCounting (基于空桶比例的估计)，避免小基数下的系统性偏差。

```
E* = m * ln(m / V)  其中 V = 空寄存器数

if E <= 2.5m and V > 0:
    return E*       (LinearCounting)
else:
    return E         (HyperLogLog)
```

HLL++ 对此进一步改进：使用经验测得的 "偏差校正表" (bias correction table) 替代简单的 LinearCounting 切换，让小到中等基数 (几百到几万) 的精度显著提升。

## 支持矩阵 (45+ 引擎)

### APPROX_COUNT_DISTINCT 函数名与算法

| 引擎 | 函数名 | 算法 | 版本/年份 | 默认精度 |
|------|--------|------|----------|---------|
| PostgreSQL (核心) | -- | -- | 不支持 | -- |
| PostgreSQL + postgresql-hll | `hll_add_agg` / `hll_cardinality` | HLL | 2013+ (Aiven/Citus) | log2m=11 |
| PostgreSQL + datasketches | `hll_sketch_distinct` | DataSketches HLL | 扩展 | log2m=12 |
| MySQL | -- | -- | 不支持 | -- |
| MariaDB | -- | -- | 不支持 | -- |
| SQLite | -- | -- | 不支持 | -- |
| Oracle | `APPROX_COUNT_DISTINCT` | HLL | 12c (2013) | ~p=13 |
| SQL Server | `APPROX_COUNT_DISTINCT` | HLL++ | 2019 | 固定 16 KB |
| DB2 LUW | -- | -- | 不支持 | -- |
| DB2 Warehouse on Cloud | `APPROX_COUNT_DISTINCT` | HLL | GA | -- |
| SAP HANA | `COUNT_APPROX_DISTINCT` | HLL | 2.0 SPS04+ | -- |
| Snowflake | `APPROX_COUNT_DISTINCT` / `HLL` | HLL | GA 2017 | p=12 |
| Redshift | `APPROXIMATE COUNT(DISTINCT ...)` | HLL | 2018 | p=15 |
| BigQuery | `APPROX_COUNT_DISTINCT` / `HLL_COUNT.*` | HLL++ | GA 2018 | precision=15 |
| Azure Synapse | `APPROX_COUNT_DISTINCT` | HLL | GA | 2% 误差 |
| Azure SQL DB | `APPROX_COUNT_DISTINCT` | HLL++ | GA | 同 SQL Server 2019 |
| Athena | `approx_distinct` | HLL | 继承 Trino | e=0.023 |
| Spark SQL | `approx_count_distinct` | HLL++ | 1.6 (2016) | rsd=0.05 |
| Databricks | `approx_count_distinct` | HLL++ | 继承 Spark | rsd=0.05 |
| Trino | `approx_distinct` | HLL | 早期 | e=0.023 |
| Presto | `approx_distinct` | HLL | 0.x | e=0.023 |
| Hive | -- (UDF) | -- | 需 UDF | -- |
| Hive + Brickhouse UDF | `approx_distinct` | HLL | 第三方 | -- |
| Impala | `NDV` | HLL | 1.2 (2013) | p=10 |
| Drill | `hll` (函数) | HLL | 1.16+ (2019) | log2m=10 |
| ClickHouse | `uniq` (默认) | 自适应 (HLL+稀疏) | 早期 | 自适应 |
| ClickHouse | `uniqHLL12` | 标准 HLL | 早期 | p=12 |
| ClickHouse | `uniqCombined` | HLL+小集合精确 | 早期 | 自适应 |
| ClickHouse | `uniqExact` | 精确 hash set | 早期 | -- |
| ClickHouse | `uniqTheta` | DataSketches Theta | 21.4+ | 默认 K |
| Druid | `APPROX_COUNT_DISTINCT_DS_HLL` | DataSketches HLL | GA | lgK=12 |
| Druid | `HLLSketchEstimate` | DataSketches HLL | GA | -- |
| Apache Pinot | `DISTINCTCOUNTHLL` / `DistinctCountHLLPlus` | HLL/HLL+ | GA | log2m=8 |
| Apache Pinot | `DistinctCountThetaSketch` | DataSketches Theta | GA | -- |
| DuckDB | `approx_count_distinct` | HLL | 0.8+ (2023) | p=11 |
| Vertica | `APPROXIMATE_COUNT_DISTINCT` | HLL | 7.2 (2015) | 1.25% 误差 |
| Greenplum | `hll_add_agg` (扩展) | postgresql-hll | 6+ | log2m=11 |
| Teradata | -- | -- | 不支持 | -- |
| Teradata Vantage | `approx_distinct` | HLL | NewSQL+ | -- |
| Netezza | `APPROX_COUNT_DISTINCT` | HLL | 11.x+ | -- |
| Yellowbrick | `APPROX_COUNT_DISTINCT` | HLL | GA | -- |
| Firebolt | `APPROX_COUNT_DISTINCT` | HLL | GA | -- |
| ksqlDB | -- | -- | 不支持 | -- |
| Flink SQL | `APPROX_COUNT_DISTINCT` | HLL | 1.13+ | -- |
| MaterializedView (Materialize) | -- | -- | 不支持 | -- |
| RisingWave | `approx_count_distinct` | HLL | GA | -- |
| StarRocks | `APPROX_COUNT_DISTINCT` / `BITMAP_UNION_COUNT` | HLL/Bitmap | GA | hll_precision=14 |
| Apache Doris | `APPROX_COUNT_DISTINCT` / `HLL_UNION_AGG` | HLL | GA | precision=14 |
| TiDB | `APPROX_COUNT_DISTINCT` | HLL | 4.0+ | -- |
| OceanBase | `APPROX_COUNT_DISTINCT` | HLL | 4.0+ | -- |
| YugabyteDB | -- (PG 兼容) | postgresql-hll 可用 | -- | -- |
| CockroachDB | -- | -- | 不支持 | -- |
| Spanner | `APPROX_COUNT_DISTINCT` / `HLL_COUNT.*` | HLL++ | GA | precision=15 |
| Crate DB | `hll_distinct` | HLL | 4.5+ | -- |
| QuestDB | -- | -- | 不支持 | -- |
| MonetDB | -- | -- | 不支持 | -- |
| Exasol | `APPROXIMATE_COUNT_DISTINCT` | HLL | 6.0+ | -- |
| ksqlDB | -- | -- | 不支持 | -- |
| Apache DataSketches (库) | `HLL` / `HllSketch` | HLL/HLL++ | 1.x+ (2015 Yahoo) | lgK=12 |

### HLL Sketch 作为数据类型

| 引擎 | 数据类型 | 长度 | 标量函数 | 备注 |
|------|---------|------|---------|------|
| PostgreSQL + hll | `hll` | 变长 | `hll_add` / `hll_union` | varlena 二进制 |
| Snowflake | -- (BINARY) | ≤ 1 KB | `HLL_ACCUMULATE` 输出 BINARY | 序列化为 BINARY |
| BigQuery | `BYTES` | 可变 | `HLL_COUNT.INIT` 输出 BYTES | 兼容 DataSketches |
| Redshift | `HLLSKETCH` | ~24 KB | `HLLSKETCH_TYPE` | JSON 或二进制格式 |
| ClickHouse | `AggregateFunction(uniq, T)` | 可变 | `uniqState` 输出 | 状态列 |
| ClickHouse | `AggregateFunction(uniqHLL12, T)` | 固定 | `uniqHLL12State` | 标准 HLL 状态 |
| Doris | `HLL` | 可变 | `HLL_HASH` / `HLL_UNION` | 列式存储类型 |
| StarRocks | `HLL` | 可变 | `HLL_HASH` / `HLL_UNION` | 列式存储类型 |
| Druid | `complex<HLLSketch>` | 可变 | `DS_HLL` | DataSketches |
| Pinot | `HLL` / `HLLPlus` | 可变 | `DistinctCountRawHLL` | 序列化二进制 |
| Vertica | -- | -- | 集成在聚合中 | 不暴露独立类型 |
| SAP HANA | `HLL_SKETCH` | 可变 | `HLL_CREATE` | 二进制类型 |
| SQL Server | -- | -- | 内部状态不可暴露 | 仅函数级 |
| Oracle | -- | -- | 内部状态不可暴露 | 仅函数级 |
| Spark SQL | `binary` | 可变 | `hll_sketch_agg` | 3.5+ DataSketches |
| Trino | `HyperLogLog` | 可变 | `cast(approx_set(x) as varbinary)` | 内置类型 |
| DuckDB | -- | -- | 仅函数级 | 0.8 起内部 HLL |

### Sketch 合并 (Merge / Union)

| 引擎 | 合并函数 | 多列合并 | 跨节点合并 |
|------|---------|---------|-----------|
| PostgreSQL + hll | `hll_union_agg(hll)` / `hll_union(hll, hll)` | 是 | 是 |
| Snowflake | `HLL_COMBINE(state)` | 是 | 是 |
| BigQuery | `HLL_COUNT.MERGE_PARTIAL(sketch)` | 是 | 是 |
| Redshift | `HLLSKETCH_UNION_AGG(sketch)` | 是 | 是 |
| ClickHouse | `uniqMerge(state)` / `uniqHLL12Merge(state)` | 是 | 是 |
| Trino | `merge(approx_set)` | 是 | 是 |
| Spark SQL (3.5+) | `hll_union_agg(sketch)` | 是 | 是 |
| Druid | `DS_HLL` 自动合并 | 是 | 是 |
| Pinot | `DistinctCountHLLMerge` | 是 | 是 |
| Doris | `HLL_UNION(hll)` | 是 | 是 |
| StarRocks | `HLL_UNION(hll)` | 是 | 是 |
| SAP HANA | `HLL_MERGE` | 是 | 是 |
| Oracle | -- (内部隐式) | -- | -- |
| SQL Server | -- (内部隐式，无显式合并) | -- | -- |
| DuckDB | -- (内部隐式) | -- | -- |
| Vertica | -- (内部隐式) | -- | -- |

### 精度参数支持

| 引擎 | 参数名 | 范围 | 默认 |
|------|--------|------|------|
| PostgreSQL + hll | `log2m` / `regwidth` / `expthresh` / `sparseon` | log2m=4-31 | log2m=11, regwidth=5 |
| Snowflake | -- (隐式) | -- | p=12 |
| BigQuery | `precision` | 10-24 | 15 |
| Redshift | -- (隐式) | -- | p=15 |
| ClickHouse | `uniqHLL{12,17,...}` 名称指定 | p=12,17 等 | uniq 自适应 |
| Trino | 第二参数 (max_standard_error) | 0.0040625 ~ 0.26 | 0.023 |
| Spark SQL | `relativeSD` (第二参数) | 0.0001 ~ 0.39 | 0.05 |
| DuckDB | -- (固定) | -- | p=11 |
| Druid | `lgK` | 4-21 | 12 |
| Pinot | `log2m` | 4-30 | 8 |
| Oracle | `MAX_REL_ERROR` (Hint) | 0.005-0.5 | 0.01225 |
| SQL Server | -- (固定 16 KB) | -- | -- |
| Doris/StarRocks | `hll_precision` (会话变量) | 5-16 | 14 |
| Vertica | 第二参数 (error tolerance) | 0.5%-10% | 1.25% |
| Apache DataSketches | `lgConfigK` | 4-21 | 12 |

### HLL++ vs 经典 HLL

| 引擎 | 算法 | 备注 |
|------|------|------|
| BigQuery | HLL++ | Google 内部即 HLL++ 起源 |
| Spark SQL | HLL++ | 1.6 起 |
| Spanner | HLL++ | 同 BigQuery |
| Athena (新版) | HLL++ | 部分版本 |
| SQL Server 2019 | HLL++ 变体 | 微软定制 |
| ClickHouse uniq | 自适应 (类 HLL++) | 小基数稀疏，大基数 HLL |
| Snowflake | 经典 HLL | 不公开是否 HLL++ |
| Redshift | 经典 HLL | 块级寄存器 |
| Trino / Presto | 经典 HLL | Airlift 实现 |
| DuckDB | 经典 HLL | 简化实现 |
| Oracle | HLL (变体) | 12c 起，细节未公开 |
| PostgreSQL + hll | 经典 HLL + 稀疏表示 | 类似 HLL++ 思路 |
| Apache DataSketches HLL | HLL + 4/6/8 bit 表示 | 受 HLL++ 启发，更激进 |

### 序列化格式

| 引擎 | 格式 | 跨引擎兼容 | 大小 |
|------|------|-----------|------|
| postgresql-hll | "Storage Specification" 二进制 | 与 java-hll/js-hll 兼容 | 几十字节 ~ 数 KB |
| BigQuery | DataSketches 兼容 BYTES | 与 Apache DataSketches 兼容 | 取决于 precision |
| Snowflake | 私有 BINARY | 不兼容其他引擎 | ≤ 1 KB |
| Redshift | JSON 或二进制 HLLSKETCH | Redshift 内部 | ~24 KB (dense) |
| ClickHouse | 私有二进制 | 不兼容其他引擎 | 取决于函数 |
| Druid / Pinot | DataSketches 二进制 | 互通 | 取决于 lgK |
| Trino | 私有二进制 (Airlift) | Presto/Trino 互通 | ~16 KB (precision=15) |
| Spark SQL 3.5+ | DataSketches HLL | 与 Druid/Pinot 互通 | -- |
| Doris/StarRocks | 私有二进制 | 双向兼容 (同源代码) | 取决于 hll_precision |
| Apache DataSketches | "Compact" 序列化 | 跨语言/跨引擎黄金标准 | -- |

> 统计：约 35+ 引擎内置或通过扩展提供 HyperLogLog 类近似去重能力，约 8 个核心 OLTP 引擎 (MySQL/MariaDB/SQLite/CockroachDB 等) 完全不支持。

## 各引擎实现详解

### PostgreSQL：核心不内置，扩展生态丰富

PostgreSQL 核心至今 (v17) 没有内置 APPROX_COUNT_DISTINCT。社区主要通过两个扩展提供能力：

**postgresql-hll (Aiven/Citus 维护)**：

```sql
CREATE EXTENSION hll;

-- 基础聚合
SELECT
    date_trunc('day', event_time) AS dt,
    hll_cardinality(hll_add_agg(hll_hash_text(user_id))) AS approx_uv
FROM events
GROUP BY 1;

-- 创建 hll 类型列存储中间状态
CREATE TABLE daily_uv (
    dt DATE,
    uv_sketch hll
);

INSERT INTO daily_uv
SELECT date_trunc('day', event_time)::date,
       hll_add_agg(hll_hash_text(user_id))
FROM events
GROUP BY 1;

-- 月度上卷：合并日级 sketch
SELECT
    date_trunc('month', dt) AS mon,
    hll_cardinality(hll_union_agg(uv_sketch)) AS monthly_uv
FROM daily_uv
GROUP BY 1;

-- 调整精度参数
SELECT hll_set_defaults(13, 5, -1, 1);
-- log2m=13 (8192 bucket, 误差 ~1.15%)
-- regwidth=5 bit/bucket
-- expthresh=-1 (auto)
-- sparseon=1 (启用稀疏表示)
```

postgresql-hll 实现了完整的 "Storage Specification"，与 Java/JavaScript 实现 (Aggregate Knowledge 开源) 兼容，可在 PG / JVM / 浏览器之间双向互通 sketch。

**datasketches-postgresql 扩展**：

```sql
CREATE EXTENSION datasketches;

-- HLL 草图
SELECT hll_sketch_to_string(hll_sketch_union(hll_sketch_build(user_id)))
FROM events;

-- 估计基数
SELECT hll_sketch_get_estimate(hll_sketch_union(hll_sketch_build(user_id)))
FROM events;

-- 与 Druid/Pinot/Spark 跨引擎互通 (序列化格式相同)
```

**性能对比** (1 亿行 × 100 万基数)：

| 方法 | 时间 | 内存 | 误差 |
|------|------|------|------|
| `count(distinct user_id)` (核心) | 22s | 80 MB hash set | 0% |
| `hll_cardinality(hll_add_agg(...))` | 4.5s | 12 KB | 1.6% |
| `count(distinct ...) ` + 索引扫描 | 14s | 80 MB | 0% |

### Oracle：12c 起内置 APPROX_COUNT_DISTINCT

```sql
-- 基础用法
SELECT
    region,
    APPROX_COUNT_DISTINCT(customer_id) AS approx_customers
FROM orders
GROUP BY region;

-- 限制相对误差
SELECT
    APPROX_COUNT_DISTINCT(customer_id, 'MAX_REL_ERROR=0.005') AS approx_customers
FROM orders;

-- 12c R2 起：APPROX_COUNT_DISTINCT_AGG / APPROX_COUNT_DISTINCT_DETAIL
-- 用于增量与上卷
CREATE TABLE daily_sketches (
    dt DATE,
    region VARCHAR2(50),
    sketch BLOB
);

INSERT INTO daily_sketches
SELECT TRUNC(order_date), region,
       APPROX_COUNT_DISTINCT_DETAIL(customer_id) AS sketch
FROM orders
GROUP BY TRUNC(order_date), region;

-- 上卷查询
SELECT region,
       APPROX_COUNT_DISTINCT_AGG(sketch) AS monthly_uv
FROM daily_sketches
WHERE dt BETWEEN DATE '2026-01-01' AND DATE '2026-01-31'
GROUP BY region;

-- 18c+：APPROX_QUANTILE / APPROX_PERCENTILE 等其他近似函数
-- 19c+：APPROX_RANK / APPROX_TOP_N
```

会话级开关：

```sql
ALTER SESSION SET APPROX_FOR_COUNT_DISTINCT = TRUE;
-- 之后所有 COUNT(DISTINCT x) 自动转为 APPROX_COUNT_DISTINCT(x)

ALTER SESSION SET APPROX_FOR_AGGREGATION = TRUE;
-- 全部聚合 (count distinct / percentile / aggregate over partition) 走近似版本
```

### Microsoft SQL Server：2019 起原生支持

```sql
-- SQL Server 2019+
SELECT
    region,
    APPROX_COUNT_DISTINCT(customer_id) AS approx_customers
FROM Sales.Orders
GROUP BY region;

-- 注意：SQL Server 的实现固定 16 KB 内存
-- 误差约 2%，不可调
-- 不支持 HLL 草图作为列类型，无法增量合并

-- 使用 OPTION 启用并行
SELECT APPROX_COUNT_DISTINCT(c)
FROM dbo.LargeTable
OPTION (MAXDOP 16);
```

SQL Server 2019 的 APPROX_COUNT_DISTINCT 是 HLL++ 的微软实现，只暴露了聚合函数本身，没有公开 sketch 类型或 union 操作。这意味着 "增量 / 上卷" 模式在 SQL Server 上无法直接实现，只能每次重算。

### Redshift：APPROX_COUNT_DISTINCT 与 HLLSKETCH 类型

```sql
-- 旧语法 (2018 起)
SELECT APPROXIMATE COUNT(DISTINCT user_id) FROM events;

-- 新语法 (函数式)
SELECT APPROX_COUNT_DISTINCT(user_id) FROM events;

-- HLLSKETCH 类型 (2020+)
CREATE TABLE daily_user_sketches (
    dt DATE,
    sketch HLLSKETCH
);

INSERT INTO daily_user_sketches
SELECT date_trunc('day', event_time)::date,
       HLL_CREATE_SKETCH(user_id)
FROM events
GROUP BY 1;

-- 月度合并
SELECT
    date_trunc('month', dt) AS mon,
    HLL_CARDINALITY(HLLSKETCH_UNION_AGG(sketch)) AS monthly_uv
FROM daily_user_sketches
GROUP BY 1;

-- 与其他类型协同
SELECT HLL_CARDINALITY(
    HLLSKETCH_UNION(
        HLL_CREATE_SKETCH(a.user_id),
        HLL_CREATE_SKETCH(b.user_id)
    )
) FROM events_a a, events_b b;

-- 序列化为 JSON 用于跨工具调试
SELECT HLLSKETCH_UNION_AGG(sketch)::VARCHAR FROM daily_user_sketches LIMIT 1;
-- 输出: {"version":1,"logm":15,"sparse":{"indices":[...],"values":[...]}}
```

Redshift 的 HLL precision 固定为 15 (32768 buckets)，dense 表示约 24 KB，sparse 表示在小基数下可压缩到几百字节。误差稳定在 ~0.2%。

### Snowflake：HLL_ACCUMULATE / HLL_COMBINE / HLL_ESTIMATE

Snowflake 提供完整的 sketch 生命周期函数：

```sql
-- 一步到位：APPROX_COUNT_DISTINCT
SELECT APPROX_COUNT_DISTINCT(user_id) FROM events;

-- HLL: 同 APPROX_COUNT_DISTINCT
SELECT HLL(user_id) FROM events;

-- 三阶段操作

-- 1. HLL_ACCUMULATE: 把原始值聚合为 sketch (BINARY)
CREATE TABLE daily_uv_sketch AS
SELECT
    date_trunc('day', event_time)::date AS dt,
    HLL_ACCUMULATE(user_id) AS sketch
FROM events
GROUP BY 1;

-- 2. HLL_COMBINE: 合并多个 sketch
SELECT
    date_trunc('month', dt) AS mon,
    HLL_COMBINE(sketch) AS combined_sketch
FROM daily_uv_sketch
GROUP BY 1;

-- 3. HLL_ESTIMATE: 从合并 sketch 计算最终基数
SELECT
    date_trunc('month', dt) AS mon,
    HLL_ESTIMATE(HLL_COMBINE(sketch)) AS monthly_uv
FROM daily_uv_sketch
GROUP BY 1;

-- HLL_EXPORT / HLL_IMPORT: 与 BINARY 互转 (用于跨系统传输)
SELECT HLL_EXPORT(HLL_ACCUMULATE(user_id)) FROM events;

-- 注意：HLL_ACCUMULATE 输出的 sketch 是 Snowflake 私有格式，
-- 不能直接喂给 BigQuery/Spark 等其他引擎
```

Snowflake 的 sketch 大小最大约 1 KB (远小于 Redshift 的 24 KB)，因为它使用了精度 12 (4096 buckets) 加压缩编码。误差约 1.6%，一般业务场景足够。

### BigQuery：HLL_COUNT.* 与可调精度

BigQuery 使用 HLL++ 实现，函数族非常完整：

```sql
-- 一步到位
SELECT APPROX_COUNT_DISTINCT(user_id) FROM `dataset.events`;

-- HLL_COUNT.INIT: 创建 sketch (BYTES)
SELECT HLL_COUNT.INIT(user_id) AS sketch
FROM `dataset.events`;

-- 指定精度 (10-24，默认 15)
SELECT HLL_COUNT.INIT(user_id, 18) AS high_precision_sketch
FROM `dataset.events`;

-- 实际使用：日级 sketch
CREATE OR REPLACE TABLE daily_user_sketch AS
SELECT
    DATE(event_time) AS dt,
    HLL_COUNT.INIT(user_id, 15) AS sketch
FROM `dataset.events`
GROUP BY 1;

-- HLL_COUNT.MERGE_PARTIAL: 合并 sketches，输出新 sketch
SELECT HLL_COUNT.MERGE_PARTIAL(sketch) AS month_sketch
FROM daily_user_sketch
WHERE dt BETWEEN '2026-01-01' AND '2026-01-31';

-- HLL_COUNT.EXTRACT: 从单个 sketch 提取基数 (无聚合)
SELECT HLL_COUNT.EXTRACT(sketch) AS daily_uv
FROM daily_user_sketch;

-- HLL_COUNT.MERGE: 合并 sketches 并直接返回基数
SELECT
    DATE_TRUNC(dt, MONTH) AS mon,
    HLL_COUNT.MERGE(sketch) AS monthly_uv
FROM daily_user_sketch
GROUP BY 1;
```

BigQuery 的 HLL sketch 序列化格式与 Apache DataSketches 兼容，可以与 Spark SQL 3.5+ / Druid / Pinot 等引擎互通：

```sql
-- BigQuery 写出 sketch -> 导出到 GCS -> Spark 读入并继续聚合
EXPORT DATA OPTIONS(uri='gs://bucket/sketch_*.parquet', format='PARQUET') AS
SELECT dt, sketch FROM daily_user_sketch;

-- 在 Spark 中:
-- df.selectExpr("hll_sketch_estimate(sketch) as uv").show()
```

### ClickHouse：uniq 家族最完整

ClickHouse 提供了 4 个不同精度/算法的去重函数：

```sql
-- uniq: 默认，自适应算法 (HLL 变体 + 稀疏存储)
SELECT uniq(user_id) FROM events;
-- 误差 ~1.5%，速度最快

-- uniqExact: 精确去重 (内存中 hash set)
SELECT uniqExact(user_id) FROM events;
-- 0 误差，但内存随基数增长

-- uniqHLL12: 标准 HyperLogLog，p=12
SELECT uniqHLL12(user_id) FROM events;
-- 误差 ~1.6%，2^12 = 4096 个寄存器

-- uniqCombined: 自适应组合
SELECT uniqCombined(user_id) FROM events;
-- 基数 < 65536: 使用精确 hash set
-- 基数 >= 65536: 转为 HLL
-- 综合误差 < 1%，但内存上限可控

-- uniqCombined64: 64-bit 哈希版本，适用于超大基数 (> 4 亿)
SELECT uniqCombined64(user_id) FROM events;

-- uniqTheta: Apache DataSketches Theta sketch (21.4+)
SELECT uniqTheta(user_id) FROM events;
-- 支持集合运算 (intersection / difference)
```

聚合状态序列化与合并：

```sql
-- 创建预聚合表
CREATE MATERIALIZED VIEW daily_uv_mv
ENGINE = AggregatingMergeTree()
ORDER BY dt
AS SELECT
    toDate(event_time) AS dt,
    uniqHLL12State(user_id) AS uv_state
FROM events
GROUP BY dt;

-- 查询时合并
SELECT
    dt,
    uniqHLL12Merge(uv_state) AS daily_uv
FROM daily_uv_mv
GROUP BY dt;

-- 跨日期范围合并
SELECT uniqHLL12Merge(uv_state) AS total_uv
FROM daily_uv_mv
WHERE dt BETWEEN '2026-01-01' AND '2026-03-31';
```

ClickHouse 的 uniqTheta 是 21.4 引入的 DataSketches 桥接：

```sql
-- Theta sketch 支持集合运算
SELECT
    uniqThetaIntersect(uniqThetaState(user_id), other_sketch) AS users_in_both
FROM events;

SELECT
    uniqThetaNot(uniqThetaState(user_id), other_sketch) AS users_only_in_first
FROM events;
```

### Apache Spark SQL：HLL++ 与 DataSketches 双引擎

```scala
// approx_count_distinct: 1.6 起支持
val df = spark.sql("SELECT region, approx_count_distinct(user_id, 0.05) FROM events GROUP BY region")

// 第二参数：相对标准差 (rsd)，默认 0.05 (5% 误差)
// rsd=0.01 (1% 误差) → 内部 precision ~ 14
// rsd=0.05 (5% 误差) → 内部 precision ~ 10
```

```sql
-- SQL 接口
SELECT
    region,
    approx_count_distinct(user_id) AS approx_uv,            -- 默认 5% 误差
    approx_count_distinct(user_id, 0.01) AS precise_approx  -- 1% 误差
FROM events
GROUP BY region;
```

Spark 3.5+ 引入 Apache DataSketches 集成 (SPARK-16484)：

```sql
-- DataSketches HLL：与 Druid / Pinot / BigQuery 兼容
SELECT
    region,
    hll_sketch_estimate(hll_sketch_agg(user_id, 12)) AS uv
FROM events
GROUP BY region;

-- 跨日期合并
SELECT
    date_trunc('month', dt) AS mon,
    hll_sketch_estimate(hll_union_agg(daily_sketch, 12)) AS monthly_uv
FROM daily_sketches
GROUP BY 1;

-- DataSketches Theta sketch：支持集合运算
SELECT theta_sketch_estimate(theta_sketch_agg(user_id)) FROM events;
SELECT theta_sketch_estimate(theta_intersection_agg(sketch_a, sketch_b)) FROM ...;
```

Spark 内部使用 stream-lib 库的 HyperLogLogPlus 实现 (HLL++)。3.5 起新加的 DataSketches 函数则使用 datasketches-java 库，两者格式不互通——选择哪个取决于跨引擎互通需求。

### Trino / Presto：approx_distinct 与 HyperLogLog 类型

```sql
-- 基础用法
SELECT approx_distinct(user_id) FROM events;

-- 精度调节 (max_standard_error)
SELECT approx_distinct(user_id, 0.01) FROM events;     -- 1% 误差，约 64 KB
SELECT approx_distinct(user_id, 0.046) FROM events;    -- 4.6% 误差，约 4 KB
-- 可选范围: 0.0040625 ~ 0.26

-- HyperLogLog 类型 (BIGINT 序列化)
SELECT cast(approx_set(user_id) as varbinary) FROM events;

-- merge: 合并多个 sketch
SELECT merge(approx_set(user_id)) FROM events;
SELECT cardinality(merge(approx_set(user_id))) FROM events;

-- empty_approx_set: 空 sketch
SELECT cardinality(empty_approx_set()) FROM events;  -- 0

-- merge 与 union 等价
WITH daily AS (
    SELECT date(event_time) AS dt, approx_set(user_id) AS sketch
    FROM events GROUP BY 1
)
SELECT
    date_trunc('month', dt) AS mon,
    cardinality(merge(sketch)) AS monthly_uv
FROM daily
GROUP BY 1;

-- 与 Java/Airlift HLL 序列化兼容，可以从应用层喂给 Trino
```

### DuckDB：approx_count_distinct (0.8+)

```sql
-- 0.8.0 起原生支持
SELECT approx_count_distinct(user_id) FROM events;

-- DuckDB 内部使用 precision=11 (2048 buckets)，误差约 2.3%
-- 不支持精度调节、不支持 sketch 类型

-- 性能 (1 亿行)
-- count(distinct): 8.5s, 80 MB
-- approx_count_distinct: 0.9s, 6 KB

-- 0.10+ 起支持以下 sketch 函数
SELECT
    region,
    sketch_hll(user_id) AS sketch_str
FROM events
GROUP BY region;

-- 与 GROUP BY ROLLUP / CUBE 协作
SELECT region, dt,
       approx_count_distinct(user_id) AS uv
FROM events
GROUP BY ROLLUP(region, dt);
```

DuckDB 的实现追求 "默认即可用"：固定精度、不暴露 sketch 类型，避免用户面对过多参数。这与 ClickHouse 的 "5 个变体" 形成鲜明对比。

### Apache Druid：DataSketches HLL 内嵌

Druid 把 sketch 作为一等公民，深度集成到 Roaring Bitmap 与 segment 文件：

```sql
-- 创建表时声明 sketch 列
{
  "type": "kafka",
  "dataSchema": {
    "metricsSpec": [
      {
        "type": "HLLSketchBuild",
        "name": "user_sketch",
        "fieldName": "user_id",
        "lgK": 12,
        "tgtHllType": "HLL_4"
      }
    ]
  }
}

-- 查询：自动合并 segment 级 sketch
SELECT
    __time,
    APPROX_COUNT_DISTINCT_DS_HLL(user_sketch) AS uv,
    HLL_SKETCH_ESTIMATE(user_sketch) AS uv_alt
FROM events
GROUP BY __time;

-- DS_HLL: 标量函数，作用于 sketch 列
SELECT DS_HLL(user_id) FROM events;

-- 估计值带置信区间
SELECT HLL_SKETCH_ESTIMATE_WITH_BOUNDS(user_sketch, 2) AS uv_with_ci
FROM events;
-- 返回 [estimate, lowerBound, upperBound]，2 个标准差
```

Druid 还支持 Theta sketch (集合运算) 和 Quantiles sketch，整套使用 DataSketches Java 库。

### Apache Impala：NDV 函数

Impala 较早 (1.2, 2013) 就引入了 NDV (Number of Distinct Values)：

```sql
-- 基础用法
SELECT NDV(user_id) FROM events;

-- 精度参数 (1-10，默认 10)
SELECT NDV(user_id, 8) FROM events;   -- 较低精度，速度更快

-- NDV_NO_FINALIZE: 返回中间状态 (用于增量)
-- (有限支持，不如 BigQuery/Snowflake 完整)

-- 用于统计信息收集
COMPUTE STATS events;
-- Impala 内部使用 NDV 估算 distinct value count，用于 join 顺序优化
```

Impala 的 NDV 实际上就是 HLL，但函数名沿用了 Hive 早期的命名。

### Vertica：APPROXIMATE_COUNT_DISTINCT

```sql
-- 7.2 起支持，单参数即可
SELECT APPROXIMATE_COUNT_DISTINCT(user_id) FROM events;

-- 第二参数：误差容忍度 (0.5%-10%，默认 1.25%)
SELECT APPROXIMATE_COUNT_DISTINCT(user_id, 0.005) FROM events;  -- 0.5% 误差

-- APPROXIMATE_COUNT_DISTINCT_OF_SYNOPSIS: 从已有 sketch 计算
SELECT APPROXIMATE_COUNT_DISTINCT_OF_SYNOPSIS(synopsis_col) FROM ...;

-- APPROXIMATE_COUNT_DISTINCT_SYNOPSIS_PLUS: 合并 sketch
-- 用法仅限内部，不暴露 sketch 类型
```

Vertica 不暴露 sketch 类型，但提供内部合并函数支撑 partition / segment 间的协作。

### StarRocks / Doris：HLL 类型与 BITMAP 兼用

StarRocks/Doris 在 OLAP 场景中既支持 HLL 也支持 BITMAP (精确去重)：

```sql
-- 建表时使用 HLL 类型
CREATE TABLE daily_uv (
    dt DATE,
    region VARCHAR(50),
    uv_sketch HLL HLL_UNION
)
AGGREGATE KEY(dt, region)
DISTRIBUTED BY HASH(dt) BUCKETS 10;

-- 写入时调用 HLL_HASH
INSERT INTO daily_uv
SELECT event_date, region, HLL_HASH(user_id)
FROM events;

-- 查询：自动合并 (因为表定义为 AGGREGATE KEY)
SELECT dt, region, HLL_UNION_AGG(uv_sketch), HLL_CARDINALITY(uv_sketch)
FROM daily_uv
GROUP BY dt, region;

-- 跨日期合并
SELECT
    date_trunc('month', dt) AS mon,
    HLL_CARDINALITY(HLL_UNION_AGG(uv_sketch)) AS monthly_uv
FROM daily_uv
GROUP BY 1;

-- 会话级精度
SET hll_precision = 14;  -- 默认 14，可选 5-16
```

BITMAP 类型提供精确去重，但只能用于 INT 类型 (或经过字典映射)；HLL 适用于任意类型，代价是 2% 误差。

### Apache DataSketches：跨引擎的 sketch 标准

Yahoo (现 Verizon Media) 在 2015 年开源 Apache DataSketches，提供了跨语言 (Java/C++/Python) 与跨引擎的 sketch 实现：

- **HLL Sketch**: HLL_4 / HLL_6 / HLL_8 三种压缩等级
- **Theta Sketch**: 支持集合 union/intersection/difference
- **Quantiles Sketch**: KLL / REQ 等近似分位数
- **Frequencies Sketch**: 近似 Top-K
- **Tuple Sketch**: 带额外维度的 sketch (如 sketch with sum)

```java
// Java SDK
HllSketch sketch = new HllSketch(12);
for (long v : values) sketch.update(v);
double estimate = sketch.getEstimate();

// 序列化为标准格式
byte[] bytes = sketch.toCompactByteArray();

// 在另一台机器上反序列化
HllSketch loaded = HllSketch.heapify(Memory.wrap(bytes));
```

DataSketches 的关键价值：

1. **跨引擎兼容**：同一个 byte[] 可以在 Druid、Pinot、Spark 3.5+、PostgreSQL (datasketches 扩展)、ClickHouse (uniqTheta)、BigQuery (HLL_COUNT.*) 之间流转
2. **可重现**：Java 和 C++ 实现产生相同的二进制 sketch
3. **理论保证**：每个 sketch 都附带相对误差与置信度的明确公式

```sql
-- 在 Spark 中读 BigQuery 输出的 sketch
val df = spark.read.parquet("gs://bucket/bigquery_export/")
df.selectExpr("hll_sketch_estimate(sketch) as uv").show()

-- 在 PostgreSQL 中读 Druid 导出的 sketch
INSERT INTO sketches SELECT hll_sketch_to_string(sketch_bytes) FROM ...;
```

## HLL++ 改进 (Heule 2013)

Stefan Heule 等人在 EDBT 2013 论文 "HyperLogLog in Practice" 中针对原始 HLL 提出了三项关键改进：

### 1. 64-bit 哈希替代 32-bit

原始 HLL 用 32-bit 哈希，在基数 > 10^9 时容易碰撞。HLL++ 使用 64-bit 哈希，把可处理的基数上限提到 ~10^18，几乎覆盖所有实际场景。

### 2. 稀疏表示 (Sparse Representation)

小基数时，大部分寄存器仍为 0。HLL++ 用稀疏数据结构 (类似 RLE 压缩) 存储非零寄存器，把内存从 "固定 m × 6 bit" 变为 "随基数线性增长"。

```
基数 = 100，m = 16384:
  原始 HLL: 16384 × 6 bit = 12 KB
  HLL++ 稀疏: 100 × 32 bit = 400 字节  (省 30 倍)

基数 = 10000, m = 16384:
  原始 HLL: 12 KB
  HLL++ 稀疏: 10000 × 32 bit = 40 KB  (反而更大)
  → 自动切换为 dense 表示
```

切换阈值通常在 m × 0.75 左右。

### 3. 经验偏差校正表

原始 HLL 在 "中等基数" (10^3 ~ 10^5) 区域，由于 LinearCounting 与 HLL 切换的不平滑，存在系统性偏差。HLL++ 用大量实测数据生成 "偏差校正表"，按估计值查表修正：

```
e_corrected = e_raw - bias_table_lookup(e_raw, m)
```

校正后 HLL++ 在全基数范围 (1 ~ 10^18) 都能保持理论标称误差。

## Sketch 互操作性：DataSketches 格式

DataSketches HLL 格式的关键设计：

1. **Header**: 版本号、序列化模式 (sparse/dense)、lgK、tgtHllType (HLL_4/6/8)
2. **Body**: 寄存器数组或稀疏列表
3. **Padding**: 固定到 8 字节边界，方便 mmap

```
DataSketches HLL Sketch Binary Layout:
+----+----+----+----+----+----+----+----+
| Preamble (8 bytes)                    |
+----+----+----+----+----+----+----+----+
| Family ID | SerVer | Mode | lgK | ... |
+----+----+----+----+----+----+----+----+
| Auxiliary header (variable)            |
+----+----+----+----+----+----+----+----+
| Compressed register data (variable)    |
+----+----+----+----+----+----+----+----+
```

兼容引擎 / 库：

| 引擎/库 | 写入 | 读取 |
|---------|------|------|
| Apache DataSketches Java | 是 | 是 |
| Apache DataSketches C++ | 是 | 是 |
| Apache DataSketches Python | 是 | 是 |
| Druid | 是 | 是 |
| Pinot | 是 | 是 |
| BigQuery (HLL_COUNT.*) | 是 | 是 |
| Spark SQL 3.5+ (hll_sketch_*) | 是 | 是 |
| ClickHouse (uniqTheta) | Theta only | Theta only |
| PostgreSQL datasketches 扩展 | 是 | 是 |
| Snowflake | 否 (私有格式) | 否 |
| Redshift | 否 (HLLSKETCH JSON) | 否 |
| Trino HyperLogLog | 否 (Airlift 格式) | 否 |
| postgresql-hll | 否 (AK 格式) | 否 |

实际工作流示例：

```sql
-- 步骤 1: BigQuery 中预聚合
CREATE OR REPLACE TABLE prod.daily_user_sketch AS
SELECT DATE(event_time) AS dt,
       HLL_COUNT.INIT(user_id, 14) AS sketch
FROM prod.events
GROUP BY 1;

-- 步骤 2: 导出到 GCS
EXPORT DATA OPTIONS(uri='gs://bucket/sketches/*.parquet', format='PARQUET') AS
SELECT dt, sketch FROM prod.daily_user_sketch;

-- 步骤 3: Spark 读入 GCS 文件并继续聚合
spark.read.parquet("gs://bucket/sketches/")
     .selectExpr("dt", "hll_sketch_estimate(sketch) as uv")
     .show()

-- 步骤 4: 同时 PostgreSQL (datasketches 扩展) 也能读
COPY sketches FROM PROGRAM 'gsutil cp gs://bucket/sketches/*.parquet -' (FORMAT 'parquet');
SELECT dt, hll_sketch_get_estimate(sketch) FROM sketches;
```

## 设计讨论

### "近似" 是否应该作为默认行为

ClickHouse 的 `uniq` 默认就是近似的，要精确去重需要显式 `uniqExact`。这与传统 OLTP 数据库的习惯相反——多数用户期望函数返回精确结果。

**支持默认近似的论点**：
- 大数据时代，"足够准" 通常胜过 "完全准"
- 用户主动选 "精确" 比主动选 "近似" 更符合 OLAP 场景

**反对的论点**：
- 财务、合规场景必须精确，"默认近似" 会误导用户
- 函数名应该 "做它说的事"，APPROX_ 前缀更诚实

主流共识倾向于：**显式命名 (APPROX_ 前缀) 优于默认近似**。但 ClickHouse 由于历史包袱无法回退。

### 自适应 vs 固定算法

**ClickHouse uniqCombined / uniq**：
- 小基数 (< 64 K) 用精确 hash set，大基数自动切换为 HLL
- 优点：低基数 0 误差、高基数有界内存
- 缺点：实现复杂，调试困难

**Snowflake / BigQuery / DuckDB**：
- 任何基数都用 HLL
- 优点：行为可预测、性能稳定
- 缺点：小基数误差较大 (HLL++ 修正部分缓解)

设计权衡：分析型引擎 (ClickHouse / Doris) 偏向自适应，云数仓 (Snowflake / BigQuery) 偏向固定算法。

### Sketch 格式标准化的价值

跨引擎 sketch 互通的实际价值：

1. **数据湖架构**：多引擎共享 sketch 列存储，避免重复计算
2. **流批一体**：Flink 实时聚合 sketch，Spark 批量回算合并
3. **联邦查询**：BigQuery 与本地 Spark 直接交换 sketch (而非原始数据)

这是 Apache DataSketches 在过去十年推动的核心目标。但仍有大量主流引擎 (Snowflake、Redshift、Trino) 使用私有格式，跨引擎互通仍是 "理论可行、工程困难"。

### 精度参数的暴露程度

| 引擎 | 精度可调 | 单位 | 范围 |
|------|---------|------|------|
| BigQuery | 是 | precision (bits) | 10-24 |
| Spark SQL | 是 | rsd (relative SD) | 0.0001-0.39 |
| Trino | 是 | max_standard_error | 0.004-0.26 |
| Vertica | 是 | error tolerance | 0.005-0.10 |
| Oracle | 是 (Hint) | MAX_REL_ERROR | 0.005-0.5 |
| ClickHouse | 函数名暴露 | uniqHLL{12,17,...} | 离散 |
| Doris/StarRocks | 会话变量 | hll_precision | 5-16 |
| Snowflake | 否 | -- | 固定 |
| Redshift | 否 | -- | 固定 |
| DuckDB | 否 | -- | 固定 |
| SQL Server | 否 | -- | 固定 |

设计权衡：暴露参数让用户可调，但增加学习成本；隐藏参数简单但缺乏灵活性。云数仓倾向隐藏 (统一服务级 SLO)，OLAP 引擎倾向暴露 (用户深度优化)。

### 何时不该用 HLL

1. **小基数 (<10000)**：精确 hash set 内存仍可接受、性能更好
2. **需要列出 distinct 值**：HLL 只能估算个数，不能枚举值
3. **集合运算 (intersection / difference)**：标准 HLL 不支持，必须用 Theta sketch
4. **审计 / 合规场景**：误差不可接受
5. **小数据预览 / 调试**：精确版本更直观

### HLL 与 Bitmap 的选择

**HLL**：
- 优点：内存固定 (KB 级)、任意类型、可估算 10^18 基数
- 缺点：1-2% 误差、不支持集合运算 (除 Theta)

**Bitmap (Roaring / EWAH)**：
- 优点：精确去重、支持完整集合运算
- 缺点：内存随基数线性增长 (虽然 Roaring 压缩很好)、仅适用于 INT 或字典映射后的整数

OLAP 场景常见模式：
- 用户 ID (INT)：用 Bitmap 精确去重 + 集合运算
- URL / 设备 ID (字符串)：用 HLL 近似去重

StarRocks / Doris / Apache Pinot 都同时提供两种类型。

## 对引擎开发者的实现建议

### 1. 选择算法变体

```
HLL (经典 Flajolet 2007):
  优点：算法简单，论文完备
  缺点：32-bit 哈希、小基数偏差大、内存固定
  适用：教学、轻量实现

HLL++ (Heule 2013):
  优点：64-bit、稀疏表示、偏差校正
  缺点：实现复杂 (~2000 行代码)
  适用：生产环境

DataSketches HLL:
  优点：4/6/8 bit 三档压缩、跨语言、KLL+Theta 配套
  缺点：依赖 Apache DataSketches 库
  适用：需要跨引擎互通

ClickHouse uniqCombined:
  优点：自适应、混合算法、性能优秀
  缺点：无标准实现、行为复杂
  适用：超高性能 OLAP
```

### 2. Hash 函数选择

```
要求：
  - 均匀分布 (key insight)
  - 高速 (聚合热路径)
  - 64-bit 输出 (HLL++ 需要)

推荐：
  MurmurHash3 64-bit (最常用)
  CityHash 64
  XXHash64 (最快)
  FarmHash (Google)

不推荐：
  CRC32 (分布不均匀)
  MD5/SHA (慢)
  std::hash (实现依赖)
```

### 3. 寄存器存储

```
密集表示 (Dense):
  m × 6 bit 数组 (压缩到 6 bit 因为 max(2^p hashed leading zeros) 通常 ≤ 63)
  访问：bit-level 索引，需小心位运算

  优化：
    - 使用 8 bit 或 16 bit per register (浪费空间但访问快)
    - SIMD 批量更新 (AVX2/NEON)
    - 缓存行对齐 (64-byte boundaries)

稀疏表示 (Sparse):
  (index, value) 对的列表 / 哈希表
  当非零寄存器 < m × 0.75 时使用
  内存与基数线性增长 (而非固定 m)
```

### 4. 合并算子

```
关键操作: 寄存器逐位取 max

伪代码:
  fn merge(this: HLL, other: HLL) -> HLL:
      assert this.m == other.m  // 必须同精度
      for i in 0..this.m:
          this.registers[i] = max(this.registers[i], other.registers[i])

复杂度: O(m)
分布式: 完全可交换、可结合，无需协调
```

### 5. 序列化

```
最小化格式:
  Header (8 bytes):
    Magic (2 bytes): "HL"
    Version (1 byte): 0x01
    Mode (1 byte): SPARSE | DENSE | EMPTY
    Precision p (1 byte): 4-18
    Reserved (3 bytes)

  Body (variable):
    DENSE: m × 6 bit packed
    SPARSE: (index varint, value 1 byte) 列表

  Trailer (4 bytes):
    CRC32 校验

兼容性建议:
  - 如果目标是跨引擎，直接用 Apache DataSketches 格式
  - 如果是私有，至少留 version 字段以便升级
```

### 6. 与查询优化器集成

```
1. 行数估计:
   approx_count_distinct(x) 输出固定 1 行

2. 谓词下推:
   approx_count_distinct(x) FILTER (WHERE pred) 可下推 pred
   分组聚合可下推到存储层 (如果存储支持 sketch 列)

3. 物化视图与增量:
   - 在 MV 中存储 HLL sketch 而非原始 distinct count
   - 上卷时用 union 而非重新扫描
   - 增量插入时与现有 sketch 合并

4. 自动近似:
   - 阈值开关 (Oracle: APPROX_FOR_COUNT_DISTINCT)
   - 优化器在大数据量时自动替换 COUNT(DISTINCT) → APPROX_COUNT_DISTINCT
```

### 7. 测试要点

```
正确性:
  - 小基数 (1-1000): 误差应符合理论值或修正后接近 0
  - 大基数 (10^6-10^9): 误差应稳定在 1.04/sqrt(m)
  - 边界: 空集合返回 0、单元素返回 1
  - 重复元素: 不影响估计

并发:
  - 多线程聚合: PRNG 不需要 (HLL 本身确定性)
  - merge 与 update 不可同时操作同一 sketch (除非使用原子操作)

序列化:
  - 同精度 sketch 序列化后大小固定
  - dense/sparse 切换正确
  - 跨语言/跨架构 (大端/小端) 一致

性能:
  - 单元素 update: < 100 ns
  - 1 亿元素聚合: < 1 秒 (单核)
  - merge 1000 个 sketch: < 10 ms
```

## 性能与成本对比 (1 亿行 × 1000 万基数)

| 引擎 | 函数 | 时间 | 内存 | 误差 |
|------|------|------|------|------|
| PostgreSQL (核心) | `count(distinct)` | 22 s | 80 MB | 0% |
| PostgreSQL + hll | `hll_cardinality(hll_add_agg)` | 4.5 s | 12 KB | 1.6% |
| ClickHouse | `uniqExact` | 3.2 s | 80 MB | 0% |
| ClickHouse | `uniq` (默认) | 1.1 s | 8 KB | 1.5% |
| ClickHouse | `uniqHLL12` | 1.0 s | 3 KB | 1.6% |
| ClickHouse | `uniqCombined` | 1.3 s | 64 KB max | <1% |
| DuckDB | `count(distinct)` | 8.5 s | 80 MB | 0% |
| DuckDB | `approx_count_distinct` | 0.9 s | 6 KB | 2.3% |
| Snowflake (M-Warehouse) | `APPROX_COUNT_DISTINCT` | 0.8 s | 1 KB | 1.6% |
| BigQuery | `APPROX_COUNT_DISTINCT` | 1.5 s | 16 KB | 0.81% |
| Redshift (dc2.large × 2) | `APPROX_COUNT_DISTINCT` | 1.2 s | 24 KB | 0.2% |
| Spark SQL (10 executors) | `approx_count_distinct(x, 0.05)` | 4 s | 4 KB | 5% |
| Trino (8 workers) | `approx_distinct(x, 0.023)` | 2.1 s | 16 KB | 2.3% |
| Druid | `APPROX_COUNT_DISTINCT_DS_HLL` | 0.5 s | 12 KB | 1.6% |

(数据为示意，实际取决于硬件、数据分布、网络等)

## 关键发现

1. **HyperLogLog 已成事实标准**：45+ 主流引擎中，35+ 都内置或通过扩展提供 HLL 类近似去重函数。仅 MySQL/MariaDB/SQLite/CockroachDB 等少数 OLTP 引擎完全不支持。

2. **HLL++ (2013) 仍是工业级首选**：BigQuery、Spark、Spanner 等 Google 系直接采用 HLL++；其他引擎多采用 HLL++ 思想 (稀疏表示、64-bit 哈希、偏差校正) 但实现细节各异。

3. **Sketch 类型暴露是分水岭**：暴露 sketch 类型 (Snowflake / BigQuery / Redshift / ClickHouse / Druid / Pinot / Doris / StarRocks) 的引擎支持增量计算和上卷；不暴露 (SQL Server / Oracle / Vertica / DuckDB) 的引擎每次都需要重算。

4. **跨引擎互通仍是难题**：Apache DataSketches 提供了跨引擎黄金标准，但 Snowflake、Redshift、Trino、postgresql-hll 等主流实现仍使用私有格式，互通需要中间转换。

5. **精度参数暴露程度差异巨大**：BigQuery / Spark / Trino / Vertica / Oracle 暴露精度参数 (rsd / max_standard_error / MAX_REL_ERROR)；Snowflake / Redshift / DuckDB / SQL Server 完全隐藏。OLAP 引擎倾向暴露，云数仓倾向隐藏。

6. **ClickHouse 的多算法策略独树一帜**：uniq / uniqExact / uniqHLL12 / uniqCombined / uniqTheta 五个变体覆盖不同场景，开放性最强但学习曲线最陡。

7. **HLL 与 Bitmap 的分工**：StarRocks / Doris / Pinot 同时提供 HLL (任意类型，近似) 与 Bitmap (整数，精确)，体现了 OLAP 场景对 "精确去重 + 集合运算" vs "任意类型 + 估算" 的双重需求。

8. **OLTP 引擎的滞后**：PostgreSQL 核心至今 (v17) 不内置 HLL；MySQL 9.0 仍然没有；CockroachDB / SQLite 也未支持。OLTP 优先精确性，HLL 在 OLTP 仍然只能通过扩展使用。

9. **Snowflake 的三阶段 API 已成模板**：HLL_ACCUMULATE / HLL_COMBINE / HLL_ESTIMATE 的设计被 BigQuery (INIT / MERGE_PARTIAL / EXTRACT) 和 Redshift (HLL_CREATE_SKETCH / HLLSKETCH_UNION_AGG / HLL_CARDINALITY) 模仿，已是事实上的 sketch 操作标准。

10. **预聚合 + Sketch 上卷**：在数据仓库场景中，"日级 sketch 列 → 月级 union → 季度 union" 的模式已成最佳实践。BigQuery、Snowflake、Redshift、Druid、ClickHouse 等都通过物化视图或增量表强力支持这一模式，让 PB 级分析在毫秒内完成。

## 参考资料

- Flajolet, P., Fusy, É., Gandouet, O., Meunier, F. "HyperLogLog: the analysis of a near-optimal cardinality estimation algorithm" (2007), AofA Conference
- Heule, S., Nunkesser, M., Hall, A. "HyperLogLog in Practice: Algorithmic Engineering of a State of The Art Cardinality Estimation Algorithm" (2013), EDBT
- Apache DataSketches: [HLL Sketch Family](https://datasketches.apache.org/docs/HLL/HLL.html)
- BigQuery: [HLL_COUNT Functions](https://cloud.google.com/bigquery/docs/reference/standard-sql/hll_functions)
- Snowflake: [HyperLogLog Functions](https://docs.snowflake.com/en/sql-reference/functions/hll)
- Redshift: [HLL Functions](https://docs.aws.amazon.com/redshift/latest/dg/r_HLL_function.html)
- ClickHouse: [uniq Functions](https://clickhouse.com/docs/en/sql-reference/aggregate-functions/reference/uniq)
- Spark SQL: [approx_count_distinct](https://spark.apache.org/docs/latest/sql-ref-functions-builtin.html)
- Trino: [HyperLogLog Functions](https://trino.io/docs/current/functions/hyperloglog.html)
- DuckDB: [Approximate Aggregates](https://duckdb.org/docs/sql/functions/aggregates)
- PostgreSQL HLL: [postgresql-hll on GitHub](https://github.com/citusdata/postgresql-hll)
- Druid: [HLL Sketch Module](https://druid.apache.org/docs/latest/development/extensions-core/datasketches-hll.html)
- Apache Pinot: [HyperLogLog](https://docs.pinot.apache.org/users/user-guide-query/supported-aggregations/distinct-count-hll)
- Vertica: [APPROXIMATE_COUNT_DISTINCT](https://www.vertica.com/docs/12.0.x/HTML/Content/Authoring/SQLReferenceManual/Functions/Aggregate/APPROXIMATE_COUNT_DISTINCT.htm)
- StarRocks: [HLL Type](https://docs.starrocks.io/docs/sql-reference/sql-functions/aggregate-functions/hll_union/)
- Apache Doris: [HLL Functions](https://doris.apache.org/docs/dev/sql-manual/sql-functions/hll-functions/hll-cardinality)
- Whang, K-Y. et al. "A Linear-Time Probabilistic Counting Algorithm for Database Applications" (1990), ACM TODS — LinearCounting 算法基础
- Durand, M., Flajolet, P. "LogLog Counting of Large Cardinalities" (2003), ESA — LogLog 前身论文
