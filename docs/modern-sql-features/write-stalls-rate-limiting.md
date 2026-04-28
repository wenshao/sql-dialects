# 写入停顿与限速 (Write Stalls and Rate Limiting)

写入停顿是数据库系统在面对压倒性写入压力时的"自我保护本能"——当后台合并、刷盘、checkpoint 跟不上前台写入速度时，引擎必须主动减速甚至阻塞应用，否则系统会陷入资源耗尽、读放大爆炸、SSTable 数量失控的不可逆状态。RocksDB 的 write stall、ClickHouse 的 parts_to_delay_insert、PostgreSQL 的 checkpoint 抢占式 sleep、SQL Server 的 lazy writer 限速——所有这些机制本质上都是同一个问题的不同答案：当生产者比消费者快时，应该让谁等？

## 写入停顿的物理本质：当 LSM 合并跟不上写入

LSM 树（Log-Structured Merge Tree）的核心契约是用顺序写换随机写——所有写入先进 MemTable，flush 成 L0 SSTable，后台合并到 L1/L2/.../Ln。这个流程的稳态有一个隐含假设：合并速度 ≥ 写入速度。当假设被打破时，三种放大会同时恶化：

- **L0 文件数失控**：L0 是唯一允许 key 区间重叠的层。L0 文件越多，点查必须二分查找的 SSTable 越多，读放大与 L0 文件数线性相关
- **空间放大爆炸**：未合并的旧版本数据残留在多个 SSTable 中，磁盘占用可能膨胀到逻辑数据的 2-5 倍
- **写放大失控**：当 L0 堆积时，紧急合并会一次性重写大量 SSTable，触发 IO 风暴反而进一步拖慢前台

```
正常稳态:
  Client → MemTable → flush 速度 1GB/s
                         ↓
  Compaction Pool → L0→L1 速度 1GB/s
                         ↓
  L1→L2→...→Ln 速度递减但跟得上
  L0 SSTable 数量稳定在 4-10 个

写入压力突增:
  Client → MemTable → flush 速度 5GB/s ↑
                         ↓
  Compaction Pool → L0→L1 速度 1.2GB/s (磁盘 IO 上限)
                         ↓
  L0 SSTable 数量持续增长: 10 → 20 → 36 → 64 → ...
  读放大:每次点查需查 64 个 L0 SSTable
  系统进入死亡螺旋:读慢 → CPU 让出给合并 → 写更慢 → L0 更多
```

写入停顿（Write Stall）就是引擎在 L0 文件数、未合并字节数、MemTable 数量超过预设阈值时，主动让前台写入 sleep 或直接阻塞的机制。这是反直觉但必要的设计：宁可让用户的写入慢一点（线性 RT 增加），也不要让整个集群崩塌（指数级故障）。

## B+树引擎也有写入停顿：checkpoint 抢占

很多人以为写入停顿是 LSM 引擎独有的问题——B+树原地更新、没有合并，应该不会停顿。这个观点是错误的。B+树系列引擎（InnoDB、PostgreSQL、SQL Server、Oracle）都有自己版本的"checkpoint stall"：

- **dirty page 比例过高**：当 buffer pool 中脏页比例超过阈值（InnoDB 默认 90%）时，前台写入会被强制等待 page cleaner / lazy writer 刷盘
- **redo log 空间耗尽**：循环 redo log 中的"未刷盘脏页对应的最早 LSN"无法推进时，新事务的 commit 会被阻塞，直到 checkpoint 推进 LSN
- **WAL 占用过多**：PostgreSQL `max_wal_size` 触发时，强制 checkpoint，bgwriter 限速变得不再温柔

```
InnoDB checkpoint 抢占的死亡螺旋:
  redo log 容量 4GB
  Active redo (oldest unflushed LSN → newest LSN) 接近 4GB
  → 强制同步 checkpoint
  → 所有事务等待 page cleaner 刷盘
  → 应用看到 commit RT 从 1ms 跳到 5s
  → 应用层超时重试 → 写入压力翻倍
  → 死锁形成:redo 越满 → checkpoint 越急 → IO 越被吃 → 越难推进
```

LSM 与 B+树的差别在于：**LSM 的停顿基于 SSTable 文件数与未合并字节数；B+树的停顿基于 dirty page 比例与 redo log 空间。但本质都是"消费者跟不上生产者，必须主动抑制生产者"**。

## 没有 SQL 标准

ISO SQL 标准（9075 系列）从未涉及写入停顿、限速、背压（backpressure）相关的语法或行为——这些完全属于实现层面，标准只关心 INSERT 语句执行成功与否、是否符合 ACID。这意味着：

1. **触发阈值各引擎差异极大**：RocksDB `level0_stop_writes_trigger` 默认 36，ClickHouse `parts_to_throw_insert` 默认 300，InnoDB `innodb_max_dirty_pages_pct` 默认 90，三者维度完全不同
2. **可观测性接口缺失**：标准没有规定如何查询当前是否处于停顿状态、剩余余量多少；每个引擎自己暴露指标（RocksDB DB::Statistics、ClickHouse system.events、InnoDB innodb_buffer_pool_pages_dirty）
3. **配置粒度不统一**：RocksDB 是 column family 级，ClickHouse 是 server 级，InnoDB 是实例级，PG 是集群级
4. **应用感知方式不同**：RocksDB 通过减慢 Put 调用让上层感知，ClickHouse 直接抛 `TOO_MANY_PARTS` 错误，InnoDB 通过 commit 延迟感知

这种碎片化使得跨引擎容量规划与运维监控异常困难，也是本文要梳理的核心动机。

相关文章：[LSM 合并策略](./lsm-compaction-strategies.md)、[WAL / Redo 日志与持久化](./wal-checkpoint-durability.md)、[准入控制与查询排队](./admission-control.md)。

## 综合支持矩阵 (45+ 引擎)

下表覆盖 45+ 主流数据库 / 存储引擎对各类写入停顿与限速机制的支持。说明：

- "原生" 表示引擎主动减速 / 阻塞写入；"-- (拒绝)" 表示直接抛错；"--" 表示不支持
- 部分行存 OLTP 引擎将限速能力分散在 dirty page 管理、redo log 管理、connection 管理多处，矩阵中按主要表现形式分类

### 写入停顿基础能力

| 引擎 | 底层存储 | 原生写入停顿 | 限速器 (Rate Limiter) | 可调阈值 | 待合并字节阈值 | 用户可见停顿指标 | 版本 |
|------|---------|------------|--------------------|---------|---------------|----------------|------|
| RocksDB | LSM | 是 (slowdown + stop) | RateLimiter | 是 | `soft/hard_pending_compaction_bytes_limit` | DB::Statistics 多维 | 全部 |
| LevelDB | LSM | 是 (slowdown 1ms / 阻塞) | -- | 部分 | -- | LOG 文件 | 早期 |
| Pebble (CockroachDB) | LSM | 是 (admission control 集成) | 是 (token bucket) | 是 | 是 | admission control metrics | 22.1+ |
| CockroachDB | Pebble + KV | 是 (admission control) | 是 | 是 | 继承 Pebble | `admission.granter.*` | 22.1+ (AC GA) |
| TiDB / TiKV | RocksDB | 是 (继承 RocksDB) | 是 | 是 | `scheduler-pending-write-bytes` | TiKV metrics | 全部 |
| YugabyteDB DocDB | RocksDB fork | 是 (继承 + 自定义) | 是 (DocDB rate limiter) | 是 | 是 | YB metrics | 2.0+ |
| MyRocks | RocksDB | 是 (继承 RocksDB) | 是 | 是 | 是 | I_S 表 | 全部 |
| Cassandra | LSM | 是 (back pressure) | 是 (write throttling) | 是 | 部分 | JMX | 4.0+ 完善 |
| ScyllaDB | LSM | 是 (per-shard backpressure) | 是 | 是 | 是 | metrics endpoint | 全部 |
| HBase | LSM | 是 (MemStore flush 阻塞) | 是 (RegionServer 级) | 是 | -- | RegionServer JMX | 全部 |
| ClickHouse | MergeTree | 是 (parts_to_delay/throw) | 是 (`max_insert_threads`) | 是 | -- | system.events | 19.x+ |
| Druid | 段存储 | 部分 (handoff 等待) | 部分 | 部分 | -- | metrics | -- |
| Pinot | 段存储 | -- | -- | -- | -- | -- | -- |
| InfluxDB | TSM | 是 (cache snapshot 阻塞) | 是 | 部分 | -- | `_internal` DB | 1.x+ |
| Elasticsearch | Lucene 段 | 是 (索引 throttling) | 是 (indices.store.throttle) | 是 | -- | _nodes/stats | 0.x |
| OpenSearch | Lucene 段 | 是 (继承 ES) | 是 | 是 | -- | metrics | 全部 |
| Solr | Lucene 段 | 是 (索引限速) | 是 | 是 | -- | metrics | 全部 |
| Lucene | 段 | 是 (TieredMerge throttle) | 是 | 是 | -- | API | 全部 |
| Kafka | LogSegments | 是 (broker 级配额) | 是 (quotas) | 是 | -- | JMX | 0.9+ |
| OceanBase | LSM 变体 | 是 (memstore 写入冻结) | 是 | 是 | -- | sys log | 全部 |
| RisingWave Hummock | LSM (S3) | 是 (compaction 背压) | 是 | 是 | 是 | Prometheus | 全部 |
| MongoDB WiredTiger | B+Tree / LSM | 是 (cache pressure) | 是 (eviction) | 是 | -- | `serverStatus` | 3.0+ |
| MySQL InnoDB | B+Tree | 是 (sync flush) | 是 (`innodb_io_capacity`) | 是 | -- | I_S | 5.5+ 完善 |
| MariaDB | B+Tree (InnoDB) | 是 (继承 InnoDB) | 是 | 是 | -- | I_S | 全部 |
| PostgreSQL | B+Tree heap | 是 (bgwriter + checkpoint sleep) | 是 (checkpoint_completion_target) | 是 | -- | pg_stat_bgwriter | 8.0+ |
| TimescaleDB | PG + chunks | 部分 (继承 PG) | 部分 | 部分 | -- | 视图 | 全部 |
| SQL Server | B+Tree | 是 (lazy writer) | 是 (Resource Governor IO) | 是 | -- | DMV | 2008 R2+ |
| Oracle | B+Tree | 是 (DBWR + log buffer wait) | 是 (Resource Manager IO) | 是 | -- | V$EVENT | 11g+ |
| DB2 | B+Tree | 是 (page cleaner) | 是 | 是 | -- | MON_GET | 9.7+ |
| SQLite | B+Tree | 是 (WAL 限速) | 部分 | 部分 | -- | -- | 3.7+ |
| Firebird | B+Tree | 部分 | -- | -- | -- | -- | -- |
| H2 | B+Tree / MVStore | 部分 | -- | 部分 | -- | -- | -- |
| HSQLDB | -- | -- | -- | -- | -- | -- | -- |
| Derby | -- | -- | -- | -- | -- | -- | -- |
| Snowflake | 微分区 | 不可见 (云托管) | 是 (自动) | -- | -- | warehouse load | GA |
| BigQuery | Capacitor | 不可见 (云托管) | 是 (slot 调度) | -- | -- | INFORMATION_SCHEMA | GA |
| Redshift | 列式块 | 部分 (commit queue) | 是 (WLM) | 是 | -- | STV/SVL 视图 | GA |
| DuckDB | 行组列存 | -- | -- | -- | -- | -- | -- |
| SingleStore | 行存+列存 | 是 (rowstore flush 限速) | 是 | 是 | -- | metrics | 7.0+ |
| Vertica | ROS/WOS | 是 (WOS 满 → tuple mover) | 是 (Resource Pool) | 是 | -- | metrics | 全部 |
| SAP HANA | delta+main | 是 (delta merge 限速) | 是 | 是 | -- | M_SYSTEM | 全部 |
| Spanner | LSM 变体 | 不可见 (托管) | 是 (priority) | -- | -- | -- | GA |
| FoundationDB | 混合 | 是 (ratekeeper) | 是 | 是 | -- | status JSON | 5.x+ |
| etcd | bbolt | 是 (compaction 阻塞) | 部分 | 部分 | -- | metrics | 全部 |
| Aerospike | 混合 | 是 (defragmenter pressure) | 是 | 是 | -- | metrics | 全部 |
| Riak | LevelDB / Bitcask | 是 (vnode 级) | 是 | 是 | -- | stats | 全部 |
| Couchbase | Magma / Couchstore | 是 (DCP 流控) | 是 | 是 | -- | stats | 全部 |
| Apache Kudu | 列存 LSM | 是 (memrowset 满) | 是 | 是 | -- | metrics | 全部 |
| MonetDB | 列存 | -- | -- | -- | -- | -- | -- |
| QuestDB | append 列存 | 部分 (commit 阻塞) | 部分 | 部分 | -- | metrics | 全部 |
| StarRocks | 段存储 | 是 (memtable 满) | 是 | 是 | -- | FE/BE metrics | 全部 |
| Doris | 段存储 | 是 (memtable 满) | 是 | 是 | -- | FE/BE metrics | 全部 |
| Greenplum | 行存 + AO/AOCO | 部分 (WAL 限流) | 是 (Resource Group) | 是 | -- | gp_toolkit | 全部 |
| Trino / Presto | -- (无持久存储) | -- | -- | -- | -- | -- | -- |
| Spark SQL | 视底层 | -- | -- | -- | -- | -- | -- |
| Materialize | 视图引擎 | 是 (源限速) | 是 | 是 | -- | 视图 | 全部 |

> 统计：约 38 个引擎实现了某种形式的写入停顿或限速，约 9 个引擎完全没有该机制（DuckDB / MonetDB / HSQLDB / Derby / Trino / Presto / Spark SQL / Pinot / Firebird 部分）。
>
> 这种差异反映了引擎的角色：**纯查询引擎（Trino/Presto/Spark SQL）不持久化数据，无需停顿；嵌入式/分析引擎（DuckDB/MonetDB）依赖单进程内串行写入；分布式/在线引擎几乎都需要停顿机制**。

### 各引擎触发阈值与默认参数

| 引擎 | 主要阈值参数 | 默认值 | 副阈值参数 | 默认值 | 单位 |
|------|------------|--------|----------|--------|------|
| RocksDB | `level0_slowdown_writes_trigger` | 20 | `level0_stop_writes_trigger` | 36 | L0 SSTable 数 |
| RocksDB | `soft_pending_compaction_bytes_limit` | 64 GB | `hard_pending_compaction_bytes_limit` | 256 GB | 字节 |
| RocksDB | `max_write_buffer_number` | 2 | -- | -- | MemTable 数 |
| LevelDB | L0_SlowdownWritesTrigger | 8 | L0_StopWritesTrigger | 12 | L0 SSTable 数 |
| Pebble | `L0CompactionThreshold` | 4 | `L0StopWritesThreshold` | 12 | L0 sublevels |
| CockroachDB Pebble | `MemTableStopWritesThreshold` | 4 | -- | -- | MemTable 数 |
| TiKV | `scheduler-pending-write-bytes` | 100 MB | `raft-store-max-leader-lease` | 9s | 字节 / 时间 |
| Cassandra | `memtable_cleanup_threshold` | 1/(memtable_flush_writers+1) | `memtable_heap_space_in_mb` | 1/4 heap | 比例 / MB |
| HBase | `hbase.regionserver.global.memstore.size` | 0.4 | `.upperLimit` (旧) | 0.4 | heap 比例 |
| HBase | `hbase.hregion.memstore.flush.size` | 128 MB | `hbase.hregion.memstore.block.multiplier` | 4 | 字节 / 倍数 |
| ClickHouse | `parts_to_delay_insert` | 150 | `parts_to_throw_insert` | 300 | parts 数 |
| ClickHouse | `inactive_parts_to_delay_insert` | 0 (off) | `inactive_parts_to_throw_insert` | 0 (off) | parts 数 |
| ClickHouse | `max_partitions_per_insert_block` | 100 | -- | -- | partitions |
| InnoDB | `innodb_max_dirty_pages_pct` | 90 | `innodb_max_dirty_pages_pct_lwm` | 10 | 百分比 |
| InnoDB | `innodb_io_capacity` | 200 | `innodb_io_capacity_max` | 2000 | IOPS |
| PostgreSQL | `bgwriter_delay` | 200 ms | `bgwriter_lru_maxpages` | 100 | 时间 / 页数 |
| PostgreSQL | `checkpoint_completion_target` | 0.9 | `max_wal_size` | 1 GB | 比例 / 字节 |
| SQL Server | `recovery interval` | 1 min | `target recovery time` | 60 s | 时间 |
| Oracle | `LOG_CHECKPOINT_TIMEOUT` | 1800 s | `FAST_START_MTTR_TARGET` | 0 | 时间 |
| Elasticsearch | `indices.store.throttle.max_bytes_per_sec` | unlimited (5.0+) | `indices.store.throttle.type` | none | 速率 / 模式 |
| MongoDB | `wiredTigerEngineRuntimeConfig.cache_size` | 50% RAM | `eviction_dirty_target` | 5% | 内存 |
| InfluxDB | `cache-max-memory-size` | 1 GB | `cache-snapshot-memory-size` | 25 MB | 字节 |
| FoundationDB | ratekeeper TPS limit | 动态 | -- | -- | 事务/秒 |

### 限速器 (Rate Limiter) 维度

| 引擎 | 限速维度 | 限速对象 | API/参数 | 默认值 | 备注 |
|------|---------|---------|---------|--------|------|
| RocksDB | 字节/秒 | flush + compaction | `Options::rate_limiter` | 无（需显式设置） | 推荐生产环境强制设置 |
| RocksDB | I/O 优先级 | foreground vs background | `Env::IOPriority` | LOW | 通过 PriRateLimiter 实现 |
| Pebble | 字节/秒 | flush + compaction | `Options.WALBytesPerSync` | 0 | I/O 提示，非硬限 |
| CockroachDB | tokens/秒 | KV / SQL admission | `admission.kv_*` | 自适应 | 基于 store p99 IO 延迟 |
| TiKV | 字节/秒 | foreground 写入 | `storage.rocksdb.rate-bytes-per-sec` | 0 (off) | 参考 IO 能力设置 |
| Cassandra | bytes/sec | compaction throughput | `compaction_throughput_mb_per_sec` | 64 MB/s | 节点级配置 |
| ScyllaDB | shard token | per-shard | `--compaction-static-shares` | 100 | 与查询竞争 |
| HBase | 字节/秒 | compaction + flush | `hbase.regionserver.thread.compaction.throttle` | 2 GB | RegionServer 级 |
| ClickHouse | parts/秒 | INSERT 延迟 | `max_part_loading_threads` | 16 | 间接限速 |
| ClickHouse | bytes/sec | merge | `background_pool_size` | 16 | 后台线程数 |
| Elasticsearch | bytes/sec | merge throttling | `indices.store.throttle.max_bytes_per_sec` | unlimited | merge 流量 |
| InnoDB | IOPS | 总体 IO | `innodb_io_capacity` | 200 | 影响所有后台 IO |
| PostgreSQL | 时间/页 | bgwriter + checkpoint | `bgwriter_delay` + `bgwriter_lru_maxpages` | 200ms / 100 页 | 简单 token bucket |
| SQL Server | IOPS / MB/s | Resource Governor | `MAX_IOPS_PER_VOLUME` | 0 (off) | 2014+ |
| Oracle | I/O calibrated | I/O Resource Manager | DBMS_RESOURCE_MANAGER | 自动校准 | 11g+ |
| DB2 | 自动 | utility throttling | `UTIL_IMPACT_PRIORITY` | 50 | 9.5+ |
| MongoDB | tickets | concurrent ops | `wiredTigerConcurrentReadTransactions` | 128 | 并发数限制 |
| Aerospike | tps | xdr / migration | `xdr-throughput-threshold` | 0 | 节点级 |
| Kafka | byte/s | producer / consumer | `producer_byte_rate` | unlimited | 配额 |
| FoundationDB | 事务/秒 | ratekeeper | 自动调节 | 自适应 | 基于 storage queue |

### 待合并字节 (Pending Compaction Bytes) 阈值机制

| 引擎 | 跟踪指标 | 软停顿阈值 | 硬停顿阈值 | 用户可见 |
|------|---------|----------|----------|---------|
| RocksDB | bytes | `soft_pending_compaction_bytes_limit` 64GB | `hard_pending_compaction_bytes_limit` 256GB | DB::GetIntProperty |
| Pebble | bytes (estimated) | 自适应 | 自适应 | metrics |
| Cassandra | pending tasks | `compaction_pending` (无硬限) | -- | nodetool compactionstats |
| ScyllaDB | pending tasks | per-shard | per-shard | metrics |
| HBase | files | `hbase.hstore.blockingStoreFiles` 16 | -- | JMX |
| ClickHouse | parts | `parts_to_delay_insert` 150 | `parts_to_throw_insert` 300 | system.parts |
| Elasticsearch | pending merges | 自适应 | 自适应 | _nodes/stats |
| Lucene | pending merges | maxMergesAtOnce | maxMergesAtOnceExplicit | API |
| MongoDB | dirty bytes | `eviction_dirty_target` 5% | `eviction_dirty_trigger` 20% | wiredTiger.cache |
| InnoDB | dirty pages | `innodb_max_dirty_pages_pct_lwm` 10% | `innodb_max_dirty_pages_pct` 90% | I_S |
| PostgreSQL | WAL bytes | `max_wal_size` 1GB | `max_wal_size` * 2 | pg_stat_wal |

## RocksDB 写入停顿机制深入

RocksDB 是工业上写入停顿机制最完善、最被研究和模仿的实现。理解 RocksDB 的停顿，就理解了 LevelDB / Pebble / TiKV / MyRocks / YugabyteDB 这一整条 LSM 引擎血脉。

### 三类触发条件

RocksDB 的写入停顿由 `WriteController` 类管理，触发条件分为三类：

1. **L0 文件数过多**：`level0_slowdown_writes_trigger`（默认 20）开始减速，`level0_stop_writes_trigger`（默认 36）完全停止
2. **未合并字节数过高**：`soft_pending_compaction_bytes_limit`（默认 64GB）开始减速，`hard_pending_compaction_bytes_limit`（默认 256GB）完全停止
3. **MemTable 数过多**：`max_write_buffer_number`（默认 2，但通常调大到 4-6），达到 `max_write_buffer_number - 1` 时开始减速

```cpp
// RocksDB 内部 ColumnFamilyData::RecalculateWriteStallConditions 简化逻辑
WriteStallCondition CFData::RecalculateWriteStallConditions(...) {
  if (vstorage->NumLevelFiles(0) >= mutable_cf_options.level0_stop_writes_trigger) {
    return WriteStallCondition::kStopped;  // 完全阻塞
  }
  if (vstorage->NumLevelFiles(0) >= mutable_cf_options.level0_slowdown_writes_trigger) {
    return WriteStallCondition::kDelayed;  // 减速
  }
  if (compaction_needed_bytes >= mutable_cf_options.hard_pending_compaction_bytes_limit) {
    return WriteStallCondition::kStopped;
  }
  if (compaction_needed_bytes >= mutable_cf_options.soft_pending_compaction_bytes_limit) {
    return WriteStallCondition::kDelayed;
  }
  if (imm()->NumNotFlushed() >= mutable_cf_options.max_write_buffer_number - 1) {
    return WriteStallCondition::kDelayed;
  }
  return WriteStallCondition::kNormal;
}
```

### 减速 (Delayed) 模式的限速算法

当进入 `kDelayed` 状态后，RocksDB 不是简单地 sleep 固定时间，而是用 token bucket 实现平滑限速：

```
初始 max_delayed_write_rate = 16 MB/s (default)

随着 L0 文件数增长，限速逐步收紧:
  L0 = 20 (slowdown trigger): rate = max_rate
  L0 = 21: rate = max_rate * 0.8
  L0 = 22: rate = max_rate * 0.64
  ...
  L0 = 35 (stop trigger - 1): rate = 几 MB/s
  L0 = 36 (stop trigger): rate = 0 (完全阻塞)

每次 Put 调用:
  bytes = WriteBatch.Size()
  GenericRateLimiter.Request(bytes, IO_HIGH)
    if (bytes_available < bytes): sleep(...)
```

实际效果：当 L0 接近 stop trigger 时，应用看到的 RT 从微秒级跳到几百毫秒，但不会一次性"完全卡死"。这种渐进式减速是 RocksDB 哲学的核心——**让应用层有时间感知压力并降级**。

### 三种典型停顿成因

```
成因 1: 写入热点超过 flush 速度
  现象: max_write_buffer_number 触发
  指标: WRITE_STALL_PROPERTY: stall by memtable count
  根因: MemTable 满后无法切换 (immutable memtable 还没 flush 完)
  解法: 增大 max_write_buffer_number、调优 flush 线程数 max_background_flushes

成因 2: L0 → L1 合并跟不上
  现象: level0_slowdown_writes_trigger 触发
  指标: WRITE_STALL_PROPERTY: stall by L0 files
  根因: L1 SST 太大、CPU 不够、磁盘带宽不够
  解法: 增大 max_background_compactions、调小 target_file_size_base
        启用 subcompaction (max_subcompactions > 1)

成因 3: 整体合并跟不上
  现象: soft_pending_compaction_bytes_limit 触发
  指标: WRITE_STALL_PROPERTY: stall by pending compaction bytes
  根因: 写入持续超过磁盘可承受合并速度
  解法: 横向扩容 (sharding)、改用 universal/tiered compaction
        如果 SSD 是瓶颈，升级硬件
```

### 关键监控指标

```cpp
// RocksDB 暴露的停顿相关 ticker
WRITE_STALL_MICROS                // 累计停顿微秒数
NUM_FILES_IN_SINGLE_COMPACTION    // 单次合并涉及文件数
COMPACT_READ_BYTES                // 合并读字节
COMPACT_WRITE_BYTES               // 合并写字节
STALL_L0_SLOWDOWN_COUNT           // L0 慢速触发次数
STALL_MEMTABLE_COMPACTION_COUNT   // memtable 满触发次数
STALL_L0_NUM_FILES_COUNT          // L0 数过多触发次数

// 用户应用监控建议
db->GetTickerCount(WRITE_STALL_MICROS) // 周期采样,差值 / 周期 = 停顿占比
// 健康集群停顿占比应 < 1%
// 5%-20%: 警告
// > 20%: 紧急扩容信号
```

### RocksDB Rate Limiter

独立于停顿机制，RocksDB 还提供 `RateLimiter` 类用于限速 flush 与 compaction 的 IO，避免后台 IO 抢占前台请求：

```cpp
Options options;
options.rate_limiter.reset(NewGenericRateLimiter(
    100 * 1024 * 1024,  // 100 MB/s 总带宽
    100 * 1000,         // refill_period_us, 默认 100ms
    10,                 // fairness, 默认 10
    RateLimiter::Mode::kWritesOnly,  // 只限速写,不限读
    true                // auto_tuned, 6.4+ 支持自适应
));
```

`auto_tuned` 模式（RocksDB 6.4+）会根据 IO 排队状况动态调节，目标利用率 50-70%，避免过度限速导致合并跟不上。这是生产环境推荐的配置。

## ClickHouse parts_to_delay_insert 背压机制

ClickHouse 的写入停顿机制在工业上独树一帜——它不是基于 SSTable 数或字节，而是基于 **parts**（每次 INSERT 创建一个 part，每个 part 对应一组列文件）。这种机制的设计假设是：**应用应该批量写入，而不是高频小批次**。

### parts_to_delay_insert 与 parts_to_throw_insert

```sql
-- 查看当前配置
SELECT name, value FROM system.merge_tree_settings
WHERE name IN ('parts_to_delay_insert', 'parts_to_throw_insert',
               'inactive_parts_to_delay_insert', 'inactive_parts_to_throw_insert');

/*
parts_to_delay_insert            150
parts_to_throw_insert            300
inactive_parts_to_delay_insert   0
inactive_parts_to_throw_insert   0
*/
```

ClickHouse 的核心阈值（针对单分区 active parts 数）：

- **`parts_to_delay_insert` = 150**：当某个分区的活跃 parts 数 ≥ 150 时，INSERT 开始被人工延迟
- **`parts_to_throw_insert` = 300**：当 parts 数 ≥ 300 时，INSERT 直接抛错 `TOO_MANY_PARTS`

这两个参数自 ClickHouse 19.x 起为默认值，多年未变（19.13 引入相关默认）。

### 延迟算法

ClickHouse 的延迟算法是**指数级**的，比 RocksDB 的线性更激进：

```cpp
// ClickHouse src/Storages/MergeTree/MergeTreeData.cpp 简化逻辑
void MergeTreeData::delayInsertOrThrowIfNeeded(...) {
    const auto data_settings = getSettings();
    const size_t parts_count_in_partition = getMaxPartsCountForPartition();

    if (parts_count_in_partition >= data_settings->parts_to_throw_insert) {
        throw Exception(ErrorCodes::TOO_MANY_PARTS,
            "Too many parts ({}). Merges are processing significantly slower than inserts",
            parts_count_in_partition);
    }

    if (parts_count_in_partition < data_settings->parts_to_delay_insert)
        return;  // 没到延迟阈值

    const size_t max_k = data_settings->parts_to_throw_insert
                       - data_settings->parts_to_delay_insert;  // 例如 150
    const size_t k = 1 + parts_count_in_partition
                       - data_settings->parts_to_delay_insert;  // 当前超出量,从 1 起

    const double delay_milliseconds =
        ::pow(data_settings->max_delay_to_insert * 1000, static_cast<double>(k) / max_k);

    // max_delay_to_insert 默认 1 秒,故最大延迟约 1 秒
    // 但延迟是指数: k=1 → 1ms 级, k=149 → 1000ms 级
    std::this_thread::sleep_for(...);
}
```

```
parts_count = 150: delay = pow(1000, 1/150) ≈ 1.05ms
parts_count = 200: delay = pow(1000, 51/150) ≈ 25ms
parts_count = 250: delay = pow(1000, 101/150) ≈ 158ms
parts_count = 299: delay = pow(1000, 149/150) ≈ 991ms
parts_count = 300: throw TOO_MANY_PARTS
```

### TOO_MANY_PARTS 是 ClickHouse 运维最常见错误

`TOO_MANY_PARTS` 是 ClickHouse 用户最常遇到的"灾难"错误之一，根因总结：

```
原因 1: 高频小批次 INSERT
  现象: 应用每次 INSERT 几行,持续高频
  诊断: SELECT count() FROM system.parts WHERE active=1 GROUP BY partition
  解法: 客户端聚批 (推荐每批 ≥ 10000 行)
        启用 async_insert (21.11+ 实验性, 22.10+ 生产可用)

原因 2: 分区数过多 (max_partitions_per_insert_block = 100 默认)
  现象: 单次 INSERT 跨越 > 100 个分区
  解法: 调小分区粒度 (按月而非按天)
        增大 max_partitions_per_insert_block

原因 3: 后台合并速度跟不上
  现象: 即使批量写入,parts 仍在堆积
  诊断: SELECT * FROM system.merges
  解法: 增大 background_pool_size (默认 16, 可调到 32-64)
        优化 ORDER BY 减少合并复杂度
        升级磁盘 (合并是顺序 IO 密集)

原因 4: 大量 mutation/alter 阻塞合并
  现象: pending mutations 堆积
  解法: 暂停大事务 mutation,等合并恢复后再做
```

### async_insert 的革命

ClickHouse 22.10+ 默认启用的 `async_insert` 机制本质上是把 ClickHouse 内部变成"客户端聚批器"——多个客户端的小 INSERT 在 server 端被合并成一个大 part，从根本上避免 parts 数失控：

```sql
-- 客户端透明启用
SET async_insert = 1;
SET wait_for_async_insert = 1;  -- 同步等待 server 端 flush

-- server 端聚批配置
SET async_insert_max_data_size = 100 MiB;  -- 内存中聚批大小
SET async_insert_busy_timeout_ms = 200;     -- 最大等待 ms

INSERT INTO events VALUES (1, 'a'), (2, 'b');  -- 不立即 flush,聚批后写
```

`async_insert` 让 ClickHouse 从"批量数据库"演化成"流式数据库"，彻底改变了 parts 管理的负担分布。

### parts_to_delay 与 parts_to_throw 的工业争议

围绕 ClickHouse 这两个参数有几个长期争议：

1. **300 对大型集群够吗？** 不够。Yandex / ClickHouse 公司内部生产经常把 `parts_to_throw_insert` 调到 600-3000，甚至关闭。代价是分区合并堆积可能使读放大恶化
2. **应该按字节还是按数量？** 按数量便于推理，但忽略 part 大小差异。RocksDB 后期引入 `pending_compaction_bytes` 就是吸取这个教训
3. **错误信号还是 SLA 信号？** 应用应该把 `TOO_MANY_PARTS` 视为重试信号还是降级信号？官方推荐前者，但实际运维中往往是后者（应用降级丢部分写入）

## 与 B+树引擎的 checkpoint 停顿对比

LSM 引擎的写入停顿基于"待合并量"，B+树引擎的停顿基于"待刷盘脏页量 + 日志推进"。两者表现形式不同，但本质都是后台跟不上前台。

### MySQL InnoDB：dirty page 与 redo log 双重制约

InnoDB 有两条独立的"水位"会触发停顿：

```
水位 1: dirty page 比例 (innodb_max_dirty_pages_pct = 90%)
  当 buffer pool 中脏页超过 90% 时:
  - innodb_io_capacity 失效, 进入 sync flush 模式
  - 前台 INSERT/UPDATE 必须等 page cleaner 刷盘后才能 dirty 新页
  - 用户层表现: commit RT 跳到几百 ms

水位 2: redo log 推进 (LSN gap)
  redo log 文件容量 (innodb_redo_log_capacity, 8.0.30+; 旧版 innodb_log_file_size)
  当 active LSN 区间接近容量上限:
  - 触发 sync checkpoint
  - 所有事务等待 page cleaner 推进 oldest LSN
  - 8.0.30 之前是死锁的常见来源
```

InnoDB 5.5 之前没有独立的 page cleaner 线程，5.5 引入后情况大幅改善，但 redo log 限制依然是高写入场景的瓶颈。8.0.30+ 引入 `innodb_redo_log_capacity` 替代 `innodb_log_file_size`，可以在线动态调整。

### PostgreSQL：bgwriter 与 checkpoint 协调

PostgreSQL 的写入停顿机制比 InnoDB 更"温和"——通过 bgwriter 持续以小步刷脏页，避免 checkpoint 一次性 IO 风暴。

```
bgwriter 工作循环 (PostgreSQL 8.0+, 2005 引入):
  while (true):
    if (dirty_pages > bgwriter_lru_maxpages):
        flush bgwriter_lru_maxpages 页 (默认 100)
    sleep(bgwriter_delay)  # 默认 200ms

checkpoint 工作循环:
  在 checkpoint_timeout (默认 5min) 或 max_wal_size (默认 1GB) 触发
  分摊到 checkpoint_completion_target * checkpoint_timeout 时间内 (默认 0.9 * 5min = 4.5min)
  即:每秒最多刷 N 页, N = 总脏页 / (270 秒)
```

PG 不会主动"阻塞"前台事务，但 commit 时如果遇到 WAL 满（极端情况），会等待 WAL 写入。9.2+ 引入 `wal_buffers` 自动调优，14+ 引入 `wal_compression` 减少 WAL 流量，进一步降低停顿概率。

### SQL Server：lazy writer 与 recovery interval

SQL Server 用 lazy writer + checkpoint 双线程协作。配置 `recovery interval` 控制 checkpoint 频率，2008+ 引入 `target recovery time`（间接 checkpoint）后默认 60 秒，比传统 checkpoint 更平滑：

```
间接 checkpoint (Indirect Checkpoint, 2008+):
  目标: recovery time ≤ target_recovery_time (默认 60s)
  工作方式: 持续刷脏页, 保证未刷盘 redo log 不超过预算
  优势: 避免长时间 IO spike,前台无明显停顿
  代价: 持续后台 IO,SSD 友好但 HDD 可能影响顺序写
```

SQL Server 还有 Resource Governor 提供 IO 限速能力（2014+），可对每个 workload 设置 `MAX_IOPS_PER_VOLUME`。

### Oracle：DBWR 与 log buffer space 等待

Oracle 通过 DBWR（数据库写入进程）异步刷脏页，前台事务感知停顿主要通过两个等待事件：

```
等待事件 1: log buffer space
  redo log buffer 满, 前台 commit 必须等 LGWR 写盘
  解法: 增大 log_buffer (默认 16MB-32MB)

等待事件 2: log file sync
  commit 等待 LGWR 完成 fsync
  解法: 调优 LGWR commit 频率, 增加 redo log group, 使用 fast commit (12c+)

等待事件 3: free buffer waits
  buffer pool 找不到 free page
  解法: 增大 buffer cache, 调优 DBWR

等待事件 4: write complete waits
  前台需要修改的页正在被 DBWR 刷盘
  解法: 增大 buffer cache, DBWR 进程数 (db_writer_processes)
```

Oracle 11g 引入 `FAST_START_MTTR_TARGET` 参数（目标恢复时间，秒），相当于 SQL Server 的间接 checkpoint，自动调整 DBWR 频率。

### B+树停顿对比表

| 引擎 | 主要触发 | 次要触发 | 用户层表现 | 调优手段 |
|------|---------|---------|----------|---------|
| InnoDB | dirty pages > 90% | redo log 满 | commit RT 跳变 | innodb_io_capacity, innodb_buffer_pool_size |
| PostgreSQL | WAL 占用 / checkpoint | 实际很少阻塞前台 | 平滑 | bgwriter_*, checkpoint_*, max_wal_size |
| SQL Server | recovery time | redo 满 | 间接 checkpoint 平滑 | target recovery time, Resource Governor |
| Oracle | log buffer space | free buffer / write complete | 等待事件 | log_buffer, db_writer_processes, FAST_START_MTTR_TARGET |
| DB2 | log full / soft checkpoint | dirty page | commit 等待 | LOGFILSIZ, NUM_IOCLEANERS |
| SQLite | WAL 大小 (WAL 模式) | -- | 罕见 | wal_autocheckpoint, journal_size_limit |

## 分布式数据库的写入停顿创新

LSM 与 B+树引擎的停顿机制都是单机视角，分布式数据库面临的复杂度更高——写入压力可能不均衡分布在多个节点上，单一节点的停顿可能引发全集群级联故障。

### CockroachDB Pebble 的 Admission Control 集成

CockroachDB 22.1 GA 的 Admission Control 是写入停顿与准入控制深度融合的代表作：

```
传统模型:
  KV 层: 收到写请求 → Pebble.Set → 可能停顿
  缺点: 停顿信号不向上传播,SQL 层不知道
        多客户端竞争时无优先级

CRDB AC 模型 (22.1+):
  Pebble metrics → admission.granter → 决定是否准入
  特性:
  - 基于 store-level p99 IO 延迟自适应调节 token rate
  - 高优先级请求 (RANGEFEED, raft heartbeat) 优先
  - 低优先级 (大 BACKUP, IMPORT) 让路
  - 用户层 ratelimit 与 admission control 联动
```

Cockroach 的 [admission control 设计文档](https://github.com/cockroachdb/cockroach/blob/master/docs/RFCS/20210604_disk_io_admission_control.md) 列出了几个核心理念：

- **不依赖配置好的硬限**：传统 RocksDB 需要 DBA 调 `level0_stop_writes_trigger`，CRDB 自动学习
- **优先级感知**：raft 心跳必须不被停顿（否则集群分裂）
- **跨层协调**：KV 层停顿信号传递给 SQL 层，SQL 层可以将查询排队而非粗暴失败

### TiDB / TiKV 的 scheduler-pending-write-bytes

TiKV（基于 RocksDB）有一个上层的写入调度器，独立于 RocksDB 内部的停顿机制：

```toml
# tikv.toml
[storage]
scheduler-pending-write-bytes = "100MB"  # 默认 100MB
scheduler-concurrency = 524288           # 调度器槽位数
```

`scheduler-pending-write-bytes` 是 KV 层的"虚拟阻塞队列"——当待处理的 KV 写请求总字节数超过阈值时，新请求被立即拒绝。这是 TiKV 在 RocksDB 之上加的一层背压，避免请求在 raft proposal 阶段堆积导致 OOM。

TiDB 还有 region 心跳机制相关的限速：当某个 region 持续高写入压力，PD（调度器）会触发 region split 或 leader transfer 平衡负载，间接限制热点节点写入压力。

### YugabyteDB DocDB 的多级限速

YugabyteDB 基于 RocksDB fork（DocDB），叠加了自己的限速器：

```
层 1: DocDB 内部 RocksDB rate limiter (继承)
层 2: tablet 级 memtable 阈值
层 3: tserver 级 admission control
层 4: 客户端 driver 级重试
```

YugabyteDB 的 `--rocksdb_max_background_compactions` 默认 16，`--rocksdb_compact_flush_rate_limit_bytes_per_sec` 默认 256MB/s，是生产环境调优重点。

### Cassandra / ScyllaDB 的 backpressure

Cassandra 历史上的 backpressure 实现比较粗糙，4.0 才引入完整的 [backpressure framework](https://issues.apache.org/jira/browse/CASSANDRA-9318)：

```yaml
# cassandra.yaml
back_pressure_enabled: true
back_pressure_strategy:
    - class_name: org.apache.cassandra.net.RateBasedBackPressure
      parameters:
          - high_ratio: 0.90
          - factor: 5
          - flow: FAST
```

`RateBasedBackPressure` 基于副本 ack 延迟计算速率因子，慢副本会拖慢整体写入速率，避免协调器堆积太多 in-flight writes。

ScyllaDB 用完全不同的设计——基于 seastar 的 per-shard 异步模型，每个 shard 有独立的 IO scheduler 和优先级队列，前台写入与后台合并按 token 分配 CPU 时间。

### HBase MemStore 与 Compaction 阻塞

HBase 的写入停顿基于 MemStore 大小：

```xml
<!-- hbase-site.xml -->
<property>
  <name>hbase.regionserver.global.memstore.size</name>
  <value>0.4</value>  <!-- heap 的 40% 上限 -->
</property>
<property>
  <name>hbase.hregion.memstore.flush.size</name>
  <value>134217728</value>  <!-- 单 region MemStore 128MB 触发 flush -->
</property>
<property>
  <name>hbase.hregion.memstore.block.multiplier</name>
  <value>4</value>  <!-- MemStore 达到 flush.size * 4 = 512MB 时阻塞写入 -->
</property>
<property>
  <name>hbase.hstore.blockingStoreFiles</name>
  <value>16</value>  <!-- 单 store 文件超过 16 个时阻塞写入 -->
</property>
```

HBase 的 `hbase.hstore.blockingStoreFiles` 类似 RocksDB 的 `level0_stop_writes_trigger`——StoreFile 太多时停止写入等待 compaction。但 HBase 没有"slowdown"中间态，只有 normal/blocked 二态。

### Kafka 的配额机制

Kafka 不是数据库，但其写入限速机制对数据库设计有深远影响：

```properties
# broker 级配额
producer_byte_rate=1048576         # 1MB/s per client
consumer_byte_rate=2097152         # 2MB/s per client
request_percentage=200             # 200% 请求处理时间配额

# 配额超出时:
# - 不是抛错,而是延迟响应
# - 客户端 KafkaProducer 自动等待
```

Kafka 的"配额 + 延迟响应"模型影响了后来很多消息队列与数据库的设计——**优雅降级（graceful degradation）比硬错误（hard error）更易于运维**。

## 系统设计的争议与权衡

### 阻塞 vs 抛错 vs 降级

不同引擎对"超过停顿阈值"的处理策略有根本差异：

```
策略 A: 阻塞 (RocksDB / InnoDB / PostgreSQL)
  优点: 应用代码无需特殊处理,自动 throttle
  缺点: RT 异常增长,容易引发应用层超时雪崩

策略 B: 抛错 (ClickHouse parts_to_throw_insert)
  优点: 应用层明确感知,可以选择重试或降级
  缺点: 错误处理复杂,新手用户经常踩坑

策略 C: 异步聚批 (ClickHouse async_insert / Kafka 配额)
  优点: 透明限速,不需要应用感知
  缺点: 实现复杂,语义微妙 (commit 不再 sync)
```

业界趋势：从策略 A 向策略 C 演进。RocksDB 6.x 增加更细的 metric 让用户提前感知；ClickHouse 22.10 默认 async_insert；Kafka 5+ 有 client.quota.callback.class 自定义。

### 静态阈值 vs 自适应

```
静态阈值 (RocksDB 历史默认):
  level0_stop_writes_trigger = 36
  优点: 简单, 可预测
  缺点: 需要 DBA 根据硬件调优, 一刀切不适合所有场景

自适应 (CRDB AC, RocksDB auto_tuned, FoundationDB ratekeeper):
  根据实时 IO 延迟、queue depth 动态调节
  优点: 免运维, 自动适应负载变化
  缺点: 调试困难,故障定位复杂,可能"震荡"
```

CockroachDB 在 admission control RFC 中明确：自适应优于静态，但实现细节非常重要——必须有抗震荡设计（PID 控制器、滑动窗口 EMA）。

### 单机 vs 分布式的停顿协调

单机停顿不影响其他节点，分布式停顿需要全局协调：

```
单机停顿不协调的副作用:
  Node A 写入压力大 → 停顿 → 客户端切到 Node B
  → Node B 压力转移 → 停顿 → 客户端切到 Node C
  → 全集群级联停顿

分布式协调机制:
  - CRDB: admission control 跨节点共享 token,基于全局 p99
  - TiDB: PD 调度器主动 region balance
  - Cassandra: gossip 传播 backpressure 信号
  - Spanner: 客户端基于服务端 hint 调整请求速率
```

### 数据安全 vs 吞吐量的折衷

写入停顿与持久化保证有微妙关系：

```
极端场景: 
  停顿被禁用 (level0_stop_writes_trigger = INT_MAX) 时
  L0 文件可能堆积到几千个
  此时如果断电:
  - WAL 仍然完整 (写入未丢)
  - 但重启时 replay WAL + 加载所有 L0 极慢
  - 启动时间从秒级跳到分钟级甚至小时级
```

工业实践：**永远不要禁用写入停顿**。可以调高阈值，但必须保留兜底机制。RocksDB 多次教训：用户为追求 benchmark 数字关掉停顿，生产环境出大故障。

## 关键发现

### 1. 写入停顿是 LSM 与 B+树共同的物理必然

LSM 与 B+树看起来差异巨大，但都面临"后台跟不上前台"的物理瓶颈：LSM 是合并跟不上 flush，B+树是 page cleaner 跟不上 dirty page 生成。两者的解决方案在概念上殊途同归——主动让前台 sleep 或阻塞。

### 2. 阈值的演化方向：从"数量"到"字节"再到"自适应"

RocksDB 早期只看 L0 文件数（`level0_stop_writes_trigger`），后期加入 `pending_compaction_bytes` 是质的飞跃——文件数无法反映合并工作量，字节才是真正的代价指标。CockroachDB Pebble 进一步抽象为"基于实时 IO 延迟的自适应 token"，是这条演化路径的终点。

### 3. ClickHouse 的"按 part 数限速"是反潮流但有效的特例

绝大多数 LSM 引擎按字节限速，ClickHouse 却按 parts 数（150/300）。这反映了 ClickHouse 的核心假设：**应用应该批量写入，单次 INSERT 应是大块**。当假设成立时，部数限制简单有效；当假设不成立（IoT 场景高频小批次），就需要 async_insert 这样的补救机制。

### 4. async_insert / client batching 是终极答案

无论引擎层做多少限速优化，最有效的方式仍是**让客户端聚批**。ClickHouse async_insert（22.10+ 生产）、Kafka producer linger.ms、Cassandra prepared batch、PG INSERT ... VALUES (...), (...), (...) 都是同一个思路。引擎做 100 倍优化不如客户端聚批 1000 倍来得直接。

### 5. 分布式停顿的可观测性远不够成熟

单机数据库（RocksDB / InnoDB / PG）的停顿指标已经相对完善，分布式数据库的跨节点停顿可观测性仍是研究热点：

- 哪个节点先停顿？
- 停顿是否在级联？
- 客户端是否在退避？
- raft 心跳是否被影响？

CRDB 22.1 admission control GA 是这个方向的重要进展，但仍有大量工作要做。

### 6. 没有标准化的"写入压力指标"

类比 CPU 的 load average、内存的 working set，数据库领域至今没有一个被广泛接受的"写入压力指标"。每个引擎暴露不同的内部状态：

- RocksDB: `WRITE_STALL_MICROS`、`STALL_L0_NUM_FILES_COUNT`
- ClickHouse: `system.events.DelayedInserts`、`InsertFailedTooManyParts`
- InnoDB: `Innodb_buffer_pool_pages_dirty`、`Innodb_log_writes`
- PG: `pg_stat_bgwriter`、`pg_stat_wal`

这种碎片化使得跨引擎运维工具（DataDog、Prometheus exporter）需要为每个引擎重新实现。OpenTelemetry 的数据库 Semantic Conventions 还在草案阶段，未来可能改善。

### 7. 停顿机制是 SLA 设计的隐藏前提

业务 SLA 通常关注 P99 延迟、可用性、吞吐量，但很少明确写入停顿的"可接受时长"。这导致 DBA 与应用开发的认知差距：

- DBA 视角：停顿是保护机制，10% 时间停顿是健康的（合并跟得上）
- 开发视角：commit 偶尔 1 秒是 bug，必须修复

实际工业实践中，应该在 SLA 中明确：

```
推荐 SLA 模板:
  - P99 commit RT < 100ms
  - WRITE_STALL_MICROS / 总时间 < 5%
  - parts_count < 200 (ClickHouse, 给 100 余量)
  - dirty_pages_pct < 75% (InnoDB, 给 15% 余量)
  - 任何阈值超过 80% 时报警, 90% 时启动应急
```

## 参考资料

- RocksDB Wiki: [Write Stalls](https://github.com/facebook/rocksdb/wiki/Write-Stalls)
- RocksDB Wiki: [Rate Limiter](https://github.com/facebook/rocksdb/wiki/Rate-Limiter)
- RocksDB Wiki: [Tuning Guide](https://github.com/facebook/rocksdb/wiki/RocksDB-Tuning-Guide)
- LevelDB: [doc/impl.md - "Slowdown writes"](https://github.com/google/leveldb/blob/main/doc/impl.md)
- Pebble: [Architecture](https://github.com/cockroachdb/pebble/blob/master/docs/architecture.md)
- CockroachDB: [Admission Control RFC](https://github.com/cockroachdb/cockroach/blob/master/docs/RFCS/20210604_disk_io_admission_control.md)
- CockroachDB Blog: [Why and How CockroachDB Builds Its Own Storage Engine](https://www.cockroachlabs.com/blog/pebble-rocksdb-kv-store/)
- TiKV: [Storage configuration](https://docs.pingcap.com/tidb/stable/tikv-configuration-file)
- ClickHouse: [parts_to_delay_insert](https://clickhouse.com/docs/en/operations/settings/merge-tree-settings#parts-to-delay-insert)
- ClickHouse: [Asynchronous Inserts](https://clickhouse.com/docs/en/optimize/asynchronous-inserts)
- ClickHouse Blog: [Mastering Asynchronous Inserts](https://clickhouse.com/blog/asynchronous-inserts-clickhouse-what-why)
- Apache Cassandra: [CASSANDRA-9318 Backpressure framework](https://issues.apache.org/jira/browse/CASSANDRA-9318)
- ScyllaDB: [Workload Prioritization](https://www.scylladb.com/2020/04/29/workload-prioritization-in-scylla/)
- HBase Reference Guide: [Region Server Memstore](https://hbase.apache.org/book.html#regions.arch.assignment)
- MySQL: [Configuring InnoDB Buffer Pool Flushing](https://dev.mysql.com/doc/refman/8.0/en/innodb-buffer-pool-flushing.html)
- PostgreSQL: [Background Writer Configuration](https://www.postgresql.org/docs/current/runtime-config-resource.html#RUNTIME-CONFIG-RESOURCE-BACKGROUND-WRITER)
- PostgreSQL: [WAL Configuration](https://www.postgresql.org/docs/current/wal-configuration.html)
- SQL Server: [Database Checkpoints](https://learn.microsoft.com/en-us/sql/relational-databases/logs/database-checkpoints-sql-server)
- Oracle: [Buffer Cache and Database Writer (DBWR)](https://docs.oracle.com/en/database/oracle/oracle-database/19/cncpt/memory-architecture.html)
- MongoDB: [WiredTiger Cache and Eviction](https://www.mongodb.com/docs/manual/core/wiredtiger/)
- FoundationDB: [The Ratekeeper](https://apple.github.io/foundationdb/transaction-processing.html)
- Athanassoulis et al. "Designing Access Methods: The RUM Conjecture", EDBT 2016
- Mohan et al. "ARIES: A Transaction Recovery Method", ACM TODS 1992
