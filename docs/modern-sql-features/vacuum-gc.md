# VACUUM 与垃圾回收 (VACUUM and Garbage Collection)

一个 PostgreSQL DBA 凌晨三点被电话叫醒，看到的不是磁盘写满，而是 `database is not accepting commands to avoid wraparound data loss`——XID 即将耗尽，所有写入都被冻结。这是 MVCC 数据库工程师最深的恐惧，也是 VACUUM/GC 子系统存在的根本原因。

## 为什么 MVCC 数据库需要垃圾回收

所有 MVCC（多版本并发控制）数据库都用一个简单的代价换取读写不互相阻塞的能力：UPDATE 不是真的更新，而是写一条新版本；DELETE 不是真的删除，而是给旧版本打上"已删除"标记。这意味着：

1. **磁盘空间会持续膨胀**：每个 UPDATE/DELETE 都留下一行"幽灵"
2. **可见性判断越来越慢**：扫描时必须跳过越来越多的死版本
3. **索引也会膨胀**：索引项可能指向已被覆盖的行
4. **事务 ID 会耗尽**：32 位 XID 总有用完的一天

垃圾回收就是把这些死掉的行版本（dead tuples）、过期的 undo 记录、墓碑（tombstone）等真正清理掉，把空间还给文件系统或重用。在 PostgreSQL 里这件事叫 VACUUM；在 InnoDB 里叫 purge；在 LSM-Tree 引擎里叫 compaction；在 CockroachDB 里叫 MVCC GC。机制名字不同，要解决的问题是同一个。

PostgreSQL 社区流传的 bloat 恐怖故事数不胜数：一张活动行只有几万行的小表，因为 autovacuum 被长事务阻塞了三周，最终膨胀到 200GB；一张高频 UPDATE 的 session 表，索引扫描比全表扫描还慢，因为 99% 的索引项指向死元组；某金融系统因为关闭了 autovacuum"以提升性能"，三个月后被强制进入只读模式。这些故事都指向同一个教训：**垃圾回收不是可选项，是必选项**。

## SQL 标准的态度：完全不管

SQL:2023 标准没有任何关于 VACUUM、GC、compaction、空间回收的内容。原因很简单——这些都是物理存储层的实现细节，标准只关心逻辑语义。但这也意味着每个引擎都按自己的需求发明了一套语法和守护进程，互相之间几乎没有共通点。

唯一勉强算"准标准"的是 `OPTIMIZE TABLE`——MySQL 引入后被多个 fork（MariaDB、TiDB、OceanBase）继承，并被一些 OLAP 引擎（ClickHouse、StarRocks、Doris）借用作为合并/压缩的触发命令。

## 支持矩阵

### VACUUM / 显式空间回收命令

| 引擎 | 命令 | 默认行为 | 是否需要 |
|------|------|---------|---------|
| PostgreSQL | `VACUUM` | 标记可重用，不缩文件 | 是（MVCC） |
| MySQL (InnoDB) | `OPTIMIZE TABLE` | 重建表 | 偶尔 |
| MariaDB | `OPTIMIZE TABLE` | 重建表 | 偶尔 |
| SQLite | `VACUUM` | 重建整库文件 | 偶尔 |
| Oracle | `ALTER TABLE ... SHRINK SPACE` | 段收缩 | 偶尔（UNDO 自动） |
| SQL Server | `DBCC SHRINKDATABASE/FILE` | 收缩文件 | 不推荐常用 |
| DB2 | `REORG TABLE` | 重组 | 偶尔 |
| Snowflake | -- | 自动 | 否（micro-partition） |
| BigQuery | -- | 自动 | 否（不可变存储） |
| Redshift | `VACUUM` | 排序 + 删除 | 是（早期） |
| DuckDB | `CHECKPOINT` | 写盘 + 紧凑 | 否 |
| ClickHouse | `OPTIMIZE TABLE` | 触发合并 | 偶尔 |
| Trino | -- | 不存数据 | 否 |
| Presto | -- | 不存数据 | 否 |
| Spark SQL | `VACUUM`（Delta） | 删除过期文件 | 是（Delta Lake） |
| Hive | -- | 依赖底层 | 否 |
| Flink SQL | -- | 状态后端管理 | 否 |
| Databricks | `VACUUM`（Delta） | 删除过期文件 | 是 |
| Teradata | `PACKDISK` | DBA 工具 | 偶尔 |
| Greenplum | `VACUUM` | 继承 PG | 是 |
| CockroachDB | -- | MVCC GC 自动 | 否（自动） |
| TiDB | -- | GC worker 自动 | 否（自动） |
| OceanBase | -- | 合并 + 转储自动 | 否（自动） |
| YugabyteDB | -- | DocDB compaction | 否（自动） |
| SingleStore | `OPTIMIZE TABLE` | 行存合并 | 偶尔 |
| Vertica | `PURGE` | 真删 | 是 |
| Impala | `COMPUTE STATS` | 不回收空间 | -- |
| StarRocks | -- | BE 后台合并 | 否 |
| Doris | -- | BE 后台合并 | 否 |
| MonetDB | -- | 自动 | 否 |
| CrateDB | `OPTIMIZE` | 触发段合并 | 偶尔 |
| TimescaleDB | `VACUUM` | 继承 PG | 是 |
| QuestDB | -- | 自动 | 否 |
| Exasol | -- | 自动 | 否 |
| SAP HANA | `MERGE DELTA OF` | 行存合并到列存 | 偶尔 |
| Informix | `UPDATE STATISTICS` + 重组 | DBA 工具 | 偶尔 |
| Firebird | `gfix` 工具 | 离线 | 偶尔 |
| H2 | `SHUTDOWN COMPACT` | 关闭时压缩 | 偶尔 |
| HSQLDB | `CHECKPOINT DEFRAG` | 重写文件 | 偶尔 |
| Derby | `SYSCS_UTIL.SYSCS_COMPRESS_TABLE` | 重组 | 偶尔 |
| Amazon Athena | -- | 不存数据 | 否 |
| Azure Synapse | -- | 自动 | 否 |
| Google Spanner | -- | 自动 GC | 否 |
| Materialize | -- | 状态自动 | 否 |
| RisingWave | -- | 状态后端自动 | 否 |
| InfluxDB | -- | TSM compaction | 否 |
| Databend | -- | 自动 + `OPTIMIZE` | 偶尔 |
| Yellowbrick | -- | 自动 | 否 |
| Firebolt | -- | 自动 | 否 |

> 统计：约 18 个引擎需要显式或可选 VACUUM 类命令，约 30 个引擎完全自动管理（多数是云原生 / OLAP / LSM 系）。

### VACUUM FULL / REBUILD 重写表

| 引擎 | 完全重写命令 | 行为 | 阻塞 |
|------|------------|------|------|
| PostgreSQL | `VACUUM FULL` | 复制到新堆文件 | AccessExclusiveLock |
| MySQL InnoDB | `OPTIMIZE TABLE` / `ALTER TABLE ... ENGINE=InnoDB` | 在线 DDL 重建 | 在线（5.6+） |
| MariaDB | 同 MySQL | 同 | 在线 |
| SQLite | `VACUUM` | 重建整库 | 写锁 |
| Oracle | `ALTER TABLE ... MOVE` 或 `SHRINK SPACE COMPACT` | 段收缩 | DDL 锁（MOVE）|
| SQL Server | `ALTER INDEX ... REBUILD` + `DBCC SHRINKFILE` | 索引重建 | 在线（企业版）|
| DB2 | `REORG TABLE ... LONGLOBDATA` | 在线/离线 | 可选 |
| Redshift | `VACUUM FULL` | 排序 + 删除 | 表锁较弱 |
| DuckDB | -- | 检查点已紧凑 | -- |
| ClickHouse | `OPTIMIZE TABLE ... FINAL` | 强制全量合并 | 后台 |
| Greenplum | `VACUUM FULL` | 同 PG | 表锁 |
| Vertica | `PURGE TABLE` | 真删除 | 不锁 |
| TimescaleDB | `VACUUM FULL` | 同 PG，慎用 | 表锁 |
| SAP HANA | `ALTER TABLE ... RECLAIM DATA SPACE` | 列存重组 | 在线 |
| Firebird | `backup + restore` | 唯一办法 | 离线 |
| H2 | `SHUTDOWN COMPACT` | 文件级 | 离线 |

### 自动 VACUUM / 后台 GC 守护进程

| 引擎 | 进程名 | 默认状态 | 触发条件 |
|------|--------|---------|---------|
| PostgreSQL | autovacuum launcher / worker | ON（8.3+，2008） | 死元组比例 / 行数阈值 |
| MySQL InnoDB | purge thread | ON（5.5+） | undo log 增长 |
| MariaDB | purge thread | ON | 同 InnoDB |
| Oracle | SMON / PMON | ON（强制） | 后台持续 |
| SQL Server | ghost cleanup task | ON（强制） | 16 个页周期 |
| DB2 | auto-reorg | 可配置 | 配置驱动 |
| SQLite | -- | 否（手动 VACUUM） | 或 `auto_vacuum=FULL` |
| Redshift | auto vacuum | ON（自 2018） | 排序混乱度 |
| ClickHouse | background merge pool | ON | 始终运行 |
| CockroachDB | MVCC GC queue | ON | gc.ttlseconds |
| TiDB | GC worker | ON | tidb_gc_run_interval |
| OceanBase | 合并/转储线程 | ON | 内存阈值 / 定时 |
| YugabyteDB | DocDB compaction | ON | LSM 触发 |
| TimescaleDB | autovacuum + 策略 jobs | ON | 继承 PG |
| Vertica | Tuple Mover (mergeout) | ON | WOS/ROS 切换 |
| StarRocks | Compaction Manager | ON | 版本数 |
| Doris | Compaction Manager | ON | 版本数 |
| ScyllaDB / Cassandra-类 LSM | compaction | ON | 策略相关 |
| Spanner | 后台 GC | ON | 1 小时版本 TTL |
| InfluxDB | TSM compactor | ON | LSM 触发 |
| Snowflake | 后台维护 | ON（不可见） | 内部 |
| BigQuery | 后台 | ON（不可见） | 内部 |
| Databricks | predictive optimization | 可选 | ML 驱动 |

### VACUUM FREEZE / 事务 ID wraparound 保护

这是 PostgreSQL 系特有的概念——32 位 XID 用完会回卷，必须周期性把"足够老的"行版本标记为 frozen，不再依赖 XID 比较。

| 引擎 | 是否需要 freeze | 命令 | 上限保护 |
|------|---------------|------|---------|
| PostgreSQL | 是 | `VACUUM FREEZE` | autovacuum_freeze_max_age = 200M |
| Greenplum | 是 | `VACUUM FREEZE` | 继承 PG |
| TimescaleDB | 是 | `VACUUM FREEZE` | 继承 PG |
| YugabyteDB (YSQL) | 否 | -- | DocDB HybridTime，无 wraparound |
| CockroachDB | 否 | -- | HLC 时间戳，无 XID |
| MySQL InnoDB | 否 | -- | 6 字节 trx id，几乎不会用完 |
| Oracle | 否 | -- | SCN 64 位 |
| SQL Server | 否 | -- | LSN |
| 其他多数引擎 | 否 | -- | 无 32 位 XID 设计 |

> PostgreSQL 的 wraparound 是历史包袱：早期为节省每行 4 字节而用 32 位 XID，后续所有版本都必须维护 freeze 机制。

### VACUUM ANALYZE（统计信息更新组合）

| 引擎 | 组合命令 | 单独 ANALYZE |
|------|---------|------------|
| PostgreSQL | `VACUUM ANALYZE` | `ANALYZE` |
| Greenplum | `VACUUM ANALYZE` | `ANALYZE` |
| TimescaleDB | `VACUUM ANALYZE` | `ANALYZE` |
| MySQL | -- | `ANALYZE TABLE` |
| MariaDB | -- | `ANALYZE TABLE` |
| Oracle | -- | `DBMS_STATS.GATHER_TABLE_STATS` |
| SQL Server | -- | `UPDATE STATISTICS` |
| DB2 | -- | `RUNSTATS` |
| ClickHouse | -- | 自动 |
| Snowflake | -- | 自动 |
| Redshift | `VACUUM` + `ANALYZE` 分开 | `ANALYZE` |

### LSM Compaction / 后台合并

| 引擎 | 类型 | 命令 | 策略 |
|------|------|------|------|
| ClickHouse | MergeTree 合并 | `OPTIMIZE TABLE` | 大小分层 |
| CockroachDB | Pebble LSM | -- | leveled |
| TiDB / TiKV | RocksDB LSM | -- | leveled |
| YugabyteDB | DocDB (RocksDB fork) | -- | leveled |
| HBase | HFile compaction | `major_compact` / `minor_compact` | 大小分层 |
| Cassandra / Scylla | SSTable | `nodetool compact` | STCS / LCS / TWCS |
| InfluxDB | TSM | -- | 时间分层 |
| RocksDB embedded | -- | -- | 多策略 |
| StarRocks | Rowset compaction | -- | base + cumulative |
| Doris | Rowset compaction | -- | base + cumulative |
| Spanner | -- | -- | 分层 |
| Databend | -- | `OPTIMIZE TABLE` | 自动 + 手动 |

### 墓碑（Tombstone）清理

LSM 引擎中，DELETE 是写入一条墓碑标记，墓碑要等到所有比它老的 SSTable 也参与合并后才能真正消失。

| 引擎 | 墓碑 GC 控制 | 默认 |
|------|------------|------|
| Cassandra | `gc_grace_seconds` | 10 天 |
| ScyllaDB | `gc_grace_seconds` | 10 天 |
| HBase | `KEEP_DELETED_CELLS` + TTL | OFF |
| ClickHouse | `OPTIMIZE FINAL` 强制 | 自然消除 |
| CockroachDB | `gc.ttlseconds` | 25 小时（旧默认 24h）|
| TiDB | `tidb_gc_life_time` | 10 分钟 |
| YugabyteDB | history retention | 900 秒 |
| RocksDB | 合并时 | -- |

### CLUSTER（按索引重组）

| 引擎 | 命令 | 物理重组 |
|------|------|---------|
| PostgreSQL | `CLUSTER tbl USING idx` | 一次性，不维持 |
| MySQL InnoDB | -- | 主键即聚簇索引（永久） |
| Oracle | `CREATE CLUSTER` / IOT | IOT 永久 |
| SQL Server | `ALTER INDEX ... REBUILD` | 聚簇索引永久 |
| DB2 | `REORG TABLE ... INDEX` | 一次性 |
| Greenplum | `CLUSTER` | 同 PG |

### REINDEX

| 引擎 | 命令 | 在线 |
|------|------|------|
| PostgreSQL | `REINDEX [CONCURRENTLY]` | 12+ CONCURRENTLY 在线 |
| MySQL | `ALTER TABLE ... DROP/ADD INDEX` | 在线 DDL（5.6+） |
| Oracle | `ALTER INDEX ... REBUILD ONLINE` | 在线 |
| SQL Server | `ALTER INDEX ... REBUILD WITH (ONLINE=ON)` | 在线（企业版） |
| DB2 | `REORG INDEXES` | 在线 |
| SQLite | `REINDEX` | 写锁 |

### OPTIMIZE TABLE 家族

| 引擎 | OPTIMIZE 含义 |
|------|-------------|
| MySQL | 重建表 + 索引（InnoDB 走 ALTER 重建路径）|
| MariaDB | 同 MySQL |
| TiDB | 兼容语法但 NOOP（DocDB 自动管理）|
| OceanBase | 兼容 MySQL |
| ClickHouse | 触发后台合并（FINAL 强制全合并）|
| StarRocks | 触发 compaction |
| Doris | 触发 compaction |
| SingleStore | 行存段合并 |
| CrateDB | Lucene 段合并 |
| Databend | 触发 segment 合并 |

## 各引擎深度剖析

### PostgreSQL（VACUUM 体系的"经典教材"）

PostgreSQL 的 VACUUM 是所有 MVCC 数据库教科书般的存在——它把 GC 的复杂度赤裸裸地暴露给了用户和 DBA。

**基本命令：**

```sql
-- 1. 标准 VACUUM：标记死元组所占空间为可重用，不收缩文件
VACUUM orders;

-- 2. 详细输出：显示扫描页数、跳过页数、回收元组数
VACUUM (VERBOSE, ANALYZE) orders;

-- 3. VACUUM FULL：完全重写表，独占锁，慎用
VACUUM FULL orders;

-- 4. VACUUM FREEZE：强制把所有可冻结的元组都打上 frozen 标记
VACUUM FREEZE orders;

-- 5. 并行 VACUUM（PG 13+）：对索引并行清理
VACUUM (PARALLEL 4) orders;

-- 6. 仅清理但跳过截断（避免 AccessExclusiveLock 短暂获取）
VACUUM (TRUNCATE FALSE) orders;

-- 7. 仅 INDEX_CLEANUP 控制
VACUUM (INDEX_CLEANUP OFF) orders;
```

**autovacuum 配置：**

```sql
-- 全局参数（postgresql.conf）
autovacuum = on                                  -- 8.3+ 默认 ON
autovacuum_max_workers = 3
autovacuum_naptime = 1min
autovacuum_vacuum_threshold = 50                 -- 死元组绝对值
autovacuum_vacuum_scale_factor = 0.2             -- 死元组比例 (20%)
autovacuum_vacuum_cost_delay = 2ms
autovacuum_vacuum_cost_limit = 200
autovacuum_freeze_max_age = 200000000            -- 2 亿事务
autovacuum_multixact_freeze_max_age = 400000000

-- 表级覆盖
ALTER TABLE orders SET (
    autovacuum_vacuum_scale_factor = 0.05,       -- 5%
    autovacuum_vacuum_cost_delay = 0,            -- 不限速
    autovacuum_freeze_max_age = 100000000        -- 1 亿
);
```

**Visibility Map 与 pg_visibility：**

PostgreSQL 8.4 引入 visibility map（VM），为每个 8KB 数据页保留 2 比特：
- bit 0：all-visible（所有元组对所有事务可见，可跳过 MVCC 检查）
- bit 1：all-frozen（所有元组都已冻结，VACUUM 可以跳过此页）

VM 的存在使得 index-only scan 成为可能，也让 freeze 操作可以增量执行——只扫描"非 all-frozen"的页。

```sql
-- 安装 pg_visibility 扩展查看 VM 状态
CREATE EXTENSION pg_visibility;

SELECT * FROM pg_visibility_map('orders'::regclass);
SELECT pg_visibility_map_summary('orders'::regclass);
-- 返回：all_visible, all_frozen 的页数

-- 强制重建 VM
SELECT pg_truncate_visibility_map('orders'::regclass);
```

**Bloat 测量：**

```sql
-- 经典查询：估算表 bloat（来自 pgstattuple 或 check_postgres）
CREATE EXTENSION pgstattuple;

SELECT * FROM pgstattuple('orders');
-- table_len, tuple_count, tuple_len, dead_tuple_count, dead_tuple_len, free_space

-- 索引 bloat
SELECT * FROM pgstatindex('orders_pkey');
-- index_size, internal_pages, leaf_pages, deleted_pages, avg_leaf_density

-- 通过统计视图（无锁，但只有上次 ANALYZE 后的估算）
SELECT schemaname, relname,
       n_live_tup, n_dead_tup,
       n_dead_tup::float / NULLIF(n_live_tup, 0) AS dead_ratio,
       last_autovacuum, autovacuum_count
FROM pg_stat_user_tables
ORDER BY n_dead_tup DESC LIMIT 10;
```

**REINDEX CONCURRENTLY（PG 12+）：**

```sql
-- 在线重建索引，不阻塞写
REINDEX INDEX CONCURRENTLY orders_pkey;
REINDEX TABLE CONCURRENTLY orders;

-- 实现原理：构造一个新索引，等待旧事务完成，原子切换
-- 失败会留下 INVALID 索引，需要 DROP INDEX 后重试
```

**VACUUM 阻塞与长事务杀手：**

VACUUM 无法回收"对某个活跃事务仍可见"的死元组。换句话说，一个持续 12 小时的 SELECT 事务，会让那 12 小时里所有表的所有 UPDATE/DELETE 留下的死元组都无法被清理。这是 PG bloat 灾难最常见的根因。

```sql
-- 找到阻塞 VACUUM 的最老事务
SELECT pid, age(backend_xmin), state, query
FROM pg_stat_activity
WHERE backend_xmin IS NOT NULL
ORDER BY age(backend_xmin) DESC LIMIT 5;
```

### Oracle（UNDO 自动管理的优雅）

Oracle 的设计哲学和 PostgreSQL 完全相反：行版本不放在表里，而是放在专门的 UNDO 表空间。表里永远只有最新版本，旧版本通过 UNDO 链按需重建。

- **SMON（System Monitor）**：实例后台进程，负责回收 temp segments、合并空闲扩展、推进 SCN 等。
- **PMON（Process Monitor）**：清理失败进程的资源，回滚未完成事务。
- **UNDO_RETENTION**：参数控制 UNDO 数据保留时长（秒），到期后自动可被覆盖。
- **自动段顾问（Automatic Segment Advisor）**：周期性扫描所有段，建议哪些表/索引适合做 `SHRINK SPACE`。

```sql
-- 查看 UNDO 使用率
SELECT tablespace_name,
       SUM(bytes)/1024/1024 AS mb_used
FROM dba_undo_extents
WHERE status = 'ACTIVE'
GROUP BY tablespace_name;

-- 段收缩（仅适用于 ASSM 表空间）
ALTER TABLE orders ENABLE ROW MOVEMENT;
ALTER TABLE orders SHRINK SPACE COMPACT;       -- 紧凑但不释放 HWM
ALTER TABLE orders SHRINK SPACE;               -- 紧凑并降低 HWM
ALTER TABLE orders SHRINK SPACE CASCADE;       -- 同时处理依赖索引

-- 在线移动段
ALTER TABLE orders MOVE ONLINE;
```

由于 UNDO 是有限资源，Oracle 上的"长事务杀手"表现为 `ORA-01555: snapshot too old`——长查询需要的旧版本被覆盖了，查询直接失败。这是 Oracle MVCC 模型的固有代价。

### SQL Server（ghost record cleanup）

SQL Server 的 MVCC 不是默认的（除非启用 RCSI/SI），即便如此，DELETE 留下的"幽灵记录"也需要后台清理。

- **Ghost cleanup task**：系统线程，每 5 秒扫描一次每个数据库的 16 个页（默认参数 `DEACTIVATE_GHOST_CLEANUP_LIST` 关）。
- **Version Store**：在 tempdb 中存储行版本，由后台线程清理超出最老活跃事务范围的版本。
- **DBCC SHRINKDATABASE / SHRINKFILE**：不推荐定期执行，会引发严重的索引碎片，应当只用于一次性回收异常增长。

```sql
-- 查看 ghost record 数量
SELECT object_name(object_id), index_id, ghost_record_count, version_ghost_record_count
FROM sys.dm_db_index_physical_stats(DB_ID(), NULL, NULL, NULL, 'DETAILED')
WHERE ghost_record_count > 0;

-- 强制 ghost cleanup（很少需要）
DBCC FORCEGHOSTCLEANUP;

-- 收缩文件（慎用）
DBCC SHRINKFILE (N'mydb_data', 5000);  -- 收缩到 5000 MB
```

### MySQL InnoDB（purge thread + undo log）

InnoDB 的 MVCC 模型类似 Oracle：旧版本通过 undo log 重建。purge 线程负责清理"无人再需要"的 undo 记录和被标记删除的索引项。

- **innodb_purge_threads**：5.5 引入单线程 purge，5.6 起支持多线程，默认 4。
- **innodb_max_purge_lag**：允许的最大未 purge 历史长度，超过后强制减慢 DML。
- **innodb_undo_log_truncate**（5.7+）：自动截断超大 undo tablespace。
- **OPTIMIZE TABLE**：在 InnoDB 上等价于 `ALTER TABLE t ENGINE=InnoDB`，触发在线表重建（5.6+ Online DDL）。

```sql
-- 查看 purge 进度
SHOW ENGINE INNODB STATUS\G
-- TRANSACTIONS 部分：History list length（HLL）

-- 系统变量
SHOW VARIABLES LIKE 'innodb_purge_threads';
SHOW VARIABLES LIKE 'innodb_max_purge_lag%';
SHOW VARIABLES LIKE 'innodb_undo_log_truncate';

-- 手动重建表
OPTIMIZE TABLE orders;

-- 等价的在线 DDL
ALTER TABLE orders ENGINE=InnoDB, ALGORITHM=INPLACE, LOCK=NONE;
```

InnoDB 没有 PostgreSQL 那样的 wraparound 灾难，因为它的事务 ID 是 6 字节（48 位），实际项目里几乎不可能用完。

### ClickHouse（MergeTree 后台合并）

ClickHouse 的存储模型本质上是 LSM 的列存版本：每次 INSERT 写一个新的 part，后台不断合并相邻的 parts。"GC"在这里就是 merge——把多个小 part 合并成大 part，顺便处理 ReplacingMergeTree 的去重、CollapsingMergeTree 的折叠、`DELETE` 标记的应用等。

```sql
-- 触发后台合并（异步，不保证完成）
OPTIMIZE TABLE events;

-- 强制合并所有 parts 到一个（同步，慢）
OPTIMIZE TABLE events FINAL;

-- 仅合并指定分区
OPTIMIZE TABLE events PARTITION '202604' FINAL;

-- 控制 deduplication
OPTIMIZE TABLE events DEDUPLICATE;

-- 查看 parts 状态
SELECT database, table, count(), sum(rows), sum(bytes_on_disk)
FROM system.parts
WHERE active
GROUP BY database, table;

-- 查看后台合并队列
SELECT * FROM system.merges;
```

`FINAL` 关键字非常昂贵，因为它要在查询时合并所有未合并的 parts。生产环境一般避免在查询里写 `FINAL`，而是让后台合并自然完成。

### CockroachDB（gc.ttlseconds 控制一切）

CockroachDB 采用 HLC（混合逻辑时钟）作为时间戳，行版本按 timestamp 索引存储在 Pebble LSM 中。GC 由 zone config 中的 `gc.ttlseconds` 参数控制——版本超过这个时长后才能被回收。

```sql
-- 查看默认 zone 配置
SHOW ZONE CONFIGURATION FROM RANGE default;
-- gc.ttlseconds = 14400 (4 小时，新版本默认)
-- 历史上长期默认 25 小时

-- 修改某张表的 TTL
ALTER TABLE orders CONFIGURE ZONE USING gc.ttlseconds = 600;

-- 行级 TTL（21.2+）
CREATE TABLE sessions (
    id UUID PRIMARY KEY,
    last_seen TIMESTAMPTZ DEFAULT now()
) WITH (ttl_expire_after = '7 days');
```

`gc.ttlseconds` 的含义有两面：一是空间回收的时间窗口，二是 AS OF SYSTEM TIME 历史查询的最大可回溯时间。设置过短会让历史查询失效，过长又会让 bloat 累积——25 小时是平衡的默认值。

### TiDB（GC worker 与 safepoint）

TiDB 的 GC 在 SQL 层调度，但实际清理发生在 TiKV 层（基于 RocksDB）。

```sql
-- 查看 GC 状态
SELECT VARIABLE_NAME, VARIABLE_VALUE
FROM mysql.tidb
WHERE VARIABLE_NAME LIKE '%gc%';

-- 关键参数
-- tikv_gc_run_interval = 10m0s          GC 运行间隔
-- tikv_gc_life_time   = 10m0s           保留多久的版本
-- tikv_gc_safe_point                    全局 safepoint

-- 修改 GC life time
SET GLOBAL tidb_gc_life_time = '24h';
```

10 分钟的默认 GC 生命周期非常短——这意味着 TiDB 不适合做长事务，超过 10 分钟的 SELECT 就有可能因为版本被 GC 而报 `GC life time is shorter than transaction duration`。

### SQLite（VACUUM 即重建整库）

SQLite 的 VACUUM 是最简单粗暴的实现——把整个数据库文件读出来，写入一个临时文件，再替换原文件。

```sql
-- 完整 VACUUM
VACUUM;

-- 只 VACUUM 单个数据库（附加多个时）
VACUUM main;

-- INTO 子句：VACUUM 到指定路径（3.27+）
VACUUM INTO 'backup.db';

-- auto_vacuum 模式：建库时设置，运行时只能改 NONE↔INCREMENTAL
PRAGMA auto_vacuum = FULL;        -- 0=NONE 1=FULL 2=INCREMENTAL
PRAGMA incremental_vacuum(100);   -- INCREMENTAL 模式下手动回收 100 页
```

`auto_vacuum=FULL` 会在每次提交时回收空闲页，但会增加每次写入的开销。`INCREMENTAL` 模式只在调用 `incremental_vacuum` 时回收，更可控。多数 SQLite 应用直接用默认 NONE，需要时手动 VACUUM。

### HBase（major / minor compaction）

HBase 是典型 LSM 模型：数据先写 MemStore，flush 成 HFile，然后通过 compaction 合并。

```bash
# HBase shell
> compact 'orders'                # minor compaction（合并少数小文件）
> major_compact 'orders'          # major compaction（合并所有文件 + 应用 delete）

# 配置
hbase.hregion.majorcompaction=604800000   # 7 天一次 major
hbase.hstore.compaction.min=3              # 最少 3 个 store files 触发 minor
hbase.hstore.compaction.max=10             # 一次最多合并 10 个

# Cell TTL
> alter 'orders', NAME=>'cf', TTL=>'2592000'   # 30 天
```

DELETE 在 HBase 里是写一条 tombstone cell，必须等到一次 major compaction 才能真正消除——这是 HBase（以及所有 LSM）的固有特性。

## PostgreSQL autovacuum 调优深度剖析

autovacuum 是 PG 性能调优中最常被误解的部分。默认参数针对的是"小表 + 中等负载"，对高吞吐表几乎一定会出问题。

### 触发阈值的数学

```
触发条件: n_dead_tup > vacuum_threshold + vacuum_scale_factor * n_live_tup
默认值:    50 + 0.2 * n_live_tup
```

对一张 1000 万行的表，触发阈值是 200 万死元组——意味着 20% 的 bloat 才会触发 autovacuum。等 autovacuum 跑起来时，表已经膨胀了 20%。对热表应该把 `scale_factor` 调到 0.01 ~ 0.05。

```sql
-- 高吞吐表的推荐设置
ALTER TABLE hot_table SET (
    autovacuum_vacuum_scale_factor = 0.02,
    autovacuum_vacuum_threshold = 1000,
    autovacuum_analyze_scale_factor = 0.01,
    autovacuum_vacuum_cost_delay = 0,
    autovacuum_vacuum_cost_limit = 10000
);
```

### Cost-based delay：autovacuum 的限速器

autovacuum 不会"全速跑"——它累积一个"成本"（读 page 1 单位、dirty page 20 单位等），到达 `cost_limit` 后睡眠 `cost_delay` 毫秒。默认的 cost_limit=200、cost_delay=2ms 意味着：

```
最大读速度 ≈ cost_limit / cost_delay * page_cost * 8KB
           = 200 / 0.002 * 1 * 8KB
           = 800 MB/s   （但默认 cost_delay 是 2ms 而非 1ms）
```

实际默认配置下，autovacuum 的有效带宽只有几十 MB/s，对 TB 级表完全跟不上写入速度。生产环境一般把 `cost_delay` 设为 0（不限速）或 `cost_limit` 调到 10000+。

### 并行 VACUUM（PG 13+）

```sql
-- 显式并行（仅索引清理阶段并行）
VACUUM (PARALLEL 4) orders;

-- autovacuum 不自动并行，需要 DBA 手动触发
-- 或通过 max_parallel_maintenance_workers 配合 maintenance_work_mem
SET max_parallel_maintenance_workers = 4;
SET maintenance_work_mem = '4GB';
```

注意 PG 13 的并行 VACUUM 只并行**索引清理**阶段，堆扫描仍然是单线程。每个并行 worker 处理一个索引——所以索引数 ≥ 2 才能受益。

### TID Store（PG 17 引入）

历史上 VACUUM 用一个动态数组保存"待清理的 TID"，每个 TID 6 字节，受 `maintenance_work_mem` 限制（最大 1GB → 约 1.78 亿 TID）。一旦超出，VACUUM 必须扫描索引多次（pass），代价巨大。

PostgreSQL 17 (2024) 引入了 TID Store（基于 radix tree 的紧凑数据结构），同样的 `maintenance_work_mem` 可以容纳数倍于以前的 TID，并且不再受 1GB 上限限制。这是过去十年对超大表 VACUUM 性能影响最大的改进之一。

## PostgreSQL TXID Wraparound：20 亿事务的灾难

PostgreSQL 用 32 位无符号整数作为事务 ID（XID），可见性判断用模运算："事务 A 在事务 B 之前 if (A - B) mod 2^32 < 2^31"。这意味着 XID 空间被切成两半：每个事务的"过去"和"未来"各 21 亿事务。

如果一个行版本的 XID 落在当前事务的"过去"超过 21 亿，可见性判断就会出错——本该可见的行会变得不可见。为了避免这个噩梦，PG 必须周期性地把所有"足够老"的元组打上 `frozen` 标记，从此它们对所有事务都可见，不再依赖 XID 比较。

### 三道防线

```
1. 日常 autovacuum: 当 age(relfrozenxid) > vacuum_freeze_min_age（默认 5000 万）
   时机会顺便 freeze 一些元组
2. 紧急 anti-wraparound autovacuum: 当 age(relfrozenxid) > autovacuum_freeze_max_age
   （默认 2 亿）时强制启动，即使 autovacuum=off 也会跑
3. 强制只读: 当 age(relfrozenxid) > 20 亿 - 3000 万安全余量时，数据库进入
   "停止接受写入"模式，必须以单用户模式手动 VACUUM
```

第三道防线就是开头那个凌晨三点的电话。它的错误信息是：

```
ERROR: database is not accepting commands to avoid wraparound data loss in database "mydb"
HINT: Stop the postmaster and vacuum that database in single-user mode.
```

恢复流程是关掉 postmaster，用 `postgres --single` 进入单用户模式，跑 `VACUUM FREEZE` 直到 `age(datfrozenxid)` 降下来。在生产环境下，这通常意味着数小时的停机。

### 如何监控

```sql
-- 数据库级 wraparound age
SELECT datname, age(datfrozenxid),
       2^31 - age(datfrozenxid) AS xact_remaining
FROM pg_database
ORDER BY age(datfrozenxid) DESC;

-- 表级
SELECT c.relname,
       age(c.relfrozenxid) AS xid_age,
       pg_size_pretty(pg_table_size(c.oid)) AS size
FROM pg_class c
JOIN pg_namespace n ON n.oid = c.relnamespace
WHERE c.relkind IN ('r','t','m')
ORDER BY age(c.relfrozenxid) DESC LIMIT 20;
```

经验法则：当 `age()` 超过 1 亿时开始关注，超过 2 亿（autovacuum_freeze_max_age）时一定会有 anti-wraparound autovacuum 自动启动，超过 15 亿就该紧急介入。

### 历史教训

- **Sentry 2015**：因为大表的 anti-wraparound VACUUM 持续阻塞 DDL，最终被迫在生产数据库上做单用户模式紧急 freeze。
- **Joyent 2014**：Manta 对象存储的元数据 PG 因为长事务阻塞 freeze，被迫停机数小时。
- **Mailchimp / Adyen / 多家公司**类似事故，都触发了对 visibility map 和 freeze 流程的优化。

PostgreSQL 9.6 引入了"page-level freeze"，让 freeze 可以仅扫描非全冻结页；PG 15 引入了 `VACUUM (FREEZE)` 的更细粒度控制；PG 17 (2024) 的 TID Store 让大表 freeze 的内存效率提升数倍。但 wraparound 这个根本性的设计限制依然存在，只要 PG 还用 32 位 XID，DBA 就必须时刻警惕。

## 关键发现

1. **MVCC 是有代价的，垃圾回收是必选项**：所有 MVCC 数据库都必须解决死版本清理问题，区别只在于是把它暴露给用户（PostgreSQL）还是隐藏起来（Snowflake / BigQuery）。

2. **三种主流 GC 模型并存**：
   - **就地版本** (PostgreSQL, Greenplum)：行版本在表里，VACUUM 显式标记可重用
   - **回滚段/UNDO** (Oracle, MySQL InnoDB)：旧版本在 UNDO，purge 线程后台清理
   - **LSM Compaction** (HBase, Cassandra, ClickHouse, CockroachDB, TiDB, RocksDB 系)：数据天然是不可变的，合并时顺便 GC

3. **PostgreSQL 的 wraparound 是历史包袱**：32 位 XID 是为了节省每行 4 字节而做的早期权衡，今天看来代价远超收益。所有新设计的 MVCC 数据库（CockroachDB、Spanner、YugabyteDB 等）都用 64 位时间戳避开了这个坑。

4. **自动化是大势所趋**：
   - 2008 年 PG 8.3 默认开启 autovacuum，是分水岭事件
   - 云原生 OLAP（Snowflake、BigQuery、Redshift 自动 vacuum）完全对用户隐藏 GC
   - LSM 引擎天然就是后台 compaction，没有"手动 GC"的概念

5. **长事务是所有 MVCC GC 的死敌**：
   - PG：长事务的 `xmin` horizon 阻塞 VACUUM 回收
   - Oracle：长事务可能被 UNDO 覆盖，触发 ORA-01555
   - TiDB：长事务超过 `tidb_gc_life_time` 直接报错
   - CockroachDB：超过 `gc.ttlseconds` 的 AS OF SYSTEM TIME 查询失效

6. **PostgreSQL 默认 autovacuum 配置面向小表**：高吞吐生产表必须重新调参，特别是 `vacuum_scale_factor`（0.01 ~ 0.05）、`vacuum_cost_delay`（0）、`vacuum_cost_limit`（10000+）。

7. **VACUUM FULL 几乎从来不应该是日常操作**：它持有 AccessExclusiveLock，会让所有读写阻塞。日常 bloat 应该靠合理调参 + 频繁 VACUUM 控制；只有事故后清理才用 VACUUM FULL，并优先考虑 `pg_repack` 这类在线方案。

8. **OPTIMIZE TABLE 是跨引擎的"伪标准"**：MySQL 引入后被 MariaDB、TiDB、OceanBase、ClickHouse、StarRocks、Doris、SingleStore 等借用，但语义差异很大——MySQL 重建整表，ClickHouse 触发后台合并，TiDB 则是兼容 NOOP。

9. **LSM 引擎的墓碑 GC 有等待时间**：Cassandra `gc_grace_seconds` 默认 10 天就是为了等待节点修复完成，避免"已删除的数据"在故障节点恢复后复活。TiDB / CockroachDB 的 GC 时间更短（10 分钟到几小时），因为它们用 Raft 而非反熵修复。

10. **PG 17 (2024) 的 TID Store 是十年来最大的 VACUUM 改进**：把 `maintenance_work_mem` 内能容纳的死元组数从约 1.78 亿提升到事实上无上限（受真实内存约束），消除了大表多 pass VACUUM 的痛点。

11. **REINDEX CONCURRENTLY（PG 12+）让索引膨胀治理变得可行**：在此之前，索引 bloat 只能通过 VACUUM FULL 或第三方工具（pg_repack）解决，前者锁表，后者复杂。

12. **没有"无 GC 的 MVCC"**：所有声称"零运维"的系统（Snowflake、BigQuery、Spanner）只是把 GC 隐藏到了云控制平面里，并没有真的消除它。理解 GC 仍然是数据库工程师的核心能力。

## 参考资料

- PostgreSQL: [VACUUM](https://www.postgresql.org/docs/current/sql-vacuum.html)
- PostgreSQL: [Routine Vacuuming](https://www.postgresql.org/docs/current/routine-vacuuming.html)
- PostgreSQL: [Preventing Transaction ID Wraparound Failures](https://www.postgresql.org/docs/current/routine-vacuuming.html#VACUUM-FOR-WRAPAROUND)
- PostgreSQL: [pg_visibility](https://www.postgresql.org/docs/current/pgvisibility.html)
- PostgreSQL: [pgstattuple](https://www.postgresql.org/docs/current/pgstattuple.html)
- PostgreSQL: [REINDEX CONCURRENTLY](https://www.postgresql.org/docs/current/sql-reindex.html)
- Oracle: [Automatic Undo Management](https://docs.oracle.com/en/database/oracle/oracle-database/19/admin/managing-undo.html)
- Oracle: [Shrinking Database Segments Online](https://docs.oracle.com/en/database/oracle/oracle-database/19/admin/managing-tables.html)
- SQL Server: [Ghost Cleanup](https://learn.microsoft.com/en-us/sql/relational-databases/system-stored-procedures/sp-spaceused-transact-sql)
- MySQL: [InnoDB Purge Configuration](https://dev.mysql.com/doc/refman/8.0/en/innodb-purge-configuration.html)
- MySQL: [OPTIMIZE TABLE](https://dev.mysql.com/doc/refman/8.0/en/optimize-table.html)
- ClickHouse: [OPTIMIZE](https://clickhouse.com/docs/en/sql-reference/statements/optimize)
- ClickHouse: [MergeTree Engine](https://clickhouse.com/docs/en/engines/table-engines/mergetree-family/mergetree)
- CockroachDB: [Configure Replication Zones](https://www.cockroachlabs.com/docs/stable/configure-replication-zones.html)
- TiDB: [GC Overview](https://docs.pingcap.com/tidb/stable/garbage-collection-overview)
- SQLite: [VACUUM](https://www.sqlite.org/lang_vacuum.html)
- HBase: [Compaction](https://hbase.apache.org/book.html#compaction)
- Cassandra: [About Deletes and Tombstones](https://docs.datastax.com/en/cassandra-oss/3.0/cassandra/dml/dmlAboutDeletes.html)
- pg_repack: [GitHub](https://github.com/reorg/pg_repack)
