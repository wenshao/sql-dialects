# 位图索引 (Bitmap Indexes)

一种几乎被时代遗忘但又在 OLAP 引擎中悄然复活的索引结构——位图索引以"每个值一张位图"的极简思想，在低基数列、AND/OR 谓词组合、星型模型 JOIN 等场景中带来 100 倍以上的查询加速，同时也带来了几乎致命的并发 DML 代价。

## 标准定位

ANSI/ISO SQL 标准从未定义位图索引（Bitmap Index）的语法或语义。SQL:2016/2023 仅规范了 `CREATE INDEX` 这一通用语法，至于索引的具体实现（B-tree、Hash、Bitmap、GiST、GIN、Inverted、Skip 等）完全由各引擎自行决定。

历史上几个关键节点：

1. **1987** — Patrick O'Neil 在 ACM 论文中正式提出 Bitmap Index 概念
2. **1993** — Model 204 (Computer Corporation of America) 商用化位图索引
3. **1996** — Oracle 7.3 引入 `CREATE BITMAP INDEX`，成为商业数据库的标志性特性，但仅限 Enterprise Edition
4. **2005** — PostgreSQL 8.1 引入 Bitmap Heap Scan，将多个 B-tree 结果通过位图运算合并（运行时位图，非持久化）
5. **2014** — Lemire 等人发表 Roaring Bitmap 论文，成为现代 OLAP 引擎事实上的位图压缩标准
6. **2015 至今** — Druid、Pinot、ClickHouse、StarRocks、Doris 等 OLAP 引擎纷纷采用 Roaring Bitmap

由于不在标准之列，各引擎对位图索引的支持差异极大，从"完全不支持"到"专门为星型模型设计的 Bitmap Join Index"应有尽有。

## 支持矩阵（综合 50+ 引擎）

### 原生位图索引 DDL

| 引擎 | 持久化位图索引 DDL | 语法 | 版本 | 备注 |
|------|------------------|------|------|------|
| Oracle | 是 | `CREATE BITMAP INDEX` | 7.3 (1996) | EE 版独占；DML 锁整段 |
| Oracle Bitmap Join | 是 | `CREATE BITMAP INDEX ... ON ... FROM ...` | 9i (2001) | 跨表预连接位图 |
| PostgreSQL | 否（运行时） | -- | 8.1 (2005) | Bitmap Heap Scan 动态构建 |
| Greenplum | 是 | `CREATE INDEX ... USING bitmap` | 4.0+ | PG 分支扩展，AO 表常用 |
| MySQL | 否 | -- | -- | 仅 InnoDB B+ tree |
| MariaDB | 否 | -- | -- | 同 MySQL |
| SQLite | 否 | -- | -- | 仅 B-tree |
| SQL Server | 否（隐式） | -- | -- | 列存中隐含位图操作 |
| DB2 | 否（动态） | -- | -- | Star Join 动态位图 |
| Sybase IQ | 是 | `CREATE BITMAP INDEX` / `LF/HG` | 12.4+ | Low Fast / High Group |
| Vertica | 否 | -- | -- | 投影 + 编码替代 |
| ClickHouse | 是（skip） | `INDEX ... TYPE bloom_filter / set` | 19.6+ | 跳数索引含位图思想 |
| ClickHouse bitmap | 是 | `bitmap_index` (实验) | 21+ | MergeTree 支持 |
| Apache Druid | 是 | 自动 | 0.7+ | Roaring Bitmap 默认 |
| Apache Pinot | 是 | `bitmapIndex` 配置 | 早期 | Roaring 倒排 |
| StarRocks | 是 | `CREATE INDEX ... USING BITMAP` | 1.x+ | 仅静态低基数列 |
| Doris | 是 | `CREATE INDEX ... USING BITMAP` | 0.10+ | 同 StarRocks |
| Apache Kylin | 是 | Cube 内部 | 早期 | 多维 Cube 加速 |
| Snowflake | 否 | -- | -- | 微分区元数据替代 |
| BigQuery | 否 | -- | -- | 列式裁剪替代 |
| Redshift | 否 | -- | -- | Zone Map 替代 |
| Spark SQL | 否 | -- | -- | 依赖 Parquet 元数据 |
| Hive | 是（已废弃） | `CREATE INDEX ... AS 'BITMAP'` | 0.8 (2011) | 3.0 移除 |
| Impala | 否 | -- | -- | -- |
| Trino/Presto | 否 | -- | -- | -- |
| Druid (Imply) | 是 | 自动 | 全部 | Roaring/Concise |
| InfluxDB | 是（内部） | -- | TSI 索引 | 时间序列倒排位图 |
| Elasticsearch | 是 | `doc_values` 自动 | 全部 | Roaring Lucene 内部 |
| Cassandra | 否 | -- | -- | SAI 索引为 trie+bitmap |
| ScyllaDB | 否 | -- | -- | 同 Cassandra |
| MongoDB | 否 | -- | -- | B-tree only |
| CockroachDB | 否 | -- | -- | -- |
| TiDB | 否 | -- | -- | TiFlash 列存隐式 |
| OceanBase | 否 | -- | -- | -- |
| YugabyteDB | 否 | -- | -- | LSM only |
| SingleStore | 否 | -- | -- | 列存压缩位图 |
| Exasol | 否 | -- | -- | 全列式 |
| MonetDB | 否 | -- | -- | 列式 imprint 索引 |
| HANA | 否 | -- | -- | 列存字典编码 |
| Teradata | 是 | Join Index Bitmap | V2R5+ | Hash + Bitmap |
| Netezza | 是（zone map） | 自动 | 全部 | ZoneMap 类位图 |
| Yellowbrick | 否 | -- | -- | 区间映射 |
| Firebolt | 否 | -- | -- | -- |
| DuckDB | 否 | -- | -- | Min-Max + 位图运行时 |
| Materialize | 否 | -- | -- | -- |
| RisingWave | 否 | -- | -- | -- |
| Crate DB | 否 | -- | -- | Lucene 后端隐式 |
| QuestDB | 否 | -- | -- | -- |
| Informix | 是 | `CREATE INDEX ... BITMAP` | 12+ | 数据仓库版本 |
| Firebird | 否（运行时） | -- | -- | 内部位图合并 |
| H2 | 否 | -- | -- | -- |
| HSQLDB | 否 | -- | -- | -- |
| Derby | 否 | -- | -- | -- |
| Amazon Athena | 否 | -- | -- | 继承 Trino |
| Azure Synapse | 否 | -- | -- | 列存替代 |
| Databricks | 否 | -- | -- | Photon 元数据替代 |
| Databend | 否 | -- | -- | -- |

> 统计：约 12 个引擎提供原生 / 持久化位图索引 DDL；约 35 个引擎完全不支持；其余通过列存元数据、Bloom filter、Zone Map 等替代方案达成相似效果。

### Bitmap Heap Scan / 运行时位图（PG-style）

运行时位图是另一类范式：索引本身仍是 B-tree，但优化器在执行期把多条 B-tree 结果合并为位图，再回表。这种做法不需要专门的位图索引 DDL，但要求执行器内置位图运算与回表逻辑。

| 引擎 | 运行时位图合并 | AND/OR Pushdown | 实现方式 | 备注 |
|------|--------------|-----------------|---------|------|
| PostgreSQL | 是 | 是 | BitmapAnd / BitmapOr 节点 | 8.1 起，单 page 一位 |
| Greenplum | 是 | 是 | 继承 PG | 增加 AO 优化 |
| Oracle | 是 | 是 | BITMAP CONVERSION FROM ROWIDS | 即使 B-tree 也能位图合并 |
| DB2 | 是 | 是 | Index ANDing/ORing | Star Join 动态位图 |
| SQL Server | 是 | 是 | Bitmap operator | Hash Join 中的 Bitmap filter |
| Firebird | 是 | 是 | Sparse Bitmap | 历史悠久（InterBase 起） |
| MySQL | 否 | -- | Index Merge 类似但非位图 | -- |
| MariaDB | 否 | -- | Index Merge | -- |
| ClickHouse | 是 | 是 | Granule 级位图 | 跳数索引转化 |
| Druid | 是 | 是 | Roaring AND/OR | 段级位图 |
| Pinot | 是 | 是 | Roaring AND/OR | 段级位图 |
| StarRocks | 是 | 是 | Roaring AND/OR | -- |
| Doris | 是 | 是 | Roaring AND/OR | -- |
| DuckDB | 是 | 是 | SelectionVector + Bitmask | 向量化执行 |
| Trino | 是 | 是 | Block-level Bitmap | 内置 BitmapBuilder |
| Snowflake | 是 | 是 | 微分区裁剪 + Bitmap | 内部不暴露 |

### 压缩位图实现

| 引擎 | 压缩格式 | 算法 | 备注 |
|------|---------|------|------|
| Apache Druid | Roaring / Concise | Lemire 2014 / Colantonio 2010 | 默认 Roaring |
| Apache Pinot | Roaring | Lemire 2014 | RoaringBitmap Java |
| ClickHouse | RoaringBitmap | Lemire 2014 | bitmap_* 函数族 |
| StarRocks / Doris | Roaring | Lemire 2014 | bitmap_* 函数族 |
| Elasticsearch / Lucene | Roaring | Lemire 2014 | doc_values & live docs |
| Apache Kylin | Roaring | Lemire 2014 | Cube measures |
| InfluxDB TSI | Roaring | Lemire 2014 | 时间序列倒排 |
| PostgreSQL | RLE 内存位图 | 自有 | 8.1 起，无持久化 |
| Oracle | BBC (Byte-aligned) | O'Neil 1989 | 经典字节对齐压缩 |
| Sybase IQ | LF/HG/HNG | 自有 | 多种位图变体 |
| Vertica | 列编码 | 自有 (RLE/Delta/BlockDict) | 非真位图 |
| Bitmagic / FastBit | WAH/EWAH | Wu 2002 / 2010 | 学术/独立库 |
| MonetDB | imprints | 内部 | 不是位图但思想相近 |

### 位图索引扩展能力

| 引擎 | Bitmap on JOIN | 星型模型加速 | 高基数适配 | 并发 DML 影响 |
|------|---------------|-------------|-----------|--------------|
| Oracle | 是 (Bitmap Join Index) | 是 (`STAR_TRANSFORMATION_ENABLED`) | 高基数不推荐 | 严重，锁整段位图 |
| DB2 | 否 | 是 (动态星型 Join) | 通用 | 无影响 (运行时) |
| SQL Server | 是 (Bitmap filter) | 是 (Star Join Hint) | 通用 | 无影响 |
| PostgreSQL | 否 | 否 | 通用 | 无影响 (运行时) |
| Greenplum | 否 | 否 | 高基数不推荐 | 中等（AO 表 OK） |
| StarRocks | 否 | 否 | 仅低基数 | 严重 (合并粒度) |
| Doris | 否 | 否 | 仅低基数 | 严重 |
| Druid | 否 | 否 | 通用（不可变段） | 无（段不可变） |
| Pinot | 否 | 否 | 通用（段不可变） | 无 |
| ClickHouse | 否 | 否 | 通用 | 无（合并时重建） |
| Sybase IQ | 是 | 是 | LF 低/HG 高 | 中等 |
| Informix | 是 | 是 | 高基数受限 | 严重 |
| Hive (旧) | 否 | 否 | -- | 严重，已废弃 |
| Vertica | 否 | 是（投影） | -- | 无 |

## SQL 标准的态度

ISO/IEC 9075:2023（即 SQL:2023）的索引相关章节大致如下：

```sql
-- 标准 CREATE INDEX 语法（SQL:2016 起明确）
CREATE [UNIQUE] INDEX <index_name>
    ON <table_name> (<column_list>)
    [<storage_options>]
```

标准对索引的"内部结构"完全不作约束。这意味着：

1. 一个引擎可以让 `CREATE INDEX foo ON bar(c)` 创建 B-tree、位图、哈希、LSM、GiST 等任意结构
2. 各厂商的扩展语法 `USING BITMAP` / `BITMAP` 关键字 / `WITH (BITMAP=ON)` 全是非标准
3. 没有标准化的位图集合运算函数（如 `bitmap_or`, `bitmap_and`），各引擎自定义

由于位图索引的实现细节强相关于物理存储（行号映射、压缩格式、合并策略），SQL 标准化几乎不可能。

## 各引擎语法详解

### Oracle（位图索引的开创者）

Oracle 是商业数据库中第一个全面支持位图索引的引擎，Oracle 7.3 (1996) 首发。

```sql
-- 1. 经典位图索引（Enterprise Edition Only）
CREATE BITMAP INDEX idx_emp_gender ON employees(gender);
-- gender 是 'M'/'F' 极低基数，非常适合位图

-- 2. 多列位图索引
CREATE BITMAP INDEX idx_sales_region_year ON sales(region, year);

-- 3. Bitmap Join Index（9i 引入）
CREATE BITMAP INDEX idx_sales_cust_state
    ON sales(c.state)
    FROM sales s, customers c
    WHERE s.cust_id = c.cust_id;
-- 这是 Oracle 独有的"预先连接好的位图"
-- 查询 SELECT ... FROM sales s, customers c WHERE c.state = 'CA'
-- 不需要 JOIN，直接用位图过滤 sales

-- 4. 启用 Star Transformation
ALTER SESSION SET STAR_TRANSFORMATION_ENABLED = TRUE;
SELECT /*+ STAR_TRANSFORMATION */ ...
FROM fact f, dim_time t, dim_product p
WHERE f.time_id = t.time_id
  AND f.product_id = p.product_id
  AND t.year = 2024
  AND p.category = 'Electronics';
-- 优化器把多个维度过滤变成位图 AND，再回 fact 表
```

Oracle 位图索引的关键限制：

- **EE 独占**：Oracle Standard Edition 不支持，必须 Enterprise Edition
- **DML 杀手**：单行更新可能锁住整段位图（数千行），高并发 OLTP 严重退化
- **基数门槛**：通常推荐 distinct 值 < 总行数 1%，否则压缩效率下降
- **限制函数索引**：`CREATE BITMAP INDEX ... ON expr(x)` 在某些情况下退化

### PostgreSQL（运行时位图，最成熟的非持久化方案）

PostgreSQL 8.1 (2005) 引入 Bitmap Heap Scan，**没有专门的"位图索引"**，所有位图都在查询期动态构建。

```sql
-- 假设有以下表和索引
CREATE TABLE orders (
    id bigserial PRIMARY KEY,
    customer_id int,
    status text,
    amount numeric,
    created_at timestamp
);
CREATE INDEX idx_orders_customer ON orders(customer_id);
CREATE INDEX idx_orders_status   ON orders(status);
CREATE INDEX idx_orders_created  ON orders(created_at);

-- 单条件 Bitmap Index Scan
EXPLAIN ANALYZE
SELECT * FROM orders WHERE customer_id = 12345;
-- 计划:
--   Bitmap Heap Scan on orders
--     Recheck Cond: (customer_id = 12345)
--     -> Bitmap Index Scan on idx_orders_customer
--           Index Cond: (customer_id = 12345)

-- 两个条件的 BitmapAnd 合并
EXPLAIN ANALYZE
SELECT * FROM orders
WHERE customer_id = 12345 AND status = 'shipped';
-- 计划:
--   Bitmap Heap Scan on orders
--     Recheck Cond: ...
--     -> BitmapAnd
--          -> Bitmap Index Scan on idx_orders_customer
--          -> Bitmap Index Scan on idx_orders_status

-- OR 条件的 BitmapOr
EXPLAIN ANALYZE
SELECT * FROM orders
WHERE status = 'shipped' OR status = 'cancelled';
-- 计划:
--   Bitmap Heap Scan on orders
--     -> BitmapOr
--          -> Bitmap Index Scan on idx_orders_status (status = 'shipped')
--          -> Bitmap Index Scan on idx_orders_status (status = 'cancelled')

-- 控制位图阈值
SET enable_bitmapscan = ON;       -- 默认启用
SHOW work_mem;                     -- 位图大小受 work_mem 限制
-- 位图过大时退化为 lossy bitmap（按 page 标记，回表后 Recheck）
```

PostgreSQL 位图的几个重要特点：

1. **动态构建**：每次查询从 B-tree 读取 TID，构建内存位图，无持久化
2. **两阶段位图**：先精确（按 TID）→ 内存不足时退化为 lossy（按 page）
3. **回表 Recheck**：lossy bitmap 必须重新检查谓词，避免误命中
4. **AND/OR 自由组合**：BitmapAnd 和 BitmapOr 节点可任意嵌套

### Greenplum（PG 衍生但有真位图）

Greenplum 是基于 PostgreSQL 的 MPP 分析数据库，扩展了真正的持久化位图索引：

```sql
-- 真正的持久化位图索引
CREATE INDEX idx_sales_region ON sales USING bitmap (region);
CREATE INDEX idx_sales_year   ON sales USING bitmap (year);

-- 适用场景：AO（Append-Only）表 + 低基数列
CREATE TABLE sales (
    id bigserial,
    region text,        -- ~10 值
    year int,           -- ~20 值
    amount numeric
)
WITH (appendoptimized = true, orientation = column)
DISTRIBUTED BY (id);

-- 多个位图条件 AND
SELECT SUM(amount) FROM sales
WHERE region = 'APAC' AND year IN (2022, 2023, 2024);
```

Greenplum 的位图索引特别适合 AO（Append-Only）表 + 列式存储 + 数仓 ETL 模式（批量插入、几乎无 UPDATE/DELETE），避开了 Oracle 位图索引的 DML 之痛。

### ClickHouse（MergeTree skip indexes 中的位图）

ClickHouse 的位图思想体现在两个层面：**跳数索引**和**位图聚合函数**。

```sql
-- 1. 跳数索引（不是真正的位图索引，但在 granule 级使用位图思想）
CREATE TABLE events (
    id UInt64,
    user_id UInt64,
    event_type String,
    event_date Date,
    INDEX idx_event_type event_type TYPE bloom_filter GRANULARITY 4,
    INDEX idx_user_id user_id TYPE bloom_filter GRANULARITY 4
)
ENGINE = MergeTree()
PARTITION BY event_date
ORDER BY (event_date, id);

-- 2. 真正的 Bitmap 数据类型（21+ 实验性 bitmap_index）
-- 在 part 级存储 RoaringBitmap
ALTER TABLE events ADD INDEX idx_user user_id TYPE bitmap_index GRANULARITY 1;

-- 3. RoaringBitmap 函数族（更常用）
SELECT
    groupBitmapState(user_id) AS daily_users
FROM events
GROUP BY event_date;
-- 返回 AggregateFunction(groupBitmap, UInt64)
-- 可用于物化视图或 SummingMergeTree 加速去重统计

-- 4. RoaringBitmap 集合运算
SELECT bitmapAnd(b1, b2) FROM ...;
SELECT bitmapOr(b1, b2) FROM ...;
SELECT bitmapXor(b1, b2) FROM ...;
SELECT bitmapCardinality(b) FROM ...;

-- 实际场景：留存率分析
SELECT
    bitmapCardinality(bitmapAnd(d1.users, d7.users)) /
    bitmapCardinality(d1.users) AS retention_d7
FROM
    (SELECT groupBitmapState(user_id) AS users FROM events
     WHERE event_date = '2026-04-01') d1,
    (SELECT groupBitmapState(user_id) AS users FROM events
     WHERE event_date = '2026-04-08') d7;
```

ClickHouse 的位图哲学：把 RoaringBitmap 暴露成数据类型而非索引，让用户在 ETL 阶段预聚合用户群体位图，查询时做集合运算。这种"位图作为数据"的范式在留存、归因、漏斗分析中威力巨大。

### Apache Druid（默认 Roaring 的列存）

Druid 是较早全面采用 RoaringBitmap 的 OLAP 引擎，从 0.7 (2015) 起所有维度列都自动构建 Roaring 位图索引。

```json
// Druid 摄入配置（spec.json 的 dimensionsSpec）
{
  "dimensionsSpec": {
    "dimensions": [
      "country",         // 自动建 Roaring bitmap
      "city",
      "device_type",
      "os"
    ]
  },
  "indexSpec": {
    "bitmap": {
      "type": "roaring"  // 默认 roaring，可选 concise
    },
    "dimensionCompression": "lz4",
    "metricCompression": "lz4",
    "longEncoding": "longs"
  }
}
```

```sql
-- Druid SQL 查询（位图自动加速）
SELECT
    country,
    COUNT(*) AS event_count,
    COUNT(DISTINCT user_id) AS users
FROM events
WHERE __time >= TIMESTAMP '2026-04-01'
  AND __time <  TIMESTAMP '2026-04-25'
  AND device_type = 'mobile'
  AND os IN ('iOS', 'Android')
GROUP BY country
ORDER BY event_count DESC;
-- 执行：
-- 1. 时间过滤定位 segment
-- 2. device_type='mobile' 取出对应 RoaringBitmap
-- 3. os IN ('iOS','Android') 取两个 bitmap 后 OR
-- 4. 两个 bitmap 做 AND
-- 5. 用最终位图筛选行
```

Druid 的位图索引特点：

- **自动且不可关闭**：所有 string/bool 类型维度默认建索引
- **段级位图**：每个 segment（典型 5-10M 行）独立的 Roaring 位图
- **段不可变**：解决了 Oracle 的 DML 之痛（追加新段而非修改）
- **可选 Concise**：旧版本默认 Concise (Colantonio 2010)，0.10 起切到 Roaring

### Apache Pinot（实时 OLAP 的 Roaring 倒排）

Pinot 同样大规模使用 RoaringBitmap，作为"倒排索引"的存储格式。

```json
// Pinot 表配置
{
  "tableIndexConfig": {
    "invertedIndexColumns": ["country", "device", "browser"],
    "createInvertedIndexDuringSegmentGeneration": true,
    "rangeIndexColumns": ["timestamp"],
    "starTreeIndexConfigs": [...]
  }
}
```

```sql
-- Pinot SQL（自动位图加速）
SELECT country, COUNT(*) FROM events
WHERE device = 'mobile'
  AND browser IN ('Chrome', 'Safari')
  AND timestamp BETWEEN 1714032000000 AND 1714118400000
GROUP BY country;
-- 优化器自动用 inverted bitmap 做 AND/OR 运算
```

Pinot 的设计选择与 Druid 类似（segment 级 Roaring），但提供了显式 `invertedIndexColumns` 控制开关。同时引入 Star-Tree Index（多维 Cube）应对超大维度组合。

### StarRocks / Doris（中国分支的位图实现）

StarRocks 与 Doris 同源，都支持位图索引 DDL：

```sql
-- 创建表（必须是 OLAP 引擎）
CREATE TABLE user_event (
    event_date DATE,
    user_id    BIGINT,
    country    VARCHAR(64),
    device     VARCHAR(32),
    amount     DECIMAL(10,2)
)
DUPLICATE KEY (event_date, user_id)
DISTRIBUTED BY HASH(user_id) BUCKETS 32
PROPERTIES ("replication_num" = "3");

-- 创建位图索引
CREATE INDEX idx_country ON user_event (country) USING BITMAP;
CREATE INDEX idx_device  ON user_event (device)  USING BITMAP;

-- 适合查询
SELECT country, SUM(amount)
FROM user_event
WHERE event_date >= '2026-04-01'
  AND device = 'mobile'
  AND country IN ('CN', 'US', 'JP')
GROUP BY country;

-- BITMAP 数据类型（与 ClickHouse 类似）
CREATE TABLE user_bitmap (
    tag_name STRING,
    user_set BITMAP BITMAP_UNION  -- AGG 表自动 union
)
AGGREGATE KEY (tag_name);

INSERT INTO user_bitmap
SELECT tag, to_bitmap(user_id)
FROM user_event_raw;

-- BITMAP 函数族
SELECT
    BITMAP_COUNT(BITMAP_AND(t1.user_set, t2.user_set)) AS overlap
FROM user_bitmap t1, user_bitmap t2
WHERE t1.tag_name = '高消费' AND t2.tag_name = '活跃用户';
```

StarRocks/Doris 的位图索引限制：

- **仅低基数**：明确文档说明 distinct < 1000 推荐
- **DUPLICATE/AGGREGATE 模型**：UNIQUE 模型不支持
- **DDL 同步**：建索引会触发整列重建
- **物化视图替代高基数**：高基数列推荐用 MV 或 Bloom filter

### Apache Kylin（多维 Cube 中的位图）

Kylin 把 Roaring Bitmap 作为 Cube measure 存储 distinct 用户/会话集合：

```sql
-- Kylin 模型定义（GUI/JSON）
-- Cube 中定义 measure：
--   COUNT_DISTINCT user_id, type=bitmap, precision=高
--
-- 物理存储：
--   每个 cuboid 的 cell 存储一个 RoaringBitmap，行号 -> 位图

SELECT
    region,
    COUNT(DISTINCT user_id) AS uv      -- 实际是 bitmap_count
FROM sales
WHERE date >= '2026-01-01'
GROUP BY region;
-- Kylin 直接读 Roaring，做 OR 合并跨 cuboid 后求基数
```

### SQL Server（隐式位图：Hash Join Bitmap Filter）

SQL Server 没有"位图索引"DDL，但执行计划里能看到 `Bitmap` 算子，主要用于 Hash Join 中的 Bloom-like 位图过滤：

```sql
-- 启用位图过滤需要并行计划
SELECT s.*, p.product_name
FROM sales s
INNER JOIN dim_product p ON s.product_id = p.id
WHERE p.category = 'Electronics';

-- 计划包含：
--   Bitmap Create (build side: dim_product)
--   Bitmap (probe side: sales) -> filter rows before hash probe
-- 这是 SQL Server 的"运行时位图"，仅在并行+Hash Join 时启用
```

SQL Server 2012 起引入 Columnstore Index，列存内部大量使用位图操作（segment 级 dictionary + bitmap），但作为黑盒不暴露 DDL。

### IBM DB2（Star Join 动态位图）

DB2 面向数据仓库的 Star Join 优化大量使用动态位图：

```sql
-- DB2 没有位图索引 DDL，但优化器有 Star Join Plan
SELECT SUM(f.amount)
FROM fact_sales f, dim_time t, dim_product p, dim_store s
WHERE f.time_key = t.time_key
  AND f.product_key = p.product_key
  AND f.store_key = s.store_key
  AND t.year = 2024
  AND p.category = 'Electronics'
  AND s.region = 'EU';

-- 计划中会出现:
--   Index ANDing
--   Hash Index Filter (动态位图)
-- DB2 在多个维度键上构建位图，AND 后回 fact 表
```

### Sybase IQ（位图变体最丰富的引擎）

Sybase IQ 是数据仓库引擎，提供多种位图索引变体：

```sql
-- LF (Low Fast)：低基数 < 1500
CREATE LF INDEX idx_gender ON customers(gender);

-- HG (High Group)：中基数，含 GROUP BY 优化
CREATE HG INDEX idx_country ON customers(country);

-- HNG (High Non-Group)：高基数，范围查询
CREATE HNG INDEX idx_amount ON sales(amount);

-- DATE / TIME 专用变体
CREATE DATE INDEX idx_order_date ON orders(order_date);
CREATE TIME INDEX idx_order_time ON orders(order_time);

-- WD (Word) 文本搜索
CREATE WD INDEX idx_descr ON products(description) DELIMITED BY ' .,;:?!';
```

Sybase IQ 把"为不同基数选择不同位图变体"做到了极致，是其在金融、电信数仓的杀手锏。

### Vertica（用列编码 + 投影替代位图）

Vertica 没有位图索引，但通过 RLE / Delta / BlockDict 等列编码达成相似效果：

```sql
-- 在 CREATE PROJECTION 时指定编码
CREATE PROJECTION sales_p1 (
    region        ENCODING RLE,        -- 低基数列：游程编码
    year          ENCODING RLE,
    customer_id   ENCODING DELTAVAL,   -- 单调递增：增量编码
    amount        ENCODING BLOCK_DICT  -- 离散值：块字典
)
AS SELECT region, year, customer_id, amount FROM sales
ORDER BY region, year;

-- RLE 编码本质上等价于"压缩位图"：
--   region='APAC', start_pos=0, length=1000000
--   region='EU',   start_pos=1000000, length=2000000
-- 优化器在过滤时直接跳过 RLE 段，无需位图

-- Vertica 哲学：投影排序 + RLE 编码 = 隐式位图索引
```

### Apache Hive（已废弃的位图索引）

Hive 0.8 (2011) 引入位图索引，但 3.0 (2018) 全面废弃，原因是列存格式 (ORC/Parquet) 自带元数据，索引收益有限：

```sql
-- 旧 Hive 语法（已废弃）
CREATE INDEX idx_sales_region
ON TABLE sales (region)
AS 'BITMAP'
WITH DEFERRED REBUILD;

ALTER INDEX idx_sales_region ON sales REBUILD;

-- Hive 3.0 起，索引完全移除，依赖：
--   ORC/Parquet stripe 级别 min/max
--   ORC bloom filter
--   Hive Materialized View
```

### Elasticsearch / Lucene（doc_values + Roaring）

Lucene 内部使用 Roaring Bitmap 存储倒排表的 docID 集合：

```json
// Elasticsearch mapping
PUT /events
{
  "mappings": {
    "properties": {
      "country":   { "type": "keyword", "doc_values": true },
      "device":    { "type": "keyword", "doc_values": true },
      "timestamp": { "type": "date" }
    }
  }
}
```

```json
// 查询：term filter 自动用 Roaring 加速
GET /events/_search
{
  "query": {
    "bool": {
      "filter": [
        { "term": { "country": "CN" } },
        { "terms": { "device": ["iOS", "Android"] } }
      ]
    }
  }
}
```

Lucene 的 `LiveDocs`（标记被删除文档）也是 Roaring Bitmap，segment 内任意 docID 集合都用 Roaring 表示。

### Informix（数仓版位图索引）

```sql
-- Informix 12+ 数据仓库选项
CREATE INDEX idx_sales_region ON sales(region) USING BITMAP;

-- 与 Oracle 类似的 DML 限制
-- 主要用于 Informix Warehouse Accelerator (IWA)
```

### MySQL / MariaDB（无位图索引但有 Index Merge）

MySQL 和 MariaDB 都没有位图索引，但 InnoDB 的 Index Merge 优化器算法功能近似：

```sql
-- MySQL Index Merge (Intersection)
EXPLAIN
SELECT * FROM orders
WHERE customer_id = 100 AND status = 'shipped';
-- type: index_merge
-- key: idx_customer,idx_status
-- Extra: Using intersect(idx_customer, idx_status); Using where

-- Index Merge (Union)
EXPLAIN
SELECT * FROM orders
WHERE customer_id = 100 OR id < 50;
-- type: index_merge
-- key: idx_customer,PRIMARY
-- Extra: Using union(idx_customer, PRIMARY); Using where
```

Index Merge 与位图扫描的区别：

| 维度 | MySQL Index Merge | PostgreSQL Bitmap Scan |
|------|------------------|----------------------|
| 实现方式 | 排序后 merge join 风格 | 内存位图 AND/OR |
| 内存复杂度 | O(matching rows) | O(table pages / 8) |
| 大结果集表现 | 可能退化为全扫 | lossy bitmap 优雅退化 |
| AND/OR 嵌套 | 部分支持 | 无限嵌套 |
| 优化器支持 | 谨慎使用，常被禁用 | 默认启用 |

## Roaring Bitmap 深度解析

Roaring Bitmap 是 Lemire、Kaser、Kurz 等人 2014 年发表的位图压缩算法（"Better bitmap performance with Roaring bitmaps"），现已成为 OLAP 引擎事实上的标准。

### 设计动机

历史上的位图压缩算法：

| 算法 | 年份 | 作者 | 思想 | 缺点 |
|------|------|-----|------|------|
| BBC (Byte-aligned) | 1989 | O'Neil | 字节对齐 RLE | Oracle 自有，效率较低 |
| WAH (Word-Aligned Hybrid) | 2002 | Wu, Otoo, Shoshani | 32 位字对齐 | 稀疏数据膨胀 |
| EWAH (Enhanced WAH) | 2010 | Lemire et al. | WAH + 跳跃 | 仍是序列扫描 |
| Concise | 2010 | Colantonio, Di Pietro | WAH 压缩极致 | 随机访问慢 |
| Roaring | 2014 | Lemire, Ssi-Yan-Kai, Kaser | 分块容器化 | 实现复杂度高 |

Roaring 的关键洞察：把 32 位整数空间按高 16 位分块，每块根据数据密度自适应选择存储格式。

### 核心数据结构

```
RoaringBitmap (32-bit integer set):
    {
        // 按 high-16-bit 分块（每块覆盖 65536 个整数）
        chunks: [
            (high_bits = 0x0000, container = ArrayContainer([1, 5, 100])),
            (high_bits = 0x0001, container = BitmapContainer([0...8191] uint64)),
            (high_bits = 0x0002, container = RunContainer([(0, 65000)])),
            ...
        ]
    }

Container 类型自适应选择：
  - ArrayContainer: 排序的 uint16 数组，cardinality < 4096 时使用
  - BitmapContainer: 8192 字节固定位图，4096 ≤ cardinality < 61440 时使用
  - RunContainer: (start, length) 列表，连续区间多时使用
```

转换规则（自动）：

- ArrayContainer 满 4096 时升级为 BitmapContainer
- BitmapContainer 删空到 4096 时降级为 ArrayContainer
- 周期性检测连续段，超过阈值转为 RunContainer

### 性能对比

```
1 亿稀疏 (1%) 整数集合:
    未压缩 (uint64 set):  ~ 800 MB
    WAH:                 ~ 16 MB
    EWAH:                ~ 12 MB
    Concise:             ~ 10 MB
    Roaring:             ~ 12 MB （不是最小，但读速最快）

随机访问性能 (contains 测试):
    BitmapContainer: O(1)，1 次内存访问
    ArrayContainer: O(log n)，二分查找
    RunContainer: O(log n)，二分查找
    WAH/EWAH/Concise: O(n)，必须顺序扫描

集合运算 (AND/OR/XOR):
    Roaring: SIMD 加速，ArrayContainer 用 galloping merge
    WAH/EWAH: 顺序扫描，无 SIMD
    Concise: 同 WAH，速度最慢
```

### 在引擎中的实际效果

```
某用户行为表 (10 亿行) 的 device 列：
    distinct 值: 5 (mobile, desktop, tablet, tv, watch)
    每值约 2 亿行 → ArrayContainer 容不下，全部 BitmapContainer
    单值位图: 8192 KB / chunk * (2e8 / 65536) ≈ 25 MB
    总位图: 5 * 25 MB = 125 MB
    AND/OR 运算: 单 chunk SIMD 8 字节并行，<10ms

某 user_id 列 (10 亿行)：
    distinct 值: 1 亿（高基数）
    平均每值 10 行 → ArrayContainer 占主导
    总位图: 数 GB，不再适合做"按值的反向索引"
    → 改用 Roaring 作为"用户群体存储"，而非"反向索引"
```

### Roaring 的"位图作为数据"用法

ClickHouse、StarRocks、Doris 都把 Roaring 暴露为数据类型，支持以下经典模式：

```sql
-- 模式 1：标签人群预聚合
CREATE TABLE user_tags (
    tag_name VARCHAR(64),
    user_bitmap BITMAP   -- StarRocks BITMAP / ClickHouse AggregateFunction
);

INSERT INTO user_tags VALUES
    ('young', to_bitmap_from_query('SELECT user_id FROM users WHERE age < 30')),
    ('high_value', to_bitmap_from_query('...')),
    ('mobile', to_bitmap_from_query('...'));

-- 标签组合（毫秒级）
SELECT bitmap_count(bitmap_and(young.user_bitmap, high_value.user_bitmap))
FROM user_tags young, user_tags high_value
WHERE young.tag_name = 'young' AND high_value.tag_name = 'high_value';

-- 模式 2：留存/漏斗
SELECT
    bitmap_count(bitmap_and(d1, d7)) / bitmap_count(d1) AS retention_d7
FROM (
    SELECT
        bitmap_union(if(date='2026-04-01', user_bitmap, NULL)) AS d1,
        bitmap_union(if(date='2026-04-08', user_bitmap, NULL)) AS d7
    FROM daily_active_users
);

-- 模式 3：广告归因
-- 把每条广告的曝光用户存为 Roaring，归因时做集合运算
```

这种范式让"留存、漏斗、归因"等复杂分析从"几分钟全表扫描"降到"几十毫秒位图运算"。

## Oracle Bitmap Index 的 DML 之痛

位图索引的最大代价在于 DML（INSERT/UPDATE/DELETE）。Oracle 的实现尤其严重，因为它使用一种基于 ROWID 范围的位图段（bitmap segment），更新单行可能锁定整段。

### 锁机制详解

```
传统 B-tree 索引：
    一个 (key, rowid) 条目对应一行
    UPDATE customers SET status = 'X' WHERE id = 100
    → 仅锁该 (status='oldval', rowid=100) 条目

Oracle Bitmap 索引：
    bitmap segment 结构:
        index_key | start_rowid | end_rowid | compressed_bitmap
        'A'       | rowid_001   | rowid_999 | 1010101...0101
    UPDATE customers SET status = 'X' WHERE id = 100
    → 必须更新 rowid=100 在所有 status 值的位图中的位
    → 锁定包含 rowid=100 的 ENTIRE bitmap segment
    → 同段内其他行的并发 UPDATE 也会被阻塞！
```

### 复现并发冲突

```sql
-- 准备
CREATE TABLE bm_demo (id NUMBER, status VARCHAR2(10));
INSERT INTO bm_demo SELECT level, 'A' FROM dual CONNECT BY level <= 10000;
COMMIT;
CREATE BITMAP INDEX idx_bm_status ON bm_demo(status);

-- Session 1
UPDATE bm_demo SET status = 'B' WHERE id = 100;
-- 不 COMMIT

-- Session 2
UPDATE bm_demo SET status = 'C' WHERE id = 200;
-- 阻塞！与 Session 1 冲突
-- (因为 id=100 和 id=200 落在同一 bitmap segment 中)

-- 类似情况：
INSERT INTO bm_demo VALUES (10001, 'D');
-- 也可能阻塞，如果和未提交的更新落在同段
```

### 为什么 Druid / ClickHouse / Pinot 没有此问题？

这些引擎采用"段不可变"模型：

- **新数据写入新 segment**：不修改现有 segment
- **删除/更新通过墓碑+合并**：周期性后台任务重写 segment
- **位图与 segment 同生命周期**：segment 不可变 → 位图不可变

代价是延迟（数据写入到可见有秒到分钟级延迟）。

### 适用场景判断

| 场景 | Oracle Bitmap 适合吗 |
|------|--------------------|
| OLTP 高并发更新 | 完全不适合（锁段灾难） |
| 数据仓库批 ETL（夜间） | 完美适合 |
| 实时数仓（持续写入） | 不适合 |
| 历史数据分析（只读） | 完美适合 |
| 高基数列（>1% 行数） | 不适合（压缩失效） |
| 低基数列 + AND/OR 查询多 | 完美适合 |

## 设计争议与陷阱

### 1. 位图索引与列存储的 "替代/互补" 之争

近 10 年新引擎几乎都不再单独提供"位图索引"，而是把位图思想融入列存元数据：

| 方案 | 代表引擎 | 思想 |
|------|---------|------|
| 持久化位图索引 | Oracle, Sybase IQ, Druid, Pinot | 显式 DDL，预存位图 |
| 列存元数据 | Snowflake, BigQuery, Vertica, Redshift | min/max + 分区裁剪 |
| 跳数索引 | ClickHouse, DuckDB | granule 级 bloom/min-max |
| 字典编码 | Vertica, ClickHouse, Parquet | 隐式位图（值→行号集合） |

主流趋势：**列存 + 字典编码 + Roaring（数据类型，非索引）** 取代了传统位图索引。

### 2. 高基数列的位图退化

教科书说"位图索引适合 distinct < 1000"。实际上：

```
低基数 (gender, M/F):
    2 个位图，每个 N bits → 总 2N/8 字节 → 高度压缩 ~ N/100 字节

中基数 (country, 200):
    200 个位图，每个 N bits → 总 200N/8 字节
    Roaring 压缩后 ~ N/10 ~ N/4 字节（取决于密度）

高基数 (user_id, 100M):
    100M 个位图，每个 N bits
    多数为单元素 ArrayContainer（仅 2 字节 + 8 字节开销）
    总 ~ 1GB+ → 不如直接扫表
```

但 Druid/Pinot 仍对高基数列建 Roaring：靠 ArrayContainer 的极小开销 (单元素仅占 ~10 字节) 缓解。

### 3. 位图 vs Bloom Filter

| 维度 | Bitmap Index | Bloom Filter |
|------|-------------|--------------|
| 准确性 | 精确 | 概率（有假阳性） |
| 空间 | O(N * V / 8) bits, V=distinct | O(N * k / log(1/p)) bits |
| 查询能力 | 等值 + IN + 范围（HNG） | 仅等值 |
| AND/OR | 自由组合 | 无（只能逐个测试） |
| 适用列基数 | 低 | 任何 |

ClickHouse 的设计哲学：高基数用 Bloom filter 跳数索引，低基数用 set/bitmap 跳数索引。

### 4. PostgreSQL 为什么不做持久化位图索引

PostgreSQL 社区多次讨论过持久化位图索引（如 `bitmap_index_am` 提案），但始终未合并，主要原因：

1. **MVCC 开销**：每个 tuple 有 32-bit ctid + xmin/xmax 元组头，位图必须按 ctid 索引
2. **死元组膨胀**：vacuum 前位图含大量"幽灵位"，正确性维护成本高
3. **B-tree + Bitmap Heap Scan 已够用**：B-tree 索引扫描结果在内存合并为位图，覆盖 80% 场景
4. **GIN 索引补足**：GIN（Generalized Inverted Index）已经是"持久化倒排索引"，对 jsonb / array / fts 场景足够

### 5. SQL Server 的"位图算子"误解

很多 SQL Server DBA 看到执行计划中的 Bitmap operator 误以为有位图索引。实际上：

- 这是 Hash Join 的 build 阶段创建的内存 Bloom-like 位图
- 仅在 **Parallel Query Plan + Hash Join** 时启用
- 单表查询和串行计划不会出现
- 与持久化位图索引完全无关

### 6. Hive 位图索引的衰落

Hive 0.8 (2011) 引入了 BITMAP 索引，但 3.0 (2018) 完全移除。原因：

- ORC/Parquet 自带 stripe/row group 级 min/max 元数据
- 列存的 dictionary encoding 天然提供值→行的映射
- 索引维护成本（每次 ETL 后 REBUILD）远高于收益
- Materialized View 比索引更灵活

这是"列式存储格式吞噬索引"的典型案例。

### 7. 多列复合位图索引：很少做

不像 B-tree 复合索引（`(a, b, c)`）很常见，复合位图索引几乎不存在：

- 复合位图基数 = card(a) * card(b) * card(c)，组合爆炸
- 单列位图通过 AND 已经能高效合并
- Oracle 的 `CREATE BITMAP INDEX ... ON (col1, col2)` 实际是分别建索引

例外：Druid/Pinot 的 Star-Tree Index 接近"多维 Cube"，本质是预聚合而非位图。

## 引擎实现建议

### 1. 内部位图选型

```
场景: 需要在引擎内部表示行集合（如 Hash Join probe filter, 删除标记）
推荐: Roaring Bitmap (croaring C 库 / RoaringBitmap Java 库)
不推荐: 自有 RLE / WAH / Concise，性能落后且生态弱

API 设计:
    bitmap_create()
    bitmap_add(uint32) / bitmap_add_range(start, end)
    bitmap_remove(uint32)
    bitmap_contains(uint32) -> bool
    bitmap_cardinality() -> u64
    bitmap_and / or / xor / sub (binary ops, in-place + non-destructive)
    bitmap_iterator (forward / batch)
    bitmap_serialize / deserialize (portable format spec)
```

### 2. 持久化位图索引的设计

```
关键决策:
1. 行号映射:
    - segment 内 0-based 序号（推荐，便于 Roaring 32-bit）
    - 全局 ROWID（Oracle 风格，复杂）

2. 段大小选择:
    - 太小（<1MB）：元数据开销大
    - 太大（>1GB）：DML 锁粒度差，合并慢
    - 推荐：~5-50MB，与 OLAP segment 一致

3. DML 策略:
    - 不可变段（推荐，OLAP 标准）
    - 可变段 + 锁（Oracle 路线，OLTP 不可用）
    - copy-on-write（折中，重写整段）

4. 高基数处理:
    - 限制 distinct < 阈值时才建索引
    - 自动降级为 Bloom filter
    - 或拒绝创建并报错
```

### 3. 运行时位图（PG 风格）

```
在执行器中实现 BitmapAnd / BitmapOr 算子:

BitmapIndexScan {
    next_block() -> Bitmap chunk:
        从 B-tree 读取 TID 列表
        构建 Roaring 位图
        返回内存位图

BitmapAnd {
    children: [BitmapIndexScan, ...]
    next() -> Bitmap:
        for child in children: bitmap = bitmap_and(bitmap, child.next())
        return bitmap

BitmapHeapScan {
    bitmap: Bitmap (from BitmapAnd/Or/IndexScan)
    next_row() -> Row:
        for tid in bitmap: row = heap.fetch(tid); recheck(row); return row

关键优化:
    - lossy bitmap: 内存超阈值时，按 page 级别标记
    - exact bitmap: 内存充足时，按 tuple 级别标记
    - recheck 必要性: lossy 必须 recheck，exact 在某些情况可跳过
```

### 4. AND/OR 谓词下推

```
优化器规则:
    1. 识别 a = X AND b = Y AND c IN (...) 等 conjunction
    2. 估算每个谓词的位图大小（基于 column stats）
    3. 排序：cardinality 小的先 AND，剩余规模快速收敛
    4. OR 子句：两端都建位图后并集

代价模型:
    - bitmap_index_scan_cost = pages_in_btree
    - bitmap_and_cost = sum(child_costs) + bitmap_size * AND_per_byte
    - bitmap_heap_scan_cost = pages_to_fetch * page_cost
```

### 5. Star Schema 优化（Bitmap Join）

```
Oracle Bitmap Join Index 的引擎实现:

CREATE BITMAP INDEX idx_sales_state
    ON sales(c.state)
    FROM sales s, customers c
    WHERE s.cust_id = c.cust_id;

物理存储:
    每个 c.state 值 -> 对应 sales 表的 ROWID 集合
    相当于预先做了 sales JOIN customers GROUP BY c.state

查询:
    SELECT ... FROM sales s, customers c
    WHERE s.cust_id = c.cust_id AND c.state = 'CA';
    -> 直接读 idx_sales_state['CA'] 得 sales ROWID
    -> 不需要做 JOIN

实现关键:
    - 维护成本：sales 或 customers 任一变化都要更新位图
    - 只适合静态维度表（customers 不常变）
    - 仅 Oracle 支持，其他引擎用物化视图替代
```

### 6. Roaring Bitmap 集成最佳实践

```
1. 用现成库:
    C/C++: CRoaring (https://github.com/RoaringBitmap/CRoaring)
    Java: RoaringBitmap (https://github.com/RoaringBitmap/RoaringBitmap)
    Go: roaring (https://github.com/RoaringBitmap/roaring)
    Rust: roaring-rs (https://crates.io/crates/roaring)

2. 用 portable serialization spec:
    https://github.com/RoaringBitmap/RoaringFormatSpec
    跨语言互操作，存储到磁盘后可被其他引擎读取

3. 64-bit 大整数: 用 Roaring64NavigableMap (Java) 或 Treemap-of-Roaring32

4. SIMD 加速: CRoaring 默认启用 AVX2/AVX-512，Java 版本无 SIMD
    （JIT 推理 SIMD 能力有限，性能差距 2-4x）

5. 序列化大小估算:
    BitmapContainer chunk: 8KB (固定)
    ArrayContainer chunk: 2 * cardinality bytes
    RunContainer chunk: 4 * runs bytes
```

### 7. 测试要点

```
正确性:
    - 单元测试: contains/cardinality/AND/OR/XOR 与朴素 set 对比
    - 边界: 空位图、单元素、全 0xFFFFFFFF
    - 容器转换: ArrayContainer ↔ BitmapContainer ↔ RunContainer

并发:
    - 多线程读 OK，写需要外部同步
    - 设计 RCU 或 copy-on-write 模式

性能基准:
    - SIMD 启用 vs 关闭
    - 不同 cardinality 下 AND/OR 速度
    - 序列化/反序列化吞吐
    - 与 std::bitset / dense_hash_set 对比

回归测试:
    - 与 PG / Druid / ClickHouse 同样数据集结果一致性
```

## 总结对比矩阵

### 主流引擎位图能力总览

| 引擎 | 持久化位图 DDL | 运行时位图合并 | Roaring | Bitmap Join | DML 影响 | 适用场景 |
|------|---------------|--------------|---------|-------------|---------|----------|
| Oracle | 是（EE） | 是 | BBC | 是 | 严重 | 数仓只读 |
| PostgreSQL | 否 | 是 | RLE 内存 | 否 | 无 | 通用 OLTP/分析 |
| Greenplum | 是 | 是 | 自有 | 否 | 中等 | AO 数仓 |
| SQL Server | 否 | 是（Hash 位图） | 否 | 否 | 无 | OLTP+少量分析 |
| DB2 | 否 | 是 | 否 | 是（动态） | 无 | Star Join 数仓 |
| Sybase IQ | 是（多种） | 是 | 否 | 是 | 中等 | 金融数仓 |
| MySQL/MariaDB | 否 | 否（Index Merge） | 否 | 否 | 无 | OLTP |
| ClickHouse | 是（实验） | 是（granule） | 是 | 否 | 无 | 实时 OLAP |
| Druid | 是（自动） | 是 | 是 | 否 | 无（不可变） | 流式分析 |
| Pinot | 是（自动） | 是 | 是 | 否 | 无（不可变） | 实时 OLAP |
| StarRocks | 是 | 是 | 是 | 否 | 严重 | OLAP 报表 |
| Doris | 是 | 是 | 是 | 否 | 严重 | OLAP 报表 |
| Vertica | 否（RLE 替代） | 是 | 否 | 否 | 无 | MPP 数仓 |
| Snowflake | 否 | 是（微分区） | 否 | 否 | 无 | 云数仓 |
| BigQuery | 否 | 是（隐式） | 否 | 否 | 无 | 云数仓 |
| Redshift | 否（Zone Map） | 是 | 否 | 否 | 无 | MPP 数仓 |
| Spark/Hive | 否（Hive 旧版有） | 否 | 否 | 否 | 无 | 离线 ETL |
| Trino/Presto | 否 | 是（block） | 否 | 否 | 无 | 跨源查询 |
| DuckDB | 否 | 是（vector） | 否 | 否 | 无 | 嵌入分析 |
| Elasticsearch | 是（doc_values） | 是 | 是 | 否 | 中等 | 全文/日志 |
| MongoDB | 否 | 否 | 否 | 否 | 无 | 文档型 |

### 引擎选型建议

| 场景 | 推荐方案 | 原因 |
|------|---------|------|
| Oracle 数仓只读分析 | `CREATE BITMAP INDEX` | 经典且优化器深度支持 |
| Oracle 高并发 OLTP | 严禁位图索引 | DML 锁段灾难 |
| PostgreSQL 任意 | 多列 B-tree + Bitmap Heap Scan | 无需特殊 DDL，效果好 |
| 实时 OLAP（用户行为） | Druid/Pinot/StarRocks Roaring | 留存/漏斗/归因 |
| 传统数仓 ETL | Greenplum AO + bitmap | 批量插入友好 |
| 跨标签人群计算 | ClickHouse/StarRocks BITMAP 类型 | 毫秒级集合运算 |
| 全文搜索 + 过滤 | Elasticsearch (Lucene Roaring) | 倒排+布尔过滤 |
| 中小型分析 | DuckDB | 向量化运行时位图 |
| 云数仓 | Snowflake/BigQuery（不需要管） | 微分区/列存元数据自动 |

## 核心结论

1. **位图索引未在 SQL 标准中**：所有引擎语法 (`CREATE BITMAP INDEX`, `USING BITMAP`) 全是非标准
2. **Oracle 1996 开创**：但 EE Only，且 DML 锁段问题严重，限制了适用场景
3. **PostgreSQL 8.1 (2005) 引入运行时位图**：Bitmap Heap Scan + BitmapAnd/Or 节点，无需持久化位图，覆盖大多数场景
4. **Roaring Bitmap (2014) 是分水岭**：现代 OLAP 引擎几乎全部采用，性能与压缩兼顾
5. **OLAP 引擎倾向"位图作为数据"**：ClickHouse/StarRocks/Doris 把 RoaringBitmap 暴露为数据类型，加速人群、留存、漏斗等场景
6. **段不可变模型解决 DML 之痛**：Druid/Pinot/ClickHouse 通过追加新段+后台合并，避开了 Oracle 的位图锁问题
7. **列存 + 字典编码 + 元数据正在替代专门位图索引**：Snowflake/BigQuery/Redshift 没有位图 DDL 也能做到极致裁剪
8. **Hive 3.0 移除位图索引是趋势信号**：列存自带元数据已足够，专门索引反而增加维护成本
9. **MySQL/MariaDB 至今无原生位图**：Index Merge 是部分替代但能力有限
10. **位图索引最佳搭档是低基数 + 只读 + AND/OR 复杂谓词**：如同时满足，加速可达 100×

## 参考资料

- O'Neil, P. "Model 204 Architecture and Performance" (1987)
- Wu, K., Otoo, E.J., Shoshani, A. "Compressing Bitmap Indexes for Faster Search Operations" (2002)
- Lemire, D., Kaser, O., Kurz, N., Deri, L., O'Hara, C., Saint-Jacques, F., Ssi-Yan-Kai, G. "Roaring Bitmaps: Implementation of an Optimized Software Library" (2017, SPE)
- Lemire, D. "Better bitmap performance with Roaring bitmaps" (2014)
- Colantonio, A., Di Pietro, R. "Concise: Compressed 'n' Composable Integer Set" (2010)
- Oracle: [Bitmap Indexes](https://docs.oracle.com/en/database/oracle/oracle-database/19/cncpt/indexes-and-index-organized-tables.html#GUID-A6FE08F6-A0D0-4CFA-9DE7-9DBE7D2BF6F2)
- Oracle: [Bitmap Join Indexes](https://docs.oracle.com/en/database/oracle/oracle-database/19/cncpt/indexes-and-index-organized-tables.html#GUID-7B62FCE6-29D4-484A-8728-C7C2B5F31827)
- PostgreSQL: [Bitmap Heap Scan](https://www.postgresql.org/docs/current/using-explain.html)
- Greenplum: [Bitmap Indexes](https://docs.vmware.com/en/VMware-Tanzu-Greenplum/index.html)
- ClickHouse: [Bitmap functions](https://clickhouse.com/docs/en/sql-reference/functions/bitmap-functions)
- ClickHouse: [Skip indexes](https://clickhouse.com/docs/en/optimize/skipping-indexes)
- Apache Druid: [Bitmap Indexes](https://druid.apache.org/docs/latest/ingestion/index-spec.html)
- Apache Pinot: [Inverted Index](https://docs.pinot.apache.org/basics/indexing/inverted-index)
- StarRocks: [Bitmap Index](https://docs.starrocks.io/docs/table_design/indexes/Bitmap_index/)
- Apache Doris: [Bitmap Index](https://doris.apache.org/docs/data-table/index/bitmap-index/)
- RoaringBitmap project: [https://roaringbitmap.org](https://roaringbitmap.org)
- RoaringBitmap Format Spec: [https://github.com/RoaringBitmap/RoaringFormatSpec](https://github.com/RoaringBitmap/RoaringFormatSpec)
- Sybase IQ: [Bitwise Indexes](https://infocenter.sybase.com/help/index.jsp)
- IBM DB2: [Star Join Optimization](https://www.ibm.com/docs/en/db2)
