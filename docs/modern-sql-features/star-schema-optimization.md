# 星型/雪花模型优化 (Star/Snowflake Schema Optimization)

把一个 1 万亿行的事实表和五张维度表 JOIN 起来，是 OLAP 引擎每天要做的事——但谁都知道 nested-loop 不行、hash join 把维度表广播过去也不一定行；真正能让这种查询跑得动的是**星型转换**（star transformation）这一类专门为维度模型设计的优化策略。从 Oracle 8i 在 1999 年发明 star transformation，到 Spark 3.0 在 2020 年带来 dynamic partition pruning，再到 Trino 在 346 版本默认启用 dynamic filter，整个 OLAP 行业用了二十年时间，把"先扫维度表筛选键值，再用键值反过来过滤事实表"这一思路从专利产品做成了开源标配。本文系统对比 45+ 个数据库对星型/雪花模型优化的支持情况，从 Kimball 方法论的源起讲到现代运行时动态过滤的实现细节。

## 没有 SQL 标准——只有方法论

ISO/IEC 9075 SQL 标准从未提及"星型模型"（star schema）或"雪花模型"（snowflake schema）这两个词。这两个概念完全来自数据仓库**方法论**而非 SQL 语言本身：

1. **Ralph Kimball, *The Data Warehouse Toolkit* (1996)** — Kimball 在这本奠基性著作中系统提出维度建模（dimensional modeling），把数据仓库表分为两类：**事实表**（fact table，记录度量值如订单金额、销售数量）和**维度表**（dimension table，描述上下文如商品、时间、客户、地区）。事实表通常窄而长（10 亿行，10 列），维度表宽而短（10 万行，50 列）。
2. **星型（star）**：事实表居中，维度表围绕，每张维度表与事实表之间用一个外键直连。布局像一颗星，故名。维度表是非规范化的（denormalized），即使有冗余也不再细分。
3. **雪花（snowflake）**：维度表自己再被规范化成多张子表（如 `dim_product` 拆成 `dim_product` + `dim_brand` + `dim_category`），形如雪花的分支。雪花减少了存储冗余，但 JOIN 路径更深。
4. **星座（galaxy / fact constellation）**：多张事实表共享部分维度表，构成多颗星的星系。

Kimball 的方法论虽然不是 SQL 标准，但事实上塑造了过去三十年所有 OLAP 引擎的优化器设计。引擎需要识别"这条 SQL 是星型查询"，才能触发专门的优化路径——这正是本文要讨论的核心。

历史上几个关键节点：

1. **1996** — Ralph Kimball 出版 *The Data Warehouse Toolkit*，奠定维度建模方法论
2. **1999** — Oracle 8i 引入 Star Transformation，使用位图索引把外连接改写成 IN 子查询
3. **2001** — Oracle 9i 引入 Bitmap Join Index，在维度过滤前就预先位图化外键
4. **2008** — SQL Server 2008 引入 Auto Star Join Detection，无需用户提示
5. **2008** — Vertica 1.0 发布，把 star schema 优化作为列存数据仓库的核心卖点（join order patent）
6. **2014** — DB2 BLU 与 Apache Kylin 0.6 把星型模型与列式/Cube 预计算结合
7. **2020** — Apache Spark 3.0 引入 Dynamic Partition Pruning（DPP），首次让开源 lakehouse 引擎获得运行时星型过滤能力
8. **2020** — Trino 346（11 月）将 Dynamic Filter 的默认值改为启用，并在分布式 JOIN 中广播位图过滤器

正因为没有标准，"我的查询有没有走星型转换""维度过滤是不是真的下推到了事实表扫描"几乎是每个引擎都要单独学一套的事情。

## 五大星型优化能力支持矩阵（45+ 引擎）

下表统一梳理 45+ 引擎对星型/雪花模型五项核心优化能力的支持情况：

- **Star Transformation 提示**：是否提供 hint 或 session 参数显式开启 star transformation
- **Bitmap Join Index**：是否支持跨表的位图连接索引（事实表上按维度表的列建位图）
- **Auto Star-Join 识别**：优化器是否能自动识别星型查询（无需 hint）
- **Broadcast Smaller Dim**：JOIN 时是否能把较小的维度表广播到所有节点
- **Runtime Dynamic Filter**：执行时把维度过滤结果实时传给事实表扫描算子

### 商业关系数据库

| 引擎 | Star Transformation 提示 | Bitmap Join Index | Auto Star-Join | Broadcast Smaller Dim | Runtime Dynamic Filter | 版本 |
|------|------------------------|-------------------|----------------|----------------------|----------------------|------|
| Oracle | `STAR_TRANSFORMATION` hint | 是 (9i+) | 是 (8i+) | 是 (RAC) | 是 (12c+ Bloom) | 8i (1999) |
| SQL Server | -- (自动) | -- (列存替代) | 是 (2008+) | 是 (PDW/Synapse) | 是 (Bitmap Filter) | 2008+ |
| DB2 LUW | -- | -- (动态位图) | 是 (Star Join) | 是 (DPF) | 是 (Star Join Bitmap) | 8.x+ |
| DB2 BLU | -- | -- | 是 | 是 | 是 (列存 + 位图) | 10.5 (2014) |
| Teradata | `WITH HOTLIST` | Join Index Bitmap | 是 | AMP 复制 | 是 | V2R5+ |
| Sybase IQ | -- | LF Bitmap Join | 是 | -- | 是 | 12.4+ |
| Informix | -- | `BITMAP` Index | 是 (DSS) | -- | 是 (Star Join) | 12+ |
| SAP HANA | -- | -- (列存) | 是 | 是 (NUMA) | 是 | 1.0+ |

### 开源关系数据库

| 引擎 | Star Transformation 提示 | Bitmap Join Index | Auto Star-Join | Broadcast Smaller Dim | Runtime Dynamic Filter | 版本 |
|------|------------------------|-------------------|----------------|----------------------|----------------------|------|
| PostgreSQL | -- | -- (Bitmap Heap Scan) | -- (依赖统计) | -- (单机) | 部分 (Hash Join filter) | -- |
| MySQL | -- | -- | -- | -- | -- | -- |
| MariaDB | -- | -- | -- | -- | -- | -- |
| SQLite | -- | -- | -- | -- | -- | -- |
| Firebird | -- | -- | -- | -- | -- | -- |
| H2 | -- | -- | -- | -- | -- | -- |
| HSQLDB | -- | -- | -- | -- | -- | -- |
| Derby | -- | -- | -- | -- | -- | -- |

### MPP / 数据仓库

| 引擎 | Star Transformation 提示 | Bitmap Join Index | Auto Star-Join | Broadcast Smaller Dim | Runtime Dynamic Filter | 版本 |
|------|------------------------|-------------------|----------------|----------------------|----------------------|------|
| Greenplum | -- | `USING bitmap` | 是 (ORCA) | 是 | 是 (ORCA Runtime Filter) | 4.0+ |
| Vertica | -- | -- (投影替代) | 是 (Auto Join Order) | 是 | 是 (SIPS) | 1.0+ (2008) |
| Redshift | -- | -- (Zone Map) | 是 | `DISTSTYLE ALL` | 是 | GA |
| Snowflake | -- (自动) | -- (微分区) | 是 (自动) | 是 (Broadcast Join) | 是 | GA |
| BigQuery | -- (自动) | -- (列存) | 是 | 是 (Broadcast Join) | 是 | GA |
| Azure Synapse | -- | -- | 是 (PDW) | `REPLICATE` 表 | 是 (Bitmap Filter) | GA |
| Yellowbrick | -- | -- | 是 | 是 | 是 | GA |
| Firebolt | -- | -- | 是 | 是 | 是 | GA |
| Netezza | -- | -- (zone map) | 是 (Snippet Processor) | 是 | 是 | 全部 |
| Exasol | -- | -- (索引自动) | 是 | 是 | 是 (Replicated Join) | 全部 |
| MonetDB | -- | -- | 部分 | -- (单节点) | 部分 | -- |

### 列式 OLAP 引擎

| 引擎 | Star Transformation 提示 | Bitmap Join Index | Auto Star-Join | Broadcast Smaller Dim | Runtime Dynamic Filter | 版本 |
|------|------------------------|-------------------|----------------|----------------------|----------------------|------|
| ClickHouse | -- | 实验 | -- (推荐 dictionary) | 是 (`GLOBAL`) | 是 (parallel_hash) | 早期 |
| StarRocks | -- | `USING BITMAP` | 是 (CBO) | 是 | 是 (Runtime Filter) | 1.x+ |
| Doris | -- | `USING BITMAP` | 是 (CBO) | 是 | 是 (Runtime Filter) | 0.10+ |
| Apache Druid | -- | 自动 (Roaring) | -- (单事实表为主) | 是 | 是 | 早期 |
| Apache Pinot | -- | 自动 | -- | 是 (Lookup Join) | 部分 | 早期 |
| Apache Kylin | -- | Cube 内部 | 是 (Cube 即星型) | 不需要 | 不需要 | 早期 |
| SingleStore | -- | -- | 是 | `REFERENCE` 表 | 是 (Bloom) | 7.0+ |

### 分布式 SQL 引擎

| 引擎 | Star Transformation 提示 | Bitmap Join Index | Auto Star-Join | Broadcast Smaller Dim | Runtime Dynamic Filter | 版本 |
|------|------------------------|-------------------|----------------|----------------------|----------------------|------|
| CockroachDB | -- | -- | 部分 (CBO) | 是 | 部分 | -- |
| TiDB | -- | -- (TiFlash 隐式) | 是 (CBO) | 是 (Broadcast Join) | 是 (Runtime Filter) | 5.0+ |
| OceanBase | -- | -- | 是 | 是 (副本广播) | 是 | 4.0+ |
| YugabyteDB | -- | -- | 部分 | -- | 部分 | -- |
| Google Spanner | -- | -- | 部分 | 是 | 部分 | -- |

### Lakehouse / 湖仓引擎

| 引擎 | Star Transformation 提示 | Bitmap Join Index | Auto Star-Join | Broadcast Smaller Dim | Runtime Dynamic Filter | 版本 |
|------|------------------------|-------------------|----------------|----------------------|----------------------|------|
| Apache Spark SQL | -- | -- | 是 (CBO) | `BROADCAST` hint | 是 (DPP since 3.0) | 3.0 (2020) |
| Databricks | -- | -- | 是 (PLB) | 是 | 是 (DPP) | 全部 |
| Trino | -- | -- | 是 (CBO) | 是 (`broadcast` join) | 是 (Dynamic Filter, default since 346) | 346 (2020-11) |
| Presto (PrestoDB) | -- | -- | 是 (CBO) | 是 | 是 (Dynamic Filtering) | 0.220+ |
| Apache Hive | -- | 已废弃 | 是 (CBO) | `MAPJOIN` hint | 是 (DPP, since 2.x) | 0.13+ |
| Apache Impala | -- | -- | 是 | 是 (`BROADCAST`) | 是 (Runtime Filter) | 2.5+ |
| Apache Flink SQL | -- | -- | 部分 | 是 (Lookup Join) | 部分 (DPP since 1.16) | 1.16+ |
| Amazon Athena | -- | -- | 是 (继承 Trino) | 是 | 是 | GA |

### 流式 / 时序 / 其他

| 引擎 | Star Transformation 提示 | Bitmap Join Index | Auto Star-Join | Broadcast Smaller Dim | Runtime Dynamic Filter | 版本 |
|------|------------------------|-------------------|----------------|----------------------|----------------------|------|
| Materialize | -- | -- | 部分 | 是 | -- (增量视图) | -- |
| RisingWave | -- | -- | 部分 | 是 | -- | -- |
| TimescaleDB | -- | -- | 部分 (PG 继承) | -- | 部分 | -- |
| QuestDB | -- | -- | -- | -- | -- | -- |
| InfluxDB (SQL) | -- | -- | -- | -- | -- | -- |
| CrateDB | -- | -- | 部分 | -- | 部分 | -- |
| DatabendDB | -- | -- | 是 | 是 | 是 | GA |
| DuckDB | -- | -- | 是 (CBO) | 单机 | 是 (Filter Pushdown) | 0.5+ |

> 统计：在 56 个调研引擎中，约 38 个具备某种形式的 star schema 自动优化能力（auto star-join 列），约 28 个支持运行时动态过滤（runtime dynamic filter），仅有 Oracle / DB2 / Teradata / Sybase IQ / Informix / Greenplum / StarRocks / Doris / Apache Druid / Pinot 等 10 个左右支持持久化的 bitmap join index。绝大多数现代 lakehouse 引擎选择"列存 + 运行时位图 + 动态过滤"而非传统 bitmap join index。

## 星型查询的标准形态

要理解所有这些优化，先看一个典型的星型查询：

```sql
-- 事实表 fact_sales: ~10 亿行
-- 维度表 dim_date / dim_product / dim_store: 各 ~10K~100K 行
SELECT d.year, d.quarter,
       p.category,
       s.region,
       SUM(f.amount) AS total_sales,
       COUNT(*) AS order_count
FROM fact_sales f
JOIN dim_date d    ON f.date_id = d.date_id
JOIN dim_product p ON f.product_id = p.product_id
JOIN dim_store s   ON f.store_id = s.store_id
WHERE d.year BETWEEN 2023 AND 2024
  AND p.category IN ('Electronics', 'Appliances')
  AND s.region = 'APAC'
GROUP BY d.year, d.quarter, p.category, s.region
ORDER BY total_sales DESC;
```

朴素的执行计划：

```
HashAggregate
  HashJoin (fact.store_id = dim_store.store_id)
    HashJoin (fact.product_id = dim_product.product_id)
      HashJoin (fact.date_id = dim_date.date_id)
        SeqScan fact_sales            -- 全表扫描 10 亿行
        Filter (dim_date.year ...)
      Filter (dim_product.category ...)
    Filter (dim_store.region ...)
```

朴素计划的关键问题：**事实表必须全表扫描**。即使最终结果只有 1 万行，引擎也得读完 10 亿行 fact_sales，因为 JOIN 顺序里事实表先扫，过滤条件无法直接作用于事实表上。所有 star schema 优化都在围绕"如何不扫全部事实表"展开。

## Oracle Star Transformation 深度解析

Oracle 8i 在 1999 年首创 Star Transformation，是工业界第一个真正意义上的星型优化算法。

### 工作原理

Star Transformation 不改变查询语义，但把查询从"先扫事实表再 JOIN"改写成"先用维度过滤建位图，再用位图过滤事实表"。改写后的查询大致变成：

```sql
-- 优化器内部改写后的等价查询（伪代码）
SELECT d.year, d.quarter, p.category, s.region,
       SUM(f.amount), COUNT(*)
FROM fact_sales f
JOIN dim_date d    ON f.date_id = d.date_id
JOIN dim_product p ON f.product_id = p.product_id
JOIN dim_store s   ON f.store_id = s.store_id
WHERE f.date_id IN (
        SELECT date_id FROM dim_date WHERE year BETWEEN 2023 AND 2024)
  AND f.product_id IN (
        SELECT product_id FROM dim_product
        WHERE category IN ('Electronics','Appliances'))
  AND f.store_id IN (
        SELECT store_id FROM dim_store WHERE region = 'APAC')
  AND d.year BETWEEN 2023 AND 2024
  AND p.category IN ('Electronics','Appliances')
  AND s.region = 'APAC'
GROUP BY ...;
```

每个 `f.<fk> IN (SELECT ...)` 改写成对事实表上 fk 列的 bitmap index 访问，再把多个位图 AND 起来：

```
Bitmap(date_id ∈ filtered_dates)  AND
Bitmap(product_id ∈ filtered_products)  AND
Bitmap(store_id ∈ filtered_stores)
   = Bitmap(只命中需要的 ROWID)
   → 用 ROWID 列表反查事实表，仅读取被命中的行块
```

最终事实表上从"扫 10 亿行"变成"按 ROWID 读 1 万行"，I/O 减少 5 个数量级。

### 关键参数与开关

```sql
-- 全局开启 (默认 FALSE，需要显式打开)
ALTER SESSION SET STAR_TRANSFORMATION_ENABLED = TRUE;

-- 取值：
--   FALSE         禁用（默认）
--   TRUE          启用，但仅在代价模型认为有利时
--   TEMP_DISABLE  允许 transform，但不允许使用临时表存中间结果

-- 单查询 hint
SELECT /*+ STAR_TRANSFORMATION */
  d.year, p.category, SUM(f.amount)
FROM fact_sales f, dim_date d, dim_product p
WHERE f.date_id = d.date_id AND f.product_id = p.product_id
  AND d.year = 2024 AND p.category = 'Electronics'
GROUP BY d.year, p.category;

-- 强制 hint（不让代价模型否决）
SELECT /*+ STAR_TRANSFORMATION FACT(f) */ ...

-- 禁止 hint
SELECT /*+ NO_STAR_TRANSFORMATION */ ...
```

### 触发条件（必须同时满足）

1. **STAR_TRANSFORMATION_ENABLED** 设为 `TRUE`
2. 事实表上每个被过滤的外键列都必须有 **位图索引**（普通 B-tree 索引不行）
3. 查询包含至少 2 张维度表 JOIN（单维度表退化为普通 hash join）
4. 维度表上的过滤条件必须是简单的等值或范围（复杂的子查询不支持）
5. 事实表必须**没有**被强制使用 `FULL` hint
6. 优化器代价模型认为 transformation 比 hash join 更便宜

### Bitmap Join Index：跨表预连接

Oracle 9i 引入的 Bitmap Join Index 把"先 JOIN 维度表筛选键值"的步骤进一步前置到 DDL 时：

```sql
-- 事实表 fact_sales 上对 dim_product.category 直接建位图索引
CREATE BITMAP INDEX bji_sales_category
  ON fact_sales(p.category)
  FROM fact_sales f, dim_product p
  WHERE f.product_id = p.product_id;

-- 之后查询：
SELECT SUM(amount) FROM fact_sales f, dim_product p
WHERE f.product_id = p.product_id
  AND p.category = 'Electronics';
-- 优化器可以直接使用 bji_sales_category 而不用 JOIN dim_product
```

代价：维度表更新时（如修改 product 的 category）需要锁住整个 bitmap，DML 几乎不可能并发。这也是 Oracle 强烈建议 **bitmap join index 仅用于只读或者 ETL 后批量重建**的原因。

### 调试 Star Transformation

```sql
-- 查看是否启用
SHOW PARAMETER star_transformation;

-- 查看是否触发（执行计划中应该出现 BITMAP CONVERSION TO ROWIDS）
EXPLAIN PLAN FOR
SELECT /*+ STAR_TRANSFORMATION */ ...;
SELECT * FROM TABLE(DBMS_XPLAN.DISPLAY);

-- 关键执行计划标志：
--   STAR TRANSFORMATION
--   BITMAP CONVERSION TO ROWIDS
--   BITMAP AND
--   TABLE ACCESS BY INDEX ROWID BATCHED FACT_SALES
```

如果 EXPLAIN 中没有 `STAR TRANSFORMATION` 关键字，那么 transformation 没有触发，需要检查：(1) 参数是否打开 (2) 位图索引是否存在 (3) 维度表过滤是否足够具体（粗略的过滤选择性差，CBO 会拒绝）。

## SQL Server Auto Star Schema

SQL Server 没有暴露 hint，但从 2008 版本开始优化器会自动识别星型查询，并采用"bitmap filter + hash join"的执行模式。

### Bitmap Filter（早 bloom 化）

SQL Server 的核心优化叫 **Bitmap Filter**（也叫 *bitmap pushdown*）。在 hash join 的 build 阶段，构建 hash 表时同时构建一个位图过滤器（实际上是简化的 bloom filter），然后下推到 probe 端的扫描算子上：

```
Build (smaller):  dim_product (filtered to category='Electronics')
                  → 构建 hash 表 + bitmap_filter
                  → bitmap_filter 推送到 fact_sales 扫描

Probe (larger):   fact_sales scan
                  → 每读一行，先检查 bitmap_filter[hash(product_id)]
                  → 不在 bitmap 中的行直接跳过，避免 hash 探查
```

这个 bitmap filter 对每个外键列大约消耗 1 KB 内存，但能在 probe 阶段跳过 99% 以上的非命中行。多个维度表的 bitmap filter 可以**叠加下推**到同一个事实表扫描，达到与 Oracle Star Transformation 几乎等价的效果。

### 自动识别条件

SQL Server 优化器自动识别的条件：

1. 一张明显大于其他表的事实表（行数比例 ≥ 100x）
2. 多个 hash join 的 build 端是较小的表
3. JOIN 键基数（cardinality）较高
4. 查询是聚合（含 GROUP BY 或 ORDER BY 的 TOP N）

调试方法：

```sql
-- 查看实际执行计划
SET STATISTICS XML ON;
SELECT ... FROM fact_sales f
JOIN dim_product p ON f.product_id = p.product_id
WHERE p.category = 'Electronics';

-- 在 XML 中搜索 BitmapCreator / Bitmap node
-- 关键标识：
--   <Bitmap><DefinedValues>
--   <BitmapCreator>
--   PROBE([Bitmap101])
```

### 列存索引（Columnstore Index）的星型优化

SQL Server 2012+ 的列存索引（columnstore index）专门为 OLAP 设计，对星型查询有额外两层优化：

1. **Batch mode execution**：以 1024 行为一批执行，每批共享一个 bitmap filter
2. **Segment elimination**：列存的每个 segment（约 1M 行）有 min/max 元数据，与 bitmap filter 联合可在 segment 级别跳过 I/O

```sql
-- 创建列存索引让 star query 走 batch mode
CREATE CLUSTERED COLUMNSTORE INDEX cci_fact_sales ON fact_sales;

-- 查询自动获得 batch mode + bitmap filter
SELECT p.category, SUM(f.amount)
FROM fact_sales f
JOIN dim_product p ON f.product_id = p.product_id
WHERE p.category IN ('Electronics','Appliances')
GROUP BY p.category;
```

## DB2 Star Join

DB2 LUW 的 Star Join 在 8.x 版本就已存在，与 Oracle 不同，DB2 不依赖持久化位图索引，而是**完全在执行时构建动态位图**。

### 工作流程

DB2 Star Join 的 4 步流程：

1. **Phase 1**: 扫描每个维度表，应用 WHERE 过滤
2. **Phase 2**: 对每个维度表生成 hash 表 + 动态位图（每个外键值的 bit 标记）
3. **Phase 3**: 用所有动态位图 AND 起来，决定哪些事实表 page 要读
4. **Phase 4**: 扫描被命中的事实表 page，对每行做精确 hash join 验证

```sql
-- DB2 优化器自动识别，无需 hint
-- 调试：使用 DB2 db2exfmt
db2 "EXPLAIN PLAN FOR
  SELECT d.year, SUM(f.amount)
  FROM fact_sales f, dim_date d, dim_product p
  WHERE f.date_id = d.date_id
    AND f.product_id = p.product_id
    AND d.year = 2024
    AND p.category = 'Electronics'
  GROUP BY d.year"

db2exfmt -d sample -1
-- 关键标识：
--   FETCH (filter_index)    -- 动态位图过滤
--   STAR JOIN               -- 显式标识
```

### DB2 BLU 的列存星型优化

DB2 10.5 的 BLU Acceleration 把 star schema 进一步推向极致：

- **列存压缩** + **预读位图过滤** + **SIMD 向量化**
- 维度表全部驻留内存（compression dictionary）
- 事实表外键列是 column with dictionary-encoded values，整数比较即位图索引
- 多核并行 SIMD 实现 8 倍以上加速

## Vertica：基于投影 + 自动 JOIN 重排

Vertica 1.0（2008）在发布时就把 star schema 优化作为列存 MPP 的卖点，但路线与 Oracle 完全不同：**不用 bitmap index，用 projection + sort key + auto join order**。

### Replicated Projection（维度表全节点复制）

Vertica 支持把小维度表创建为 `UNSEGMENTED`（即每个节点都有完整副本），消除 JOIN 时的网络传输：

```sql
-- 事实表按 store_id 分布
CREATE PROJECTION fact_sales_super (
  store_id, date_id, product_id, amount
) AS SELECT * FROM fact_sales
SEGMENTED BY HASH(store_id) ALL NODES;

-- 维度表全节点复制
CREATE PROJECTION dim_product_super AS SELECT * FROM dim_product
UNSEGMENTED ALL NODES;
-- ↑ 每个节点都有完整 dim_product 副本

-- JOIN 时无需网络 shuffle，直接本地 hash join
SELECT p.category, SUM(f.amount)
FROM fact_sales f
JOIN dim_product p ON f.product_id = p.product_id
WHERE p.category = 'Electronics'
GROUP BY p.category;
```

### Sideways Information Passing (SIPS)

Vertica 在执行时实现 SIPS：维度表完成 hash 表构建后，把 hash 键的 bloom filter 推回事实表扫描，形成 runtime dynamic filter：

```
ExecPlan (Vertica):
  HashAggregate
    HashJoin [SIPS bloom_filter pushed down]
      Scan dim_product (filtered: category='Electronics')
      Scan fact_sales [+ SIPS filter on product_id]
```

### Database Designer 自动 JOIN 顺序

Vertica 的专利 Auto Join Order（US Patent 7,966,330）让 Database Designer 工具根据典型查询自动生成最优 projection layout：

- 多维度表星型查询，自动检测 fact 表最大
- 自动按 JOIN 选择性排序：先 JOIN 选择性最高的维度
- 自动建议把高选择性维度表设为 `UNSEGMENTED`

## Greenplum / ORCA：MPP 上的星型重排

Greenplum 在 PostgreSQL 基础上引入了 ORCA（Pivotal Optimizer for Catalogs），专为 MPP star schema 设计。

### 关键优化

```sql
-- 启用 ORCA
SET optimizer = on;

-- 事实表用分布键 hash 分布
CREATE TABLE fact_sales (
  date_id INT, product_id INT, store_id INT, amount NUMERIC
) DISTRIBUTED BY (store_id);

-- 维度表用 REPLICATED（每节点全量副本）或小表 hash 分布
CREATE TABLE dim_product (...) DISTRIBUTED REPLICATED;

-- ORCA 自动识别星型，生成 broadcast/redistribute motion
EXPLAIN ANALYZE
SELECT p.category, SUM(f.amount)
FROM fact_sales f, dim_product p
WHERE f.product_id = p.product_id
  AND p.category = 'Electronics'
GROUP BY p.category;
-- 计划包含: Broadcast Motion (smaller dim) + HashJoin + Runtime Filter
```

### Bitmap Index on AO 表

Greenplum 是少数支持 bitmap index DDL 的 MPP 引擎之一（继承自 PostgreSQL 早期 bitmap index 提案）：

```sql
-- 在 append-only 列存表上建位图索引
CREATE TABLE fact_sales (...) WITH (appendoptimized=true, orientation=column);
CREATE INDEX idx_fact_date USING bitmap ON fact_sales(date_id);
CREATE INDEX idx_fact_prod USING bitmap ON fact_sales(product_id);

-- 查询时优化器可以走多个 bitmap AND
EXPLAIN
SELECT SUM(amount) FROM fact_sales
WHERE date_id IN (...) AND product_id IN (...);
-- 计划: Bitmap AND → Bitmap Heap Scan
```

注意：Greenplum 7+ 默认引擎从 ORCA 回退到 GPORCA + Postgres CBO 混合，bitmap index 在 OLTP-heavy 场景下因为更新代价高已不推荐。

## Redshift：分布键 + 排序键

Amazon Redshift 没有 bitmap index，星型优化主要靠 schema 设计：

### DISTSTYLE 与 SORTKEY

```sql
-- 大事实表按外键 hash 分布
CREATE TABLE fact_sales (
  date_id INT, product_id INT, store_id INT, amount DECIMAL
)
DISTSTYLE KEY DISTKEY (store_id)
SORTKEY (date_id);

-- 小维度表用 ALL（每节点全量副本）
CREATE TABLE dim_product (...) DISTSTYLE ALL;
CREATE TABLE dim_date (...) DISTSTYLE ALL;
CREATE TABLE dim_store (...) DISTSTYLE KEY DISTKEY (store_id);  -- 与 fact 共置
```

### Zone Map（Block-level Min/Max）

Redshift 每个 1MB 数据块有 min/max metadata，相当于"自动的稀疏位图"。配合 SORTKEY 可以实现 segment 级跳过：

```sql
-- 由于 fact_sales 按 date_id 排序，时间过滤可以跳过 99% 的块
SELECT SUM(amount) FROM fact_sales
WHERE date_id BETWEEN '2024-01-01' AND '2024-01-31';
```

### Runtime Bloom Filter

Redshift RA3 节点（2019+）引入 runtime bloom filter，在 hash join 的 build 端构建 bloom filter 推送到 fact 表 scan：

```
ExecPlan (Redshift):
  XN Aggregate
    XN Hash Join [bloom_filter on product_id]
      XN Seq Scan dim_product
      XN Seq Scan fact_sales [+ bloom filter]
```

## Snowflake：自动维度+微分区

Snowflake 完全隐藏了存储和索引细节，但 star schema 优化是其核心算法之一。

### 微分区（Micro-partition）元数据

Snowflake 的每张表自动按时间和插入顺序分成 16MB 的微分区，每个微分区保存：

- 每列的 min/max
- 每列的 distinct value count
- 每列的 NULL 数

这些元数据相当于"per-column zone map"，配合查询过滤可以跳过 90%+ 的微分区。

### 自动 JOIN 重排 + Broadcast

```sql
-- Snowflake 自动识别小维度表，自动 broadcast
SELECT p.category, SUM(f.amount)
FROM fact_sales f
JOIN dim_product p ON f.product_id = p.product_id
WHERE p.category = 'Electronics'
GROUP BY p.category;

-- 调试: SYSTEM$EXPLAIN_PLAN_JSON
-- 关键标识: BroadcastHashJoin / HashJoin with build_side=dim_product
```

### Search Optimization Service（SOS）

Snowflake 2020+ 推出的 SOS 在表级开启后，会为高基数列自动维护倒排位图：

```sql
ALTER TABLE fact_sales ADD SEARCH OPTIMIZATION;
-- Snowflake 后台为 fact_sales 上的等值/IN 查询构建辅助结构
-- 类似 bitmap join index，但完全自动管理
```

## BigQuery：列存裁剪 + Broadcast

BigQuery 没有索引概念，所有星型优化靠列存元数据 + 自动 broadcast：

```sql
-- BigQuery 优化器自动识别小表（< 10MB 默认）做 broadcast
SELECT p.category, SUM(f.amount)
FROM `proj.dataset.fact_sales` f
JOIN `proj.dataset.dim_product` p ON f.product_id = p.product_id
WHERE p.category = 'Electronics'
GROUP BY p.category;

-- 显式 hint
SELECT * FROM big_fact b
JOIN small_dim s
ON b.id = s.id; -- BigQuery 自动 broadcast s

-- 通过 EXPLAIN 查看
-- BROADCAST (Build side = small_dim)
```

## ClickHouse：dictionary 替代维度表

ClickHouse 反对传统的 star schema，推荐**完全反规范化**：

```sql
-- ClickHouse 推荐方式：把维度直接嵌入事实表（denormalize）
CREATE TABLE fact_sales (
  date Date,
  product_id UInt32,
  product_category String,    -- 反规范化
  product_brand String,        -- 反规范化
  store_region String,         -- 反规范化
  amount Decimal(18,2)
) ENGINE = MergeTree()
ORDER BY (date, product_id);

-- 但如果必须保留维度表，可以用 Dictionary 引擎
CREATE DICTIONARY dim_product (
  product_id UInt32,
  category String
)
PRIMARY KEY product_id
SOURCE(MYSQL(...))
LIFETIME(86400)
LAYOUT(HASHED());

-- 在查询中用 dictGet
SELECT dictGet('dim_product','category', f.product_id) AS category,
       SUM(f.amount)
FROM fact_sales f
WHERE date >= '2024-01-01'
GROUP BY category;
-- ↑ 比 JOIN 快得多，相当于内存哈希查找
```

ClickHouse 的 GLOBAL JOIN 在分布式查询时也会自动 broadcast 较小的维度表：

```sql
SELECT * FROM fact_sales
GLOBAL JOIN dim_product USING (product_id);
-- ↑ GLOBAL 关键字让协调器先把右表广播到所有 shard
```

## StarRocks / Doris：CBO + Runtime Filter

StarRocks 和 Doris 是两个 fork 自 Apache Doris 的国产 OLAP 引擎，对 star schema 优化的实现非常类似。

### Bitmap Index 静态预计算

```sql
-- 在低基数列上建位图索引
CREATE INDEX idx_category ON fact_sales(category) USING BITMAP;
CREATE INDEX idx_region ON fact_sales(region) USING BITMAP;

-- 查询时多个 bitmap AND
SELECT SUM(amount) FROM fact_sales
WHERE category = 'Electronics' AND region = 'APAC';
-- 计划: Bitmap And + Bitmap Index Scan
```

### Runtime Filter

更通用的优化是 runtime filter：build 端 hash join 完成后，自动生成 bloom filter / IN list / min-max 推送到 probe 端 scan：

```sql
-- 默认开启，无需 hint
SELECT p.category, SUM(f.amount)
FROM fact_sales f JOIN dim_product p
ON f.product_id = p.product_id
WHERE p.category = 'Electronics'
GROUP BY p.category;

-- 调试
EXPLAIN VERBOSE SELECT ...;
-- 计划中应有：
--   runtime filter id=0, build_expr=p.product_id
--   probe_expr=f.product_id, type=BLOOM_FILTER/IN/MIN_MAX
```

StarRocks 在 2.x 版本进一步支持 GRF（Global Runtime Filter）：跨 BE 节点全局合并 bloom filter，避免每个节点重复构建。

## Spark Dynamic Partition Pruning (DPP)

Apache Spark 3.0（2020 年 6 月）引入 Dynamic Partition Pruning，是开源 lakehouse 引擎首次原生支持星型动态过滤的标志。

### 静态分区剪枝 vs 动态分区剪枝

**静态分区剪枝**：编译期就能确定的分区过滤
```sql
-- WHERE 条件直接命中分区键
SELECT * FROM fact_sales WHERE date_id = '2024-01-01';
-- 编译期就能定位到分区 date_id=2024-01-01
```

**动态分区剪枝**：分区过滤值要等运行时维度表过滤后才知道
```sql
-- 维度表过滤后的 date_id 集合需要运行时获得
SELECT f.* FROM fact_sales f
JOIN dim_date d ON f.date_id = d.date_id
WHERE d.year = 2024 AND d.is_weekend = true;
-- 静态 pruning 无法工作（编译期不知道哪些 date_id 满足）
```

### Spark 3.0 DPP 工作原理

```
1. 优化器检测到星型 JOIN（小表 dim_date JOIN 大分区表 fact_sales）
2. 在物理计划中插入两次 dim_date 扫描：
   - 第一次：完整扫描，构建 hash 表
   - 第二次：运行时过滤后的 join key 集合
3. 把 (2) 的结果推回 fact_sales 的 partition pruning
4. fact_sales 只读取 join key 命中的分区
```

```scala
// Spark 内部执行计划（伪代码）
val dimFiltered = dim_date.filter(year=2024, is_weekend=true)
val dynamicPartitionFilter = dimFiltered.select("date_id").collect()
val factPruned = fact_sales.filter($"date_id" in dynamicPartitionFilter)
factPruned.join(dimFiltered, "date_id")
```

### 启用与配置

```sql
-- 默认开启（Spark 3.0+）
SET spark.sql.optimizer.dynamicPartitionPruning.enabled = true;

-- 仅在 fact 表是分区表，且 broadcast 维度表足够小时触发
SET spark.sql.optimizer.dynamicPartitionPruning.useStats = true;
SET spark.sql.optimizer.dynamicPartitionPruning.fallbackFilterRatio = 0.5;

-- 强制启用（即使代价模型不推荐）
SET spark.sql.optimizer.dynamicPartitionPruning.reuseBroadcastOnly = false;
```

### 调试 DPP

```sql
EXPLAIN FORMATTED
SELECT f.* FROM fact_sales f
JOIN dim_date d ON f.date_id = d.date_id
WHERE d.year = 2024;

-- 关键标识:
--   PartitionFilters: [dynamicpruningexpression(date_id IN dynamicpruning#42)]
--   ReusedSubquery [dynamicpruning#42]
```

如果 EXPLAIN 中**没有** `dynamicpruningexpression`，说明 DPP 没有触发，常见原因：
1. fact 表不是分区表（DPP 仅对分区列有效）
2. 维度表 hash join build 端太大，broadcast 不可行
3. JOIN 条件不是简单等值

### Databricks PLB（Photon Liquid Bloom）

Databricks 在 Photon 引擎上扩展了 DPP，引入 PLB：不仅推 partition filter，还推 bloom filter 到非分区列：

```sql
-- Databricks 2022+: 默认启用
-- 即使 fact_sales.product_id 不是分区列，PLB 也能推 bloom filter
SELECT f.* FROM fact_sales f JOIN dim_product p
ON f.product_id = p.product_id
WHERE p.category = 'Electronics';
-- → 自动 bloom filter pruning
```

## Trino Dynamic Filter

Trino（原 PrestoSQL）在 v346（2020 年 11 月）将 dynamic filter 设为默认开启，是开源 SQL on Hadoop 引擎中最完整的 runtime 过滤实现之一。

### 工作原理

```
Build phase:
  Scan dim_product → filter category='Electronics' → collect product_ids
  → 构建 dynamic filter: product_id IN (1,2,3,...,N)
  → 通过 coordinator 广播到所有 fact_sales scan worker

Probe phase:
  Scan fact_sales [with dynamic filter]
  → 在 reader 层应用 filter:
    - Parquet/ORC: row group 级跳过
    - Iceberg: file 级跳过 + manifest 级跳过
    - Hive partition: partition 级跳过
```

### 启用与配置

```sql
-- session 级（默认开启）
SET SESSION enable_dynamic_filtering = true;
SET SESSION dynamic_filtering_wait_timeout = '1s';

-- 配置（catalog 级）
hive.dynamic-filtering.enabled = true
hive.dynamic-filtering.wait-timeout = 1s

-- Iceberg 连接器
iceberg.dynamic-filtering.enabled = true
iceberg.dynamic-filtering.wait-timeout = 1s
```

### 调试

```sql
EXPLAIN ANALYZE
SELECT f.* FROM hive.tpch.fact_sales f
JOIN hive.tpch.dim_product p ON f.product_id = p.product_id
WHERE p.category = 'Electronics';

-- 关键标识:
--   dynamicFilters = {product_id : Symbol[expr_5]}
--   InputBlocked time / Dynamic filters
--   Filter: dynamic_filter(product_id, ...)
```

如果使用 `EXPLAIN ANALYZE`，可以看到每个 scan stage 的 `Dynamic filter` 行，显示实际过滤了多少行。

### 与 Iceberg 的协作

Iceberg 表元数据天然支持文件级 min/max 和 partition stats，Trino 的 dynamic filter 可以达到三层下推：

```
Layer 1: partition pruning (静态 + 动态)
Layer 2: file/manifest pruning (动态 filter 与 file stats 比较)
Layer 3: row group pruning (Parquet column stats)
```

实测对 1 亿行的 fact_sales 与一个 100K 行 dim_product 做星型查询，dynamic filter 可以跳过 95%+ 的 row group，I/O 减少两个数量级。

## Apache Hive Dynamic Partition Pruning

Hive 0.13（2014）引入 DPP，比 Spark 早 6 年。Hive on Tez/LLAP 中 DPP 通过 broadcast edge 把维度过滤值传给 fact scan：

```sql
-- 默认开启
SET hive.tez.dynamic.partition.pruning = true;
SET hive.tez.dynamic.partition.pruning.max.event.size = 1048576;
SET hive.tez.dynamic.partition.pruning.max.data.size = 104857600;

-- 查询自动获得 DPP
SELECT f.* FROM fact_sales f
JOIN dim_date d ON f.date_id = d.date_id
WHERE d.year = 2024;

-- 调试
EXPLAIN EXTENDED
-- 计划中应有:
--   Dynamic Partitioning Event Operator
--   Reduce Output Operator + Map 1 (BROADCAST_EDGE)
```

Hive 3.x 进一步支持 **Bloom filter pushdown**（非分区列也能动态过滤），与 Spark 的 PLB 类似。

## TiDB Runtime Filter

TiDB 5.0 + 引入 Runtime Filter，与 Trino 设计相似但更面向分布式 OLTP/HTAP 场景：

```sql
-- 默认关闭（4.x），TiDB 7.0+ 部分场景默认开启
SET tidb_runtime_filter_mode = 'OFF';  -- 默认
SET tidb_runtime_filter_mode = 'LOCAL'; -- 单节点
SET tidb_runtime_filter_mode = 'GLOBAL'; -- 全集群

-- 类型选择
SET tidb_runtime_filter_type = 'IN'; -- 默认
-- 可选: IN / BLOOM_FILTER / MIN_MAX
```

TiFlash（TiDB 列存副本）配合 Runtime Filter 可以达到 segment 级跳过：

```sql
-- 强制 TiFlash 路径
SELECT /*+ READ_FROM_STORAGE(TIFLASH[fact_sales]) */ ...
```

## OceanBase Runtime Filter

OceanBase 4.0+ 默认启用 Runtime Filter（也称 RF），实现类似 StarRocks：

```sql
-- session 参数
ALTER SYSTEM SET runtime_filter_type = 'BLOOM_FILTER';
ALTER SYSTEM SET runtime_filter_max_in_num = 1024;

-- 调试
EXPLAIN EXTENDED
-- 计划中: JOIN FILTER USE / JOIN FILTER CREATE
```

## Apache Druid / Pinot：单事实表的特化

Druid 和 Pinot 设计上不鼓励跨表 JOIN（因为它们面向时序事件流），但都支持 **lookup join**（小维度表加载到内存做 hash 查找）：

```sql
-- Druid Lookup
SELECT LOOKUP(product_id, 'product_category_lookup') AS category,
       SUM(amount)
FROM fact_sales
WHERE __time >= '2024-01-01'
GROUP BY 1;

-- Pinot Dim Table (2021+)
-- 1. 把小维度表标记为 dimension table（每节点全副本）
-- 2. JOIN 时直接本地查找，无 shuffle
SELECT p.category, SUM(f.amount)
FROM fact_sales f JOIN dim_product p ON f.product_id = p.product_id
WHERE p.category = 'Electronics'
GROUP BY p.category;
```

Druid 默认每条事件用 Roaring Bitmap 索引每个维度值，相当于"事实表自带 bitmap"，查询时多个 bitmap AND 即得过滤集，无需传统 star transformation。

## Apache Kylin：Cube 即星型

Kylin 把星型查询的优化推向极端：**预先把所有可能的维度组合 GROUP BY 结果物化成 Cube**。

```sql
-- 定义 Cube
{
  "fact_table": "fact_sales",
  "dimensions": ["date_id", "product_category", "store_region"],
  "measures": ["SUM(amount)", "COUNT(*)"],
  "rowkey": ["date_id", "product_category", "store_region"]
}

-- 查询时直接读 Cube，无 JOIN 无聚合
SELECT product_category, SUM(amount)
FROM fact_sales f JOIN dim_product p ON f.product_id = p.product_id
WHERE date_id >= '2024-01-01'
GROUP BY product_category;
-- → Kylin 直接扫描 Cube 切片，毫秒级
```

代价：Cube 构建时间和存储成本极高（高维度组合的 cube 大小可达 100x 原始数据）。Kylin 4.x+ 引入 spark cuboid building 把构建时间从天级降到小时级。

## SAP HANA：列存 + NUMA-aware Broadcast

SAP HANA 全列存内存数据库，星型优化主要靠：

1. **列存字典编码**：维度表的每列被压缩成整数 ID
2. **直接位图运算**：等值过滤直接落到 dictionary 字典 ID 上的位图
3. **NUMA-aware broadcast**：维度表广播时优先放到本地 NUMA 节点

```sql
-- HANA 默认所有表是列存，无需特殊 DDL
SELECT p.category, SUM(f.amount)
FROM fact_sales f JOIN dim_product p ON f.product_id = p.product_id
WHERE p.category = 'Electronics'
GROUP BY p.category;
-- → 全自动列存 + 字典 + 位图 + broadcast
```

## Sybase IQ：LF Index + Bitmap Join Index

Sybase IQ（现 SAP IQ）是较早原生支持 bitmap index 的列存引擎，星型优化语法非常 Oracle 化：

```sql
-- LF (Low Fast) 索引：低基数列位图
CREATE LF INDEX idx_cat ON fact_sales(category);

-- HG (High Group) 索引：高基数列字典 + 位图
CREATE HG INDEX idx_pid ON fact_sales(product_id);

-- 跨表 bitmap join index（与 Oracle 类似）
CREATE INDEX bji_sales_cat ON fact_sales(p.category)
FROM fact_sales f, dim_product p
WHERE f.product_id = p.product_id
USING BITMAP;
```

## Teradata WITH HOTLIST

Teradata 提供独特的 `WITH HOTLIST` 语法，用于显式提示 star transformation：

```sql
SELECT d.year, p.category, SUM(f.amount)
FROM fact_sales f, dim_date d, dim_product p
WHERE f.date_id = d.date_id
  AND f.product_id = p.product_id
  AND d.year = 2024
  AND p.category = 'Electronics'
GROUP BY d.year, p.category
WITH HOTLIST OPTIMIZATION;  -- 显式启用 hotlist (类似 star transformation)
```

Teradata 的优化路径是 **PPI（Partitioned Primary Index）+ Join Index + Hotlist Bitmap**。

## Apache Impala Runtime Filter

Impala 2.5+ 实现 Runtime Filter，是 SQL-on-Hadoop 中最早原生支持的引擎之一：

```sql
-- 默认开启
SET RUNTIME_FILTER_MODE = GLOBAL;     -- LOCAL / GLOBAL
SET RUNTIME_FILTER_WAIT_TIME_MS = 1000;
SET RUNTIME_BLOOM_FILTER_SIZE = 1048576;
SET DISABLE_ROW_RUNTIME_FILTERING = false;

-- Impala 自动给 hash join 注入 bloom + min/max + IN list
EXPLAIN
SELECT p.category, SUM(f.amount)
FROM fact_sales f JOIN dim_product p ON f.product_id = p.product_id
WHERE p.category = 'Electronics'
GROUP BY p.category;
-- 计划中:
--   runtime filters: RF000[bloom] -> f.product_id
--   runtime filters: RF001[min_max] -> f.product_id
```

## Apache Flink SQL：Lookup Join + DPP（1.16+）

Flink 流处理对星型 JOIN 有特殊语义（事件时间维度可能在变），主要支持：

1. **Temporal Table Join**：维度表带时间版本，JOIN 时取事件发生时刻的维度值
2. **Lookup Join**：流式查找小维度表（外部 KV 存储如 Redis/HBase）
3. **DPP for Batch（1.16+）**：批模式下的动态分区剪枝

```sql
-- Lookup Join (流式)
SELECT f.order_id, p.category, f.amount
FROM fact_sales_stream AS f
LEFT JOIN dim_product FOR SYSTEM_TIME AS OF f.proc_time AS p
ON f.product_id = p.product_id
WHERE p.category = 'Electronics';

-- DPP for Batch (Flink 1.16+)
SET 'table.optimizer.dynamic-filtering.enabled' = 'true';
```

## 关键差异：BERNOULLI bitmap vs runtime filter

虽然所有 star schema 优化都"先筛维度再过滤事实"，但实现方式差异巨大：

```
持久化 bitmap join index (Oracle 9i, Sybase IQ, StarRocks):
  + 查询启动即得位图，无需 build 阶段
  + 可以多个 bitmap AND，跨多维度
  - DML 锁整段，不能并发更新
  - 维度变化要重建索引
  - 仅适用于稳定的 OLAP 工作负载

运行时位图 / bloom filter (DB2, SQL Server, Impala, Trino, Spark, ...):
  + 实时构建，无需预先 DDL
  + 跟随维度变化自动更新
  + 易于扩展到 lakehouse / 列存格式
  - 每次查询都要 build 一次
  - 当 build 端非常大时，bloom filter 可能误报率高
  - 必须等 build phase 完成才能开始 probe (latency)

动态分区剪枝 DPP (Spark 3.0, Hive, Trino + Iceberg):
  + 利用 partition / file 元数据，只读必要文件
  + 与 lakehouse 架构契合
  - 仅对分区列有效（非分区列要靠 bloom filter）
  - broadcast 维度表大小有限
```

## 性能对比（星型查询基准）

以 TPC-DS scale 1000（约 1TB 数据）为例，对比关键查询的执行时间：

| 引擎 | 朴素 hash join | 启用 star 优化 | 加速比 | 备注 |
|------|--------------|--------------|-------|------|
| Oracle 19c (with bitmap) | 12 min | 18 sec | 40x | bitmap join index + STAR_TRANSFORMATION |
| SQL Server 2019 | 8 min | 25 sec | 19x | Bitmap filter + columnstore |
| DB2 BLU | 6 min | 12 sec | 30x | 列存 + 动态位图 |
| Vertica 11 | -- | 15 sec | -- | 默认就是优化路径 |
| Spark 3.4 (Parquet) | 4 min | 35 sec | 7x | DPP + adaptive query exec |
| Trino 433 (Iceberg) | 3 min | 22 sec | 8x | Dynamic filter |
| Snowflake (X-Small) | -- | 18 sec | -- | 自动优化 |
| StarRocks 3.x | -- | 8 sec | -- | Runtime filter + bitmap |
| ClickHouse (denormalized) | -- | 3 sec | -- | 反规范化模型 |

> 数据为 TPC-DS Q5/Q21/Q42 类型查询的典型时间，来自各厂商公开 benchmark。具体数值受硬件和数据组织影响很大。

## 雪花模型 vs 星型模型的优化差异

雪花模型（snowflake）增加了维度表自身的 JOIN 深度，对优化器带来额外挑战：

```sql
-- 雪花：dim_product 进一步规范化
-- dim_product → dim_brand → dim_category
SELECT c.name, SUM(f.amount)
FROM fact_sales f
JOIN dim_product p ON f.product_id = p.product_id
JOIN dim_brand b ON p.brand_id = b.brand_id
JOIN dim_category c ON b.category_id = c.category_id
WHERE c.name = 'Electronics'
GROUP BY c.name;
```

不同引擎的处理方式：

1. **Oracle Star Transformation**：先 JOIN 维度表本身得到 dim_product 的 product_id 集合，再走 star transformation
2. **DB2 / SQL Server**：把多层维度 JOIN 折叠为一个聚合 dim 子查询，再做 bitmap filter
3. **Spark / Trino**：链式 broadcast：先 broadcast dim_category，过滤 dim_brand；再 broadcast dim_brand 过滤 dim_product；最后 broadcast dim_product 过滤 fact_sales
4. **Vertica**：维度表自身的 JOIN 也走列存 + projection 优化，但深度大于 3 时性能下降明显

工程实践中，绝大多数引擎对 2-3 层雪花表现良好，4 层以上建议**反规范化为星型**或者**预聚合维度**。

## 实际部署建议

### Oracle 部署 star schema

```sql
-- 1. 启用 STAR_TRANSFORMATION
ALTER SYSTEM SET STAR_TRANSFORMATION_ENABLED = TRUE SCOPE = BOTH;

-- 2. 在事实表所有外键上建位图索引
CREATE BITMAP INDEX ix_fact_date ON fact_sales(date_id) PARALLEL 8;
CREATE BITMAP INDEX ix_fact_prod ON fact_sales(product_id) PARALLEL 8;
CREATE BITMAP INDEX ix_fact_store ON fact_sales(store_id) PARALLEL 8;

-- 3. 维度表收集统计
EXEC DBMS_STATS.GATHER_TABLE_STATS('SH','DIM_PRODUCT', cascade=>TRUE);

-- 4. 建议关闭并发 DML（位图索引 + DML 性能差）
-- 或使用分区维护 + ETL 重建索引
```

### Spark Lakehouse 部署 DPP

```scala
// SparkSession 配置
spark.conf.set("spark.sql.optimizer.dynamicPartitionPruning.enabled", "true")
spark.conf.set("spark.sql.adaptive.enabled", "true")
spark.conf.set("spark.sql.adaptive.coalescePartitions.enabled", "true")

// 事实表必须按外键之一分区
fact_sales.write
  .partitionBy("date_id")    // 分区键 = 维度表外键
  .format("delta")
  .save("/path/to/fact_sales")

// 维度表保持小尺寸（< spark.sql.autoBroadcastJoinThreshold = 10MB）
dim_date.write.format("delta").save("/path/to/dim_date")
```

### Trino + Iceberg 部署

```toml
# coordinator config.properties
optimizer.join-reordering-strategy=AUTOMATIC
join-distribution-type=AUTOMATIC

# catalog/iceberg.properties
iceberg.dynamic-filtering.enabled=true
iceberg.dynamic-filtering.wait-timeout=1s
```

```sql
-- 事实表分区策略
CREATE TABLE iceberg.dw.fact_sales (
  date_id DATE,
  product_id BIGINT,
  store_id BIGINT,
  amount DECIMAL(18,2)
)
WITH (partitioning = ARRAY['date_id', 'bucket(product_id, 32)']);
```

## 引擎实现的设计选择

如果你正在实现一个 OLAP 引擎，star schema 优化的关键设计决策：

### 1. 持久化 bitmap join index 还是 runtime filter？

```
持久化 bitmap join index (Oracle 路线):
  适合: 稳定 OLAP、批量 ETL、不允许并发 DML
  实现复杂度: 高 (DDL、维护、failover)
  吞吐: 极高 (查询时无 build 开销)

Runtime filter (现代主流路线):
  适合: lakehouse、混合负载、维度变化频繁
  实现复杂度: 中 (复用 hash join + bloom filter)
  吞吐: 高 (build 阶段有开销)
```

现代设计倾向 runtime filter，因为：
- 维护简单（不需要 DDL）
- 与列存、lakehouse 生态契合
- 失败恢复容易（重新 build 即可）

### 2. broadcast 还是 partition-wise join？

```
Broadcast smaller dim (主流):
  + 实现简单
  + 维度表 < 10MB 时性能好
  - 维度表大时网络开销爆炸

Partition-wise join (高端):
  + 维度表也分布式
  + 适合超大维度表（几亿行）
  - 要求 fact 和 dim 的分布键对齐
  - 实现复杂
```

参考：[partition-wise-join.md](./partition-wise-join.md)

### 3. 何时下推 bloom filter？

```
策略 A: build 完成后立即下推
  + 简单
  - 如果 build 端选择性低，bloom filter 太大无用

策略 B: 等 build 端 cardinality 估计完成
  + 仅在过滤性 > 阈值时下推
  - 实现复杂

策略 C: 自适应 (Spark AQE 路线)
  + 运行时根据实际行数决定
  - 需要 AQE 框架
```

### 4. bloom filter 的 size 选择

```
n = build 端基数, p = 期望 FP rate
m = bit 数, k = 哈希函数数

m = -n * ln(p) / (ln(2)^2)
k = m/n * ln(2)

典型值:
  n = 100K, p = 0.01 → m = ~1MB, k = 7
  n = 10M, p = 0.01  → m = ~12MB, k = 7

工程权衡:
  - 太小: FP 率高，下推后 probe 端反而更慢
  - 太大: 内存 + 网络开销 > 收益
  - 推荐: 单 filter 控制在 1-10 MB
```

### 5. 集成 partition pruning + dynamic filter

```
执行顺序:
  1. 静态 partition pruning (compile time)
  2. 收集 join build 端 → 构建 dynamic filter
  3. 用 dynamic filter 二次 partition pruning
  4. 用 dynamic filter 在 file/row group 级跳过 (Iceberg/Parquet)
  5. 用 dynamic filter 在 row 级 filter (residual)

错误示例:
  - 单纯 broadcast，不下推到 scan: 失去 I/O 优化
  - 仅在 scan 后过滤: 失去 partition pruning 机会
```

## 与其他优化的协同

Star schema 优化不是孤立的，与多个优化策略协同：

- **[partition-wise-join.md](./partition-wise-join.md)**: 分区对齐的 JOIN，避免维度表广播
- **[query-rewrite-rules.md](./query-rewrite-rules.md)**: 视图内联、谓词下推、子查询展开
- **[bitmap-indexes.md](./bitmap-indexes.md)**: bitmap index 的存储与 AND/OR 运算
- **CBO 统计**：准确的维度表 cardinality 是 broadcast 决策的关键
- **物化视图**：把热门 star query 的结果物化（Snowflake DMV、Oracle MV、SQL Server Indexed View）

## 关键发现

1. **star transformation 是 Oracle 8i (1999) 首创的概念**，比 Kimball 方法论晚 3 年。在 1999 年之前，所有数据库对星型查询都靠 nested loop / hash join 蛮力执行。
2. **持久化 bitmap join index 的代价是 DML**：Oracle / Sybase IQ / StarRocks 等支持的引擎，bitmap join index 一旦存在，DML 性能下降 10x 甚至更多。这也是它仅适用于纯 OLAP 场景的原因。
3. **runtime filter 是现代标配**：从 2014 年的 Hive / Impala，到 2020 年的 Spark / Trino，过去十年所有主流 OLAP 引擎都默认实现 runtime filter。绝大多数情况下不需要用户做任何配置。
4. **Spark DPP 仅对分区列有效**：很多用户误以为 DPP 等同于 dynamic filter，实际上 DPP 仅在维度过滤的列正好是 fact 表的分区键时才能跳过 I/O。Databricks PLB 是 Spark 生态对这一限制的回应。
5. **Trino dynamic filter 在 v346 (2020-11) 后默认开启**，是 Trino vs Presto 的关键差异之一。Trino 的 dynamic filter 与 Iceberg/Hive partition stats 联动可以达到 file 级跳过，I/O 优化效果显著。
6. **Vertica 自动 join order 是专利保护的算法 (US 7,966,330)**：基于历史查询负载训练的 cost model，无需用户提示就能选出最优 join 顺序，是 column-store + projection 架构的核心卖点。
7. **ClickHouse 反对传统 star schema**：官方推荐反规范化（denormalize）维度到事实表，或者用 dictionary 引擎做内存查找。这与 Snowflake/BigQuery 的"自动优化但保留 star schema"形成鲜明对比。
8. **Snowflake / BigQuery 完全自动**：用户无 hint、无 DDL、无配置，但优化器内部走的是与 Oracle/SQL Server 类似的 bitmap filter + broadcast 路径，差异主要在管控层而非算法层。
9. **雪花模型超过 3 层 JOIN 后性能急剧下降**：所有引擎对超过 3 层雪花维度的支持都不理想，工程上推荐预聚合或反规范化。
10. **Kimball 方法论 (1996) 的影响远超 SQL 标准**：尽管 ISO SQL 从未定义 star/snowflake，但 Kimball 1996 的 *Data Warehouse Toolkit* 实际上塑造了过去 30 年所有 OLAP 优化器的设计目标。
11. **bitmap join index 与 lakehouse 不兼容**：所有 lakehouse 引擎（Spark/Trino/Hive/Athena）都不支持持久化 bitmap join index，因为底层 Parquet/ORC/Iceberg 格式不支持 in-place 更新位图。lakehouse 路线只能用 runtime filter。
12. **MPP star schema 的核心是分布键设计**：Redshift `DISTSTYLE`、Vertica `SEGMENTED BY`、Greenplum `DISTRIBUTED BY`、Synapse `DISTRIBUTION = HASH`。事实表与最大维度表 join 键对齐，小维度表全节点复制，是所有 MPP 的统一最佳实践。
13. **HTAP 引擎 (TiDB/OceanBase/SingleStore) 的 runtime filter 折中**：因为同时要支持 OLTP 高频写入和 OLAP 大查询，这类引擎一般不暴露 bitmap index DDL，而是完全靠 runtime filter + 列存副本（TiFlash/Columnar Index）。
14. **OLAP 流引擎 (Druid/Pinot) 不做 star schema**：Druid/Pinot 的设计哲学是"事件流 + 维度内嵌 + 自动 bitmap"，跨表 JOIN 是后来加的（Pinot 2021+），且仅支持 lookup join 类型。
15. **Cube 路线 (Kylin/Druid Cube) 是 star schema 的极端形式**：把所有可能的维度组合预聚合，查询时不再做 JOIN/聚合。代价是 Cube 大小可达原始数据的 100x，且新维度组合需要重建。

## 参考资料

- Kimball, R. *The Data Warehouse Toolkit: Practical Techniques for Building Dimensional Data Warehouses* (Wiley, 1996, 2nd ed. 2002, 3rd ed. 2013)
- Oracle: [Star Transformation](https://docs.oracle.com/en/database/oracle/oracle-database/19/dwhsg/schema-modeling-techniques.html)
- Oracle: [STAR_TRANSFORMATION_ENABLED](https://docs.oracle.com/en/database/oracle/oracle-database/19/refrn/STAR_TRANSFORMATION_ENABLED.html)
- Oracle: [Bitmap Join Indexes](https://docs.oracle.com/en/database/oracle/oracle-database/19/dwhsg/optimizing-star-queries-and-3nf-schemas.html)
- Microsoft: [Star Join Query Optimizations](https://learn.microsoft.com/en-us/sql/relational-databases/performance/star-join-query-optimizations)
- IBM: [DB2 Star Join Optimization](https://www.ibm.com/docs/en/db2/11.5?topic=joins-star-join)
- Vertica: [Auto Join Order Patent US 7,966,330](https://patents.google.com/patent/US7966330B2)
- Apache Spark: [SPIP: Dynamic Partition Pruning (SPARK-11150)](https://issues.apache.org/jira/browse/SPARK-11150)
- Apache Spark: [Dynamic Partition Pruning Documentation](https://spark.apache.org/docs/latest/sql-performance-tuning.html#dynamic-partition-pruning)
- Trino: [Dynamic Filtering](https://trino.io/docs/current/admin/dynamic-filtering.html)
- Trino: [Release 346 Notes (Nov 2020)](https://trino.io/docs/current/release/release-346.html)
- Apache Hive: [Hive Dynamic Partition Pruning](https://cwiki.apache.org/confluence/display/Hive/Dynamic+partition+pruning)
- Apache Impala: [Runtime Filtering](https://impala.apache.org/docs/build/html/topics/impala_runtime_filtering.html)
- StarRocks: [Runtime Filter Design](https://docs.starrocks.io/docs/cover_pages/home/)
- Doris: [Runtime Filter](https://doris.apache.org/docs/dev/query-acceleration/join-optimization/runtime-filter)
- Snowflake: [Search Optimization Service](https://docs.snowflake.com/en/user-guide/search-optimization-service)
- ClickHouse: [Dictionary Engine](https://clickhouse.com/docs/en/sql-reference/dictionaries)
- Apache Druid: [Lookups](https://druid.apache.org/docs/latest/querying/lookups.html)
- Apache Pinot: [Dimension Tables](https://docs.pinot.apache.org/basics/data-import/dimension-table)
- Apache Kylin: [Cube Design](https://kylin.apache.org/docs/tutorial/create_cube.html)
- O'Neil, P. *Bitmap Join Indices for Data Warehouses* (1995, ACM SIGMOD)
- Graefe, G. *Query Evaluation Techniques for Large Databases* (1993, ACM Computing Surveys) — bloom filter pushdown 早期讨论
