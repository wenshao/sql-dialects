# 缓冲池管理 (Buffer Pool / Page Cache Management)

在 OLTP 世界里，如果只允许你调一个参数，那就是缓冲池大小——它决定了多少数据能放进内存，而这往往意味着 100 倍以上的延迟差异。一个命中率 99% 的 InnoDB 缓冲池和一个命中率 90% 的缓冲池，用户感受到的是"丝滑"与"卡顿"两个世界。

## SQL 标准并未定义

与本系列其他主题不同，缓冲池管理完全是引擎内部实现细节。SQL 标准（SQL:2023）不涉及任何内存缓存机制——这些都属于物理层，由各引擎自行设计。但正因为没有标准约束，各家的设计哲学反而展现出强烈对比：

- **自管理派**（Oracle / MySQL / DB2 / SQL Server / SAP HANA）：自己分配大块内存，跳过或绕过 OS 页缓存，精细控制驱逐、预热、脏页刷写
- **OS 协作派**（PostgreSQL / SQLite）：只分配相对较小的共享缓冲区，把"大容量缓存"这件事交给 OS 的 page cache
- **列存多缓存派**（ClickHouse / StarRocks / Doris）：为压缩块、标记、mmap 文件设立多套独立缓存
- **内存优先派**（DuckDB / SAP HANA / SingleStore）：缓冲池和执行内存共享同一个预算
- **全托管派**（Snowflake / BigQuery / Firebolt）：用户看不到缓冲池，服务内部按 warehouse 或 slot 自动管理

本文对 50+ 引擎的缓冲池设计进行横向对比，覆盖配置、驱逐算法、预热、绑定、脏页控制、后台写、OS 缓存依赖、NUMA 感知等维度。

## 支持矩阵

### 1. 固定大小缓冲池 (Fixed-size Buffer Pool)

| 引擎 | 参数名 | 默认值 | 生产典型值 | 可在线调整 |
|------|--------|--------|-----------|-----------|
| PostgreSQL | `shared_buffers` | 128MB | 25% RAM | 否（重启） |
| MySQL InnoDB | `innodb_buffer_pool_size` | 128MB | 70-80% RAM | 是 (5.7+) |
| MariaDB | `innodb_buffer_pool_size` | 128MB | 70-80% RAM | 是 |
| SQLite | `PRAGMA cache_size` | 2000 页 | 按需 | 是（会话） |
| Oracle | `DB_CACHE_SIZE` / SGA_TARGET | 自动 | 40-60% RAM | 是 (ASMM) |
| SQL Server | `max server memory` | 2147483647MB | 80-90% RAM | 是 |
| DB2 | `BUFFERPOOL` 对象 | IBMDEFAULTBP | 按表空间分配 | 是 (ALTER) |
| Snowflake | warehouse 内部 SSD cache | 自动 | 托管 | 否 |
| BigQuery | 执行引擎内部 | 自动 | 托管 | 否 |
| Redshift | 内部 block cache | 自动 | 托管 | 否 |
| DuckDB | `memory_limit` | 80% RAM | 按会话 | 是 |
| ClickHouse | `mark_cache_size` / `uncompressed_cache_size` | 5GB / 8GB (22.x+, 历史上为 0) | 按负载 | 是 |
| Trino | `memory.heap-headroom-per-node` | 30% heap | 按负载 | 否 |
| Presto | `query.max-memory-per-node` | 0.1 heap | 按负载 | 否 |
| Spark SQL | `spark.memory.storageFraction` | 0.5 | 按工作集 | 否 |
| Hive | HDFS 依赖 OS cache | 无 | -- | -- |
| Flink SQL | `taskmanager.memory.managed.size` | 自动 | 按状态 | 否 |
| Databricks | Delta cache | 自动 | SSD 缓存 | 是 |
| Teradata | FSG cache | 自动 | 60-80% RAM | 重启 |
| Greenplum | `shared_buffers` (segment) | 128MB | 25% per seg | 重启 |
| CockroachDB | `--cache` | 128MB | 25% RAM | 重启 |
| TiDB (TiKV) | `storage.block-cache.capacity` | 45% RAM | 45-60% | 热更新 |
| OceanBase | `memory_limit` / `cache_wash_threshold` | 自动 | 50-80% | 动态 |
| YugabyteDB | `--db_block_cache_size_percentage` | 50% | 40-60% | 重启 |
| SingleStore | `maximum_memory` | 90% RAM | 80-90% | 是 |
| Vertica | ROS container cache | 自动 | 托管 | -- |
| Impala | `--buffer_pool_limit` | 80% mem_limit | 按查询 | 重启 |
| StarRocks | `storage_page_cache_limit` | 20% | 20-40% | 热更新 |
| Doris | `storage_page_cache_limit` | 20% | 20-40% | 热更新 |
| MonetDB | 依赖 mmap + OS cache | 无 | -- | -- |
| CrateDB | Lucene + OS cache | 继承 ES | -- | -- |
| TimescaleDB | `shared_buffers` | 继承 PG | 25% RAM | 重启 |
| QuestDB | `cairo.sql.page.frame.cache.size` | 32KB | 按列 | 重启 |
| Exasol | DB RAM | 配置时 | 90% RAM | 重启 |
| SAP HANA | column store main / delta | 自动 | 全内存 | 动态 |
| Informix | `BUFFERPOOL` | 按 page size | 50-70% | 重启 |
| Firebird | `DefaultDbCachePages` | 2048 | 按库调整 | 重启 |
| H2 | `CACHE_SIZE` | 16MB | 按需 | 是 (SET) |
| HSQLDB | `hsqldb.cache_size` | 10000 行 | 按需 | 启动 |
| Derby | `derby.storage.pageCacheSize` | 1000 页 | 按需 | 启动 |
| Amazon Athena | 继承 Trino | 托管 | -- | -- |
| Azure Synapse | 内部 | 托管 | -- | -- |
| Google Spanner | 内部（Colossus + cache） | 托管 | -- | -- |
| Materialize | 全内存 arrangements | 按 dataflow | -- | -- |
| RisingWave | `block_cache_capacity_mb` | 1GB | 可配 | 重启 |
| InfluxDB (IOx) | 内部 TSM cache | 自动 | -- | -- |
| DatabendDB | `table_data_cache_population_queue_size` | 可配 | 对象存储 cache | 重启 |
| Yellowbrick | blade cache | 自动 | -- | -- |
| Firebolt | F3 engine cache | 自动 | SSD 缓存 | -- |

> 约 25 个引擎提供"单一主缓冲池"参数；约 12 个走"多池/多层"路线；其余为全托管或全内存模型。

### 2. 多缓冲池 / 命名池 (Multiple / Named Buffer Pools)

| 引擎 | 多池支持 | 创建方式 | 用途 |
|------|---------|---------|------|
| PostgreSQL | -- | -- | 只有一个 shared_buffers |
| MySQL InnoDB | 是 | `innodb_buffer_pool_instances` | 减锁竞争，默认 8 |
| Oracle | 是 (3 个) | `DB_KEEP_CACHE_SIZE` / `DB_RECYCLE_CACHE_SIZE` | KEEP / RECYCLE / DEFAULT |
| SQL Server | -- | -- | 单缓冲池 + BPE |
| DB2 | 是（任意多个） | `CREATE BUFFERPOOL` | 按表空间绑定 |
| Informix | 是 | 按 page size 一个 | 2K/4K/8K/16K 分开 |
| Sybase ASE | 是 | 命名缓存 + buffer pool | 多粒度 |
| Teradata | -- | FSG cache 单一 | -- |
| ClickHouse | 是（功能区分） | mark / uncompressed / mmap / query cache | 多用途分离 |
| StarRocks | 是 | page cache + metadata cache | 分层 |
| Doris | 是 | page cache + segment v2 cache | 分层 |
| TiKV | 是 | block cache + write buffer | RocksDB 多层 |
| 其他 | -- | -- | -- |

**DB2 是唯一允许任意数量命名缓冲池、并按表空间绑定的引擎**；Oracle 给了 3 个固定名额（DEFAULT / KEEP / RECYCLE）；MySQL 的"多实例"本质是分片同一个大池以减少 mutex 竞争，不是按表绑定。

### 3. CLOCK-sweep 驱逐算法

| 引擎 | 算法 | 说明 |
|------|------|------|
| PostgreSQL | CLOCK-sweep (GCLOCK) | 每页有 usage_count（0-5），扫描时递减，归零可淘汰 |
| Greenplum | CLOCK-sweep | 继承 PG |
| TimescaleDB | CLOCK-sweep | 继承 PG |
| CockroachDB (Pebble) | CLOCK | RocksDB 血缘 |
| YugabyteDB | CLOCK | 继承 RocksDB |
| LevelDB / RocksDB 派系 | CLOCK（可选） | TiKV/Kudu/Pebble 可选 LRU 或 CLOCK |
| 其他 | LRU / LRU-K / 混合 | 见下表 |

CLOCK-sweep 的优势是无需维护双向链表，只需一个环形指针和 usage_count 字节，避免了 LRU 在并发读下的链表 hot-spot。PG 这套算法在 8.1 之后稳定下来，是"简单但足够好"的代表。

### 4. LRU / LFU / LRU-K / 中点 LRU

| 引擎 | 驱逐算法 | 特点 |
|------|---------|------|
| MySQL InnoDB | 中点插入 LRU (midpoint LRU) | 默认 5/8 young, 3/8 old |
| MariaDB | 中点插入 LRU | 同 InnoDB |
| Oracle | TOUCH_COUNT LRU | 介于 LRU 与 LFU 之间 |
| SQL Server | LRU-K (近似 LRU-2) | 基于访问时间戳 |
| DB2 | 分层 LRU + 预取队列 | 可配置 |
| SAP HANA | column unload priority + LRU | 按列管理 |
| SQLite | 近似 LRU | 简单链表 |
| DuckDB | 基于 buffer manager 的引用计数 + LRU | -- |
| H2 | LRU | -- |
| Derby / HSQLDB | LRU | -- |
| ClickHouse uncompressed cache | SLRU (Segmented LRU) | 防止扫描污染 |
| StarRocks / Doris page cache | SLRU/LRU-K | 防止一次性扫描污染 |
| TiKV block cache | LRU + 分片 | RocksDB LRUCache |
| Informix | LRU + 队列 | 脏队列 / 干净队列分离 |
| Firebird | LRU | -- |

**MySQL 中点 LRU 是 OLTP 领域的经典设计**：新读入的页不放在链表头部（"年轻"端），而是放在 3/8 位置的"old sublist"头部，只有真正被第二次访问（间隔 > `innodb_old_blocks_time`）才"升级"到 young。这个设计专门对抗"一次性全表扫描污染缓冲池"问题。

**Oracle 的 TOUCH_COUNT 机制**：每个 buffer header 维护一个访问计数，每次访问递增；扫描时把低 touch_count 的驱逐，类似 CLOCK 但权重更丰富。

### 5. 预热 (Pre-warm)

| 引擎 | 机制 | 细节 |
|------|------|------|
| PostgreSQL | `pg_prewarm` 扩展 | `pg_prewarm('table')` 装入 shared_buffers |
| PostgreSQL 11+ | `pg_prewarm.autoprewarm` | 后台进程记录/恢复 buffer 状态 |
| MySQL 5.6+ | `innodb_buffer_pool_dump_at_shutdown` / `load_at_startup` | 保存 space_id + page_no 列表 |
| MariaDB | 同 MySQL | 兼容 |
| Oracle | `ALTER TABLE ... CACHE` + DB_KEEP_CACHE_SIZE | 绑定 KEEP 池 |
| Oracle 11g+ | `DBMS_SHARED_POOL.MARKHOT` 等内部 | -- |
| SQL Server | 无官方 pre-warm；可用 `SELECT *` 扫描 | BPE 可持久化 |
| DB2 | `BLOCK BASED BUFFER POOLS` + `db2pd -buffer` | 可脚本化 |
| ClickHouse | `SYSTEM RELOAD DICTIONARY` / `OPTIMIZE` 扫描 | 无专用预热 |
| DuckDB | 显式 `PRAGMA force_checkpoint` 或扫描 | 按需 |
| TiDB | `LOAD STATS` + 自动热点加载 | -- |
| Databricks | Delta cache 预热 `CACHE SELECT` | SSD 层 |
| Spark SQL | `CACHE TABLE` | 显式 |
| Impala | `ALTER TABLE ... SET CACHED IN 'pool'` | HDFS 层 cache |
| SingleStore | `OPTIMIZE TABLE ... WARM BLOB CACHE` | -- |
| SAP HANA | `LOAD ... INTO MEMORY` | 列级 |
| Exasol | 自动 warm up on boot | -- |
| 其他未列出 | 无专用机制 | -- |

### 6. 页面绑定 (Pin Pages)

| 引擎 | 机制 | 粒度 |
|------|------|------|
| Oracle | `ALTER TABLE t STORAGE (BUFFER_POOL KEEP)` | 表 / 分区 |
| DB2 | 将表空间绑定到专用 bufferpool | 表空间 |
| MySQL | 无"钉住"，但 old sublist 可视为隔离 | -- |
| SQL Server | 无显式 pin | -- |
| PostgreSQL | 无（只有短期 pin 计数用于读写保护） | -- |
| Informix | `ALTER TABLE ... LOCK MODE PAGE` + 专用 bufferpool | 表空间 |
| Impala | `SET CACHED IN 'pool' WITH REPLICATION = N` | HDFS 块 |
| SAP HANA | `ALTER TABLE ... PRELOAD` / UNLOAD PRIORITY | 列 |
| Spark SQL | `CACHE TABLE ... MEMORY_ONLY` | 表 |
| 其他 | 不支持 | -- |

### 7. 脏页刷写控制 (Dirty Page Flush Control)

| 引擎 | 参数 | 语义 |
|------|------|------|
| PostgreSQL | `bgwriter_lru_maxpages` / `bgwriter_delay` | 后台扫描并刷 |
| PostgreSQL | `checkpoint_completion_target` | 控制 checkpoint 平滑度 |
| MySQL InnoDB | `innodb_io_capacity` / `innodb_max_dirty_pages_pct` | 上限 75% |
| MySQL InnoDB | `innodb_flush_neighbors` | 相邻脏页合并 |
| Oracle | `FAST_START_MTTR_TARGET` | 目标恢复时间反推刷写速率 |
| SQL Server | `recovery interval` / lazy writer / checkpoint | 自动 |
| DB2 | `CHNGPGS_THRESH` / `NUM_IOCLEANERS` | 脏页阈值 + 清理线程 |
| SQLite | `PRAGMA wal_autocheckpoint` | WAL 合并 |
| ClickHouse | `background_pool_size` + merge | 合并时刷 |
| RocksDB 系 | `max_background_flushes` | memtable flush |
| InnoDB adaptive flushing | `innodb_adaptive_flushing` | 按 redo 增长自适应 |

### 8. 后台写入 (Background Writer / Writer)

| 引擎 | 进程/线程 | 目的 |
|------|---------|------|
| PostgreSQL | bgwriter + checkpointer + walwriter | 分离 |
| MySQL InnoDB | page cleaner threads (`innodb_page_cleaners`) | 5.7+ 默认 4 |
| Oracle | DBWn (最多 36 个) | 写脏块 |
| SQL Server | Lazy Writer + checkpoint | 2 个路径 |
| DB2 | IOCLEANER 进程 | `NUM_IOCLEANERS` |
| SQLite | 单线程 + WAL | -- |
| Informix | Page Cleaner 线程 | `CLEANERS` |
| Firebird | Cache Writer | 可选 |

### 9. 依赖 OS Page Cache

| 引擎 | 依赖程度 | 说明 |
|------|---------|------|
| PostgreSQL | 高（双缓冲） | shared_buffers 后还有 OS cache |
| SQLite | 高 | 小 page cache + 文件系统 |
| MonetDB | 极高 | 几乎全 mmap |
| Hive / Impala on HDFS | 高 | HDFS read cache + OS |
| MySQL InnoDB | 低 | `O_DIRECT` 默认，绕过 OS cache |
| Oracle | 低 | 通常用 direct I/O / ASM raw |
| SQL Server | 低 | 使用 FILE_FLAG_NO_BUFFERING |
| DB2 | 低 | `NO FILE SYSTEM CACHING` 默认 |
| ClickHouse | 中 | mmap + 自管缓存 |
| RocksDB 系 | 可选 | `use_direct_reads` |
| DuckDB | 低-中 | 自管 buffer manager |
| QuestDB | 高 | mmap 为主 |
| MariaDB ColumnStore | 中 | 混合 |

### 10. NUMA 感知 (NUMA-aware Buffer Pool)

| 引擎 | NUMA 支持 | 机制 |
|------|----------|------|
| MySQL InnoDB | 是 (`innodb_numa_interleave`) | 交错分配 |
| Oracle | 是 (`_enable_NUMA_support`) | 12c+ |
| SQL Server | 是（自动） | soft-NUMA + buffer partitions |
| DB2 | 是 | 按 NUMA node 分配 bufferpool |
| PostgreSQL | 有限（通过 numactl） | 自身无 NUMA 感知 |
| ClickHouse | 有限 | `--numa` 参数仅线程亲和 |
| SAP HANA | 是（深度集成） | column table 分区到 NUMA node |
| Exasol | 是 | 节点级 NUMA 感知 |
| SingleStore | 是 | leaf node 亲和 |
| TiKV | 是（通过 cgroup） | RocksDB block cache NUMA |
| 其他 | 否 | -- |

## 详细引擎分析

### PostgreSQL：shared_buffers + OS cache 双层

PostgreSQL 的设计哲学非常鲜明：**只做"小而精"的共享缓冲区，其余交给内核**。

```ini
# postgresql.conf
shared_buffers = 16GB          # 25% of 64GB RAM
effective_cache_size = 48GB    # 告诉优化器: OS cache 大约 48GB
bgwriter_delay = 200ms
bgwriter_lru_maxpages = 100
bgwriter_lru_multiplier = 2.0
checkpoint_completion_target = 0.9
```

为什么不设 80% 给 shared_buffers？原因有几条：

1. **双缓冲浪费不明显**：即使同一个页同时存在于 shared_buffers 和 OS cache，现代 Linux 对 OS cache 的管理效率极高，浪费几乎可以忽略
2. **CLOCK-sweep 在超大池下性能下降**：shared_buffers 超过 40GB 后，页扫描成本显著上升
3. **检查点抖动**：shared_buffers 越大，checkpoint 时要刷的脏页越多，WAL 峰值 I/O 越高
4. **fork() 代价**：PG 使用进程模型，shared memory 过大影响 fork/exec 性能（尽管已有优化）

```sql
-- 查看 shared_buffers 使用情况
SELECT c.relname,
       count(*) AS buffers,
       pg_size_pretty(count(*) * 8192) AS cached_size
FROM pg_buffercache b
JOIN pg_class c ON b.relfilenode = pg_relation_filenode(c.oid)
GROUP BY c.relname
ORDER BY 2 DESC
LIMIT 20;

-- 命中率
SELECT datname,
       100.0 * blks_hit / nullif(blks_hit + blks_read, 0) AS hit_pct
FROM pg_stat_database;
```

**CLOCK-sweep 算法**：每个 buffer header 有一个 `usage_count`（0-5）。读命中时递增，驱逐扫描器（clocksweep hand）顺序扫描，每扫一个递减，降到 0 时可被换出。相比双向链表 LRU，无需在热路径上操作指针，大大降低了并发读下的内存屏障开销。

**pg_prewarm**：

```sql
CREATE EXTENSION pg_prewarm;

-- 立即装入 shared_buffers
SELECT pg_prewarm('large_table', 'buffer');

-- 只读 OS cache 不入 shared_buffers
SELECT pg_prewarm('large_table', 'read');

-- 仅 prefetch（posix_fadvise）
SELECT pg_prewarm('large_table', 'prefetch');
```

PG 11 引入 `pg_prewarm.autoprewarm_worker`：后台进程每 5 分钟把 shared_buffers 中的 buffer 列表写到 `autoprewarm.blocks` 文件，启动时自动恢复，解决了"重启即冷启动"痛点。

### MySQL InnoDB：缓冲池是生命线

MySQL 走的是另一条路——**把内存的 70-80% 全部交给 InnoDB，用 O_DIRECT 绕过 OS cache**。

```ini
# my.cnf
innodb_buffer_pool_size = 48G          # 64G 机器的 75%
innodb_buffer_pool_instances = 8       # 默认, 分片降 mutex 竞争
innodb_buffer_pool_chunk_size = 128M   # 在线调整粒度
innodb_old_blocks_pct = 37             # 3/8 用于 old sublist
innodb_old_blocks_time = 1000          # 毫秒, 防止扫描升级
innodb_io_capacity = 2000              # SSD
innodb_io_capacity_max = 4000
innodb_max_dirty_pages_pct = 75
innodb_flush_method = O_DIRECT
innodb_page_cleaners = 4
innodb_flush_neighbors = 0             # SSD 上关闭
innodb_numa_interleave = ON
innodb_buffer_pool_dump_at_shutdown = ON
innodb_buffer_pool_load_at_startup = ON
innodb_buffer_pool_dump_pct = 25       # 只 dump 热 25%
```

**中点插入 LRU 详解**：

```
LRU 链表 (示意):

  head (young sublist, 5/8)                tail
    │                                       │
    ▼                                       ▼
  [P1]-[P2]-[P3]- ... -[Pm] | [Pm+1]-...-[Pn]
                           ▲
                           │
                  midpoint (3/8 from tail, old sublist)
```

- 新页插入：放在 midpoint 位置（old sublist 头）
- 命中 old sublist：若距首次插入超过 `innodb_old_blocks_time`，升级到 young head
- 命中 young sublist：只在处于后 1/4 时才移动到 head（`innodb_old_blocks_pct` 反过来控制）

对抗扫描污染的效果：一次 `SELECT * FROM huge_table` 读入的页进 old sublist，立即被下一批挤掉，不会污染 young 区的 OLTP 热点。

**buffer_pool_instances 的作用**：8 个独立的子池，每个有自己的 LRU 链表和 mutex，把"一把大锁"拆成 8 把。页按 `(space_id, page_no)` 哈希到子池。只有在 >1GB 时 Linux 默认启用 8 实例。

### Oracle：三个命名池 + KEEP/RECYCLE 策略

Oracle 是**多命名池思想的开创者**。从 8i 起就有 3 个固定池：

| 池 | 参数 | 用途 |
|----|------|------|
| DEFAULT | `DB_CACHE_SIZE` | 普通对象 |
| KEEP | `DB_KEEP_CACHE_SIZE` | 常驻热表：参考数据、小维表 |
| RECYCLE | `DB_RECYCLE_CACHE_SIZE` | 一次性大扫描：避免污染 DEFAULT |

```sql
-- 分配三个池
ALTER SYSTEM SET DB_CACHE_SIZE = 8G;
ALTER SYSTEM SET DB_KEEP_CACHE_SIZE = 2G;
ALTER SYSTEM SET DB_RECYCLE_CACHE_SIZE = 512M;

-- 将小维表绑定到 KEEP
ALTER TABLE country_codes
    STORAGE (BUFFER_POOL KEEP);

-- 将大日志表绑定到 RECYCLE
ALTER TABLE audit_log_2024
    STORAGE (BUFFER_POOL RECYCLE);

-- 查看使用情况
SELECT name, block_size, current_size
FROM v$buffer_pool;

-- 命中率按池查看
SELECT name,
       1 - (physical_reads / nullif(db_block_gets + consistent_gets, 0)) AS hit_ratio
FROM v$buffer_pool_statistics;
```

**Oracle 的 TOUCH_COUNT LRU**：每个 buffer header 维护 `tch` 字段，访问时递增。驱逐扫描器优先换出 tch=0 的 buffer。这是介于 LRU 与 LFU 之间的折中——既考虑"最近"也考虑"频繁"。

Oracle 11g 之后还提供了 Database Smart Flash Cache（扩展到 SSD），思想与 SQL Server BPE 类似。

### SQL Server：单缓冲池 + Buffer Pool Extension

SQL Server 是"单缓冲池 + 智能驱逐"路线：

```sql
-- 设置内存上下限
EXEC sp_configure 'max server memory (MB)', 56320;  -- 55GB
EXEC sp_configure 'min server memory (MB)', 8192;
RECONFIGURE;

-- 查看内存 clerk 分布
SELECT type, pages_kb / 1024 AS MB
FROM sys.dm_os_memory_clerks
ORDER BY pages_kb DESC;

-- Buffer Pool Extension (2014+): 扩展到 SSD
ALTER SERVER CONFIGURATION
SET BUFFER POOL EXTENSION ON
    (FILENAME = 'D:\SSD\bpe.bpe', SIZE = 128 GB);

-- 查看 BPE 状态
SELECT * FROM sys.dm_os_buffer_pool_extension_configuration;

-- 页在哪一层
SELECT COUNT(*) AS pages,
       is_in_bpool_extension
FROM sys.dm_os_buffer_descriptors
GROUP BY is_in_bpool_extension;
```

SQL Server 使用 **LRU-K 的近似变体**（LRU-2），基于每个页的最后两次访问时间戳。驱逐时选择"倒数第二次访问时间最久"的页。

**Lazy Writer** 是独立的后台线程，定期扫描 buffer pool，把最少使用的脏页写回并标记为 free。checkpoint 则是周期性或由 `recovery interval` 触发的批量刷写。

### DB2：任意多个命名 bufferpool

DB2 在灵活性上走得最远——你可以创建任意多个 bufferpool，按表空间绑定：

```sql
-- 创建多个 bufferpool
CREATE BUFFERPOOL bp_oltp_8k
    SIZE 256000 PAGESIZE 8K;

CREATE BUFFERPOOL bp_dw_32k
    SIZE 128000 PAGESIZE 32K;

CREATE BUFFERPOOL bp_hot_keep
    SIZE 50000 PAGESIZE 8K
    EXTENDED STORAGE;        -- 扩展存储

-- 创建表空间时绑定
CREATE TABLESPACE ts_orders
    PAGESIZE 8K
    MANAGED BY AUTOMATIC STORAGE
    BUFFERPOOL bp_oltp_8k;

-- 动态调整大小
ALTER BUFFERPOOL bp_oltp_8k SIZE 512000 AUTOMATIC;

-- 查看命中率
SELECT bp_name,
       (pool_data_lbp_pages_found + pool_index_lbp_pages_found) * 100.0
       / nullif(pool_data_l_reads + pool_index_l_reads, 0) AS hit_ratio
FROM table(mon_get_bufferpool('', -2));
```

**Extended Storage**：DB2 早期（v7/v8）就支持把 bufferpool 扩展到 4GB+ 的物理内存，通过辅助缓存层。这是 SQL Server BPE 的"内存版"先驱。

DB2 还有 `BLOCK BASED BUFFER POOLS`：为 prefetch 预留连续块，使顺序扫描的 I/O 合并更高效。

### ClickHouse：多个专用缓存

ClickHouse 完全抛弃了"统一缓冲池"概念，为不同数据类型设独立缓存：

```xml
<clickhouse>
    <mark_cache_size>5368709120</mark_cache_size>          <!-- 5GB -->
    <uncompressed_cache_size>8589934592</uncompressed_cache_size>  <!-- 8GB -->
    <mmap_cache_size>1000</mmap_cache_size>                <!-- 文件数 -->
    <index_mark_cache_size>0</index_mark_cache_size>
    <query_cache>
        <max_size_in_bytes>1073741824</max_size_in_bytes>  <!-- 1GB -->
    </query_cache>
</clickhouse>
```

| 缓存 | 内容 | 单位 |
|------|------|------|
| mark cache | 列数据的索引标记 (mrk2) | 字节 |
| uncompressed cache | 解压后的 column block | 字节，默认 0（禁用） |
| mmap cache | 已 mmap 的文件句柄 | 个数 |
| query cache | 查询结果 | 字节 |
| page cache | 依赖 OS | -- |

```sql
-- 查看各缓存命中率
SELECT event, value FROM system.events
WHERE event LIKE '%Cache%';

-- MarkCacheHits / MarkCacheMisses
-- UncompressedCacheHits / UncompressedCacheMisses
-- QueryCacheHits / QueryCacheMisses

-- 强制刷 mark cache
SYSTEM DROP MARK CACHE;
SYSTEM DROP UNCOMPRESSED CACHE;
SYSTEM DROP MMAP CACHE;
```

为什么历史上 `uncompressed_cache_size` 默认是 0？因为对于全表扫描型查询，缓存解压结果反而会污染其他查询的命中——列存的"每次解压都不贵"让 OS page cache 已经够用。早期社区版 ClickHouse（18.x–21.x）因此将其关闭，只在**点查 / 小范围查询 >50% 的负载**下才建议开启。不过自 ClickHouse 22.x 起官方默认配置已经将其调整为约 8 GiB（上方 `config.xml` 示例即为现代默认），新部署无需手动打开。

### SQLite：page_cache_size 三种含义

```sql
-- 正数: 页数 (默认 -2000 = 2MB)
PRAGMA cache_size = 10000;   -- 10000 pages

-- 负数: KiB (推荐)
PRAGMA cache_size = -200000; -- 200 MB
```

SQLite 的缓存完全是 per-connection 的（非共享模式），这意味着 10 个连接会有 10 个独立缓存。从 3.11 起有 shared cache 模式，但已不推荐。大多数负载下，SQLite 的真正"缓冲池"是 OS page cache——内存足够时，整个数据库文件都可能常驻 page cache。

### DuckDB：memory_limit 统一预算

DuckDB 没有独立的"缓冲池"——它有一个 **buffer manager**，同时服务于表数据缓存和执行算子内存：

```sql
SET memory_limit = '10GB';
SET temp_directory = '/tmp/duckdb_spill';
SET threads = 8;

-- 查看当前使用
SELECT * FROM duckdb_memory();
```

当内存不够时，DuckDB 会把 buffer manager 中的冷页 spill 到 `temp_directory`。这个模型的精妙之处在于：**OLAP 查询通常需要大量执行内存（hash table / sort buffer），把缓存预算和执行预算合并能避免两头都不够用**。

`memory_limit` 默认是 80% RAM，但因为 DuckDB 常作为进程内库被嵌入宿主程序，实际使用中用户往往会调低。

### 其他引擎速览

**SAP HANA**：列存整列驻留内存；`ALTER TABLE ... PRELOAD` 强制加载；`UNLOAD PRIORITY` 控制驱逐顺序；column store 按 NUMA node 分布式存放。

**SingleStore**：行存放在 rowstore（全内存），列存在 columnstore（SSD + blob cache）；`OPTIMIZE TABLE t WARM BLOB CACHE` 预热。

**Exasol**：开机时自动预热，按表的 access pattern 智能加载；缓冲池几乎占满 DB RAM。

**TiKV**：依赖 RocksDB 的 block cache + page cache，默认 45% 内存；支持"共享 block cache"让多个 ColumnFamily 共用预算。

**CockroachDB**：基于 Pebble（RocksDB 重写），`--cache` 参数控制 block cache，默认只有 128MB（因为预期多租户部署），生产环境必须调到 25% RAM 以上。

**Hive / Impala on HDFS**：无独立缓冲池，依赖 HDFS 客户端 cache + OS page cache；Impala 提供 `ALTER TABLE ... SET CACHED IN 'pool'` 触发 HDFS Centralized Cache Management 固定块在 DataNode 内存。

**Materialize / RisingWave**：流式增量视图引擎，buffer pool 的角色被"arrangements"（增量状态）取代；RisingWave 用 `block_cache_capacity_mb` 控制底层对象存储读取的缓存。

**Firebolt / Databricks / Snowflake**：全托管，用户无法直接调整。Databricks 的 **Delta Cache** 会把 Parquet 解码后的数据放在集群节点 SSD，查询下次访问直接命中本地 SSD。

## Oracle KEEP / RECYCLE 策略深度剖析

这是 Oracle DBA 面试的经典问题。典型场景：

**场景 A：小维表被大事实表挤掉**

```sql
-- 问题: products 表 10MB, 被 1TB 的 sales 表扫描不断挤出 DEFAULT 池
-- 解决: 绑定到 KEEP 池
ALTER SYSTEM SET DB_KEEP_CACHE_SIZE = 256M;
ALTER TABLE products STORAGE (BUFFER_POOL KEEP);

-- 首次全扫触发加载
SELECT /*+ FULL(products) */ COUNT(*) FROM products;

-- 之后 products 的页永远不会被 sales 扫描挤出
```

**场景 B：一次性日志扫描污染热点**

```sql
-- 问题: 每晚的审计扫描把 OLTP 热点从 DEFAULT 池挤掉
-- 解决: 绑定 audit_log 到 RECYCLE 池
ALTER SYSTEM SET DB_RECYCLE_CACHE_SIZE = 512M;
ALTER TABLE audit_log_2024 STORAGE (BUFFER_POOL RECYCLE);

-- 审计扫描时, 页只进 RECYCLE 池并很快被下一批挤掉
-- DEFAULT 池中的 OLTP 热点不受影响
```

KEEP 池的容量规划原则：**总大小 ≥ 所有绑定表的 sum(blocks) × 1.25**。RECYCLE 池的原则相反：**刻意设小**，让页被快速驱逐，仅作为"临时中转站"。

Oracle 在 10g 引入的 ASMM（Automatic Shared Memory Management）和 11g 的 AMM（Automatic Memory Management）可以自动调整这些池大小，但对于生产关键表，DBA 通常仍会手动固定 KEEP 池。

## MySQL buffer pool dump/load 深度剖析

MySQL 5.6 引入的这个特性，解决了"重启即冷启动 1 小时"的痛点。

**工作原理**：

```
关机时:
  1. 扫描 LRU 链表, 按 young → old 顺序记录 (space_id, page_no)
  2. 根据 innodb_buffer_pool_dump_pct 截断列表
  3. 写入 ib_buffer_pool 文件 (纯文本, 每行一个 page)

启动时:
  1. 读 ib_buffer_pool 文件
  2. 排序 page list (按 space_id, page_no) → 转为顺序 I/O
  3. 后台线程并发读入 shared_buffers
  4. 前台服务立即可用, 即使加载未完成
```

**dump 文件示例**：

```
# ib_buffer_pool (文本)
0,12
0,14
4,1523
4,1524
...
```

**关键配置**：

```ini
innodb_buffer_pool_dump_at_shutdown = ON
innodb_buffer_pool_load_at_startup = ON
innodb_buffer_pool_dump_pct = 25         # 只 dump LRU 头部 25% (最热)
innodb_buffer_pool_load_abort = OFF      # 是否允许中断加载
```

**手动触发**：

```sql
-- 立即 dump (不等关机)
SET GLOBAL innodb_buffer_pool_dump_now = ON;

-- 立即 load (不等启动)
SET GLOBAL innodb_buffer_pool_load_now = ON;

-- 检查进度
SHOW STATUS LIKE 'Innodb_buffer_pool_dump_status';
SHOW STATUS LIKE 'Innodb_buffer_pool_load_status';
```

**加载是纯 I/O 优化，不重放 WAL**：dump 只记录 `(space_id, page_no)`，不保存页内容；load 时重新从磁盘读入。这意味着两次启动之间的数据变化不影响 dump/load 机制的正确性——因为 MySQL 读的总是最新的磁盘页。

**典型效果**：512GB buffer pool 的实例，不用 dump/load 启动后命中率爬升到 99% 需要约 2 小时；使用 dump/load 约 5-10 分钟。

## PostgreSQL pg_prewarm + OS cache 的协同

PG 的"双层缓存"可以被 pg_prewarm 的不同模式精细控制：

```sql
-- 模式 1: buffer (进 shared_buffers)
SELECT pg_prewarm('orders', 'buffer');
-- 实际做: 逐页调 ReadBuffer(), 触发 CLOCK-sweep 驱逐

-- 模式 2: read (只进 OS cache)
SELECT pg_prewarm('orders', 'read');
-- 实际做: 逐页用 read(), 数据进内核 page cache 但不占 shared_buffers

-- 模式 3: prefetch (posix_fadvise)
SELECT pg_prewarm('orders', 'prefetch');
-- 实际做: 告诉内核"我将要读这些页", 内核异步预取
```

**典型策略**：

```sql
-- 启动后: 先 prefetch 大表到 OS cache (不占 shared_buffers)
SELECT pg_prewarm(oid::regclass::text, 'prefetch')
FROM pg_class
WHERE relname IN ('orders', 'order_items', 'customers')
  AND relkind = 'r';

-- 再把真正热的小索引加载进 shared_buffers
SELECT pg_prewarm('idx_orders_customer_id', 'buffer');
SELECT pg_prewarm('idx_orders_created_at', 'buffer');
```

**autoprewarm** 的工作机制：

```sql
-- 需要在 shared_preload_libraries 加载
-- shared_preload_libraries = 'pg_prewarm'
-- pg_prewarm.autoprewarm = on
-- pg_prewarm.autoprewarm_interval = 300s

-- 每 5 分钟, worker 把当前 buffer 列表写到 $PGDATA/autoprewarm.blocks
-- 启动时 (checkpoint 后) 自动读取并装入
```

**与 MySQL dump/load 的对比**：

| 维度 | PG autoprewarm | MySQL dump/load |
|------|---------------|-----------------|
| 触发点 | 周期 + 关机 | 关机 + 手动 |
| 存储格式 | 二进制 (db_oid, tablespace, rel, fork, block) | 文本 (space_id, page_no) |
| 装入方式 | 前台单线程 | 后台并发 |
| 装入比例 | 全部 | 可配 (dump_pct) |
| 默认启用 | 否 | 是 (8.0+) |

## 关键发现

### 1. 内存分配哲学的分裂

从 shared_buffers 的默认设置可以看出两种截然不同的哲学：

- **"占满内存派"**（MySQL/Oracle/SQL Server/DB2）：默认就期望用户把 70-90% 内存交给自己，O_DIRECT 绕过 OS cache 避免双缓冲
- **"协作派"**（PostgreSQL/SQLite/MonetDB）：只拿一小块，剩下交给 OS page cache，接受双缓冲的代价以换取简单性

这种分裂不是"谁对谁错"的问题——PG 之所以能在大内存机器上运行良好，正是因为 Linux page cache 的优化已经足够好。

### 2. 中点 LRU 是对抗扫描污染的成熟方案

MySQL 的 3/8 midpoint + `innodb_old_blocks_time` 是经过 20 年验证的设计。后来 ClickHouse 的 SLRU、Oracle 的 TOUCH_COUNT、SQL Server 的 LRU-K 都在解决同一个问题：**如何让一次性大扫描不破坏热点**。CLOCK-sweep（PostgreSQL）则是另一条路——用"分级 usage_count"近似达到同样效果。

### 3. 多命名池只在 Oracle/DB2/Sybase 这条血脉里存活

当年 Oracle 发明的 KEEP/RECYCLE 思想非常先进，但除了 IBM DB2 和 Sybase ASE 继承下来外，后来的开源引擎几乎都没走这条路。原因：

- 复杂度显著增加（DBA 要手动规划每个表的 pool 归属）
- 现代 LRU 变体（midpoint、SLRU）已经能自动处理大部分扫描污染
- 云时代 RAM 充裕，不需要精细划分

MySQL 的 `innodb_buffer_pool_instances` 是**把一个池切片**，不是**多个功能各异的池**，本质是不同概念。

### 4. BPE / Flash Cache：内存与 SSD 的分层

SQL Server 的 Buffer Pool Extension（2014）、Oracle Database Smart Flash Cache（11g）、DB2 Extended Storage 都在尝试同一件事：**把缓冲池扩展到 SSD**。思路是把 LRU 尾部的"温页"放 SSD 而非直接淘汰，下次命中 SSD 比从 HDD 读快 100 倍。

这个理念在云时代被 **Databricks Delta Cache** 和 **Firebolt F3 Engine Cache** 复活——不过现在缓存的对象是对象存储（S3）的 Parquet 块，目标是避免每次都跨网络拉远端文件。

### 5. 列存引擎走向"多专用缓存"

ClickHouse、StarRocks、Doris、DatabendDB 的共同选择是**为不同数据设独立缓存**：mark cache（索引）、uncompressed cache（数据）、mmap cache（文件句柄）、query cache（结果）。每一层的命中率、淘汰策略都独立调优。

这个方向的本质原因：列存数据粒度差异巨大（几字节的 mark vs 几 MB 的 data block），放在同一个 LRU 里必然导致小对象被大对象挤掉。

### 6. 内存优先与统一预算

DuckDB、SingleStore、SAP HANA 代表了一个新趋势：**不区分"缓存"与"执行内存"**，一个预算统一管理。OLAP 查询的 hash join / sort / window 本来就需要大量临时内存，把它们和"数据缓存"绑在一起能更好地 spill 和回收。

### 7. 预热是生产系统的标配

主流引擎都提供了某种预热机制：

| 引擎 | 机制 | 持久化 |
|------|------|-------|
| MySQL | dump/load | 文本 |
| PG | pg_prewarm + autoprewarm | binary |
| Oracle | KEEP pool + CACHE 提示 | 启动自动 |
| SAP HANA | PRELOAD | 元数据 |
| SingleStore | WARM BLOB CACHE | 命令 |
| Exasol | 自动 | 启动集成 |

没有预热的引擎（例如早期 SQL Server、大多数 NewSQL）在大数据集上重启后需要数小时才能恢复命中率，这对 OLTP 是不可接受的。

### 8. NUMA 感知仍是大内存机器的必答题

256GB+ 服务器上，跨 NUMA socket 访问内存延迟比本地访问高 50-100%。MySQL 的 `innodb_numa_interleave`、Oracle 的 NUMA 支持、SAP HANA 的深度 NUMA 集成都在处理这个问题。PostgreSQL 目前只能靠 `numactl --interleave=all` 这种外部方案——这是 PG 在超大单机部署下相对弱势的一个点。

### 9. OS page cache 不是"免费资源"

相信 OS cache 的引擎（PG/SQLite/MonetDB/Hive）在以下场景会吃亏：

- 其他进程（备份、日志 rotation、临时文件）抢占 page cache
- 内核的 LRU 对 DB 页没有任何语义，可能淘汰本应留存的关键索引
- 跨 NUMA 的 cache 访问内核调度不友好
- fsync 会把写入的数据留在 cache 中（PG 的 `effective_io_concurrency` 反映了这一点）

但对中小规模（< 64GB）数据库，OS cache 依然是最简单、最稳健的选择。

### 10. 云原生 = 用户看不到缓冲池

Snowflake、BigQuery、Redshift、Firebolt、Azure Synapse 全都对用户隐藏了缓冲池配置。这是云时代的必然：

- 多租户隔离要求服务商统一管理内存
- 按量计费模型下，用户不应该为"没命中"的冷启动额外付费
- 服务内部可以使用更激进的策略（跨 warehouse 的分布式 cache、SSD 分层）

代价是**可调优性下降**——当 Snowflake 查询变慢时，你无法像 MySQL 那样查 `innodb_buffer_pool_reads`，只能扩大 warehouse。

## 总结对比矩阵

### 核心能力速查

| 能力 | PG | MySQL | Oracle | SQL Server | DB2 | ClickHouse | DuckDB | SAP HANA | SingleStore |
|------|----|------|--------|-----------|-----|-----------|--------|---------|-------------|
| 固定大小池 | 是 | 是 | 是 | 是 | 是 | 分缓存 | 统一 | 列常驻 | 统一 |
| 多命名池 | -- | 分实例 | 3 个 | -- | 任意 | 功能分 | -- | 列分区 | -- |
| CLOCK-sweep | 是 | -- | -- | -- | -- | -- | -- | -- | -- |
| 中点 LRU | -- | 是 | TOUCH | LRU-K | 分层 | SLRU | LRU | -- | -- |
| 预热 | pg_prewarm | dump/load | KEEP | -- | 脚本 | -- | -- | PRELOAD | WARM CACHE |
| 页面 pin | -- | -- | KEEP pool | -- | 表空间 | -- | -- | UNLOAD PRIO | -- |
| 脏页控制 | bgwriter | pct + io_cap | MTTR | lazy writer | CLEANERS | merge | -- | auto | -- |
| NUMA 感知 | 外部 | 是 | 是 | 是 | 是 | 有限 | -- | 是 | 是 |
| OS cache 依赖 | 高 | 低 | 低 | 低 | 低 | 中 | 低-中 | 低 | 低 |
| BPE / SSD 扩展 | -- | -- | Flash | BPE | -- | -- | -- | -- | blob cache |

### 调优建议矩阵

| 场景 | 推荐设置 |
|------|---------|
| PG OLTP，64GB RAM | `shared_buffers = 16GB`，`effective_cache_size = 48GB`，启用 pg_prewarm.autoprewarm |
| MySQL OLTP，64GB RAM | `innodb_buffer_pool_size = 48G`，`instances = 8`，`dump/load = ON`，O_DIRECT |
| Oracle 混合负载 | DEFAULT 60% + KEEP 20%（小维表）+ RECYCLE 5%（审计日志） |
| SQL Server，256GB | `max server memory = 220GB`，考虑 BPE 500GB 到 NVMe |
| DB2 DW | 按 page size 分 bufferpool（8K/16K/32K），按 workload 绑定表空间 |
| ClickHouse 点查多 | 开启 `uncompressed_cache_size = 10G`，增大 `mark_cache_size` |
| DuckDB 嵌入式 | `memory_limit` 设为可用 RAM 的 70%，留 temp 空间给 spill |
| 云数仓 | 优先用 warehouse size 调整而非纠结缓存 |

## 参考资料

- PostgreSQL: [Resource Consumption - shared_buffers](https://www.postgresql.org/docs/current/runtime-config-resource.html)
- PostgreSQL: [pg_prewarm](https://www.postgresql.org/docs/current/pgprewarm.html)
- PostgreSQL: [pg_buffercache](https://www.postgresql.org/docs/current/pgbuffercache.html)
- MySQL: [InnoDB Buffer Pool Configuration](https://dev.mysql.com/doc/refman/8.0/en/innodb-buffer-pool.html)
- MySQL: [Saving and Restoring the Buffer Pool State](https://dev.mysql.com/doc/refman/8.0/en/innodb-preload-buffer-pool.html)
- MySQL: [Making the Buffer Pool Scan Resistant (midpoint LRU)](https://dev.mysql.com/doc/refman/8.0/en/innodb-performance-midpoint_insertion.html)
- Oracle: [Multiple Buffer Pools](https://docs.oracle.com/en/database/oracle/oracle-database/19/admin/managing-memory.html)
- Oracle: [Database Smart Flash Cache](https://docs.oracle.com/en/database/oracle/oracle-database/19/admin/managing-memory.html)
- SQL Server: [Buffer Pool Extension](https://learn.microsoft.com/en-us/sql/database-engine/configure-windows/buffer-pool-extension)
- SQL Server: [sys.dm_os_memory_clerks](https://learn.microsoft.com/en-us/sql/relational-databases/system-dynamic-management-views/sys-dm-os-memory-clerks-transact-sql)
- DB2: [CREATE BUFFERPOOL](https://www.ibm.com/docs/en/db2/11.5?topic=statements-create-bufferpool)
- DB2: [Buffer Pool Design](https://www.ibm.com/docs/en/db2/11.5?topic=performance-buffer-pools)
- ClickHouse: [Server Settings - Caches](https://clickhouse.com/docs/en/operations/server-configuration-parameters/settings)
- DuckDB: [Memory Management](https://duckdb.org/docs/operations_manual/footprint_of_duckdb)
- SAP HANA: [Column Store Memory Management](https://help.sap.com/docs/SAP_HANA_PLATFORM)
- SQLite: [PRAGMA cache_size](https://www.sqlite.org/pragma.html#pragma_cache_size)
- Corbato, F.J. "A Paging Experiment with the Multics System" (1968) - CLOCK algorithm origin
- O'Neil et al. "The LRU-K Page Replacement Algorithm" (1993), SIGMOD
- Effelsberg, W. & Haerder, T. "Principles of Database Buffer Management" (1984), ACM TODS
