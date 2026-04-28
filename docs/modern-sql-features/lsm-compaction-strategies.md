# LSM 合并策略 (LSM Compaction Strategies)

LSM 的本质矛盾不在于"是否合并"，而在于"如何合并"——合并策略决定了写放大、空间放大、读放大三者的取舍曲线，而 RocksDB / Cassandra / HBase / ScyllaDB 等引擎在过去十五年里探索了几乎所有可能的合并算法。Leveled、Tiered、FIFO、TimeWindow 这四种主流策略代表了 LSM 工业实践中沉淀下来的智慧，理解它们才能真正读懂现代分布式数据库的存储层设计。

## 写放大、空间放大、读放大的根本权衡

LSM 通过把所有写入转化为顺序写赢得了惊人的写吞吐量，但 MemTable 转储下来的 SSTable 数量会无限增长——如果不合并，一次点查可能要遍历数百个 SSTable，范围扫描更是灾难。合并不是可选项，而是 LSM 的生存必需。问题在于：合并本身要写、要读、要占用 IO 带宽，合并策略的选择直接决定了三类放大的曲线形状。

### Lemire RUM 三角与 LSM 合并

2016 年 Boston University 的 Manos Athanassoulis 等人在论文 *"Designing Access Methods: The RUM Conjecture"*（EDBT 2016）中正式提出了 RUM 三角猜想。LSM 合并策略的选择本质上就是在这个三角形上选择具体的位置：

- **写放大（Write Amplification, WA）**：实际写入磁盘字节 / 用户逻辑写入字节。Leveled 通常 10-30x，Tiered 通常 2-10x，FIFO 接近 1x
- **读放大（Read Amplification, RA）**：一次查询实际读取的页面数 / 期望读取的页面数。Leveled 因层间不重叠所以读放大低；Tiered 因每层多个 SSTable 所以读放大高
- **空间放大（Space Amplification, SA）**：磁盘实际占用 / 数据逻辑大小。Leveled 接近 1.1x，Tiered 可能高达 2-3x（同 key 在多个 SSTable 中存在不同版本）

合并策略的选择就是在这三者之间画一条曲线：你不能同时优化全部三个维度。Daniel Lemire 在他关于性能工程的多次演讲中也强调过类似的三角约束——这是物理层面的限制，不是工程问题。

### 三类放大在 LSM 各阶段的体现

```
写入路径:
  Client → WAL → MemTable → flush → L0 SSTable
  这一步 WA = 1 (WAL) + 1 (memtable flush) ≈ 2x

合并路径 (Leveled, fanout=10):
  L0 → L1: 1 个 L0 SSTable + 约 10 个 L1 SSTable 一起重写 → WA += 10
  L1 → L2: 1 个 L1 SSTable + 约 10 个 L2 SSTable → WA += 10
  ...重复 6 层: 总 WA ≈ 60 (理论最坏); 实际生产 10-30x

合并路径 (Tiered, factor=4):
  累积 4 个相近大小的 SSTable → 合并为 1 个更大的 → WA += 1
  每个数据点会被合并 log_4(数据总量 / 起始 SSTable 大小) 次
  约 5-7 次合并 → 实际生产 2-10x
```

## 没有 SQL 标准

合并策略完全是引擎实现细节，SQL 标准（ISO/IEC 9075）从未涉及——标准只关注 SELECT/INSERT 等语言层面，对存储层的物理组织保持沉默。这意味着：

1. **配置语法各引擎完全不同**：Cassandra 用 `WITH compaction = {'class': 'LeveledCompactionStrategy'}`，RocksDB 用 options 文件或 SetOptions API，HBase 用 `hbase-site.xml`
2. **概念命名不统一**：RocksDB 称 "Universal" Compaction，Cassandra 称 "SizeTieredCompactionStrategy" (STCS)，HBase 早期称 "DefaultCompactionPolicy"，但本质都是 Tiered
3. **手动触发命令五花八门**：RocksDB `CompactRange()` API，Cassandra `nodetool compact`，HBase `major_compact 'table'` shell 命令，ClickHouse `OPTIMIZE TABLE ... FINAL`
4. **可观测性接口缺失**：标准没有规定如何查询当前合并状态、SSTable 数量、写放大指标——每个引擎自己提供 system 表或 JMX/HTTP 端点

这种碎片化使得跨引擎迁移和能力对比格外困难，也是本文要尝试梳理的核心动机。

## 综合支持矩阵 (45+ 引擎)

下表覆盖 45+ 主流数据库 / 存储引擎对各类合并策略的支持。说明：

- "默认" 表示开箱即用的策略；"可选" 表示需要显式配置；"--" 表示不支持
- 行存 OLTP（PG/MySQL/Oracle 等）使用 B+Tree，没有合并概念；为完整性也列出（仅作为参照）

### Leveled 与 Tiered 合并策略支持

| 引擎 | 底层存储 | Leveled | Tiered/Universal | FIFO | TimeWindow | 默认策略 | 可调 | 手动 COMPACT |
|------|---------|---------|------------------|------|-----------|---------|------|-------------|
| RocksDB | LSM | 默认 | 是（Universal）| 是 | -- | Leveled | 是 | `CompactRange()` |
| LevelDB | LSM | 默认 | -- | -- | -- | Leveled（唯一）| -- | `CompactRange()` |
| Pebble (CockroachDB) | LSM | 默认 | -- | -- | -- | Leveled（唯一）| 部分参数 | `Compact()` API |
| Cassandra | LSM | LCS | STCS（默认）| -- | TWCS | STCS | 表级 | `nodetool compact` |
| ScyllaDB | LSM | 是 | 是 | -- | TWCS | STCS | 表级 + Incremental | `nodetool compact` |
| HBase | LSM | -- | Stripe / Exploring | -- | Date Tiered | Exploring | RegionServer 级 | `major_compact` |
| TiDB / TiKV | RocksDB | 默认 | 可选 | -- | -- | Leveled | 是 | `tikv-ctl compact` |
| YugabyteDB DocDB | RocksDB fork | 是 | 是 | -- | -- | 默认 Leveled | 是 | API |
| MyRocks | RocksDB | 默认 | 可选 | -- | -- | Leveled | 是 | RocksDB API |
| MongoDB WiredTiger | LSM 或 B+Tree | 不分层 | -- | -- | -- | -- | -- | `compact` 命令 |
| ClickHouse | MergeTree | 类 Leveled | -- | -- | TTL TO/MOVE | 后台 merge pool | 是 | `OPTIMIZE` |
| Druid | 段存储 | 段合并 | -- | -- | 时间分片 | 后台 task | 是 | `compact` task |
| Pinot | 段存储 | minion 合并 | -- | -- | -- | 后台 minion | 是 | minion task |
| InfluxDB | TSM | -- | -- | -- | TSM 时间分层 | TSM | 部分 | -- |
| Elasticsearch | Lucene 段 | -- | 段合并 | -- | ILM rollover | 段合并 | 是 | `_forcemerge` |
| OpenSearch | Lucene 段 | -- | 段合并 | -- | ISM rollover | 段合并 | 是 | `_forcemerge` |
| Solr | Lucene 段 | -- | TieredMergePolicy | -- | -- | TieredMergePolicy | 是 | `optimize` |
| Lucene | 段 | -- | TieredMergePolicy（默认）| -- | -- | TieredMergePolicy | 是 | API |
| Kafka | LogSegments | -- | log compaction | -- | TimeBased | TimeBased | 是 | -- |
| OceanBase | LSM 变体 | -- | -- | -- | 每日 major freeze | major+minor freeze | 否（系统调度）| `ALTER SYSTEM MAJOR FREEZE` |
| RisingWave Hummock | LSM (S3) | 默认 | -- | -- | -- | Leveled | 是 | -- |
| CrateDB | Lucene 段 | -- | 段合并 | -- | -- | TieredMergePolicy | 是 | `OPTIMIZE TABLE` |
| Greenplum AO/AOCO | 追加优化 | -- | -- | -- | -- | -- | -- | `VACUUM` |
| StarRocks | 段存储 | base+cumulative | -- | -- | -- | base+cumulative | 是 | -- |
| Doris | 段存储 | base+cumulative | -- | -- | -- | base+cumulative | 是 | -- |
| TimescaleDB | PG + chunks | -- | -- | -- | chunk 时间分区 | 时间分块 | 是 | `add_compression_policy` |
| QuestDB | append 列存 | -- | -- | -- | partition by time | 时间分区 | 否 | `ALTER TABLE ... DROP PARTITION` |
| Vertica | ROS/WOS | -- | mergeout (类 tiered) | -- | -- | mergeout | 是 | `DO_TM_TASK('mergeout')` |
| SAP HANA | delta+main | -- | delta merge | -- | -- | delta+main | 是 | `MERGE DELTA OF` |
| Snowflake | 微分区 | -- | -- | -- | -- | 不可见（云托管）| 否 | -- |
| BigQuery | Capacitor | -- | -- | -- | -- | 不可见（云托管）| 否 | -- |
| Redshift | 列式块 | -- | -- | -- | -- | -- | -- | `VACUUM` |
| DuckDB | 行组列存 | -- | -- | -- | -- | -- | -- | -- |
| SingleStore | rowstore + columnstore | columnstore 段合并 | -- | -- | -- | -- | 部分 | `OPTIMIZE TABLE` |
| Spanner | Ressi（LSM 变体）| -- | -- | -- | -- | -- (托管) | 否 | -- |
| FoundationDB | Redwood (B+Tree) | -- | -- | -- | -- | -- | -- | -- |
| etcd | bbolt (B+Tree) → Pebble (实验) | -- | -- | -- | -- | -- | -- | -- |
| Aerospike | 混合 | -- | defrag | -- | -- | defragmenter | 是 | -- |
| Riak | LevelDB / Bitcask | LevelDB Leveled | -- | -- | -- | 视后端 | -- | -- |
| Couchbase | Magma / Couchstore | Magma 类 LSM | -- | -- | -- | append-only | -- | `compact` |
| Apache Kudu | 列存 LSM | -- | -- | -- | -- | merge | 是 | -- |
| Apache Iceberg | 表格式 (元数据) | -- | rewriteDataFiles | -- | -- | -- | 是 | `REWRITE DATA FILES` |
| Apache Hudi | COW / MOR | MOR 合并 | -- | -- | -- | MOR | 是 | `RUN COMPACTION` |
| Delta Lake | Parquet + log | -- | OPTIMIZE | -- | -- | OPTIMIZE | 是 | `OPTIMIZE` |
| Spark SQL (on Iceberg/Hudi/Delta) | 表格式 | 通过表格式 | -- | -- | -- | -- | 是 | `OPTIMIZE` / `CALL` |

> 注：约 30 个系统提供某种形式的合并/压缩控制；纯 B+Tree 引擎（PostgreSQL、MySQL InnoDB、Oracle、SQL Server、DB2、SQLite、MariaDB、Informix、Firebird、H2、HSQLDB、Derby）没有 LSM 合并概念，只有 VACUUM / OPTIMIZE TABLE / 检查点等空间回收机制。

### 手动 COMPACT / OPTIMIZE 命令对照

| 引擎 | 触发命令 | 作用 |
|------|---------|------|
| RocksDB | `db->CompactRange(options, begin, end)` | 强制合并指定 key 范围 |
| Cassandra | `nodetool compact [keyspace] [table]` | 触发主合并（major compaction）|
| ScyllaDB | `nodetool compact` | 触发主合并 |
| HBase | `major_compact 'table'` (HBase shell) | 把所有 HFile 合并为一个 |
| ClickHouse | `OPTIMIZE TABLE name [PARTITION p] [FINAL]` | 强制合并 part；FINAL 合并到只剩一个 part |
| Elasticsearch | `POST /index/_forcemerge?max_num_segments=1` | 强制合并段 |
| OpenSearch | `POST /index/_forcemerge?max_num_segments=1` | 同 ES |
| Solr | `solrctl ... optimize` 或 API `optimize` | 合并所有段 |
| TiKV | `tikv-ctl --host ip:port compact -r region_id` | 强制合并指定 region |
| MongoDB | `db.runCommand({compact: 'collection'})` | 整理碎片，回收空间 |
| Hudi | `CALL run_compaction(table => 'tbl')` (Spark SQL) | 触发 MOR 合并 |
| Iceberg | `CALL system.rewrite_data_files('tbl')` | 重写小文件 |
| Delta Lake | `OPTIMIZE tbl [WHERE pred] [ZORDER BY (cols)]` | 合并小文件 + 可选 Z-order |
| OceanBase | `ALTER SYSTEM MAJOR FREEZE` | 触发集群级 major 合并 |
| StarRocks | 通过 `BE` 配置自动；可手动通过 admin API | 触发 base/cumulative compaction |
| Doris | `ADMIN COMPACT TABLE tbl` | 手动合并 |
| Vertica | `SELECT DO_TM_TASK('mergeout');` | 手动触发 mergeout |
| SAP HANA | `MERGE DELTA OF tbl` | 手动 delta-to-main 合并 |
| CrateDB | `OPTIMIZE TABLE tbl WITH (max_num_segments = 1)` | Lucene 强制合并 |

> 经验法则：手动触发 major compaction 仅在维护窗口或迁移场景使用，正常生产环境应让后台合并自然进行，否则会造成 IO 风暴。

### TTL 与时间窗口策略支持

| 引擎 | TTL 机制 | 时间窗口合并 |
|------|---------|------------|
| Cassandra | `WITH default_time_to_live = N` | TWCS（3.0.8/3.8 引入）|
| ScyllaDB | 同 Cassandra | TWCS（继承自 Cassandra）|
| HBase | `TTL` 列族属性 | Date Tiered Compaction |
| RocksDB | TTL Compaction Filter（用户自定义）| FIFO + TTL |
| ClickHouse | `TTL` 列/表达式 | TTL `MOVE TO`/`DELETE`/`GROUP BY` |
| InfluxDB | retention policy | TSM 时间分层 |
| TimescaleDB | `add_retention_policy()` | chunk 按时间分区 |
| Elasticsearch | ILM (Index Lifecycle Management)| rollover + delete |
| OpenSearch | ISM (Index State Management)| rollover + delete |
| Druid | retention rules | 时间分片 |
| Pinot | segment retention config | 时间分片 |
| Kafka | `log.retention.ms` | 时间/大小双触发 |
| Hudi | retention config | -- |

## 各引擎的合并实现剖析

### RocksDB：Leveled、Universal、FIFO 三套并存

RocksDB 是 LSM 工业化的标杆，由 Facebook 在 2012 年从 Google 的 LevelDB fork 而来。它同时支持三种主要合并策略，是少有的把所有主流策略集于一身的引擎。

#### Leveled Compaction（默认）

RocksDB 的默认策略，结构与 LevelDB 一致但参数更灵活：

```
L0: 多个 SSTable（key 范围可重叠）
L1: 总大小 max_bytes_for_level_base（默认 256MB）
L2: 总大小 = L1 × max_bytes_for_level_multiplier (默认 10)
L3: 总大小 = L2 × 10
...
L6: 总大小 = L5 × 10 (默认最深 7 层)
```

触发条件：

- **L0 → L1**：L0 文件数达到 `level0_file_num_compaction_trigger`（默认 4）
- **Ln → Ln+1（n>=1）**：Ln 总大小超过 `target_file_size_base × multiplier^(n-1)` 时

合并算法：

1. 选择 Ln 中"最优"的一个 SSTable（按 score 排序，score = 当前大小 / 目标大小）
2. 找出 Ln+1 中所有与该 SSTable key range 重叠的 SSTable
3. 把它们一起读出，归并去重，按目标 SSTable 大小切分写回 Ln+1

```
RocksDB Leveled 写放大（理论上界）:
WA = 1 (WAL) + 1 (memtable flush) + Σ_{i=1..n} fanout_i
   = 2 + 10 × 6 = 62 (默认配置最坏情况)
   生产实测约 10-30x
```

关键配置：

```ini
# RocksDB options 文件
[CFOptions "default"]
  # 选择 leveled
  compaction_style = kCompactionStyleLevel
  # 每层倍率
  max_bytes_for_level_multiplier = 10
  # L1 大小
  max_bytes_for_level_base = 268435456   # 256MB
  # 单个 SSTable 大小
  target_file_size_base = 67108864       # 64MB
  # L0 触发合并的文件数
  level0_file_num_compaction_trigger = 4
  # L0 减速阈值
  level0_slowdown_writes_trigger = 20
  # L0 停止阈值
  level0_stop_writes_trigger = 36
```

#### Universal Compaction (Tiered)

RocksDB 对 Tiered 策略的实现，更适合写密集场景：

```
所有数据保持在 L0（概念上）
新 SSTable 进来时，按文件大小分组
组内文件数达到阈值时合并为更大的 SSTable
```

触发条件（Universal 有多个）：

1. **空间放大**：`(总大小 - 最大 SSTable) / 最大 SSTable > level0_file_num_compaction_trigger / 100`
2. **文件数**：所有 sorted run 数达到 `level0_file_num_compaction_trigger`
3. **大小比**：相邻 sorted run 大小差异超过 `compaction_options_universal.size_ratio`

```ini
[CFOptions "default"]
  compaction_style = kCompactionStyleUniversal
  level0_file_num_compaction_trigger = 4
  
[Universal CompactionOptions]
  size_ratio = 1                  # 相邻 run 大小差异容忍度（百分比）
  min_merge_width = 2             # 最少合并 2 个 run
  max_merge_width = 4294967295    # 最多合并的 run 数（默认无限）
  max_size_amplification_percent = 200  # 最大允许空间放大 200%
  compression_size_percent = -1   # 压缩比例
```

性能特点：

- 写放大：约 2-10x（明显低于 Leveled）
- 空间放大：可能高达 2-3x（同 key 多版本）
- 读放大：高（需要扫描所有 sorted run）

#### FIFO Compaction

最简单的策略，专为时序日志设计：

```
新 SSTable → flush 到 L0
所有 SSTable 按创建时间排序
当总大小超过 max_table_files_size 时，删除最旧的 SSTable
完全没有合并，只有删除
```

```ini
[CFOptions "default"]
  compaction_style = kCompactionStyleFIFO
  
[FIFO CompactionOptions]
  max_table_files_size = 1073741824  # 1GB；超过则删除最旧
  ttl = 86400                         # 可选：24 小时 TTL
  allow_compaction = false            # 是否允许小文件合并
```

特点：

- 写放大：~1x（除 WAL 外没有任何重写）
- 空间稳定：固定上限
- 适用场景：日志、监控、时序，数据有明确 TTL 且不需要更新

### Cassandra：STCS、LCS、TWCS、DTCS 四代演进

Cassandra 在合并策略上走在了所有 LSM 数据库前面，几乎所有现代合并思想都最先在 Cassandra 中实现并验证。

#### STCS (SizeTieredCompactionStrategy) - 默认

Cassandra 自 0.6 版本以来的默认策略，本质就是 Tiered：

```cql
-- Cassandra 创建表时指定 STCS（也是默认）
CREATE TABLE events (
    user_id UUID,
    event_id TIMEUUID,
    payload TEXT,
    PRIMARY KEY (user_id, event_id)
) WITH compaction = {
    'class': 'SizeTieredCompactionStrategy',
    'min_threshold': 4,           -- 至少 4 个 SSTable 才合并
    'max_threshold': 32,          -- 一次最多合并 32 个
    'bucket_low': 0.5,            -- 大小相似度下限
    'bucket_high': 1.5,           -- 大小相似度上限
    'min_sstable_size': 50        -- 50MB 以下文件视为同一桶
};
```

工作原理：

1. 把 SSTable 按大小分桶（bucket），同一桶内文件大小相近
2. 当某桶 SSTable 数达到 `min_threshold` 时，把整个桶合并为一个新 SSTable
3. 新 SSTable 进入更大的桶

特点：

- 写放大低：每条数据被合并 log_N(总数据量 / SSTable 大小) 次
- 空间放大可能严重：合并过程中需要 2 倍空间（旧文件 + 新文件并存）
- 读延迟有抖动：单点查询可能需要查询多个 SSTable

#### LCS (LeveledCompactionStrategy) - 1.0 引入 (2011)

为解决 STCS 的读放大和空间放大问题，Cassandra 1.0（2011 年）引入 LCS：

```cql
CREATE TABLE events_lcs (
    user_id UUID PRIMARY KEY,
    payload TEXT
) WITH compaction = {
    'class': 'LeveledCompactionStrategy',
    'sstable_size_in_mb': 160,         -- 单个 SSTable 大小
    'fanout_size': 10,                  -- 每层倍率
    'tombstone_threshold': 0.2,         -- tombstone 比例触发额外合并
    'tombstone_compaction_interval': 86400
};
```

LCS 的层结构：

```
L0: 新 flush 的 SSTable（可重叠）
L1: 总大小 = sstable_size × fanout = 1.6GB
L2: 总大小 = L1 × fanout = 16GB
L3: 总大小 = L2 × fanout = 160GB
...
```

适用场景：

- 单点读密集（key-value 工作负载）
- 数据更新频繁（同 key 多次更新需要合并去重）
- 空间敏感（LCS 空间放大约 1.1x）

代价：

- 写放大显著高于 STCS（约 10-30x vs 2-10x）
- 后台 IO 持续，可能影响业务延迟

#### TWCS (TimeWindowCompactionStrategy) - 3.0.8/3.8 引入 (2016)

为时序数据设计的策略，2016 年随 Cassandra 3.0.8 / 3.8 正式引入主线（更早作为 contrib 存在）：

```cql
CREATE TABLE metrics (
    metric_name TEXT,
    bucket TIMESTAMP,
    timestamp TIMESTAMP,
    value DOUBLE,
    PRIMARY KEY ((metric_name, bucket), timestamp)
) WITH compaction = {
    'class': 'TimeWindowCompactionStrategy',
    'compaction_window_unit': 'DAYS',     -- 时间单位
    'compaction_window_size': 1,          -- 窗口大小（1 天）
    'expired_sstable_check_frequency_seconds': 600,
    'tombstone_threshold': 0.2
};
```

工作原理：

1. SSTable 按写入时间分配到对应时间窗口（如每天一个）
2. 同一时间窗口内的 SSTable 用 STCS 合并
3. 跨时间窗口的 SSTable 不合并
4. 达到 TTL 的整个时间窗口直接删除（无合并开销）

适用场景：

- IoT、监控、日志等时序数据
- 数据按时间到达，按时间过期
- 不需要更新历史数据

性能特点：

- 写放大：约 2-5x（仅在窗口内合并）
- 删除高效：整段删除，无 tombstone 累积
- 旧数据查询慢：需要访问多个 SSTable

#### DTCS (DateTieredCompactionStrategy) - 已弃用

DTCS 是 TWCS 的前身（约 2014 年引入），但因为复杂的"窗口分裂"逻辑导致严重的合并问题。**自 Cassandra 3.0.8 / 3.8 起被官方标记为弃用，推荐使用 TWCS 替代**。现代部署中不应使用 DTCS。

### ScyllaDB：增量合并 (Incremental Compaction)

ScyllaDB 是 Cassandra 的 C++ 重写版本（API 兼容），但在合并策略上做了大量创新。最重要的是 **Incremental Compaction Strategy (ICS)**，3.1 版本引入：

```cql
-- ScyllaDB 创建表使用 ICS
CREATE TABLE events (
    user_id UUID PRIMARY KEY,
    payload TEXT
) WITH compaction = {
    'class': 'IncrementalCompactionStrategy',
    'min_threshold': 4,
    'sstable_size_in_mb': 1000,
    'space_amplification_goal': 1.5      -- 目标空间放大
};
```

设计动机：传统 STCS 在合并大 SSTable 时需要 2 倍磁盘空间（旧 + 新并存），对存储密集型部署是致命问题。

ICS 的核心：

1. 把每个"概念上的大 SSTable"切分成多个小的"片段"（fragment）
2. 合并时只读写涉及的片段，不需要重写整个 SSTable
3. 显著降低合并所需的临时空间（从 100% → 几个 GB）

性能特点（来自 ScyllaDB 官方对比）：

- 临时空间需求：从原始 SSTable 大小 → 几 GB（数十倍降低）
- 写放大：与 STCS 接近（~3-5x）
- 适合超大节点（10TB+ 数据）

### HBase：Major、Minor、Stripe、Date Tiered

HBase 的合并术语与其他 LSM 引擎不同，分为 Minor 和 Major 两个层次：

#### Minor Compaction（小合并）

```
触发条件: 某个 region 的 HFile 数量达到 hbase.hstore.compactionThreshold (默认 3)
作用: 选择若干个相邻的小 HFile 合并为一个大 HFile
特点: 不删除已标记为 deleted 的数据，不处理过期 TTL
频率: 频繁，对性能影响小
```

#### Major Compaction（大合并）

```
触发条件: 
  - 定时（默认 7 天一次）
  - 手动（major_compact 命令）
  - 自动（满足特定条件，如 store size 增长）

作用: 把 region 内所有 HFile 合并为一个 HFile
关键: 这是真正的"全量重写" - 整个 region 的所有数据都要被读出、归并、写回
特点:
  - 真正删除标记为 deleted 的数据
  - 真正删除过期 TTL 数据
  - 真正应用 version 限制（如 max versions = 3 时，删除多余版本）
代价: 极重的 IO 操作；生产环境通常关闭自动 major compaction，改为低峰期手动触发
```

```bash
# HBase shell 触发 major compaction
hbase> major_compact 'tablename'
hbase> major_compact 'tablename', 'cf1'      # 仅特定列族

# 检查合并进度
hbase> compaction_state 'tablename'
```

```xml
<!-- hbase-site.xml 配置 -->
<property>
  <name>hbase.hregion.majorcompaction</name>
  <value>0</value>  <!-- 0 = 关闭自动 major compaction -->
</property>
<property>
  <name>hbase.hstore.compactionThreshold</name>
  <value>3</value>  <!-- minor compaction 触发文件数 -->
</property>
<property>
  <name>hbase.hstore.compaction.max</name>
  <value>10</value>  <!-- 单次 minor compaction 最多文件数 -->
</property>
```

#### Stripe Compaction

为大 region 设计：把 row key 范围水平切分为多个"条带"（stripe），每个 stripe 内独立合并。类似把一个大 region 当作多个小 region 处理。适合 row key 写入分布均匀的场景。

#### Date Tiered Compaction

HBase 0.98+ 引入，与 Cassandra TWCS 类似，按时间窗口分组合并。适合时序数据。

### LevelDB：永远 Leveled

LevelDB 是 Google 在 2011 年开源的嵌入式 LSM 库，由 Sanjay Ghemawat 和 Jeff Dean（GFS / BigTable / MapReduce 的设计者）开发。它是 RocksDB 的祖先，但只支持一种合并策略：**Leveled（且不可配置）**。

```
LevelDB 的层结构（与 RocksDB Leveled 几乎一致）:
L0: 4 个 file 触发合并
L1: 10MB
L2: 100MB
L3: 1GB
L4: 10GB
L5: 100GB
L6: 1TB
```

LevelDB 的设计哲学是"简洁优于灵活"——只支持一种策略意味着代码简单、易于嵌入、行为可预测。这也是它至今仍被许多嵌入式场景（Chrome IndexedDB、比特币节点）使用的原因。

### ClickHouse MergeTree：后台 Pool 驱动的合并

ClickHouse MergeTree 严格说不是标准 LSM（没有独立 memtable，是按批 immutable 写入），但它的合并模型与 LSM 同源。

```sql
CREATE TABLE events (
    user_id UInt64,
    event_time DateTime,
    event_type String,
    payload String
) ENGINE = MergeTree
PARTITION BY toYYYYMM(event_time)
ORDER BY (user_id, event_time)
SETTINGS
    merge_with_ttl_timeout = 86400,
    max_parts_in_total = 100000,
    parts_to_throw_insert = 300,        -- part 数超过 300 时拒绝插入
    parts_to_delay_insert = 150;        -- part 数超过 150 时减速
```

#### ClickHouse 合并的关键特征

1. **由背景 merge pool 驱动**：每个表的合并是后台任务，由全局的 merge thread pool 调度
2. **分区内合并**：跨分区的 part 不合并；这与 RocksDB 跨 SSTable 合并不同
3. **immutable parts**：每个 part 是不可变的列存目录，新数据 → 新 part → 后台合并
4. **OPTIMIZE TABLE 强制合并**：

```sql
-- 触发分区内的合并
OPTIMIZE TABLE events;

-- 强制合并整个分区到一个 part
OPTIMIZE TABLE events PARTITION '202604' FINAL;

-- 触发去重合并（要求 ENGINE = ReplacingMergeTree）
OPTIMIZE TABLE events_replacing FINAL;
```

#### TTL：基于时间的删除与移动

ClickHouse 把 TTL 集成到合并过程中，是 LSM 引擎中最强大的 TTL 实现：

```sql
CREATE TABLE events (
    user_id UInt64,
    event_time DateTime,
    payload String
) ENGINE = MergeTree
ORDER BY (user_id, event_time)
TTL event_time + INTERVAL 30 DAY,                              -- 30 天后删除行
    event_time + INTERVAL 7 DAY TO VOLUME 'cold',              -- 7 天后移动到冷存储
    event_time + INTERVAL 90 DAY GROUP BY user_id              -- 90 天后聚合
            SET payload = argMax(payload, event_time);
```

#### 后台合并 Pool 调优

```xml
<!-- ClickHouse config.xml -->
<background_pool_size>16</background_pool_size>
<background_merges_mutations_concurrency_ratio>2</background_merges_mutations_concurrency_ratio>
<background_schedule_pool_size>128</background_schedule_pool_size>
```

性能特点：

- 写放大：取决于 part 大小演进，通常 2-5x（远低于 RocksDB Leveled）
- 列存压缩：单列同质数据压缩率 5-20x
- 读延迟：依赖 part 数（每个 part 是独立的列存目录）

### TiDB / TiKV：基于 RocksDB 的工业部署

TiDB 的存储层 TiKV 直接使用 RocksDB（每个 TiKV 节点 1-2 个 RocksDB 实例：一个存数据，一个存 Raft log）。合并策略完全继承自 RocksDB：

```toml
# tikv.toml
[rocksdb.defaultcf]
compaction-style = "level"           # leveled
max-bytes-for-level-base = "512MB"
max-bytes-for-level-multiplier = 10
target-file-size-base = "8MB"
level0-file-num-compaction-trigger = 4
level0-slowdown-writes-trigger = 20
level0-stop-writes-trigger = 36

# Bloom Filter 配置
bloom-filter-bits-per-key = 10
bloom-filter-block-based = false     # 使用 full filter
optimize-filters-for-hits = false

# Titan（key-value 分离，用于大 value）
[rocksdb.titan]
enabled = false                       # 默认关闭，大 value 场景开启
min-blob-size = "1KB"
```

TiDB 的特殊点：

- **Region 分裂触发额外合并**：96MB region 分裂时需要重写
- **Raft log 单独 RocksDB 实例**：避免 raft log 合并干扰数据合并
- **手动 compaction**：

```bash
# tikv-ctl 手动 compact
tikv-ctl --host 127.0.0.1:20160 compact-cluster --bottommost force
tikv-ctl --host 127.0.0.1:20160 compact -d kv -c default --from <start_key> --to <end_key>
```

### CockroachDB Pebble：Go 原生 Leveled

Pebble 是 Cockroach Labs 在 2018 年开始开发，2020 年随 CockroachDB 20.1 替代 RocksDB 成为默认存储引擎的纯 Go LSM 库：

```go
// CockroachDB Pebble 配置（伪代码示例）
opts := &pebble.Options{
    Levels: []pebble.LevelOptions{
        {TargetFileSize: 2 << 20},        // L0: 2MB
        {TargetFileSize: 4 << 20},        // L1: 4MB
        {TargetFileSize: 8 << 20},        // L2: 8MB
        {TargetFileSize: 16 << 20},       // L3: 16MB
        {TargetFileSize: 32 << 20},       // L4: 32MB
        {TargetFileSize: 64 << 20},       // L5: 64MB
        {TargetFileSize: 128 << 20},      // L6: 128MB
    },
    MemTableSize:                 64 << 20,
    L0CompactionThreshold:        2,
    L0StopWritesThreshold:        12,
    LBaseMaxBytes:                64 << 20,
    MaxOpenFiles:                 16384,
}
```

Pebble 的设计特点：

1. **只支持 Leveled**：刻意舍弃了 Universal 和 FIFO（CRDB 的工作负载不需要）
2. **针对 MVCC 优化**：CRDB 大量使用范围扫描，Pebble 在 SSTable 索引、Bloom Filter、迭代器上都做了 MVCC 友好的优化
3. **完全 RocksDB 兼容**：SSTable 格式、WAL 格式与 RocksDB 完全兼容，可以无缝迁移
4. **Cgo 零开销**：纯 Go 实现，CockroachDB 的 Go 调用没有跨语言边界开销

### MyRocks：MySQL + RocksDB

MyRocks 是 Facebook 在 2016 年开发的 MySQL 存储引擎插件，底层是 RocksDB。合并策略完全是 RocksDB 的：

```sql
-- MyRocks 创建表
CREATE TABLE events (
    id BIGINT PRIMARY KEY,
    payload BLOB,
    ts BIGINT
) ENGINE=ROCKSDB;

-- 强制 compaction
SET GLOBAL rocksdb_force_flush_memtable_now=1;
SET GLOBAL rocksdb_compact_cf='default';

-- 查看 SSTable 状态
SELECT * FROM information_schema.ROCKSDB_DDL;
SELECT * FROM information_schema.ROCKSDB_CFSTATS;
```

Facebook 在 UDB（社交图谱核心数据库）的实测：MyRocks 相比 InnoDB 节省 50% 存储空间、写放大降低 3x、SSD 寿命延长 2.5x。

### Druid：段合并与 Compaction Task

Druid 的存储单元是 segment（段），每个 segment 是一个不可变的列存文件，按时间分片：

```
Datasource: events
├─ 2026-04-27 (interval)
│  ├─ shard_0_segment.smoosh
│  ├─ shard_1_segment.smoosh
│  └─ ...
├─ 2026-04-28
│  └─ ...
```

Druid 的合并模型：

1. **实时摄入**：流式摄入产生大量小 segment（"sub-segment"）
2. **后台 compaction task**：定期把同一时间段的小 segment 合并为大 segment
3. **配置示例**：

```json
{
  "type": "compact",
  "dataSource": "events",
  "interval": "2026-04-01/2026-04-30",
  "tuningConfig": {
    "type": "index_parallel",
    "maxRowsPerSegment": 5000000,
    "maxNumConcurrentSubTasks": 4
  },
  "granularitySpec": {
    "segmentGranularity": "DAY",
    "queryGranularity": "MINUTE"
  }
}
```

Druid Coordinator 自动调度 compaction task；也可通过 API 手动触发。

### Pinot：Minion 驱动的段合并

LinkedIn 开源的 Pinot 类似 Druid，使用 segment 模型。合并由 Minion（独立的合并 worker）执行：

```json
{
  "tableName": "events",
  "tableType": "REALTIME",
  "task": {
    "taskTypeConfigsMap": {
      "MergeRollupTask": {
        "bucketTimePeriod": "1d",
        "bufferTimePeriod": "1d",
        "1d.mergeType": "concat",
        "1d.maxNumRecordsPerSegment": "5000000"
      }
    }
  }
}
```

Pinot 的 Minion 框架支持多种 task：

- **MergeRollupTask**：合并小段，按时间 rollup 聚合
- **RealtimeToOfflineSegmentsTask**：实时段转离线段
- **SegmentGenerationAndPushTask**：从 batch 数据生成段

### InfluxDB TSM：时间序列专用的分层合并

InfluxDB 1.x 使用 TSM（Time-Structured Merge Tree）引擎，专为时序数据设计：

```
TSM 文件结构（按时间分层）:
Level 0: 实时摄入的 WAL → 转储为 TSM file
Level 1: 同一时间段的 Level 0 文件合并
Level 2: 更长时间段的 Level 1 文件合并
Level 3: 最大的 TSM 文件，长期存储

合并触发: 每层文件数达到阈值
合并策略: 同一时间段优先合并（类似 TWCS 思想）
```

特点：

- **时间作为一等公民**：所有合并都按时间窗口组织
- **shard 自动按时间切分**：与 retention policy 配合，过期 shard 整体删除
- **压缩高效**：列存 + 时间序列特定编码（delta encoding、Gorilla 压缩）

```sql
-- InfluxDB retention policy（控制数据生命周期）
CREATE RETENTION POLICY "30d" ON "telegraf"
DURATION 30d REPLICATION 1 DEFAULT;

-- 创建 continuous query 做下采样（相当于带 GROUP BY 的合并）
CREATE CONTINUOUS QUERY "cq_30m" ON "telegraf"
BEGIN
    SELECT mean("value") INTO "downsampled"
    FROM "metrics" GROUP BY time(30m), *
END;
```

InfluxDB 2.x 引入了新的 IOx 存储引擎（基于 Arrow + Parquet + DataFusion），合并模型有所改变，但 TSM 在 1.x 系列仍是事实标准。

### Elasticsearch / OpenSearch / Solr / Lucene：段合并

虽然不是传统 SQL 引擎，Lucene 系是另一个采用 LSM 思想的重要分支：

```
Lucene 段（segment）模型:
新文档 → 索引 buffer → flush 为 segment
后台 merger → 合并相邻段
触发条件: 段数量、段大小比、deletion 比例

TieredMergePolicy（Lucene 默认）:
- 类似 RocksDB Universal
- 按段大小分层，组内合并
- max_merged_segment 控制最大段大小
```

```bash
# Elasticsearch 强制合并
POST /index_name/_forcemerge?max_num_segments=1

# 仅合并 deletion 比例高的段
POST /index_name/_forcemerge?only_expunge_deletes=true
```

### OceanBase：每日 Major Freeze 模型

OceanBase 是 LSM 设计的一个独特变体，把合并集中在固定时间点：

```
基线数据 (baseline): 磁盘上的 SSTable
增量数据 (delta): 内存中的 memtable + 部分 SSTable

每日合并周期:
00:00 - 02:00 (低峰期): 集群级 major freeze
   - 所有节点冻结当前 memtable
   - 触发增量与基线的合并
   - 生成新的基线文件

白天: minor freeze 定期发生
   - memtable 满了 → 转储为 minor SSTable
   - 不与基线合并，仅作为增量
```

```sql
-- OceanBase 手动触发 major freeze
ALTER SYSTEM MAJOR FREEZE;

-- 查看合并进度
SELECT * FROM oceanbase.CDB_OB_MAJOR_COMPACTION;
```

设计动机：传统 RocksDB 的"持续后台合并"会造成 IO 抖动，对银行核心系统这种延迟敏感的 OLTP 是不可接受的。OceanBase 把合并集中在低峰期，白天的 OLTP 几乎没有合并干扰。

代价：白天的读取需要在多个 SSTable + memtable 之间归并，单点查询延迟略高。

## Leveled vs Tiered：核心权衡

理解 LSM 合并策略的关键，是理解 Leveled 和 Tiered 这两个最基础的策略代表的两种哲学。

### 写放大对比

```
Leveled (RocksDB 默认, fanout=10, 6 层):
  最坏: WA = 10 × 6 = 60
  典型: WA = 10-30x（部分 key 在合并前被覆盖）

Tiered (RocksDB Universal, factor=4):
  WA = log_4(总数据量 / 起始 SSTable 大小) + 1 (WAL)
  典型: WA = 2-10x

Tiered 写放大优势: 3-10 倍
```

### 空间放大对比

```
Leveled:
  最坏: 1 + 1/(fanout-1) = 1 + 1/9 ≈ 1.11
  典型: 1.05-1.15x（接近最优）

Tiered:
  最坏: N (合并因子，例如 4)
  典型: 2-3x（同 key 在多个 sorted run 中存在）

Leveled 空间放大优势: 2-3 倍
```

### 读放大对比

```
Leveled (无 Bloom Filter):
  最坏: L0 文件数 + (n_levels - 1) ≈ 4 + 6 = 10 次 IO
  带 Bloom: 10 × 0.01 = 0.1 次有效 IO（绝大多数 SSTable 被 Bloom 过滤）

Tiered (无 Bloom Filter):
  最坏: 所有 sorted run 的所有 SSTable，可能数十到数百
  带 Bloom: 仍需查每个 sorted run 的 Bloom，CPU 开销显著

Leveled 读放大优势: 显著（5-10 倍）
```

### 量化对比表

| 维度 | Leveled | Tiered | 优胜方 |
|------|---------|--------|--------|
| 写放大 | 10-30x | 2-10x | Tiered |
| 空间放大 | 1.1x | 2-3x | Leveled |
| 读放大（有 Bloom）| 低 | 中 | Leveled |
| 范围扫描 | 优（每层不重叠）| 中（多 run 归并）| Leveled |
| 后台 IO 平稳性 | 高（持续小合并）| 低（偶尔大合并）| Leveled |
| 实现复杂度 | 高 | 低 | Tiered |
| SSD 寿命友好 | 中 | 优 | Tiered |

### 何时选择 Leveled

- 读密集，对查询延迟敏感
- 数据更新频繁（合并能去重，节省空间）
- 存储空间受限或成本敏感
- 范围扫描占主要工作负载
- 数据规模适中（合并的 IO 开销可接受）

### 何时选择 Tiered

- 写密集，写吞吐量是首要目标
- SSD 磨损敏感（写次数最少化）
- 存储空间充足（可承受 2-3x 空间放大）
- 工作负载主要是顺序写 + 查询近期数据
- 数据规模极大（Leveled 的多层合并代价高）

## Universal Compaction 的设计哲学

RocksDB 的 Universal Compaction 名字源于"Universal Compaction Style"——它是 Tiered 思想的具体实现，但有一些 RocksDB 特有的设计。

### 触发条件的三重保险

Universal 同时考虑三个触发条件：

1. **Sorted run 数量**：当 sorted run 数达到 `level0_file_num_compaction_trigger` 时触发
2. **大小比例**：当连续的几个 sorted run 大小差异超过 `size_ratio` 时合并
3. **空间放大**：当 `(total_size - largest_sorted_run) / largest > max_size_amplification_percent / 100` 时强制合并所有 run

```
触发示例:
sorted runs: [1MB, 1MB, 1MB, 1MB, 100MB]
- 检测到前 4 个 run 大小相近 → 合并为 4MB
- 现在变成: [4MB, 100MB]
- 4 / 100 = 4% < size_ratio (默认 1%) → 不合并
- 继续等待新 run 到来
```

### 单一 Sorted Run 优化

Universal 的"理想终态"是一个 sorted run（包含所有数据的一个排序文件），此时空间放大 = 1，读放大 = 1。但要达到这个状态需要把所有数据合并一次，写放大极高。

实践中通过 `max_size_amplification_percent` 控制：

- 设为 200% 表示允许 2x 空间放大
- 设为 100% 表示要求 sorted run = 1（极端的"全量合并"）

### Periodic Compaction

Universal 还支持周期性合并：

```ini
[Universal CompactionOptions]
  periodic_compaction_seconds = 86400 * 30  # 30 天强制合并一次
```

用途：清理 tombstone、应用 TTL 过滤、整理碎片。

### Subcompactions 并行化

Universal 的合并任务可以拆分为多个子任务并行执行：

```ini
max_subcompactions = 4   # 单个合并任务可拆分为 4 个并行子任务
```

这显著加快了大合并的完成时间，避免单次合并阻塞太久。

## TimeWindow Compaction：时序场景的最佳解

时序数据的特点：

1. **写入按时间顺序**：新数据 timestamp 总是 > 旧数据
2. **查询多按时间窗口**：99% 的查询是 `WHERE time > now() - 1h`
3. **数据按时间过期**：`WITH default_time_to_live = 30 * 86400`
4. **不更新历史**：极少 update 已写入的数据

针对这些特点，TimeWindow Compaction 是几乎完美的解决方案。

### Cassandra TWCS 实战

```cql
CREATE TABLE iot_metrics (
    device_id UUID,
    bucket TIMESTAMP,
    timestamp TIMESTAMP,
    temperature DOUBLE,
    PRIMARY KEY ((device_id, bucket), timestamp)
)
WITH compaction = {
    'class': 'TimeWindowCompactionStrategy',
    'compaction_window_unit': 'HOURS',
    'compaction_window_size': 1                -- 每小时一个窗口
}
AND default_time_to_live = 2592000             -- 30 天 TTL
AND gc_grace_seconds = 0;                       -- 时序数据可设为 0
```

工作流程：

```
小时 1 的窗口:
  10:00 写入 → memtable
  10:30 flush → SSTable_1 (10:00-10:30 数据)
  11:00 flush → SSTable_2 (10:30-11:00 数据)
  ...
  小时结束 → 用 STCS 合并所有该小时的 SSTable → 1 个最终 SSTable

30 天后:
  30 天前的所有窗口达到 TTL → 整段删除（无需读出再写）
```

性能特点：

- 写放大：约 2-3x（仅在窗口内 STCS 合并一次）
- 删除高效：整段删除，无需 tombstone 和 compaction
- 查询近期：性能极佳（命中最近几个窗口）
- 查询历史：性能下降（需要扫描多个窗口的 SSTable）

### TWCS 的陷阱

**陷阱 1：跨窗口 tombstone 累积**

如果数据有 update 或 delete（非纯 append），tombstone 可能跨窗口累积：

```
窗口 1: 写入 user_id=42, value=100
窗口 50: 删除 user_id=42 → tombstone

每次查询 user_id=42 时:
  扫描窗口 50 (找到 tombstone)
  扫描窗口 1 (找到 value=100)
  应用 tombstone → 返回空

直到 gc_grace_seconds 后才能真正删除 tombstone
```

解决：纯 append 工作负载才适合 TWCS；有 update/delete 的工作负载用 STCS 或 LCS。

**陷阱 2：窗口大小选择**

窗口太小：SSTable 数量爆炸，文件描述符耗尽；窗口太大：合并开销大、TTL 粒度粗。经验法则：每个窗口 30-100 个 SSTable 较优。

**陷阱 3：迟到数据**

如果数据写入时 timestamp 显著晚于实际事件时间（迟到数据），会被分配到当前窗口而非历史窗口，破坏窗口划分。需要应用层保证时序。

### HBase Date Tiered Compaction

HBase 0.98+ 引入的策略，与 Cassandra TWCS 类似但实现细节不同：

```xml
<property>
  <name>hbase.hstore.compaction.compaction.policy</name>
  <value>org.apache.hadoop.hbase.regionserver.compactions.DateTieredCompactionPolicy</value>
</property>
<property>
  <name>hbase.hstore.compaction.date.tiered.max.storefile.age.millis</name>
  <value>2592000000</value>  <!-- 30 days -->
</property>
<property>
  <name>hbase.hstore.compaction.date.tiered.base.window.millis</name>
  <value>3600000</value>     <!-- 1 hour base window -->
</property>
```

特点：窗口大小指数增长（1h → 4h → 16h → 64h），近期窗口小适合频繁合并，远期窗口大减少合并次数。

## 关键发现

1. **没有银弹**：合并策略的本质是 RUM 三角的位置选择。Leveled 和 Tiered 各自代表两个端点；TWCS 和 FIFO 是为特定场景设计的特殊点。任何"优于所有维度"的策略都违反 RUM 猜想。

2. **RocksDB 的三策略集合是工业标杆**：RocksDB 同时支持 Leveled / Universal / FIFO，覆盖了几乎所有 LSM 工作负载需求。这是 RocksDB 被几十个项目复用的核心原因——它不强迫你选择特定哲学。

3. **Cassandra 是合并策略创新的先驱**：STCS（默认）→ LCS（1.0, 2011）→ DTCS（已弃用）→ TWCS（3.0.8/3.8, 2016）的演进路径，几乎所有现代合并思想都最先在 Cassandra 中实现并验证。

4. **TWCS 是时序数据的杀手级特性**：对纯 append 时序工作负载（IoT、监控、日志），TWCS 的写放大可低至 2-3x，删除完全无开销。其他策略在此场景下都不如 TWCS。

5. **DTCS 已被官方弃用**：自 Cassandra 3.0.8 / 3.8 起官方推荐 TWCS 替代 DTCS。生产环境不应使用 DTCS——其窗口分裂逻辑导致严重的合并问题。

6. **HBase Major Compaction 是真正的全量重写**：与 RocksDB 的"按需合并"不同，HBase 的 Major Compaction 把整个 region 的所有 HFile 重写为一个文件。生产环境通常关闭自动触发，改为低峰期手动。

7. **LevelDB 永远 Leveled，且不可配置**：这种"简洁优于灵活"的设计哲学使 LevelDB 至今仍被嵌入式场景（Chrome IndexedDB、比特币节点）大量使用。

8. **ScyllaDB Incremental Compaction 解决临时空间问题**：传统 STCS 合并大 SSTable 时需要 2x 临时空间，对超大节点是致命问题。ScyllaDB 3.1 引入的 ICS 把 SSTable 切分为 fragment，临时空间从 100% 降到几个 GB。

9. **ClickHouse 没有传统 memtable，但合并思想同源**：ClickHouse MergeTree 的每次 INSERT 直接产生 part（不可变列存目录），后台 merge pool 持续合并相邻 part。这是 LSM 思想在列存上的应用。

10. **Pebble 刻意舍弃 Universal/FIFO**：CockroachDB 的 Pebble 只支持 Leveled——因为 CRDB 的工作负载不需要其他策略。专一的引擎可以做更深的优化（MVCC 友好的 SSTable 索引、迭代器优化）。

11. **OceanBase 的"每日合并"是反潮流的设计**：与 RocksDB 系的"持续后台合并"相反，OceanBase 把所有合并集中在凌晨低峰期。这是为银行核心系统的延迟稳定性专门设计的取舍。

12. **TiDB / YugabyteDB / MyRocks 共享 RocksDB 生态**：这三大分布式 SQL 系统都基于 RocksDB（YugabyteDB 是 fork），合并策略默认都是 Leveled。RocksDB 实际上是分布式 SQL 的"事实标准存储引擎"。

13. **手动 COMPACT 是双刃剑**：触发 major compaction 可以清理空间、应用 TTL，但会造成 IO 风暴和延迟尖峰。生产环境应仅在维护窗口或迁移场景使用。

14. **Lucene 系（ES/OpenSearch/Solr）是另一个独立分支**：它们使用 TieredMergePolicy（类似 RocksDB Universal），但术语完全不同（segment 而非 SSTable，merger 而非 compaction）。LSM 思想在不同社区独立演化。

15. **TimeWindow 不能解决所有时序问题**：TWCS 假设数据按时间到达且不更新。如果有迟到数据、历史更新或删除，TWCS 会出现 tombstone 累积、跨窗口查询性能下降等问题。需要根据真实工作负载选择。

16. **InfluxDB TSM 与 ClickHouse / Druid / Pinot 收敛**：所有时序分析引擎都演化出了"时间分片 + 窗口合并"的相似模式，证明这是时序场景的最优解。InfluxDB 2.x 的 IOx 引擎也走向了类似的"列存 + Parquet + 时间分片"路线。

17. **合并策略对 SSD 寿命影响巨大**：写放大每增加 10x，SSD 写入量增加 10x，寿命缩短 10x。Facebook 把 InnoDB 换成 MyRocks 节省了 50% 存储，但更重要的是把 SSD 寿命从 2 年延长到 5+ 年，这才是经济账上的胜利。

18. **未来方向：Adaptive Compaction**：学术界正在研究"运行时自动选择合并策略"的引擎（如 Endure、CASSANDRA-15265），根据当前工作负载动态切换 Leveled/Tiered。截至 2026 年尚未在主流生产引擎中落地，但很可能是下一个突破点。

## 参考资料

- O'Neil, P., Cheng, E., Gawlick, D., O'Neil, E. (1996). *The Log-Structured Merge-Tree (LSM-Tree)*. Acta Informatica.
- Chang, F., et al. (2006). *Bigtable: A Distributed Storage System for Structured Data*. OSDI.
- Athanassoulis, M., et al. (2016). *Designing Access Methods: The RUM Conjecture*. EDBT.
- Dong, S., et al. (2017). *Optimizing Space Amplification in RocksDB*. CIDR.
- Matsunobu, Y., Dong, S., Lee, H. (2020). *MyRocks: LSM-Tree Database Storage Engine Serving Facebook's Social Graph*. VLDB.
- RocksDB Wiki: [Compaction](https://github.com/facebook/rocksdb/wiki/Compaction)
- RocksDB Wiki: [Leveled Compaction](https://github.com/facebook/rocksdb/wiki/Leveled-Compaction)
- RocksDB Wiki: [Universal Compaction](https://github.com/facebook/rocksdb/wiki/Universal-Compaction)
- RocksDB Wiki: [FIFO Compaction](https://github.com/facebook/rocksdb/wiki/FIFO-compaction-style)
- Cassandra Documentation: [Compaction](https://cassandra.apache.org/doc/latest/cassandra/managing/operating/compaction/index.html)
- ScyllaDB Documentation: [Incremental Compaction Strategy](https://docs.scylladb.com/stable/architecture/compaction/compaction-strategies.html)
- HBase Reference Guide: [Compaction](https://hbase.apache.org/book.html#compaction)
- ClickHouse Documentation: [MergeTree](https://clickhouse.com/docs/en/engines/table-engines/mergetree-family/mergetree)
- Cockroach Labs Blog (2020): *Pebble: A RocksDB Inspired Key-Value Store Written in Go*
- Yang, Z., et al. (2022). *OceanBase: A 707 Million tpmC Distributed Relational Database System*. VLDB.
- Apache Lucene Documentation: [TieredMergePolicy](https://lucene.apache.org/core/9_0_0/core/org/apache/lucene/index/TieredMergePolicy.html)

## 相关阅读

- [B+Tree vs LSM-Tree 存储引擎对比](btree-vs-lsm.md) - 存储引擎类型对比与 RUM 三角理论
