# 布隆过滤器索引 (Bloom Filter Indexes)

给我一个 10 比特、告诉我这个值"肯定不在"——布隆过滤器是懒人 DBA 最忠实的朋友：它不精确，也不需要精确，只要能让查询跳过 99% 不相关的数据块就够了。在现代 OLAP 和 LSM 存储引擎里，布隆过滤器索引已经从"学术玩具"进化为支撑 PB 级查询的核心基础设施。

## 一、无 SQL 标准：厂商与引擎各自为政

SQL 标准（ISO/IEC 9075）从未定义布隆过滤器索引。原因很简单：布隆过滤器是物理存储与访问路径的优化，属于实现细节。SQL 标准只定义逻辑语义，不规定 B-Tree、Hash、Bitmap、Bloom 这些具体的索引结构。

因此每个引擎对布隆过滤器的暴露方式千差万别：

- **PostgreSQL**：通过 `bloom` contrib 模块提供显式的 `CREATE INDEX USING bloom`
- **ClickHouse**：通过 `INDEX ... TYPE bloom_filter` 的数据跳过索引（Data Skipping Index）
- **Oracle / SQL Server / PostgreSQL 14+**：运行时布隆过滤器（Runtime Bloom Filter），用于哈希连接（Hash Join）的 build 端下推 probe 端
- **Cassandra / RocksDB / LevelDB**：SSTable 级别的自动布隆过滤器，用户不需要声明
- **Parquet**：文件格式层的 Bloom Filter Page（格式 v2.10+，2020 年发布）
- **Snowflake / BigQuery**：在微分区（micro-partition）元数据里暗含布隆过滤器，对用户透明

## 二、为什么需要布隆过滤器索引？

### 2.1 概率数据结构的价值

布隆过滤器由 Burton Howard Bloom 于 1970 年在论文《Space/Time Trade-offs in Hash Coding with Allowable Errors》中提出。核心思想：用 m 比特位数组和 k 个哈希函数表示一个集合，支持两种操作：

1. **insert(x)**：将 x 的 k 个哈希值对应的位全部置 1
2. **contains(x)**：检查 k 个位是否全为 1，若否则 x **肯定不在**，若是则 x **可能在**（假阳性率 p）

关键性质：**无假阴性，有假阳性**。这恰好是数据库跳过索引想要的语义——

- 如果过滤器说"可能有"，就读这个块验证（可能白跑一次）
- 如果过滤器说"肯定没有"，就跳过这个块（节省 I/O，零误判）

### 2.2 "懒人 DBA"的三大场景

1. **LSM 树 SST 文件的点查**：Cassandra / RocksDB / HBase 每个 SST 文件带一个布隆过滤器，点查时先查过滤器，避免读不必要的 SST
2. **列式存储的数据跳过**：ClickHouse / Parquet 为每个 granule 或 row group 建布隆过滤器，扫描时 block-skip
3. **哈希连接的运行时下推**：build 端构建布隆过滤器，传给 probe 端扫描算子，在读数据时就过滤掉不可能匹配的行——"动态谓词下推"（Dynamic Filtering）

## 三、支持矩阵（综合 50 个引擎）

### 3.1 显式 Bloom Filter CREATE INDEX 语法

| 引擎 | 语法 | 块级/表级 | 版本 |
|------|------|---------|------|
| PostgreSQL | `CREATE INDEX ... USING bloom` | 表级（contrib 扩展） | 9.6+（2016） |
| MySQL | -- | -- | 不支持 |
| MariaDB | -- | -- | 不支持 |
| SQLite | -- | -- | 不支持 |
| Oracle | -- | -- | 无显式语法（内部使用） |
| SQL Server | -- | -- | 无显式语法（内部使用） |
| DB2 | -- | -- | 无显式语法（内部使用） |
| Snowflake | -- | -- | 无显式语法（元数据暗含） |
| BigQuery | -- | -- | 不支持 |
| Redshift | -- | -- | 无显式语法（内部使用） |
| DuckDB | -- | -- | 无显式语法（内部使用） |
| ClickHouse | `INDEX ... TYPE bloom_filter / tokenbf_v1 / ngrambf_v1` | granule 级 | 20.x+ |
| Trino | -- | -- | 无显式语法（Iceberg/Hive 透明使用） |
| Presto | -- | -- | 无显式语法 |
| Spark SQL | -- | -- | 无显式语法（运行时过滤） |
| Hive | ORC `'orc.bloom.filter.columns'` | stripe 级 | 1.2+ |
| Flink SQL | -- | -- | 不支持 |
| Databricks | -- | -- | 无显式 SQL（Delta Lake 自动） |
| Teradata | -- | -- | 无显式语法 |
| Greenplum | `CREATE INDEX ... USING bloom` | 表级（继承 PG） | 6.x+ |
| CockroachDB | -- | -- | 无显式语法（Pebble SST 自动） |
| TiDB | -- | -- | 无显式语法（RocksDB 自动） |
| OceanBase | -- | -- | 无显式语法 |
| YugabyteDB | -- | -- | 无显式语法（RocksDB 自动） |
| SingleStore | -- | -- | 无显式语法 |
| Vertica | -- | -- | 无显式语法 |
| Impala | -- | -- | 无显式语法（运行时过滤） |
| StarRocks | `CREATE INDEX ... USING BLOOMFILTER` 或表属性 | 列级/block 级 | 2.x+ |
| Doris | `CREATE INDEX ... USING BLOOM FILTER` 或表属性 | 列级 | 1.2+ |
| MonetDB | -- | -- | 不支持 |
| CrateDB | -- | -- | 不支持 |
| TimescaleDB | `CREATE INDEX ... USING bloom` | 表级（继承 PG） | 继承 PG |
| QuestDB | -- | -- | 不支持 |
| Exasol | -- | -- | 不支持 |
| SAP HANA | -- | -- | 无显式语法 |
| Informix | -- | -- | 不支持 |
| Firebird | -- | -- | 不支持 |
| H2 | -- | -- | 不支持 |
| HSQLDB | -- | -- | 不支持 |
| Derby | -- | -- | 不支持 |
| Amazon Athena | -- | -- | 无显式语法（Parquet Bloom Filter 透明） |
| Azure Synapse | -- | -- | 无显式语法 |
| Google Spanner | -- | -- | 不支持 |
| Materialize | -- | -- | 不支持 |
| RisingWave | -- | -- | 不支持 |
| InfluxDB (SQL) | -- | -- | 不支持 |
| Databend | -- | -- | 无显式 SQL（Fuse 引擎自动） |
| Yellowbrick | -- | -- | 不支持 |
| Firebolt | -- | -- | 无显式语法（内部使用） |
| Apache Pinot | 表配置 `bloomFilterColumns` | segment 级 | GA |
| Apache Druid | 表配置 `bloomFilter` | segment 级 | GA |
| Cassandra | 自动 | SSTable 级 | 自 0.6+ |

> 统计：约 7 个引擎提供显式 `CREATE INDEX` 语法（PostgreSQL/Greenplum/TimescaleDB/ClickHouse/Doris/StarRocks/Hive ORC），其他要么通过表属性配置，要么完全透明自动。

### 3.2 按块 / 按部分的数据跳过索引

| 引擎 | 粒度 | 自动 / 显式 | 备注 |
|------|------|------------|------|
| ClickHouse | granule（~8192 行） | 显式 | `GRANULARITY N` 参数 |
| Doris | data page / segment | 显式 | 列级，存于 index file |
| StarRocks | block | 显式 | 列级 |
| Hive ORC | stripe / row group | 显式 | 表属性配置 |
| Parquet | row group / page | 显式 | 写入时 enable |
| Databricks Delta | 文件 | 显式 | `CREATE BLOOMFILTER INDEX` |
| Apache Pinot | segment | 显式 | 表配置 |
| Apache Druid | segment | 显式 | 列维度聚合时生成 |
| Cassandra | SSTable | 自动 | `bloom_filter_fp_chance` 可调 |
| RocksDB / TiDB / CockroachDB / YugabyteDB | SST file | 自动 | `filter_policy` 可配置 |
| HBase | HFile | 自动 | `BLOOMFILTER => 'ROW'/'ROWCOL'` |
| Snowflake | micropartition | 自动 | 元数据一部分，不可见 |
| Firebolt | tablet | 自动 | 内部使用 |
| Iceberg | data file（Parquet） | 写入时 | Trino/Spark 写 Parquet 时启用 |

### 3.3 哈希函数 / 假阳性率配置

| 引擎 | 哈希个数可配 | FP 率可配 | 默认值 |
|------|------------|----------|--------|
| PostgreSQL `bloom` | `length` / `col1...col16` | 通过 length 间接控制 | length=80 比特 |
| ClickHouse `bloom_filter` | 是（seeds） | 是（`false_positive` 参数） | 0.025 |
| ClickHouse `tokenbf_v1` | 是（`number_of_hash_functions`） | 通过 `size_of_bloom_filter_in_bytes` 间接 | -- |
| ClickHouse `ngrambf_v1` | 是 | 同 tokenbf_v1 | -- |
| Cassandra | -- | `bloom_filter_fp_chance` | 0.01（STCS）/ 0.1（LCS） |
| HBase | 固定 | 固定 | ~1% |
| RocksDB | 固定（double hashing） | `bits_per_key`（默认 10） | ~1% |
| Doris | -- | `bloom_filter_fpp` | 0.05 |
| StarRocks | -- | `bloom_filter_fpp` | 0.05 |
| Hive ORC | -- | `orc.bloom.filter.fpp` | 0.05 |
| Parquet | 算法固定（xxHash） | 写入时 NDV 决定 bitset 大小 | 1% |

### 3.4 运行时布隆过滤器（Join Bloom Filter Pushdown）

这是近年最热门的优化：Build 端先构建布隆过滤器，作为动态谓词传给 probe 端，在扫描时就跳过不可能匹配的 row group / block。

| 引擎 | 运行时布隆过滤器 | 版本 / 备注 |
|------|----------------|------------|
| Oracle | 是 | 10g+（2003），是最早的实现之一 |
| SQL Server | 是 | 内部使用于 batch mode hash join |
| DB2 | 是 | DB2 LUW 11.1+ |
| PostgreSQL | 部分 | 14+（2021）：并行哈希连接内部使用 |
| MySQL | -- | 不支持 |
| MariaDB | -- | 不支持 |
| Greenplum | 是 | Runtime filters |
| Vertica | 是 | SIPs（Sideways Information Passing） |
| Snowflake | 是 | 自动 |
| Redshift | 是 | Late Materialization + Bloom |
| BigQuery | 是 | Dremel 内部 |
| Impala | 是 | 2.5+（2016），`RUNTIME_FILTER_MODE` |
| Spark SQL | 是 | 3.0+ `spark.sql.optimizer.runtime.bloomFilter.enabled`（3.3+ 默认开） |
| Trino | 是 | `enable-dynamic-filtering`（默认开） |
| Presto | 是 | 0.220+ dynamic filtering |
| Hive | 是 | LLAP + Tez, hive.tez.dynamic.semijoin.reduction |
| Databricks | 是 | Photon runtime filter |
| ClickHouse | 部分 | 23.x+ `enable_hash_join_bloom_filter` |
| DuckDB | 是 | Late 2022+ Perfect Hash Join + Bloom |
| StarRocks | 是 | 2.x+ Global Runtime Filter |
| Doris | 是 | 1.2+ Runtime Filter |
| CockroachDB | 部分 | 分布式 bloom filter lookup join |
| TiDB | 部分 | MPP 下 Runtime Filter（7.x+） |
| OceanBase | 是 | 4.x+ 分布式 bloom filter |
| SingleStore | 是 | Bloom filter pushdown |
| Teradata | 是 | Dynamic row filtering |
| SAP HANA | 是 | 内部使用 |
| Firebolt | 是 | 自动 |
| Yellowbrick | 是 | 自动 |
| Databend | 是 | 运行时过滤 |
| Flink SQL | 部分 | 流处理中 miniBatch 里使用 |
| Materialize | -- | 增量视图不需要 |
| RisingWave | -- | 增量视图不需要 |

> 统计：约 30+ 现代 OLAP 引擎实现了运行时布隆过滤器下推，已成为事实标准。

### 3.5 LSM SST 级别布隆过滤器（自动）

| 引擎 | 存储层 | 默认开启 | 配置项 |
|------|--------|---------|--------|
| Cassandra | SSTable | 是 | `bloom_filter_fp_chance` |
| ScyllaDB | SSTable | 是 | 同 Cassandra |
| HBase | HFile | 是 | `BLOOMFILTER` 列族属性 |
| RocksDB | SST | 是 | `BlockBasedTableOptions::filter_policy` |
| LevelDB | SST | 是 | `Options::filter_policy` |
| TiDB / TiKV | RocksDB SST | 是 | 继承 RocksDB |
| CockroachDB | Pebble SST | 是 | Pebble 的 Go 版 RocksDB 实现 |
| YugabyteDB | RocksDB SST | 是 | 继承 RocksDB |
| Kvrocks | RocksDB SST | 是 | 继承 RocksDB |
| MyRocks | RocksDB SST | 是 | MySQL + RocksDB |
| FoundationDB | redwood / SQLite | 视版本 | -- |
| MongoDB (WiredTiger) | -- | 否 | WiredTiger 不用 bloom |
| Aerospike | -- | 否 | 内存索引 |

## 四、各引擎详解

### 4.1 PostgreSQL bloom 扩展（9.6+）

PostgreSQL 是少数提供显式 `CREATE INDEX USING bloom` 语法的主流关系数据库。自 9.6（2016 年）起作为 contrib 模块提供：

```sql
CREATE EXTENSION bloom;

-- 创建布隆索引：多列等值查询的理想场景
CREATE TABLE tbloom (
    i1 int, i2 int, i3 int, i4 int, i5 int, i6 int
);

CREATE INDEX bloomidx ON tbloom
    USING bloom (i1, i2, i3, i4, i5, i6)
    WITH (length = 80, col1 = 2, col2 = 2, col3 = 4,
          col4 = 2, col5 = 2, col6 = 2);

-- 任意列组合的等值查询都可以使用这个索引
SELECT * FROM tbloom
WHERE i2 = 898732 AND i5 = 123451;
```

关键参数：

- `length`：每个索引项的总比特数（默认 80，范围 1..4096），四舍五入到 16 的倍数
- `colN`：第 N 列占的哈希位数（默认 2，范围 1..4095）
- **无假阴性保证**：布隆索引永远不会错过匹配行，但会产生假阳性（返回后由 recheck 过滤）

典型用例：
- **多列多任意列等值查询**：B-Tree 每个列要建一个，而布隆索引一个就能覆盖所有列组合
- **数据仓库宽表**：200 列的事实表上，用户可能查任意列组合
- **点查密集型负载**：不适合范围扫描

限制：
- 只支持等值查询（`=`），不支持范围
- 不支持 UNIQUE 约束
- 假阳性率随数据量增长，需定期 REINDEX
- 必须 bitmap heap scan，不能直接从索引得到 tuple

### 4.2 ClickHouse 数据跳过索引（4 种布隆变体）

ClickHouse 的 Data Skipping Index 是最完整的布隆过滤器实现，提供 5 种类型（`minmax`、`set`、`bloom_filter`、`tokenbf_v1`、`ngrambf_v1`），其中 3 种基于布隆过滤器：

```sql
CREATE TABLE events (
    event_date Date,
    user_id UInt64,
    url String,
    user_agent String,
    INDEX idx_user_id user_id TYPE bloom_filter(0.01) GRANULARITY 4,
    INDEX idx_url url TYPE tokenbf_v1(256, 2, 0) GRANULARITY 4,
    INDEX idx_ua user_agent TYPE ngrambf_v1(4, 1024, 2, 0) GRANULARITY 4
) ENGINE = MergeTree()
ORDER BY (event_date, user_id);
```

四种类型对比：

| 类型 | 输入 | 适用谓词 | 参数 |
|------|------|---------|------|
| `bloom_filter(fpr)` | 整列值（hash 后） | `=`、`IN`、`hasToken`（少数场景） | `fpr`（假阳性率，默认 0.025） |
| `tokenbf_v1(size, hash_count, seed)` | 按非字母数字拆分的 token | `hasToken`、`=`（限制字符串） | bitset 字节数 / 哈希数 / 种子 |
| `ngrambf_v1(n, size, hash_count, seed)` | 长度 n 的 n-gram | `LIKE '%xyz%'`、`hasToken` | n-gram 长度 / 字节 / 哈希数 / 种子 |
| `set(max_rows)`（非布隆） | 精确集合 | 任意等值 | 集合最大行数 |

关键点：

1. **GRANULARITY N**：每 N 个主键 granule（默认 8192 行）合并成一个跳过索引条目。N 越大索引越小但跳过粒度越粗。
2. **tokenbf_v1 vs bloom_filter**：前者对字符串做 tokenize（空格、标点分词）后每个 token 进布隆过滤器；后者对整列值做哈希。前者适合 `hasToken('error')`，后者适合 `user_id = 12345`。
3. **ngrambf_v1**：对字符串的所有长度为 n 的子串建布隆过滤器，可加速 `LIKE '%search%'` 查询。代价：每 k 字节的字符串生成 (len-n+1) 个 token，索引会变大。
4. **Part 级 vs Granule 级**：ClickHouse 的 skip index 存于 part 的单独文件，查询时先读 skip index 决定哪些 granule 需要读列数据。

诊断 skip index 效率：

```sql
-- 查看 skip index 命中情况
SET send_logs_level = 'trace';
SELECT count() FROM events WHERE url = 'http://example.com/page';

-- 输出示例：
-- <Debug> Index `idx_url` has dropped 15/20 granules
```

调优经验：
- `bloom_filter(0.01)` 对高基数精确查询最有效
- `tokenbf_v1` 的 bitset 大小要 ≥ distinct token 数 × 10 比特
- `ngrambf_v1(n=4)` 对 CJK 字符串要选 n=2 或用 ICU tokenizer

### 4.3 Oracle（10g+ 的运行时布隆过滤器，2003）

Oracle 是最早将布隆过滤器用于生产数据库的商业引擎。自 10g 起，哈希连接的 build 端会自动构建布隆过滤器，下推到 probe 端的分区扫描：

```sql
-- Oracle 10g+ 自动应用，无需语法
SELECT /*+ USE_HASH(f d) */ *
FROM fact f
JOIN dim d ON f.dim_id = d.id
WHERE d.region = 'APAC';
```

执行计划（简化）：

```
HASH JOIN
  BUILD: dimension → build bloom filter :BF0000
  PROBE: fact partition range access
         PART JOIN FILTER: :BF0000  -- 布隆过滤器分区裁剪
         TABLE ACCESS BY INDEX
```

关键技术：

1. **PX JOIN FILTER CREATE / USE**：在并行查询中，Oracle 会显式展示布隆过滤器的构建和使用算子
2. **Partition Pruning via Bloom**：对分区表，build 端哈希后生成布隆过滤器，probe 端直接跳过整个分区
3. **Exadata Offload**：Exadata 存储单元支持将布隆过滤器下推到存储层，真正减少磁盘读
4. **Star Transformation**：星型查询中多维布隆过滤器级联

### 4.4 SQL Server（无显式语法，batch mode 内部使用）

SQL Server 没有 `CREATE INDEX USING bloom` 之类的显式语法，但在 columnstore 的 batch mode hash join 中广泛使用布隆过滤器：

```sql
-- 使用 columnstore index 的表自动启用 batch mode
SELECT f.*, d.name
FROM fact_cs f
JOIN dim d ON f.dim_id = d.id;

-- 执行计划的 XML 中会出现 BatchHashTableBuild 算子
-- 以及 BitmapCreate / BitmapFilter 节点
```

SQL Server 的"Bitmap Filter"（实质上是布隆过滤器）从 2008 开始用于星型连接优化，2016 起与 columnstore + batch mode 深度集成。

### 4.5 Impala（2.5+，2016 年的先驱）

Impala 是 OLAP 领域最早大规模引入 Runtime Bloom Filter 的开源引擎：

```sql
-- Impala 从 2.5 开始默认启用
SELECT * FROM sales s
JOIN customer c ON s.c_id = c.id
WHERE c.country = 'US';

-- 可通过 query option 控制
SET RUNTIME_FILTER_MODE = GLOBAL;  -- OFF / LOCAL / GLOBAL
SET RUNTIME_BLOOM_FILTER_SIZE = 1048576;  -- 默认 1MB
SET RUNTIME_FILTER_WAIT_TIME_MS = 1000;   -- probe 端等待 build 端的时间
```

Impala 的布隆过滤器通过 KRPC 在 coordinator 聚合，再下发到所有 probe 端的 scan 节点。Parquet/Kudu 扫描时，在 row group / row 级别做 early filter。

### 4.6 Spark SQL 的 Runtime Bloom Filter

Spark 3.0+ 引入 AQE（Adaptive Query Execution），3.3+ 默认启用运行时布隆过滤器：

```sql
SET spark.sql.optimizer.runtime.bloomFilter.enabled=true;
SET spark.sql.optimizer.runtime.bloomFilter.applicationSideScanSizeThreshold=10GB;
SET spark.sql.optimizer.runtime.bloomFilter.creationSideThreshold=10MB;

-- AQE 会在 exchange 之前插入 ObjectHashAggregate + BloomFilterAggregate
SELECT * FROM fact f JOIN dim d ON f.id = d.id WHERE d.x > 100;
```

Spark 的实现基于 `BloomFilterAggregate` 聚合函数——build 端先 shuffle 聚合出布隆过滤器，再广播给 probe 端的 scan。这与传统 dynamic partition pruning 的区别是：DPP 只在分区列上工作，而 bloom filter 可以用于**任意**连接键。

### 4.7 Trino / Presto Dynamic Filtering

Trino（前 PrestoSQL）在 346 版本开始默认开启 dynamic filtering，底层就是运行时布隆过滤器：

```sql
SET SESSION enable_dynamic_filtering = true;
SET SESSION dynamic_filtering_wait_timeout = '1s';

-- 自动应用，查询计划中出现 DynamicFilter
SELECT * FROM tpch.sf100.orders o
JOIN tpch.sf100.customer c ON o.custkey = c.custkey
WHERE c.nationkey = 1;
```

Trino 的动态过滤支持三种形式：
1. **值列表**：build 端 distinct 值少时直接发 IN 列表
2. **值区间**：连续区间时发 min/max
3. **布隆过滤器**：高基数连接键时发布隆过滤器

与 Iceberg / Hive Parquet 深度集成，可以直接跳过 row group 而不读 column chunks。

### 4.8 Cassandra SSTable Bloom Filter（自动）

Cassandra 每个 SSTable 附带一个布隆过滤器文件（`*-Filter.db`），点查（primary key lookup）时先查所有 SSTable 的布隆过滤器，只读真正可能包含数据的 SSTable：

```sql
-- 创建表时配置假阳性率
CREATE TABLE users (
    user_id uuid PRIMARY KEY,
    name text,
    email text
) WITH bloom_filter_fp_chance = 0.01;

-- 查看运行时命中
nodetool tablestats keyspace.users
-- Bloom filter false positives: 123
-- Bloom filter false ratio: 0.00012
-- Bloom filter space used: 4.5 MiB
```

默认值：
- STCS / TWCS：`bloom_filter_fp_chance = 0.01`（1% 假阳性）
- LCS：`bloom_filter_fp_chance = 0.1`（10%，因为 LCS 点查最多读 1-2 个 SSTable，没必要花内存）

### 4.9 RocksDB 家族（TiDB / CockroachDB / YugabyteDB）

RocksDB 的布隆过滤器是所有点查性能的核心。默认配置：

```cpp
BlockBasedTableOptions bbt_opts;
bbt_opts.filter_policy.reset(NewBloomFilterPolicy(10, false));
// 10 bits/key, full filter (非 block-based)
```

关键特性：
1. **Full Filter vs Block-Based Filter**：5.0 后默认 full filter——整个 SST 一个大布隆过滤器，比每 data block 一个更省空间
2. **Ribbon Filter**（6.15+）：比标准布隆过滤器在相同假阳性率下节省 30% 空间
3. **Prefix Bloom Filter**：对 prefix extractor 生成的 prefix 建过滤器，加速前缀扫描
4. **Partitioned Filters**：大 SST 的布隆过滤器分片，避免单次加载过多

TiDB / CockroachDB / YugabyteDB 都继承这套机制。TiDB 额外在 TiFlash 列存层又加了 coarse-grained skip index。

### 4.10 Parquet Bloom Filter Page（格式 v2.10，2020）

Apache Parquet 格式规范在 v2.10（2020 年）正式引入 Bloom Filter Page，存于 column chunk 之后、footer metadata 之前：

```
File Layout:
  Row Group 0:
    Column A:
      Data Pages ...
      Bloom Filter Page    <-- NEW in 2.10
    Column B: ...
  Row Group 1: ...
  Footer:
    FileMetaData:
      RowGroupMetadata:
        ColumnMetadata:
          bloom_filter_offset  <-- 指向 Bloom Filter Page
          bloom_filter_length
```

关键设计：
- **算法**：Split Block Bloom Filter（SBBF），Putze 等人 2007 年提出，对 CPU cache 友好
- **哈希函数**：xxHash64（固定）
- **块大小**：256 比特一个"块"，每个哈希落到一个块内的 8 个 word
- **NDV 驱动**：写入时根据 distinct count 和目标 FPR 决定比特数
- **配置**：Parquet-Java / Parquet-C++ 通过 `parquet.bloom.filter.enabled` + `parquet.bloom.filter.expected.ndv` 控制

读端集成：
- Trino / Spark / Impala / Athena / DuckDB / ClickHouse 都能读 Parquet bloom filter
- 结合 dynamic filtering，probe 端扫 Parquet 时先查 bloom filter page 决定整个 row group 是否跳过

### 4.11 Hive ORC Bloom Filter（1.2+）

Hive ORC 格式早在 2015 年就内置布隆过滤器，按 stripe 或 row group 存储：

```sql
CREATE TABLE orders (
    order_id BIGINT,
    customer_id BIGINT,
    order_date DATE
) STORED AS ORC
TBLPROPERTIES (
    'orc.create.index' = 'true',
    'orc.bloom.filter.columns' = 'order_id,customer_id',
    'orc.bloom.filter.fpp' = '0.05'
);
```

- `orc.bloom.filter.columns`：指定列
- `orc.bloom.filter.fpp`：假阳性率（默认 0.05）
- 读端：Hive / Presto / Trino / Spark 都能读 ORC bloom filter 做 predicate pushdown

### 4.12 Apache Doris 和 StarRocks

两者同源（都从 Apache Doris 分叉），都支持显式的布隆过滤器索引：

```sql
-- Doris
CREATE TABLE sales (
    sale_id BIGINT,
    user_id BIGINT,
    product_code VARCHAR(64),
    sale_amount DECIMAL(10,2)
) ENGINE=OLAP
DUPLICATE KEY(sale_id)
DISTRIBUTED BY HASH(sale_id) BUCKETS 32
PROPERTIES (
    "bloom_filter_columns" = "user_id, product_code",
    "bloom_filter_fpp" = "0.05"
);

-- StarRocks
ALTER TABLE sales SET ("bloom_filter_columns" = "user_id, product_code");
```

- 作用粒度：每个 data page（Doris）或 segment（StarRocks）一个布隆过滤器
- 数据类型限制：不支持 TINYINT / FLOAT / DOUBLE / BOOLEAN（小基数或浮点）
- 在 scan 算子层做 predicate 过滤

### 4.13 Databricks Delta Lake Bloom Filter Index

Databricks（基于 Spark + Delta Lake）从 2020 年开始支持显式布隆过滤器索引：

```sql
CREATE BLOOMFILTER INDEX
ON TABLE delta.events
FOR COLUMNS(user_id OPTIONS (fpp=0.05, numItems=5000000))
```

- 按 Delta Lake 的 data file（Parquet）级别存储
- 与 Z-Order + data skipping stats 三件套配合使用
- OPTIMIZE 命令会维护过滤器

### 4.14 Snowflake Micropartition 元数据

Snowflake 的每个微分区（默认 16MB 压缩）的元数据里暗含布隆过滤器（官方未公开具体格式，但从 EXPLAIN 和 patent 可以推断）：

```
Snowflake Micropartition Metadata:
  Min/Max per column
  NDV per column
  Null count
  Bloom filter (for high-cardinality equality)
```

对 equality predicates，Snowflake 的 scan 算子会先查元数据的布隆过滤器决定是否打开微分区。这是 Snowflake "automatic clustering" + "micro-partition pruning" 的重要组成部分。

## 五、Parquet Bloom Filter Page 格式深入

Parquet 的 SBBF（Split Block Bloom Filter）细节值得单独展开：

### 5.1 SBBF 算法（Putze 等 2007）

传统布隆过滤器的问题：k 次哈希访问 k 个不同 cache line，L1 cache miss 灾难。SBBF 的改进：

1. 将 bitset 分成大小为 256 比特（= 32 字节 = L1 cache line 的一半）的**块**
2. 第一次哈希选中一个块，后 8 次哈希都落到该块内的 8 个 word
3. 结果：一次 contains() 只碰一个 cache line

```
SBBF block (256 bits = 8 words of 32 bits):
  word[0] |= 1 << hash_bit(h0)
  word[1] |= 1 << hash_bit(h1)
  ...
  word[7] |= 1 << hash_bit(h7)

contains(x):
  block_id = hash_block(x)
  for i in 0..8:
    if block[i] & mask_i != mask_i: return false
  return true
```

### 5.2 Parquet 写入端

```python
# pyarrow 3.0+
import pyarrow.parquet as pq

pq.write_table(
    table, 'data.parquet',
    bloom_filter_columns=['user_id', 'order_id'],
    bloom_filter_options={
        'fpp': 0.01,
        'ndv': 1_000_000  # 预估 distinct count
    }
)
```

写入时的大小计算：

```
m = -n * ln(fpp) / (ln(2)^2)
# n=1M, fpp=0.01 → m ≈ 9.6M bits ≈ 1.2 MB per column chunk
```

### 5.3 读取端集成示例

Trino 读 Parquet 时：

```
ParquetReader:
  for each row_group:
    metadata = read_column_metadata(row_group, col)
    if metadata.bloom_filter_offset:
      bf = read_bloom_filter_page(metadata.bloom_filter_offset, length)
      if not bf.contains(dynamic_filter_value):
        skip_row_group()
        continue
    read_column_chunk(row_group, col)
```

与 dynamic filter 结合，Trino / Spark / Impala 可以在扫 fact 表时：

1. Build 端（小 dim 表）先执行，产生 bloom filter
2. 下推给 fact 表 scan
3. Scan 算子读每个 row group 时先查 Parquet bloom filter page
4. 若 bloom filter page 说"肯定不存在"→ 整个 row group 跳过
5. 否则按常规 page 级 predicate 下推继续

这是现代 lakehouse 架构 I/O 减少 10-100 倍的关键机制之一。

## 六、ClickHouse 4 种跳过索引深度剖析

ClickHouse 的 data skipping index 是教科书级的实现，值得单独分析：

### 6.1 bloom_filter

```sql
INDEX idx_user_id user_id TYPE bloom_filter(0.01) GRANULARITY 4
```

- 最通用，对整列值做哈希
- 支持谓词：`=`、`!=`、`IN`、`NOT IN`、`has()`（数组）、`hasAny()`、`hasAll()`
- `GRANULARITY 4` 表示每 4 个 MergeTree granule（每个 granule 默认 8192 行）合并为一个 skip index entry
- 实现：底层是 ClickHouse 自己的 `BloomFilter` 类（非 SBBF），用 2 个哈希函数做 double hashing 生成 k 个位置

### 6.2 tokenbf_v1

```sql
INDEX idx_log log_message TYPE tokenbf_v1(8192, 3, 0) GRANULARITY 4
```

参数：`tokenbf_v1(size_bytes, num_hash, seed)`

- 字符串按**非字母数字字符**切分（如空格、标点），每个 token 进布隆过滤器
- 适用：`hasToken('ERROR')`、`hasTokenCaseInsensitive()`、部分 `=` 和 `LIKE`
- 典型使用：日志搜索，"找出包含 error 和 timeout 的行"
- size_bytes 建议：distinct token 数 × 10 / 8

### 6.3 ngrambf_v1

```sql
INDEX idx_url url TYPE ngrambf_v1(3, 2048, 2, 0) GRANULARITY 4
```

参数：`ngrambf_v1(n, size_bytes, num_hash, seed)`

- 将字符串切成所有长度为 n 的**子串（n-gram）**，每个子串进布隆过滤器
- 支持谓词：`LIKE '%search%'`、`equals`、`hasToken`
- 关键：`LIKE '%xyz%'` 查询时，把模式串也切成 n-gram，查每个 n-gram 是否都在过滤器里
- 代价：存储成本高，每个长度 L 的字符串产生 L-n+1 个 token
- CJK 场景：n=2 较合适；英文：n=3 或 4

### 6.4 set（非布隆但相关）

```sql
INDEX idx_status status TYPE set(100) GRANULARITY 4
```

- 精确存储每个 granule group 中 ≤ 100 个 distinct value
- 超过就不存（skip index 失效）
- 适合低基数列（status、country 等）

### 6.5 调优原则

```
选择决策树:
  高基数精确点查 (user_id, order_id)    → bloom_filter(0.01..0.001)
  字符串关键词搜索 (日志 message)        → tokenbf_v1(8192, 3, 0)
  子串模糊匹配 (URL 路径)                → ngrambf_v1(3..4, 4096, 2, 0)
  低基数精确值 (< 100 distinct)         → set(N)
  数值范围 (时间戳、价格)                → minmax
```

关键提示：**跳过索引不是"越多越好"**。每个 skip index 都会增加 merge 的开销，而且只在 WHERE 子句谓词与索引列完全匹配时才能跳过。实践中 2-3 个精心选择的 skip index 就能覆盖 80% 查询。

## 七、运行时布隆过滤器（Runtime Bloom Filter）机制

这是现代 OLAP 最重要的优化之一。以下是主流引擎的实现对比：

### 7.1 基本原理

```
             ┌─────────────┐
             │  Dim scan   │ (small)
             └──────┬──────┘
                    │
             ┌──────▼──────────┐
             │  Hash table +   │
             │  Bloom filter   │ ← build 端
             │  build          │
             └──────┬──────────┘
                    │ broadcast bloom filter
                    ▼
             ┌─────────────────┐
             │  Fact scan      │ ← probe 端
             │  + bloom pushed │   扫描时早期过滤
             └──────┬──────────┘
                    │
             ┌──────▼──────┐
             │  Hash Join  │
             └─────────────┘
```

### 7.2 Oracle（10g+）

Oracle 的实现是最成熟的，支持三层使用：

1. **JOIN FILTER**：在 probe 端 hash join 执行器里，扫描 fact 表 row 时查 bloom filter
2. **PART JOIN FILTER**：对分区 fact 表，build 端 bloom filter 决定哪些 partition 可以剪掉
3. **Exadata Smart Scan**：将 bloom filter 下推到 Exadata 存储单元，在存储层直接过滤

### 7.3 PostgreSQL（14+）

PG 14（2021）引入并行哈希连接的 bloom filter（PG 源码 `src/backend/executor/nodeHash.c`）：

```c
// build 端
ExecHashBuildBloomFilter(hashtable);
// probe 端
if (hashtable->bloom_filter &&
    !bloom_lookup(hashtable->bloom_filter, hashvalue))
    continue;  // skip probe tuple
```

这是一个内部优化，用户无法控制，也不体现在执行计划中。仅在并行哈希连接、build 端足够小的情况下启用。

### 7.4 Spark SQL（3.3+ 默认开）

```
AQE 优化规则 InjectRuntimeFilter：
  1. 找出符合条件的 join：build 端 size < 10MB, probe 端 > 10GB
  2. 在 build 端插入 BloomFilterAggregate
  3. 在 probe 端插入 MightContain filter
  4. shuffle 阶段将 bloom filter 广播到所有 probe tasks
```

关键参数：

```sql
SET spark.sql.optimizer.runtime.bloomFilter.enabled = true;
SET spark.sql.optimizer.runtime.bloomFilter.creationSideThreshold = 10MB;
SET spark.sql.optimizer.runtime.bloomFilter.applicationSideScanSizeThreshold = 10GB;
SET spark.sql.optimizer.runtime.bloomFilter.maxNumBits = 67108864;  -- 8MB
```

### 7.5 Trino Dynamic Filtering

Trino 的动态过滤不只是 bloom filter，而是一个多形式的 predicate：

```java
// DynamicFilter 三种形态
TupleDomain<String>     // min/max range
Set<Object>             // distinct values (small)
BloomFilter             // high cardinality bloom
```

Optimizer 会根据 build 端大小自动选择。对于 500MB 的 dim 表，bloom filter 通常比 IN 列表更紧凑。

### 7.6 Impala（2.5+，最早的开源实现）

Impala 在 2016 年就把运行时 bloom filter 做到 MPP 集群级别：

```
RUNTIME_FILTER_MODE:
  OFF    - 禁用
  LOCAL  - 只在同一节点内使用（没 shuffle 开销）
  GLOBAL - 通过 coordinator 聚合，广播到所有 scan 节点（默认）
```

Impala 还支持 min/max runtime filter 和 bloom runtime filter 共存，优化器自己选。

### 7.7 StarRocks / Doris 的 Global Runtime Filter

```sql
SET GLOBAL runtime_filter_type = "IN_OR_BLOOM_FILTER";
-- 可选: IN, BLOOM_FILTER, MIN_MAX, IN_OR_BLOOM_FILTER
SET GLOBAL runtime_filter_mode = "GLOBAL";
SET GLOBAL runtime_filter_wait_time_ms = 1000;
```

StarRocks 2.0+ 支持 Global Runtime Filter：在 FE 侧汇总所有 BE 的 build hash，生成全局 bloom filter，再分发给所有 probe BE。

## 八、实现陷阱与调优

### 8.1 假阳性率、内存、哈希函数数的三角权衡

```
m = -n * ln(p) / (ln(2))^2       # 比特数
k = (m/n) * ln(2)                 # 最优哈希函数数

例: n=1M, p=0.01:
  m = 9,585,059 bits ≈ 1.2 MB
  k ≈ 7 hash functions

例: n=1M, p=0.001:
  m = 14,377,588 bits ≈ 1.8 MB
  k ≈ 10 hash functions
```

经验值：`10 bits per key` 对应约 1% 假阳性率，是 RocksDB 和多数 LSM 引擎的默认值。

### 8.2 哈希函数选择

现代引擎主流：
- **xxHash64 / xxHash3**：Parquet、ClickHouse、RocksDB（可选）都用
- **MurmurHash3**：Cassandra、HBase、Lucene
- **CityHash / FarmHash**：Google 系
- **SipHash**：安全性优先（PostgreSQL 某些场景）

**Double Hashing 技巧**：只计算 2 个"种子"哈希 h1、h2，然后 `h_i = h1 + i * h2` 生成 k 个哈希。Dillinger & Manolios 2004 证明这对假阳性率影响可忽略，但性能提升 2-3 倍。RocksDB、Parquet SBBF 都用这招。

### 8.3 布隆过滤器何时变差

1. **过饱和**：插入数量远超设计 NDV → 假阳性率爆涨到 50%+，过滤器失效
2. **低基数 + 小块**：比如 status 只有 10 个值，整块的布隆过滤器几乎总是 contains → 无意义
3. **范围查询**：布隆过滤器不支持 `<`、`>`、`BETWEEN` → 写错条件时过滤器被跳过
4. **NULL 语义**：多数实现把 NULL 排除在布隆过滤器之外，`col IS NULL` 不能用

### 8.4 监控指标

```sql
-- ClickHouse: system.merge_tree_settings + 查询 trace log
SELECT * FROM system.parts_columns WHERE index_name = 'idx_user_id';

-- Cassandra
nodetool tablestats ks.tbl | grep -i bloom

-- RocksDB
rocksdb.bloom.filter.useful               -- bloom filter 命中数
rocksdb.bloom.filter.full.positive        -- 真阳性
rocksdb.bloom.filter.full.true.positive   -- 实际匹配

-- Trino JMX
io.trino.operator.DynamicFilterSourceOperator
```

黄金比例：`bloom_filter_useful / bloom_filter_checked > 50%` 说明过滤器真正起作用。

### 8.5 高并发下的竞争

在 Spark / Trino / Impala 的 probe 端，bloom filter 是**只读**结构（build 完成后不再改），所以可以无锁并发访问。但是：

- **缓存污染**：几 MB 的布隆过滤器可能把 scan 的列数据挤出 L3 cache
- **NUMA 访问**：跨 socket 读布隆过滤器比读本地数据还慢
- **向量化集成**：SBBF 的优势在这里发挥——每 256 bit 一个 block，适合 AVX-512 gather

## 九、可运行查询示例

### 9.1 PostgreSQL bloom 扩展

```sql
CREATE EXTENSION bloom;

CREATE TABLE user_events AS
SELECT generate_series(1, 10000000) AS id,
       (random()*1000)::int AS country,
       (random()*100)::int AS device,
       (random()*50)::int AS browser,
       md5(random()::text) AS session_id;

CREATE INDEX bloom_idx ON user_events
  USING bloom (country, device, browser)
  WITH (length=80, col1=4, col2=2, col3=2);

EXPLAIN ANALYZE
SELECT COUNT(*) FROM user_events
WHERE country = 42 AND device = 7;
-- Bitmap Heap Scan → Bitmap Index Scan on bloom_idx
```

### 9.2 ClickHouse skip indexes

```sql
CREATE TABLE log_events (
    ts DateTime,
    level LowCardinality(String),
    message String,
    user_id UInt64,
    INDEX idx_user user_id TYPE bloom_filter(0.01) GRANULARITY 1,
    INDEX idx_msg_token message TYPE tokenbf_v1(32768, 3, 0) GRANULARITY 1,
    INDEX idx_msg_ngram message TYPE ngrambf_v1(4, 8192, 2, 0) GRANULARITY 1
) ENGINE = MergeTree
ORDER BY ts;

-- 启用 trace 看跳过率
SET send_logs_level = 'trace';
SELECT count() FROM log_events
WHERE user_id = 42 AND hasToken(message, 'ERROR');
```

### 9.3 Spark SQL Runtime Bloom Filter

```sql
SET spark.sql.adaptive.enabled=true;
SET spark.sql.optimizer.runtime.bloomFilter.enabled=true;

EXPLAIN EXTENDED
SELECT f.*
FROM fact_sales f
JOIN dim_customer c
  ON f.customer_id = c.id
WHERE c.country = 'JP';

-- 计划中出现:
-- BloomFilterAggregate
-- Filter (might_contain(bloom_filter, ...))
```

### 9.4 Trino Dynamic Filtering

```sql
EXPLAIN (TYPE IO, FORMAT JSON)
SELECT l.*
FROM hive.tpch.lineitem l
JOIN hive.tpch.orders o ON l.orderkey = o.orderkey
WHERE o.orderdate BETWEEN DATE '1995-01-01' AND DATE '1995-01-31';

-- DynamicFilterAssignments 节点会显示 bloom filter 大小
```

### 9.5 Cassandra 配置布隆过滤器

```sql
ALTER TABLE events
WITH bloom_filter_fp_chance = 0.005;

-- 强制 compaction 让新的 fp 生效
-- nodetool upgradesstables -a keyspace events
```

### 9.6 Hive ORC Bloom Filter

```sql
CREATE TABLE orc_sales (
    sale_id BIGINT,
    customer_id BIGINT,
    amount DECIMAL(10,2)
) STORED AS ORC
TBLPROPERTIES (
    'orc.bloom.filter.columns' = 'sale_id,customer_id',
    'orc.bloom.filter.fpp' = '0.01'
);

SET hive.optimize.ppd.storage=true;
SELECT * FROM orc_sales WHERE customer_id = 123456;
```

## 十、总结对比矩阵

### 10.1 布隆过滤器能力总览（核心 15 引擎）

| 能力 | PostgreSQL | MySQL | Oracle | SQL Server | ClickHouse | Snowflake | BigQuery | Redshift | Trino | Spark | Impala | Doris | StarRocks | Cassandra | RocksDB |
|------|-----------|-------|--------|------------|-----------|-----------|---------|----------|-------|-------|--------|-------|-----------|-----------|---------|
| 显式 CREATE INDEX | 是（contrib） | -- | -- | -- | 是 | -- | -- | -- | -- | -- | -- | 是 | 是 | -- | -- |
| Per-block skip | -- | -- | -- | -- | 是 | 是 | -- | -- | 是 | 是 | 是 | 是 | 是 | -- | -- |
| FP 率可配 | length | -- | -- | -- | 是 | -- | -- | -- | -- | -- | -- | 是 | 是 | 是 | bits/key |
| Runtime bloom (join) | 14+ | -- | 10g+ | 是 | 23+ | 是 | 是 | 是 | 是 | 3.3+ | 2.5+ | 是 | 2.0+ | -- | -- |
| LSM SST 自动 | -- | -- | -- | -- | -- | -- | -- | -- | -- | -- | -- | -- | -- | 是 | 是 |
| Parquet bloom 读 | -- | -- | -- | -- | 是 | 是 | 是 | 是 | 是 | 是 | 是 | 是 | 是 | -- | -- |

### 10.2 选型建议

| 场景 | 推荐方案 | 原因 |
|------|--------|------|
| PG 宽表任意多列等值 | PostgreSQL `bloom` 扩展 | 一个索引覆盖所有列组合 |
| 时序日志全文过滤 | ClickHouse `tokenbf_v1` | 日志分词 + 跳过整 granule |
| 子串模糊搜索 | ClickHouse `ngrambf_v1` | 支持 LIKE '%x%' 加速 |
| Fact 表按 dim 过滤 | Spark / Trino / Impala Runtime BF | 无需手动建索引 |
| 点查密集 KV | Cassandra / RocksDB | 自动 SSTable bloom |
| Parquet 湖仓 equality 点查 | Parquet BF + Trino dynamic filter | row group 级跳过 |
| Databricks Delta | CREATE BLOOMFILTER INDEX | 配合 Z-Order 使用 |
| Oracle 星型查询 | 自动运行时 bloom（10g+） | 无需配置 |

## 十一、关键发现 / Key Findings

1. **无 SQL 标准**：ISO/IEC 9075 从未定义布隆过滤器索引。50 个调研引擎中只有 7 个（PostgreSQL/Greenplum/TimescaleDB/ClickHouse/Doris/StarRocks + Hive ORC 表属性）提供显式 `CREATE INDEX` 或表属性语法。

2. **PostgreSQL 是唯一主流关系数据库提供显式 bloom 索引的引擎**——2016 年 9.6 版本 contrib 模块中的 `bloom` 扩展。其他商业关系数据库（Oracle / SQL Server / DB2）都**只在哈希连接内部使用布隆过滤器**，不允许用户创建。

3. **ClickHouse 的数据跳过索引是最完整的实现**：5 种类型中 3 种基于布隆过滤器（`bloom_filter`、`tokenbf_v1`、`ngrambf_v1`），覆盖精确等值、token 搜索、n-gram 模糊匹配三大场景。

4. **运行时布隆过滤器已成为现代 OLAP 的事实标准**：30+ 引擎实现了 Dynamic Filtering / Runtime Filter / Runtime Bloom Filter：
   - **Oracle 10g（2003）是商业数据库的先驱**
   - **Impala 2.5（2016）是开源 MPP 的先驱**
   - **Spark SQL 3.3（2022）默认开启**，基于 AQE 插入 `BloomFilterAggregate`
   - **Trino / Presto 默认开启**，多形式动态过滤（值列表/区间/布隆）
   - **PostgreSQL 14（2021）在并行哈希连接中内部使用**，但对用户不可见

5. **LSM 存储引擎的 SST 级布隆过滤器是透明且强制的**：Cassandra / HBase / RocksDB 系（TiDB、CockroachDB、YugabyteDB、MyRocks 等）都自动为每个 SSTable 生成布隆过滤器，这是 LSM 点查性能的支柱。默认 `10 bits/key` 对应 ~1% 假阳性率。

6. **Parquet Bloom Filter Page（格式 v2.10，2020）**使布隆过滤器成为**列式文件格式的一部分**，与引擎解耦。采用 Split Block Bloom Filter（SBBF）+ xxHash64，对 cache line 友好。Trino / Spark / Impala / ClickHouse / DuckDB / Athena / Databricks 都能读。

7. **Hive ORC 早于 Parquet 5 年**（2015 vs 2020）引入 stripe / row group 级布隆过滤器，通过 `orc.bloom.filter.columns` 表属性配置。

8. **ClickHouse `tokenbf_v1` 与 `ngrambf_v1` 的区别**：前者用非字母数字字符做分词（空格、标点），每个 token 进布隆过滤器，适合日志搜索；后者对字符串的所有 n-gram 进布隆过滤器，支持 `LIKE '%x%'`，代价是索引体积大得多。

9. **Doris 和 StarRocks 的显式 bloom filter index 基于表属性**（`"bloom_filter_columns"` + `"bloom_filter_fpp"`），而非 `CREATE INDEX` 语句。粒度为 data page / segment，类型限制排除低基数和浮点类型。

10. **Databricks Delta Lake 提供独立的 `CREATE BLOOMFILTER INDEX` 语法**（2020 年），按 Delta data file（Parquet）级别建立，与 Z-Order + data skipping stats 三件套配合使用。

11. **Snowflake 的微分区元数据暗含布隆过滤器**——官方未公开具体格式，但 EXPLAIN 和专利显示 equality pruning 的核心就是布隆过滤器。这是完全透明的自动化，用户无法配置。

12. **MySQL / MariaDB 完全不支持布隆过滤器**——既没有显式语法也没有运行时下推（MySQL 8.0 的 hash join 实现不用布隆过滤器）。MyRocks（MySQL + RocksDB 引擎）是例外，通过 RocksDB 自动获得 SST 级别的 bloom filter。

13. **Split Block Bloom Filter（SBBF）是现代实现的主流**：Parquet、ClickHouse 的最新版本、Apache Impala 都采用。核心优势是 **每次 contains() 只访问一条 cache line**，配合 SIMD / AVX-512 可以在 GB/s 吞吐下完成过滤。

14. **布隆过滤器 vs Ribbon Filter**：RocksDB 6.15+ 引入 Ribbon Filter，在相同 FP 率下比标准布隆过滤器节省 ~30% 空间，代价是构建时间稍慢。这是 LSM 空间优化的新方向。

15. **典型配置经验**：
    - RocksDB 系：`10 bits/key`，约 1% 假阳性率
    - Cassandra STCS/TWCS：`bloom_filter_fp_chance = 0.01`
    - Cassandra LCS：`bloom_filter_fp_chance = 0.1`（LCS 点查只读 1-2 个 SSTable，不需要精确过滤器）
    - Parquet：根据 NDV 估算，默认 1%
    - ClickHouse `bloom_filter`：默认 0.025
    - Doris / StarRocks：默认 0.05

16. **布隆过滤器的根本局限**：只支持等值（`=`、`IN`），不支持范围（`<`、`>`、`BETWEEN`）。范围查询要依赖 min/max skip index 或 zone map。实际生产里布隆过滤器几乎总是与 min/max 配合使用。

17. **假阳性率 vs 内存 vs 哈希数的权衡公式**（Bloom 1970）：
    - `m = -n * ln(p) / ln(2)^2`（比特数）
    - `k = (m/n) * ln(2)`（最优哈希数）
    - `n=1M, p=0.01 → m ≈ 1.2 MB, k ≈ 7`
    - 这个公式从 1970 年至今没变过，所有实现都在这个框架内优化常数因子。

18. **布隆过滤器发明人 Burton Howard Bloom**于 1970 年在 CACM 发表《Space/Time Trade-offs in Hash Coding with Allowable Errors》，最初动机是拼写检查器——55 年后，它成为了从 Cassandra 到 Snowflake 的万亿美元数据基础设施的基石。

## 参考资料

- Bloom, B.H. "Space/time trade-offs in hash coding with allowable errors". Communications of the ACM, 13(7), 1970.
- Putze, Sanders, Singler. "Cache-, Hash- and Space-Efficient Bloom Filters". WEA 2007 (Split Block Bloom Filter)
- Dillinger, Manolios. "Bloom Filters in Probabilistic Verification". FMCAD 2004 (double hashing)
- PostgreSQL: [bloom — bloom filter index access method](https://www.postgresql.org/docs/current/bloom.html)
- ClickHouse: [Data Skipping Indexes](https://clickhouse.com/docs/en/engines/table-engines/mergetree-family/mergetree#table_engine-mergetree-data_skipping-indexes)
- Apache Parquet: [Bloom Filter format v2.10](https://github.com/apache/parquet-format/blob/master/BloomFilter.md)
- Apache ORC: [Indexes (Bloom Filter)](https://orc.apache.org/specification/ORCv1/)
- Oracle: "Bloom Filters in Oracle Database 10g" (Oracle Whitepaper, 2005)
- Apache Impala: [Runtime Filtering](https://impala.apache.org/docs/build/html/topics/impala_runtime_filtering.html)
- Apache Spark: [Runtime Filter in AQE (SPARK-32268)](https://issues.apache.org/jira/browse/SPARK-32268)
- Trino: [Dynamic filtering](https://trino.io/docs/current/admin/dynamic-filtering.html)
- Databricks: [Bloom Filter Indexes](https://docs.databricks.com/en/optimizations/bloom-filters.html)
- Apache Cassandra: [Bloom Filters](https://cassandra.apache.org/doc/latest/cassandra/operating/bloom_filters.html)
- RocksDB: [Full Filter Block](https://github.com/facebook/rocksdb/wiki/RocksDB-Bloom-Filter)
- Apache Doris: [Bloom Filter Index](https://doris.apache.org/docs/table-design/index/bloomfilter/)
- StarRocks: [Bloom Filter Indexing](https://docs.starrocks.io/docs/table_design/indexes/Bloomfilter_index/)
- Apache Hive: [ORC File Format — Bloom Filter](https://cwiki.apache.org/confluence/display/Hive/LanguageManual+ORC)
- Graf, Lemire. "Xor Filters: Faster and Smaller Than Bloom and Cuckoo Filters" (2019)
