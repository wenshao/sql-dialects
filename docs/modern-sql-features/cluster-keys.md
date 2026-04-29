# 聚簇键与排序键 (Cluster Keys and Sort Keys)

同样是 1TB 的订单表，按 `customer_id, order_date` 聚簇排列后，按客户查询的 I/O 量可以从 1TB 降到 1GB——三个数量级的差距。聚簇键与排序键决定了数据在存储介质上的物理排列顺序，是分析型引擎从慢到快的关键转折点。

## 物理排序 vs 逻辑主键/索引

理解聚簇键，必须先把三个常被混淆的概念分开:

```
逻辑主键 (Logical Primary Key):
  - SQL 标准概念，定义唯一性约束
  - 不规定物理顺序，只规定每行可被唯一标识
  - 一张表只能有一个 PK，但 PK 可以是任何列组合

聚簇索引 / 聚簇键 (Clustered Index / Cluster Key):
  - 物理存储顺序的载体
  - 行按某个键的顺序排列在数据页 / 数据块中
  - 一张表通常只能有一个聚簇键 (因为物理顺序只有一个)
  - 二级索引、ZoneMap、Bloom Filter 都建立在这个物理顺序之上

二级索引 / 排序键 (Secondary Index / Sort Key):
  - 在聚簇键之外的、用于加速查询的辅助结构
  - 行存引擎: B+ 树二级索引指向聚簇键 (InnoDB) 或 RID (Oracle/PG)
  - 列存引擎: SortKey/ClusterBy 不再是 B+ 树，而是数据块的组织维度
```

聚簇键的存在意义:

1. **减少 I/O**: 范围查询、相等查询命中聚簇键时，只需读取连续的少量数据块
2. **启用 Zone Map / Min-Max 索引**: 数据块按聚簇键有序，每个块的 min/max 值高度紧凑，过滤效率极高
3. **提升压缩率**: 相邻行字段值相似，列存压缩率显著提升 (RLE、Delta、字典编码均受益)
4. **改善 Join 性能**: 两表按相同键聚簇时，可启用 Sort Merge Join 或 Bucket Join，避免 Shuffle
5. **加速 ORDER BY / GROUP BY**: 已排序数据可跳过排序步骤或使用流式聚合

但聚簇键也有代价:

1. **写入放大**: 维持物理顺序需要重写数据，OLTP 引擎用 B+ 树分裂分摊，分析引擎用后台合并 (compaction)
2. **只能选一个键**: 物理顺序只有一个，多列聚簇是 "字典序" 而非 "多维聚簇"
3. **基数选择敏感**: 聚簇键基数过低 (如布尔列) 几乎无效；基数过高 (如 UUID) 等同随机
4. **维护开销**: ClickHouse 后台 merge、Snowflake auto-clustering 都消耗资源

## 没有 SQL 标准

SQL:92 到 SQL:2023 从未对 "物理排序顺序" 做出规定。标准只关心逻辑模型：表是行的多重集合 (multiset)，行的物理位置不可见。因此:

1. **聚簇键 / 排序键 / CLUSTER BY / ORDER BY (DDL)** 都是各厂商的扩展语法，没有跨引擎兼容性
2. **隐式聚簇 vs 显式聚簇**: MySQL InnoDB 隐式按 PK 聚簇 (无需 DDL)，BigQuery 必须 CLUSTER BY 才聚簇
3. **聚簇行为差异巨大**: PostgreSQL 的 `CLUSTER` 是一次性重排，ClickHouse 的 `ORDER BY` 是持续维护的物理顺序，Snowflake 的 `CLUSTER BY` 是后台异步重排
4. **数据模型差异**: 行存的 "聚簇" 指 B+ 树叶子节点的物理顺序，列存的 "聚簇" 指 row group / 微分区 / segment 的边界
5. SQL 标准的 `ORDER BY` 是**查询子句**，仅影响查询结果顺序；DDL 中的 `ORDER BY` (ClickHouse) 或 `CLUSTER BY` (BigQuery/Snowflake) 是**表定义**，影响物理存储

本文按 "显式聚簇键 DDL"、"自动维护 vs 手动重排"、"列基数限制"、"对应优化器特性 (zone map / pruning)" 四个维度，对 45+ 个引擎做横向对比。聚簇 vs 堆的对比 (主键索引层面) 已在 `clustered-heap-storage.md` 中详细讨论，本文聚焦于**显式排序键 DDL 与自动聚簇维护机制**。

## 支持矩阵 (45+ 引擎)

### 显式聚簇键 DDL 支持

| 引擎 | 关键字 | 多列聚簇 | 自动维护 | 一次性 vs 持续 | 引入版本 |
|------|--------|---------|---------|----------------|---------|
| PostgreSQL | `CLUSTER` 命令 | 单列/单索引 | 否 | 一次性 | 6.0+ (1997) |
| pg_repack | `pg_repack -o` | 单索引 | 否 | 一次性，在线 | 1.0+ (2012) |
| MySQL (InnoDB) | 隐式 (PK) | 复合 PK | 是 | 持续维护 | 4.0+ |
| MariaDB (InnoDB) | 隐式 (PK) | 复合 PK | 是 | 持续维护 | 与 MySQL 一致 |
| SQL Server | `CREATE CLUSTERED INDEX` | 多列 | 是 | 持续维护 | 7.0+ |
| Oracle | `ORGANIZATION INDEX` (IOT) | 主键 | 是 | 持续维护 | 8i (1999) |
| Oracle Cluster | `CREATE CLUSTER` | 单 cluster key | 是 | 持续维护 | 早期 (V6+) |
| Oracle Attribute Clustering | `CLUSTERING BY LINEAR/INTERLEAVED` | 多列 | 重组时维护 | 后台/重组 | 12c R1 (2013) |
| DB2 (LUW) | MDC `ORGANIZE BY DIMENSIONS` | 多维 | 是 | 持续维护 | 8.1+ |
| DB2 (z/OS) | `CLUSTER` index option | 单索引 | 部分 (REORG) | 半持续 | 早期 |
| SQLite | `WITHOUT ROWID` (按 PK) | 复合 PK | 是 | 持续维护 | 3.8.2 (2013) |
| ClickHouse | `ORDER BY` (MergeTree, 强制) | 多列 | 是 (后台 merge) | 持续维护 | 早期 (2016) |
| Snowflake | `CLUSTER BY (cols)` | 多列 | 是 (auto-clustering) | 后台异步 | 2018 |
| BigQuery | `CLUSTER BY (cols)` | 最多 4 列 | 是 (后台) | 后台异步 | 2018-06 |
| Redshift | `COMPOUND SORTKEY` | 多列 (默认) | 否 (VACUUM SORT) | 半持续 | 2013 GA |
| Redshift | `INTERLEAVED SORTKEY` | 最多 8 列 | 否 (需重写) | 半持续 | 2014 |
| Redshift | `AUTO SORTKEY` | 自动选择 | 是 | 后台 | 2020 |
| Vertica | Projection `ORDER BY` | 多列 | 是 (mergeout) | 持续维护 | 1.0 (2005) |
| Greenplum | `DISTRIBUTED BY` + AOT 排序 | 多列 | 否 | 一次性 | 4+ |
| CockroachDB | PRIMARY KEY | 复合 PK | 是 (Raft + sst) | 持续维护 | 1.0+ |
| TiDB | `CLUSTERED PRIMARY KEY` | 复合 PK | 是 | 持续维护 | 5.0+ |
| YugabyteDB | PRIMARY KEY (HASH/ASC) | 复合 PK | 是 | 持续维护 | 1.0+ |
| Spanner | PRIMARY KEY | 复合 PK | 是 | 持续维护 | GA |
| OceanBase | PRIMARY KEY (LSM) | 复合 PK | 是 | 持续维护 (compaction) | 全部版本 |
| SingleStore | `SORT KEY` (列存) | 多列 | 是 (后台) | 持续维护 | 6.0+ |
| StarRocks | `ORDER BY` (Primary Key 表) | 多列 | 是 | 持续维护 | 2.5+ |
| Doris | Key columns (Aggregate/Unique) | 多列 | 是 | 持续维护 | 早期 |
| DuckDB | 不支持显式聚簇键 | -- | -- | -- | -- |
| Spark SQL (Iceberg) | `WRITE ORDERED BY` | 多列 | 否 (写入时) | 写入时 | Iceberg 0.13+ |
| Spark SQL (Delta) | `OPTIMIZE ZORDER BY` | 多列 | 否 (手动 OPTIMIZE) | 手动重排 | Delta 1.2+ |
| Databricks | `OPTIMIZE ZORDER BY` / Liquid Clustering | 多列 | Liquid: 是 | Liquid: 后台 | Liquid 2024 |
| Hive (Iceberg) | `WRITE ORDERED BY` | 多列 | 否 | 写入时 | Iceberg 集成版本 |
| Hive (ORC) | `SORTED BY` | 多列 | 否 | 写入时 | 0.13+ |
| Trino (Iceberg) | `WITH (sorted_by = ...)` | 多列 | 否 | 写入时 | 早期 |
| Presto (Iceberg) | 同 Trino | 多列 | 否 | 写入时 | 同上 |
| Impala (Kudu) | PRIMARY KEY | 复合 PK | 是 | 持续维护 | 2.7+ |
| Impala (Iceberg) | `SORT BY` | 多列 | 否 | 写入时 | 4.0+ |
| Kudu | PRIMARY KEY | 复合 PK | 是 | 持续维护 | 1.0+ |
| Teradata | Primary Index (HASH) | 复合 PI | 是 (HASH 分布) | 持续维护 | 早期 |
| Netezza/PureData | `ORGANIZE ON` | 多列 (CBT) | 否 | GROOM 时 | 6.0+ |
| Yellowbrick | `CLUSTER ON` | 多列 | 否 (REORGANIZE) | 半持续 | GA |
| MonetDB | 列存自动 | -- | 是 (自适应索引) | 后台 | -- |
| SAP HANA | `MERGE DELTA` + 主键 | 主键 | 是 | 持续维护 | 早期 |
| Exasol | 不支持显式 | -- | 自动 (索引) | 后台 | -- |
| Firebolt | `PRIMARY INDEX` | 多列 | 是 | 持续维护 | GA |
| TimescaleDB | `add_dimension` + 块级聚簇 | 多列 | 否 (chunk 级) | -- | 1.0+ |
| Materialize | 不支持显式 | -- | -- | -- | -- |
| RisingWave | 不支持显式 (流) | -- | -- | -- | -- |
| Flink SQL | 不支持 (流) | -- | -- | -- | -- |
| QuestDB | `TIMESTAMP` 列时间分区 + 排序 | 单列 | 是 | 持续维护 | -- |
| InfluxDB IOx | 时间排序 (固定) | 单列 (time) | 是 | 持续维护 | -- |
| Druid | `granularitySpec.segmentGranularity` + segment 内排序 | 多列 | 是 (compaction) | 后台 | 早期 |
| Pinot | 表配置 `sortedColumn` | 单列 | 是 (segment 创建时) | 写入时 | 0.1+ |
| Crate DB | `CLUSTERED BY` (分布), 不是聚簇键 | -- | -- | -- | -- |
| H2 / HSQLDB / Derby | 隐式 PK 聚簇 (各引擎不同) | 复合 PK | 是 | 持续维护 | -- |
| Firebird | 不支持 (堆为主) | -- | -- | -- | -- |
| Informix | `CLUSTER` index 选项 | 单索引 | 部分 | 半持续 | 早期 |
| Tableau Hyper | 列存自动 | -- | 是 | 后台 | -- |
| Apache Iceberg | `WRITE ORDERED BY` | 多列 | 否 | 写入时 | 0.13+ |
| Apache Hudi | `clusteringConfig` | 多列 | 是 (后台 cluster service) | 后台 | 0.7+ (2021) |
| Delta Lake | `OPTIMIZE ZORDER BY` / Liquid | 多列 | Liquid: 是 | 视模式而定 | 1.2+ / 3.2+ |

> 统计: 约 40 个引擎支持某种形式的显式聚簇键 / 排序键 DDL，约 8 个完全隐式或不支持。其中 **支持后台自动维护** 的引擎包括: ClickHouse、Snowflake、BigQuery、Vertica、Hudi、Liquid Clustering、Redshift AUTO SORTKEY、SAP HANA。**仅一次性重排** 的引擎包括: PostgreSQL CLUSTER、Greenplum、Iceberg WRITE ORDERED BY (写入时)、Delta OPTIMIZE ZORDER BY (手动)。

### 自动维护语义对比

| 引擎 | 自动维护机制 | 触发条件 | 是否阻塞写入 | 资源消耗位置 |
|------|------------|---------|------------|------------|
| ClickHouse MergeTree | 后台 merge 线程合并 part | 持续 (插入触发) | 否 | 当前节点 CPU/IO |
| Snowflake | auto-clustering 服务 | 后台周期性扫描 clustering depth | 否 | 独立 serverless compute (单独计费) |
| BigQuery | 后台重写 storage | 系统决定 | 否 | 后台 (无用户感知) |
| Redshift AUTO SORT | VACUUM SORT 后台运行 | 集群空闲时 | 否 (但占资源) | 集群计算节点 |
| Vertica | mergeout (Tuple Mover) | ROS 数量超阈值 | 否 | 各节点 |
| Hudi clustering | 异步 / 内联 cluster 任务 | 配置触发 | 异步: 否；内联: 是 | Spark 作业 |
| Delta Liquid | 后台 cluster 任务 | OPTIMIZE / 配置 | 否 | Spark 作业 |
| MySQL InnoDB | B+ 树就地分裂 | 每次插入 | 短暂行锁 | 在线事务路径 |

## 各引擎深度解析

### PostgreSQL: CLUSTER 命令 (一次性重排，不维护)

PostgreSQL 在 1997 年的 6.0 版本就引入了 `CLUSTER` 命令，但行为非常特殊: 它是一次性的物理重排，**不会自动维护**:

```sql
-- 第一次使用: 必须按某个索引重排
CLUSTER orders USING orders_customer_idx;

-- 之后可以省略索引名
CLUSTER orders;

-- 全库重排所有标记过的表
CLUSTER;

-- 查看哪些表被聚簇过
SELECT relname, indrelid::regclass
FROM pg_index
WHERE indisclustered;
```

关键限制:

1. **一次性**: `CLUSTER` 重写整张表，但之后的 INSERT / UPDATE 不维护顺序
2. **完全锁表**: 重写期间持有 `ACCESS EXCLUSIVE` 锁，应用无法读写
3. **空间放大**: 重写需要 2 倍磁盘空间 (新旧两份)
4. **统计信息**: `pg_stats.correlation` 反映物理顺序，可指导优化器

PostgreSQL 不支持类似 InnoDB 的 "聚簇主键"。所有表都是堆表 (heap)，主键和其他索引一样都是独立的 B+ 树，叶子节点指向 ctid (page, slot) 物理地址。即使 `CLUSTER` 后，新数据仍会追加到表末尾。

### pg_repack: 在线维护聚簇顺序

为弥补 `CLUSTER` 锁表的痛点，社区扩展 `pg_repack` (2012 年由 NTT OSS Center 开源) 实现了在线重排:

```bash
# 按主键重排，不锁表
pg_repack -d mydb -t orders

# 按指定索引重排
pg_repack -d mydb -t orders -o customer_id

# 仅重建索引
pg_repack -d mydb -t orders --only-indexes
```

实现原理:

1. 创建影子表 (shadow table) 和触发器，捕获原表的所有 DML
2. 复制原表数据到影子表，按目标索引顺序排列
3. 应用复制期间累积的 DML
4. 短暂获取 `ACCESS EXCLUSIVE` 锁，交换原表和影子表

`pg_repack` 仍是 "一次性 + 周期性运行"，不是持续维护。许多 PostgreSQL 用户用 cron 每周运行 `pg_repack` 维护聚簇顺序。

### Oracle: Index-Organized Table (IOT, 8i 引入)

Oracle 在 8i (1999 年) 引入 IOT (Index-Organized Table)，这是 Oracle 在 SQL Server 之后第二个引入聚簇主键概念的主流引擎:

```sql
-- 创建 IOT
CREATE TABLE orders (
    order_id    NUMBER,
    customer_id NUMBER,
    order_date  DATE,
    amount      NUMBER,
    CONSTRAINT pk_orders PRIMARY KEY (order_id)
)
ORGANIZATION INDEX
TABLESPACE iot_ts
PCTTHRESHOLD 20
INCLUDING amount   -- amount 之前的列存主索引段，之后的列存溢出段
OVERFLOW TABLESPACE overflow_ts;

-- 查询执行计划显示 INDEX UNIQUE SCAN，无堆访问
EXPLAIN PLAN FOR SELECT * FROM orders WHERE order_id = 12345;
```

特点:

1. **PCTTHRESHOLD**: 行超过页大小该比例时，溢出列分裂到 overflow segment
2. **INCLUDING 列**: 主段保留的列范围
3. **二级索引**: 存主键值 (logical rowid)，加 PCT-FREE physical guess 加速访问
4. **MOVE 语句**: 类似 PG CLUSTER，可重组 IOT (`ALTER TABLE ... MOVE`)

IOT 适合 PK 范围查询频繁、表较小、列数少的场景。Oracle 还有更早的 **Cluster** (V6 即支持，1988 年):

```sql
-- 多表共享一个 cluster key (early 1990s)
CREATE CLUSTER customer_cluster (customer_id NUMBER) SIZE 8192;

CREATE INDEX customer_cluster_idx ON CLUSTER customer_cluster;

CREATE TABLE customers (..., customer_id NUMBER) CLUSTER customer_cluster (customer_id);
CREATE TABLE orders    (..., customer_id NUMBER) CLUSTER customer_cluster (customer_id);

-- 同一 customer_id 的 customers 行和 orders 行存储在同一页
SELECT * FROM customers c JOIN orders o ON c.customer_id = o.customer_id
WHERE c.customer_id = 100;
-- 一次 I/O 即可读取该客户的所有信息
```

Cluster 在 OLTP 场景一度流行，但维护复杂、扩展性差，后被 IOT 和分区表替代。

### Oracle Attribute Clustering (12c R1, 2013)

Oracle 12.1 引入 Attribute Clustering，专为分析负载设计，类似 BigQuery / Snowflake 的 CLUSTER BY:

```sql
-- 线性聚簇 (字典序)
CREATE TABLE sales (
    sale_date DATE, region VARCHAR2(20), product_id NUMBER, amount NUMBER
)
CLUSTERING BY LINEAR ORDER (region, sale_date)
YES ON LOAD YES ON DATA MOVEMENT;

-- 交错聚簇 (Z-order，类似 Redshift INTERLEAVED)
CREATE TABLE sales_zorder (...)
CLUSTERING BY INTERLEAVED ORDER (region, sale_date, product_id);
```

关键点:

1. **YES ON LOAD**: 直接路径加载 (DataPump、SQL*Loader、INSERT /*+ APPEND */) 时聚簇
2. **YES ON DATA MOVEMENT**: 分区移动、ALTER TABLE MOVE 时聚簇
3. **不维护 OLTP DML**: 普通 INSERT 不会聚簇 (避免影响事务性能)
4. **配合 Zone Map**: Oracle 12c 引入 Zone Map，存储 min/max，配合 attribute clustering 实现块级 pruning

### MySQL InnoDB: 隐式聚簇 (无 DDL)

MySQL InnoDB 自 4.0 起即默认聚簇，**没有显式的 CLUSTER BY DDL**:

```sql
CREATE TABLE orders (
    order_id    BIGINT PRIMARY KEY,        -- 隐式聚簇键
    customer_id BIGINT,
    order_date  DATE,
    amount      DECIMAL(10,2),
    KEY idx_customer (customer_id)         -- 二级索引存 order_id (主键值)
);
```

行为:

1. **总是聚簇**: 每张 InnoDB 表都是 B+ 树，叶子节点是行
2. **聚簇键 = 主键**: 没有显式主键时，InnoDB 选第一个 NOT NULL UNIQUE 索引；都没有时生成隐藏 6 字节 DB_ROW_ID
3. **二级索引格式**: 二级索引叶子节点存主键值 (而非物理地址)，回表必须走主键 B+ 树
4. **AUTO_INCREMENT 推荐**: 顺序主键避免 B+ 树页分裂；UUID/随机主键导致严重碎片
5. **改聚簇键代价高**: ALTER TABLE 修改主键等于重建整张表

InnoDB 没有提供 "重新聚簇" 的命令 (因为始终维护)。性能退化主要是 **碎片化** (FRAG_RATE)，可通过 `OPTIMIZE TABLE` 重建。

### SQL Server: CLUSTERED INDEX (默认即聚簇)

SQL Server 7.0 起支持 CLUSTERED INDEX，PRIMARY KEY 默认创建聚簇索引:

```sql
-- PRIMARY KEY 默认 CLUSTERED
CREATE TABLE orders (
    order_id    INT PRIMARY KEY,           -- = PRIMARY KEY CLUSTERED
    customer_id INT,
    order_date  DATE
);

-- 显式声明聚簇 / 非聚簇
CREATE TABLE orders2 (
    order_id    INT PRIMARY KEY NONCLUSTERED,   -- PK 非聚簇
    customer_id INT,
    order_date  DATE
);
CREATE CLUSTERED INDEX cix_order_date ON orders2(order_date);  -- 按日期聚簇

-- 后期添加聚簇索引 (堆表 → 聚簇表)
CREATE CLUSTERED INDEX cix_orders ON heap_table(some_column);
```

特点:

1. **每表一个聚簇索引**: 物理顺序只有一个
2. **二级索引存 cluster key**: 类似 InnoDB
3. **堆表 (无聚簇索引)**: 用 RID (page_id, slot) 标识行；可以选不建聚簇索引
4. **可换聚簇键**: `DROP INDEX cix_old; CREATE CLUSTERED INDEX cix_new` (重建表)

### ClickHouse: ORDER BY (强制，MergeTree 必填)

ClickHouse 是显式聚簇键设计的极端代表: MergeTree 引擎**必须**指定 `ORDER BY` 子句:

```sql
CREATE TABLE events (
    event_time   DateTime,
    user_id      UInt64,
    event_type   String,
    payload      String
)
ENGINE = MergeTree()
PARTITION BY toYYYYMM(event_time)
ORDER BY (user_id, event_time)             -- 物理排序 + 主键索引
SETTINGS index_granularity = 8192;
```

关键点:

1. **ORDER BY 必填**: MergeTree 系列没有 `ORDER BY` 不能创建表
2. **主键 = ORDER BY 前缀**: 默认主键就是 ORDER BY 列；可显式 `PRIMARY KEY (user_id)` 让主键短于排序键
3. **稀疏索引**: ClickHouse 主键不是 B+ 树，而是每 `index_granularity` (默认 8192) 行一个 mark
4. **后台合并**: 数据写入产生小 part，后台 merge 线程合并并维持 ORDER BY 顺序
5. **多线程并行 merge**: 严重写入时 part 数飙升，merge 跟不上会触发 throttle

ClickHouse 的 ORDER BY 是 OLAP 性能的核心:

- 范围扫描: `WHERE user_id = X` 命中前缀，二分查找定位 mark
- ZoneMap (min-max): 每个 part 的每个 mark 自动维护 min/max
- Skip Index: 在 ORDER BY 之外的列建立 minmax / set / bloom_filter 跳过索引
- 字典编码 / RLE: 排序后相邻值相同，压缩率显著提升

### Snowflake: CLUSTER BY + Auto-Clustering (2018)

Snowflake 在 2018 年正式 GA Auto-Clustering 服务，将聚簇键提升为后台自动维护:

```sql
-- 创建表时定义 cluster key
CREATE TABLE sales (
    sale_date DATE, region VARCHAR, product_id INT, amount DECIMAL
)
CLUSTER BY (region, sale_date);

-- 已有表添加 cluster key
ALTER TABLE sales CLUSTER BY (region, sale_date);

-- 取消 cluster
ALTER TABLE sales DROP CLUSTERING KEY;

-- 暂停自动重组 (节省 credit)
ALTER TABLE sales SUSPEND RECLUSTER;
ALTER TABLE sales RESUME RECLUSTER;

-- 查看聚簇深度 (clustering depth)
SELECT SYSTEM$CLUSTERING_INFORMATION('sales');
SELECT SYSTEM$CLUSTERING_DEPTH('sales');
```

`CLUSTER BY` 表达式可以包含函数:

```sql
-- 按月聚簇 (减少 cluster key 基数)
CLUSTER BY (region, DATE_TRUNC('MONTH', sale_date));

-- 按截断的字符串聚簇
CLUSTER BY (SUBSTR(country, 1, 2), city);
```

### Snowflake Auto-Clustering 深入

Snowflake auto-clustering 是一个独立的、serverless 的后台服务，2018 GA。理解其工作机制对于评估成本和性能至关重要:

**核心概念 - Clustering Depth**:

Snowflake 的存储是**微分区** (micro-partition, 50-500MB 压缩列存)。每个微分区有所有列的 min/max。"Clustering depth" 衡量微分区在 cluster key 上的重叠程度:

```
理想情况: depth = 1
  分区 A: cluster_key 范围 [1, 100]
  分区 B: cluster_key 范围 [101, 200]
  分区 C: cluster_key 范围 [201, 300]
  → 任意点查询只命中 1 个分区

最坏情况: depth = N (完全未聚簇)
  分区 A: cluster_key 范围 [1, 1000]
  分区 B: cluster_key 范围 [1, 1000]
  分区 C: cluster_key 范围 [1, 1000]
  → 任意点查询都要扫描所有分区
```

**Auto-Clustering 工作流程**:

1. 持续监控 cluster_depth (per table, per cluster key)
2. 当 depth 超过阈值时，启动后台 reclustering 任务
3. 任务在 Snowflake 拥有的 serverless compute 上运行 (不占用客户 warehouse)
4. 重写一组 "重叠最严重" 的微分区，按 cluster key 排序后写出新分区
5. 新分区可见后，旧分区进入 fail-safe (7 天保留)

**计费模型**:

Auto-clustering 是**单独计费**的，按消耗的 serverless credit 数量。账单可见:

```sql
SELECT *
FROM SNOWFLAKE.ACCOUNT_USAGE.AUTOMATIC_CLUSTERING_HISTORY
WHERE TABLE_NAME = 'SALES'
  AND START_TIME > DATEADD(day, -7, CURRENT_TIMESTAMP());
```

**调优要点**:

1. **避免高基数 cluster key**: UUID / timestamp (秒级) 几乎等同随机，重组无效。建议 `DATE_TRUNC('DAY', ts)` 或 `DATE_TRUNC('HOUR', ts)`
2. **不要超过 3-4 列**: 超过 4 列的字典序聚簇基本无效 (维度越后越无序)
3. **写入模式**: 大批量、有序的 INSERT (如 ETL) 触发重组少；高频小批量 INSERT 触发重组多
4. **SUSPEND**: 历史不再变更的表，重组完成后可 SUSPEND，节省 credit
5. **PARTITION 不可用**: Snowflake 没有传统分区概念 (只有微分区)，cluster key 是唯一控制物理布局的手段

**何时 Auto-Clustering 不值得**:

- 表小于 1TB: 微分区数量少，pruning 收益低
- 写入频繁、读取少: 重组成本可能超过查询收益
- 查询模式不固定: 选不出有效的 cluster key
- 主要是点查询且 PK 已选好: 普通 micro-partition 已足够

### BigQuery: CLUSTER BY (2018-06，4 列限制)

BigQuery 在 2018 年 6 月引入 CLUSTER BY，是大数据时代第一个公开提供 "免费、自动" 聚簇服务的引擎:

```sql
CREATE TABLE `project.dataset.events` (
    event_time TIMESTAMP, user_id STRING, event_type STRING, region STRING
)
PARTITION BY DATE(event_time)
CLUSTER BY user_id, event_type, region;          -- 最多 4 列

-- 已有表修改聚簇 (BigQuery 2020 起支持)
ALTER TABLE `project.dataset.events`
SET OPTIONS (
    clustering_fields = ['user_id', 'event_type', 'region']
);

-- 删除聚簇
ALTER TABLE `project.dataset.events`
SET OPTIONS (clustering_fields = NULL);
```

### BigQuery 4 列限制详解

BigQuery 限制 CLUSTER BY 最多 4 列，这是经过深思熟虑的设计选择:

**字典序聚簇的本质**:

`CLUSTER BY (a, b, c, d)` 的语义是按 (a, b, c, d) 字典序排序。但 N 列字典序的 pruning 效果随列数指数衰减:

```
假设每列基数 100:
  CLUSTER BY (a):       pruning 后扫描 1/100
  CLUSTER BY (a, b):    a 命中后 b 进一步 pruning 到 1/10000 (但需要 a 等值)
  CLUSTER BY (a, b, c): 类似，但 c 仅在 (a, b) 都等值时有效
  CLUSTER BY (a, b, c, d): 第 5 列后几乎无 pruning 收益

而 BigQuery 微分区典型 100MB-1GB:
  小表 100GB: ~100-1000 个 block
  大表 10TB:  ~10000-100000 个 block

第 4 列后的 pruning 收益不足以补偿额外的存储分层管理开销
```

**与 Snowflake 的对比**:

Snowflake 也有 4-5 列的实际建议，但没有硬限制。BigQuery 的硬限制反映了团队对 "多列字典序聚簇收益递减" 的明确判断。

**4 列内的最佳实践**:

```sql
-- 推荐: 高过滤率列在前，低基数列在后
CLUSTER BY (date_trunc(event_time, DAY),  -- 时间维度，高过滤率
            country_code,                  -- 中等基数
            event_type,                    -- 低基数
            user_segment)                  -- 最低基数

-- 不推荐: 把 user_id (高基数) 放第一位
CLUSTER BY (user_id, event_type)
-- user_id 几乎随机，第二列 event_type 已无序，等同单列聚簇
```

**自动维护**:

BigQuery 后台自动维护聚簇，**无需用户操作，不计费**。这是 BigQuery 商业模式的优势 (storage 已计费，clustering 包含其中)。

```sql
-- 查看聚簇有效性
SELECT *
FROM `project.dataset.INFORMATION_SCHEMA.TABLE_STORAGE`
WHERE table_name = 'events';
```

### Redshift SORTKEY 三种模式

Amazon Redshift 自 2013 GA 起就支持 SORTKEY，是 MPP 列存数据库中最早提供显式排序键 DDL 的:

#### COMPOUND SORTKEY (默认，2013)

```sql
CREATE TABLE sales (
    sale_date DATE, region VARCHAR(20), product_id INT, amount DECIMAL
)
DISTSTYLE KEY DISTKEY (product_id)
COMPOUND SORTKEY (sale_date, region);   -- 字典序排序
```

行为类似 ClickHouse ORDER BY:

- 按 (sale_date, region) 字典序排序
- 每个 1MB block 维护 min/max (zone map)
- 查询 `WHERE sale_date BETWEEN ...` 高效跳过 block
- 第二列 region 仅在 sale_date 范围窄时有效

#### INTERLEAVED SORTKEY (2014)

2014 年引入的 INTERLEAVED 是 Z-order 多维聚簇的早期工业实现:

```sql
CREATE TABLE sales (
    sale_date DATE, region VARCHAR(20), product_id INT, amount DECIMAL
)
INTERLEAVED SORTKEY (sale_date, region, product_id);   -- 最多 8 列
```

#### Redshift INTERLEAVED SORTKEY 深入

INTERLEAVED 排序的目标是让所有列对查询的过滤效果**接近相同权重**:

**Z-order 原理**:

```
COMPOUND (sale_date, region):
  排序键 = sale_date 在前 + region 在后
  查询 WHERE sale_date = '2024-01-01' → 命中连续少量 block (高效)
  查询 WHERE region = 'APAC'         → 几乎扫全表 (低效)

INTERLEAVED (sale_date, region):
  Z-order: 每个键映射到固定字节位，然后 bit 交错
  查询 WHERE sale_date = ...          → 中等高效
  查询 WHERE region = ...             → 中等高效
  查询 WHERE sale_date AND region     → 高效 (Z-order pruning 生效)
```

**实现**:

Redshift 内部为每行计算一个 Z-value:

```
sale_date  = 0b 11010110 ... (32 bit)
region_id  = 0b 01101001 ... (32 bit)

Z-value    = 0b 0|1 1|1 0|0 1|1 0|0 1|1 ... (位交错)
```

数据按 Z-value 排序后，单维度查询都能命中部分 block，多维度组合查询效果更好。

**INTERLEAVED 限制**:

1. **最多 8 列**: 比 COMPOUND 多
2. **写入时不维护**: INSERT 后 zonemap 退化，需要 `VACUUM REINDEX` 重建
3. **Skew 敏感**: 数据分布偏斜时 Z-order 效果退化
4. **不支持 INTERLEAVED 列添加**: 改 SORTKEY 必须重建表
5. **小数据量低效**: 小于 100GB 的表收益有限

**何时用 INTERLEAVED**:

```sql
-- 推荐: 多个维度查询频率相近
INTERLEAVED SORTKEY (date, region, product_id, customer_segment)
-- 数据分析师不知道具体查哪个维度，但每次都查 1-2 个维度

-- 不推荐: 90% 查询带日期过滤
COMPOUND SORTKEY (date, region)   -- COMPOUND 更高效
```

#### AUTO SORTKEY (2020)

Redshift 2020 年引入 `AUTO`，让系统选择最佳 SORTKEY:

```sql
CREATE TABLE sales (...)
SORTKEY AUTO;
```

系统监控查询模式，定期推荐并自动应用 SORTKEY。这是 Redshift 与 Snowflake auto-clustering 的对标产品，但目前推荐质量不如人工选择。

### Vertica: Projection ORDER BY (2005，最早)

Vertica 在 2005 年 1.0 版本就引入了 **Projection** 概念 - 把同一张逻辑表用不同物理排序、不同列子集存储多份:

```sql
-- 逻辑表
CREATE TABLE sales (
    sale_date DATE, region VARCHAR, product_id INT, amount NUMERIC
);

-- Projection 1: 按时间排序
CREATE PROJECTION sales_by_date (sale_date, region, product_id, amount)
AS SELECT sale_date, region, product_id, amount FROM sales
ORDER BY sale_date, region
SEGMENTED BY HASH(sale_date) ALL NODES;

-- Projection 2: 按 region 排序 (相同表的另一份物理副本)
CREATE PROJECTION sales_by_region (region, product_id, sale_date, amount)
AS SELECT region, product_id, sale_date, amount FROM sales
ORDER BY region, product_id
SEGMENTED BY HASH(region) ALL NODES;
```

特点:

1. **Vertica 没有传统 "表" 物理结构**: 表是逻辑的，物理只有 projection
2. **多 projection 多重排序**: 一张逻辑表可以有多个 projection，每个有不同的 ORDER BY (类似多个聚簇键)
3. **超 projection (super projection)**: 包含所有列，相当于主存储
4. **查询路由**: 优化器选择最适合的 projection 执行查询
5. **写入放大**: INSERT 写入所有 projection (代价高，类似多个索引)
6. **Mergeout (Tuple Mover)**: 后台合并 ROS (Read Optimized Store) 维持 ORDER BY

Vertica 的 projection 是 "用空间换时间" 的极致体现，理念后来在 ClickHouse Projection (2021)、StarRocks MV、Snowflake Materialized View 中都有体现。

### CockroachDB / TiDB: PRIMARY KEY 即聚簇

分布式 NewSQL 引擎普遍采用 PRIMARY KEY 隐式聚簇:

```sql
-- CockroachDB
CREATE TABLE orders (
    customer_id INT, order_id INT, order_date DATE, amount DECIMAL,
    PRIMARY KEY (customer_id, order_id)
);
-- 数据按 (customer_id, order_id) 字典序分布到多个 range，每个 range 内部按 PK 排序

-- 改聚簇键 (CockroachDB 22.1+)
ALTER TABLE orders ALTER PRIMARY KEY USING COLUMNS (customer_id, order_date, order_id);

-- TiDB
CREATE TABLE orders (
    customer_id BIGINT, order_id BIGINT, order_date DATE,
    PRIMARY KEY (customer_id, order_id) CLUSTERED   -- 显式 CLUSTERED 关键字 (TiDB 5.0+)
);
-- TiDB 5.0 之前默认 NONCLUSTERED (RowID 聚簇)，5.0+ 默认 CLUSTERED
```

CockroachDB / TiDB 的 PK 排序是**全局**的 (跨节点)，依赖 Raft + KV 存储 (RocksDB) 的字节序分布。范围扫描效率高，但热点 PK 会导致 range hot spot。

### SingleStore / StarRocks / Doris (现代 MPP)

SingleStore (前 MemSQL) 列存表用 SORT KEY 控制物理排序:

```sql
-- SingleStore 列存表
CREATE TABLE events (
    event_time DATETIME, user_id BIGINT, event_type VARCHAR(64),
    SORT KEY (event_time, user_id),
    SHARD KEY (user_id)
);
```

StarRocks 主键模型 (Primary Key Model) 自 2.5 起支持显式 ORDER BY:

```sql
-- StarRocks 主键模型 (2.5+)
CREATE TABLE events (
    event_time DATETIME, user_id BIGINT, event_type VARCHAR(64), payload VARCHAR
)
PRIMARY KEY (user_id, event_time)
DISTRIBUTED BY HASH (user_id) BUCKETS 32
ORDER BY (event_time, user_id);   -- 物理排序与 PK 不同
```

Apache Doris 的 Aggregate / Unique 模型用 KEY 列同时充当 PK 和聚簇键:

```sql
-- Doris Unique 模型
CREATE TABLE user_profile (
    user_id BIGINT, last_login DATETIME, login_count INT, last_ip VARCHAR(64)
)
UNIQUE KEY (user_id)
DISTRIBUTED BY HASH (user_id) BUCKETS 32;
```

### Apache Iceberg / Delta Lake / Hudi: 现代湖表

数据湖表格式都支持 "写入时排序" 和 "后续重组":

#### Iceberg WRITE ORDERED BY

```sql
-- Spark SQL on Iceberg
ALTER TABLE catalog.db.events WRITE ORDERED BY user_id, event_time;

-- 写入时按指定列排序 (写入路径)
INSERT INTO catalog.db.events SELECT * FROM source;

-- 重写已有数据
CALL catalog.system.rewrite_data_files(
    table => 'db.events',
    sort_order => 'user_id, event_time'
);
```

#### Delta Lake OPTIMIZE ZORDER BY

Delta Lake 1.2 (2022) 引入 ZORDER BY，类似 Redshift INTERLEAVED:

```sql
OPTIMIZE events
WHERE event_date >= '2024-01-01'
ZORDER BY (user_id, event_type);
```

ZORDER 是手动操作，需要定期运行。Z-order 算法在 Delta 中通过 `interleave_bits` UDF 实现。

#### Databricks Liquid Clustering (2024)

Databricks 2024 年 GA 的 Liquid Clustering 是 ZORDER 的下一代，目标是 "自动维护 + 可演进 cluster key":

```sql
CREATE TABLE events (...)
CLUSTER BY (user_id, event_type);   -- 声明 cluster key

-- 切换 cluster key (ZORDER 必须重写整张表，Liquid 增量适应)
ALTER TABLE events CLUSTER BY (event_time, user_id);

-- 触发后台优化 (但 Liquid 也可以 Auto)
OPTIMIZE events;
```

Liquid 的优势:

1. **可演进**: 修改 cluster key 不需要重写全表
2. **自动维护**: 写入时和后台均会维护
3. **Z-order 改进**: 不依赖 fixed-width 编码，支持任意类型
4. **性能优于 ZORDER**: Databricks 公布数据快 7 倍

#### Apache Hudi Clustering (2021)

Hudi 0.7 引入 clustering service:

```
hoodie.clustering.inline=true
hoodie.clustering.async.enabled=true
hoodie.clustering.plan.strategy.sort.columns=user_id,event_time
hoodie.clustering.plan.strategy.target.file.max.bytes=1073741824
```

Hudi clustering 可以是 inline (写入路径) 或 async (后台 Spark 作业)。

### DB2: MDC (Multi-Dimensional Clustering)

IBM DB2 LUW 在 8.1 版本引入 MDC，是工业界最早的 "多维聚簇" 实现:

```sql
CREATE TABLE sales (
    sale_date DATE, region CHAR(10), product_id INT, amount DECIMAL
)
ORGANIZE BY DIMENSIONS (sale_date, region);
```

MDC 不是字典序，而是按每个维度值分配 **block**:

```
传统 B+ 树: 一行一行有序排列
MDC:       (date='2024-01-01', region='APAC') 的所有行存在同一组 block
           (date='2024-01-01', region='EMEA') 的所有行存在另一组 block
           ...

每个维度组合对应一个 cell，cell 由整数倍 extents (block) 组成
```

MDC 优点: 维度等值查询极快 (block 级 pruning)；维度独立 (不像字典序后维度受限)。
缺点: 维度基数过高时空间浪费严重 (空 cell)；只适合低基数、固定维度的事实表。

### Oracle: Cluster (老式) vs IOT vs Attribute Clustering

Oracle 有三套并行的聚簇机制，各自适合不同场景:

| 机制 | 引入版本 | 适合场景 | 维护方式 |
|------|---------|---------|---------|
| Index Cluster | V6 (1988) | 多表共享列、关联查询频繁 | 持续维护 |
| Hash Cluster | 早期 | 等值查找静态数据 | 持续维护 |
| Index-Organized Table (IOT) | 8i (1999) | 主键范围查询、小表 | 持续维护 |
| Attribute Clustering | 12c R1 (2013) | 数据仓库、批量加载 | 加载/重组时 |

### TimescaleDB / QuestDB / InfluxDB IOx

时序数据库的聚簇键几乎总是时间列:

```sql
-- TimescaleDB hypertable
CREATE TABLE metrics (time TIMESTAMPTZ NOT NULL, device_id INT, value DOUBLE PRECISION);
SELECT create_hypertable('metrics', 'time');
ALTER TABLE metrics SET (timescaledb.compress, timescaledb.compress_segmentby = 'device_id');

-- QuestDB
CREATE TABLE metrics (time TIMESTAMP, device_id LONG, value DOUBLE)
TIMESTAMP(time)
PARTITION BY DAY;
-- 时间列即聚簇键
```

时序场景的特殊性:

1. **写入有序**: 数据按时间到达，天然就是聚簇的 (无需重组)
2. **TTL**: 旧数据按时间分区淘汰
3. **乱序数据**: late-arriving 数据需要后台合并

## 关键发现

### 1. 显式聚簇键 DDL 的演进

- **1988**: Oracle Cluster (V6)，多表共享物理空间
- **1999**: Oracle IOT (8i)，主键聚簇
- **2005**: Vertica Projection ORDER BY (1.0)，第一个 MPP 列存的显式排序键
- **2013**: Redshift COMPOUND SORTKEY (GA)
- **2014**: Redshift INTERLEAVED SORTKEY (Z-order 工业化)
- **2016**: ClickHouse ORDER BY (MergeTree)，强制聚簇键
- **2018**: BigQuery CLUSTER BY (June 2018) + Snowflake Auto-Clustering 同年 GA
- **2021**: Hudi Clustering Service
- **2022**: Delta OPTIMIZE ZORDER BY
- **2024**: Databricks Liquid Clustering，可演进 + 自动维护

20 年间从 "OLTP 主键聚簇" 演化到 "OLAP 多列聚簇 + 自动维护 + 可演进"。

### 2. 三种维护模式的取舍

| 模式 | 代表 | 优点 | 缺点 |
|------|------|------|------|
| 持续 (B+ 树) | InnoDB / SQL Server CI / Oracle IOT | OLTP 友好，无需重组 | 写入放大；只能选一个聚簇键 |
| 后台异步 | Snowflake / BigQuery / Vertica / ClickHouse | 写入快；OLAP 友好 | 需要后台资源；clustering depth 监控 |
| 一次性 / 手动 | PG CLUSTER / Iceberg / Delta ZORDER | 简单可控 | 退化后须手动维护；需要锁表或大量计算 |

### 3. 为什么 OLAP 引擎不用 B+ 树聚簇?

OLTP 的 B+ 树聚簇 (InnoDB) 在 OLAP 不适用:

- B+ 树叶子页 4KB-16KB，对扫描太小 (cache miss 多)
- B+ 树为顺序写优化，OLAP 的批量加载产生大量页分裂
- B+ 树不支持跨节点的 range pruning (需要全局排序)
- OLAP 用 100MB-1GB 的 segment / part / micro-partition + ZoneMap，扫描效率高 100 倍

因此 OLAP 引擎都采用 "大块 + 块内有序 + 块级 zone map" 模式。

### 4. CLUSTER BY 列数限制对比

| 引擎 | 列数限制 | 排序方式 |
|------|---------|---------|
| BigQuery | 4 | 字典序 |
| Snowflake | 无硬限制 (建议 3-4) | 字典序 |
| ClickHouse | 无硬限制 | 字典序 |
| Redshift COMPOUND | 无硬限制 (建议 4) | 字典序 |
| Redshift INTERLEAVED | 8 | Z-order |
| Vertica Projection | 无硬限制 | 字典序，但可有多 projection |
| Snowflake | 无硬限制 | 字典序 |
| Oracle Linear Clustering | 无硬限制 | 字典序 |
| Oracle Interleaved Clustering | 无硬限制 | Z-order |

字典序聚簇的本质是 "前缀渐弱": 第 N+1 列的 pruning 收益是第 N 列的 1/基数。Z-order 让所有维度权重接近，但实现复杂度更高。

### 5. 自动维护的成本归属

| 引擎 | 资源消耗位置 | 计费方式 |
|------|------------|---------|
| ClickHouse merge | 集群节点 | 包含在节点计费中 |
| Snowflake auto-clustering | Snowflake serverless | **单独按 credit 计费** |
| BigQuery clustering | Google 后台 | **不单独计费** |
| Redshift VACUUM SORT | 集群节点 | 包含在集群计费中 |
| Vertica mergeout | 集群节点 | 包含 |
| Hudi clustering | 用户 Spark 作业 | 用户付费 |
| Delta Liquid | 用户 Databricks 集群 | 用户付费 |

BigQuery 的 "免费自动聚簇" 是其相对 Snowflake 的独特商业优势。

### 6. PostgreSQL 的特殊地位

PostgreSQL 是主流引擎中**唯一**没有任何形式的持续聚簇维护的:

- `CLUSTER` 是一次性，且锁表
- `pg_repack` 在线但仍是周期性
- 没有原生的聚簇主键概念 (堆表 + ctid)
- 没有 zone map (BRIN 索引部分弥补)

这是 PG 在 OLAP 性能上长期落后于 Oracle / SQL Server / 各 MPP 的根因之一。Citus、Greenplum 等扩展通过补 zone map / aot 排序部分弥补。

### 7. 引擎选型决策树

```
是否 OLTP？
├─ 是: 选 PRIMARY KEY 即聚簇键的引擎
│   ├─ 单机: MySQL InnoDB / SQL Server CI / Oracle IOT / SQLite WITHOUT ROWID
│   └─ 分布式: CockroachDB / TiDB / YugabyteDB / Spanner
│
└─ 否 (OLAP):
    ├─ 主要批量加载: Iceberg WRITE ORDERED BY / Hudi clustering
    ├─ 实时写入 + 列存: ClickHouse ORDER BY / StarRocks PK 模型
    ├─ 云仓库 (托管):
    │   ├─ 多维查询: BigQuery CLUSTER BY (4 列) / Snowflake CLUSTER BY (含 Auto)
    │   └─ AWS 生态: Redshift COMPOUND/INTERLEAVED SORTKEY
    ├─ 多 projection 需求: Vertica
    └─ 多维聚簇 (固定维度): DB2 MDC / Oracle Attribute Clustering
```

### 8. 容易踩的坑

1. **InnoDB UUID 主键**: 随机 PK 导致页分裂，写入退化 5-10x；解决: 用顺序 PK + UUID 作为二级索引列
2. **BigQuery 5+ 列聚簇**: 超过 4 列硬限制，但即使 4 列内，第 4 列收益也很有限
3. **Snowflake 高基数 cluster key**: timestamp(s) 几乎随机，重组无效；用 `DATE_TRUNC` 降基数
4. **Redshift INTERLEAVED 写后退化**: INSERT 后必须 VACUUM REINDEX 重建 zonemap
5. **PostgreSQL CLUSTER 后不维护**: 用户常误认为持续聚簇，实际只是一次性快照
6. **ClickHouse ORDER BY 选错列**: 选了高基数的列在前，等同没排序；ORDER BY 设计是 ClickHouse 调优 80% 的工作
7. **Iceberg WRITE ORDERED BY 不重写老数据**: 仅影响新写入，老数据需 `rewrite_data_files`
8. **Vertica Projection 过多**: 每个 projection 都要写入，10 个 projection = 10x 写入放大

### 9. 与查询优化器的协同

聚簇键只是底盘，要发挥效用需要优化器配合:

| 特性 | 含义 | 引擎支持 |
|------|------|---------|
| Zone Map / Min-Max | 块级 min/max，谓词下推时跳过块 | 几乎所有 OLAP 引擎 |
| Bloom Filter on cluster key | 等值查询的存在性测试 | ClickHouse skip index, Hudi, Iceberg |
| Sort-Merge Join | 两表按相同键聚簇时跳过排序 | Vertica, Spark, Snowflake |
| Streaming aggregation | 聚簇键即 GROUP BY 键时 | ClickHouse, Vertica |
| Predicate Pushdown | WHERE 推到块级 zonemap | 所有 |
| Top-N Pushdown | ORDER BY + LIMIT 跳过排序 | ClickHouse, Snowflake, Vertica |

### 10. 对引擎设计者的建议

```
1. 聚簇键 DDL 应该是显式且必填 (ClickHouse 模式)
   - 强制用户思考物理布局
   - 避免 "默认堆表" 导致的性能陷阱

2. 提供 clustering_depth 监控
   - Snowflake SYSTEM$CLUSTERING_INFORMATION 是良好范例
   - 让 DBA 知道何时需要重组

3. 后台自动维护应是 serverless / 独立资源
   - 避免影响在线查询
   - Snowflake 的 dedicated compute 模式优于 Redshift VACUUM 占用集群资源

4. cluster key 演进能力很重要
   - 业务需求会变化，最初的 cluster key 不一定最优
   - Liquid Clustering / BigQuery ALTER OPTIONS 都支持演进
   - Redshift / Iceberg WRITE ORDERED BY 的 "改即重写" 是负担

5. 字典序 vs Z-order 都应支持
   - 单维度查询为主用字典序
   - 多维度查询为主用 Z-order

6. 与分区策略正交
   - Partition + Cluster 是经典模式 (BigQuery、Snowflake、Redshift)
   - 分区做粗粒度 pruning，cluster 做块级 pruning
   - 详见 partition-strategy-comparison.md

7. cluster key 列基数感知
   - 引擎应自动警告高基数 cluster key (如 UUID)
   - 自动建议 DATE_TRUNC、SUBSTR 等降基数函数
```

## 与相关概念的关系

- **聚簇 vs 堆表**: 见 `clustered-heap-storage.md`，本文聚焦显式 DDL，该文聚焦默认存储组织
- **分区策略**: 见 `partition-strategy-comparison.md`，分区是粗粒度物理布局，聚簇是块内有序
- **索引类型**: 见 `index-types-creation.md`，二级索引建立在聚簇之上，B+ 树/LSM/列存索引实现差异
- **Bloom Filter / Zone Map**: 块级元数据是聚簇收益的兑现机制
- **Sort-Merge Join**: 聚簇键对齐时可跳过 Shuffle 和 Sort

## 参考资料

- Oracle: [Index-Organized Tables](https://docs.oracle.com/en/database/oracle/oracle-database/19/cncpt/indexes-and-index-organized-tables.html#GUID-25513019-EBC8-432A-8DCA-D6004D044C6F)
- Oracle: [Attribute Clustering](https://docs.oracle.com/en/database/oracle/oracle-database/19/dwhsg/improving-query-performance-with-attribute-clustering.html)
- PostgreSQL: [CLUSTER](https://www.postgresql.org/docs/current/sql-cluster.html)
- pg_repack: [Online table reorganization](https://reorg.github.io/pg_repack/)
- SQL Server: [Clustered Indexes](https://learn.microsoft.com/en-us/sql/relational-databases/indexes/clustered-and-nonclustered-indexes-described)
- MySQL: [Clustered and Secondary Indexes](https://dev.mysql.com/doc/refman/8.0/en/innodb-index-types.html)
- ClickHouse: [MergeTree ORDER BY](https://clickhouse.com/docs/en/engines/table-engines/mergetree-family/mergetree)
- Snowflake: [Automatic Clustering](https://docs.snowflake.com/en/user-guide/tables-auto-reclustering)
- Snowflake: [Clustering Keys & Clustered Tables](https://docs.snowflake.com/en/user-guide/tables-clustering-keys)
- BigQuery: [Clustered Tables](https://cloud.google.com/bigquery/docs/clustered-tables)
- Redshift: [Choosing Sort Keys](https://docs.aws.amazon.com/redshift/latest/dg/t_Sorting_data.html)
- Vertica: [Projections](https://docs.vertica.com/latest/en/data-analysis/projections/)
- DB2: [Multidimensional Clustering Tables](https://www.ibm.com/docs/en/db2/11.5?topic=tables-multidimensional-clustering-mdc)
- CockroachDB: [PRIMARY KEY](https://www.cockroachlabs.com/docs/stable/primary-key.html)
- Apache Iceberg: [WRITE ORDERED BY](https://iceberg.apache.org/docs/latest/spark-ddl/#alter-table-write-ordered-by)
- Apache Hudi: [Clustering](https://hudi.apache.org/docs/clustering)
- Delta Lake: [OPTIMIZE ZORDER BY](https://docs.delta.io/latest/optimizations-oss.html#z-ordering-multi-dimensional-clustering)
- Databricks: [Liquid Clustering](https://docs.databricks.com/en/delta/clustering.html)
- TiDB: [Clustered Indexes](https://docs.pingcap.com/tidb/stable/clustered-indexes)
