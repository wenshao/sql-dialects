# WAL / Redo 日志与持久化配置 (WAL, Redo Log, and Durability)

数据库的 ACID 中最难的不是 A、C、I，而是 D——持久化。停电、内核 panic、磁盘故障，所有这些都发生在事务"已经提交"之后。WAL（Write-Ahead Log，预写日志）是过去四十年里唯一一个被几乎所有关系数据库共同接受的解决方案：先把变更写到日志里、刷盘、再修改数据页。本文系统对比 45+ 数据库引擎的 WAL/Redo 日志、checkpoint、fsync 与持久化配置。

## 为什么 WAL 是 ACID 持久化的基石

一个事务从用户的 `COMMIT` 到磁盘上"绝对不丢"，至少要经过这样几步：

1. 内存中的数据页被修改（dirty page）。
2. 修改对应的 redo 记录被追加到日志缓冲区。
3. 日志缓冲区在 commit 时（或后台线程触发时）`write()` 到 OS 页缓存。
4. `fsync()` 强制 OS 把日志页缓存刷到磁盘控制器。
5. 磁盘控制器把数据从其 DRAM cache 写到非易失介质。
6. （可选）数据页在某个时间点被 checkpoint 刷盘，使日志可以截断。

WAL 的核心思想是：第 2、3、4 步必须发生在第 6 步之前。这样即使数据页还没刷盘就崩溃，重启时只要 replay 日志就能把内存状态恢复到崩溃前的最新提交。这一约束被称为 **Write-Ahead Logging 协议**，由 Mohan 等人在 1992 年的 ARIES 论文中系统化，几乎所有现代数据库的 redo/undo 实现都源于此。

WAL 还顺带解决了几个问题：

- **顺序写优化**：日志只追加写，比随机改写数据页快一个数量级。
- **组提交（group commit）**：多个事务可以共享一次 fsync，把 IOPS 摊薄到几十甚至几百倍。
- **复制基础**：WAL 流就是天然的 logical/physical replication 源。
- **PITR (Point-In-Time Recovery)**：基于归档的日志可以恢复到任意时间点。

## 没有 SQL 标准

SQL 标准只定义了 ACID 的语义（COMMIT 后修改必须持久），完全没有规定日志格式、刷盘策略、checkpoint 触发方式或恢复算法。WAL 是 100% 的实现细节：

- PostgreSQL 称之为 **WAL** (Write-Ahead Log)，文件位于 `pg_wal/`。
- MySQL InnoDB 称之为 **redo log**，文件曾叫 `ib_logfile0/1`，8.0.30 后改为 `#innodb_redo/` 目录下的多个段。
- Oracle 称之为 **redo log**，由 LGWR 进程写入 redo log groups。
- SQL Server 称之为 **transaction log**，物理文件 `.ldf`。
- DB2 称之为 **transaction log** 或简称 **log**，可以是 circular 或 archive。
- SQLite 提供两种模式：传统的 **rollback journal** 和 3.7.0 引入的 **WAL 模式**。
- Firebird 称之为 **careful write** + **forced writes**（早期没有真正的 WAL，2.x 后加入）。

在分布式数据库里，WAL 通常和共识算法绑定：

- **CockroachDB / TiDB / YugabyteDB** 用 **Raft log**，每个 range/region 一份。
- **Spanner** 用 Paxos log（实际是基于 Colossus 的复制日志）。
- **OceanBase** 用 Paxos clog（commit log）。

而一些列式分析引擎（**ClickHouse**、**DuckDB 早期版本**、**MonetDB**）历史上**没有传统意义的 redo log**，靠 immutable file + atomic rename 维持崩溃一致性，最近版本才陆续加入 WAL 支持事务。

下面用 11 张支持矩阵覆盖 45+ 数据库的 WAL 实现细节。

## 支持矩阵

### 1. WAL / Redo 日志名称与文件位置

| 引擎 | 日志名称 | 文件位置/格式 | 多日志流 | 备注 |
|------|---------|--------------|---------|------|
| PostgreSQL | WAL | `pg_wal/0000...` 16MB 段 | 单流 | 7.1+ 引入 WAL，之前是 fsync 数据页 |
| MySQL InnoDB | redo log + binlog + undo log | `#innodb_redo/`、`mysql-bin.*`、undo tablespace | 三种 | 8.0.30 redo 改为目录形式 |
| MariaDB | redo + binlog + undo | 同 InnoDB；10.5+ 也可 Aria | 三种 | Aria 引擎独立 control/log |
| SQLite | rollback journal 或 WAL | `*-journal` 或 `*-wal` + `*-shm` | 单流 | 3.7.0+ 支持 WAL 模式 |
| Oracle | redo log | online redo log groups（每组多个 member） | 多组 + archive | LGWR 进程写入 |
| SQL Server | transaction log | `.ldf` 文件，VLF 划分 | 单流 | 多个 .ldf 顺序使用，非并行 |
| DB2 | transaction log | 主日志 + 二级日志，可 circular/archive | 单流 | LOGPRIMARY/LOGSECOND |
| Snowflake | metadata + micro-partitions | FoundationDB metadata + S3 immutable | 不暴露 | 用户无法配置 |
| BigQuery | Capacitor + Spanner metadata | 不暴露 | 不暴露 | 完全托管 |
| Redshift | WAL（基于 PostgreSQL 8.0 fork） | 内部，不暴露 | 单流 | 用户不可见 |
| DuckDB | WAL | `.wal` 文件伴随数据库 | 单流 | 0.5+ 引入持久化 WAL |
| ClickHouse | 无传统 redo；MergeTree write-ahead log | 部分引擎有 WAL（in-memory parts） | 表级 | 主要靠 immutable parts |
| Trino | 无（计算引擎） | -- | -- | 状态外置在 metastore |
| Presto | 无（计算引擎） | -- | -- | 同 Trino |
| Spark SQL | 无（计算引擎） | -- | -- | Delta/Iceberg 提供事务日志 |
| Hive | 无传统 redo；ACID 表有 delta/base 文件 | HDFS 目录 | -- | Hive 3 ACID v2 |
| Flink SQL | checkpoint + changelog state backend | RocksDB WAL + checkpoint | -- | 流处理 |
| Databricks | Delta Lake `_delta_log/` | 对象存储 JSON + Parquet | -- | 基于 Delta |
| Teradata | TJ (Transient Journal) + PJ (Permanent Journal) | DBC 系统区 | 多种 | TJ 用于回滚，PJ 用于恢复 |
| Greenplum | WAL（继承 PG） | `pg_wal/` per segment | 每 segment | 分布式 |
| CockroachDB | Raft log + Pebble WAL | `cockroach-data/`，每 store 一个 Pebble WAL | 多 range | Pebble 是 RocksDB fork |
| TiDB | Raft log（TiKV 内）+ binlog（可选） | TiKV RocksDB WAL | 多 region | 计算层 TiDB 无日志 |
| OceanBase | clog (commit log) | clog 目录，per partition group | 多分区 | Paxos 日志 |
| YugabyteDB | Raft WAL + RocksDB WAL | tablet WAL 目录 | 多 tablet | 双层 WAL |
| SingleStore | transaction log | 内存 row store + 列存 segment | 多分区 | 内存优先 |
| Vertica | WOS/ROS + DC log | catalog + DC | -- | 已废弃 WOS（10.0） |
| Impala | 无（计算引擎） | -- | -- | 依赖 HMS/Iceberg |
| StarRocks | edit log（FE）+ tablet meta | BDB JE 日志 | -- | FE Raft 选举 |
| Doris | edit log + tablet meta | BDB JE | -- | 同 StarRocks 起源 |
| MonetDB | WAL | `wal/` 目录 | 单流 | 主要面向 BAT 持久化 |
| CrateDB | translog（继承 Lucene/Elasticsearch） | per shard | 多分片 | translog + Lucene commit |
| TimescaleDB | WAL（继承 PG） | `pg_wal/` | 单流 | hypertable 复用 PG WAL |
| QuestDB | WAL（4.0+）| `db/<table>/wal*/` | 表级 | 早期版本无 WAL |
| Exasol | redo log | 内部，不暴露 | 不暴露 | 列存 + 内存 |
| SAP HANA | redo log + savepoint | log volume `logsegment_*` | 多分区 | 内存为主，日志为辅 |
| Informix | physical log + logical log | dbspace 内 | 双日志 | physical 用于 fast recovery |
| Firebird | careful write + forced writes | 数据文件原地 | 无独立日志 | 没有传统 WAL，2.x 后引入 nbackup |
| H2 | transaction log | `*.mv.db` 中的 chunk | 单流 | MVStore 基于 chunk |
| HSQLDB | `.log` + `.script` | 文件 | 单流 | append-only |
| Derby | log file | `log/` 目录 | 单流 | append-only |
| Amazon Athena | 无 | -- | -- | 无状态计算 |
| Azure Synapse | transaction log | 不暴露（dedicated SQL pool） | 单流 | 类 SQL Server |
| Google Spanner | Paxos log（基于 Colossus） | 不暴露 | 多 split | 完全托管 |
| Materialize | persist 日志（基于对象存储） | S3 等 | -- | 流式物化视图 |
| RisingWave | hummock + meta store WAL | 对象存储 SST + meta | -- | LSM-tree on S3 |
| InfluxDB | WAL（IOx 中是 catalog） | per shard `wal/` | 多 shard | 1.x 经典 WAL，3.x 改 Parquet |
| Databend | 无传统 redo；快照 + WAL meta | meta service Raft 日志 | -- | 计算存储分离 |
| Yellowbrick | redo log | 内部 | 单流 | 类 PostgreSQL |
| Firebolt | 无传统 redo | -- | -- | 完全托管 |

> 关键观察：传统行存 OLTP 几乎全部使用 WAL；分析型云数仓（Snowflake/BigQuery/Athena）将日志作为**实现细节隐藏**；流处理与对象存储原生引擎（Materialize/RisingWave/Databricks/Iceberg）则将日志**外置到对象存储**作为事务日志而非二进制 WAL。

### 2. fsync 配置（提交时刷盘策略）

| 引擎 | 默认 fsync 时机 | 配置项 | 可关闭 fsync |
|------|---------------|--------|-------------|
| PostgreSQL | 每次 commit | `fsync`、`synchronous_commit` | 是（不安全） |
| MySQL InnoDB | 每次 commit | `innodb_flush_log_at_trx_commit` | 是（值 0/2） |
| MariaDB | 每次 commit | 同上 | 是 |
| SQLite | 取决于 PRAGMA | `PRAGMA synchronous` (OFF/NORMAL/FULL/EXTRA) | 是 |
| Oracle | 每次 commit | `COMMIT WRITE [WAIT|NOWAIT] [IMMEDIATE|BATCH]` | 是 |
| SQL Server | 每次 commit | `DELAYED_DURABILITY` (2014+) | 是（DD = FORCED） |
| DB2 | 每次 commit | `LOGBUFSZ` + `MINCOMMIT` (废弃) | 部分 |
| DuckDB | 每次 commit | `checkpoint_threshold` + 内部 fsync | 否（默认强制） |
| ClickHouse | 周期性 | `fsync_after_insert`（默认 0） | 是（默认就关） |
| CockroachDB | 每次 commit | `--disable-sync-write` (调试) | 是 |
| TiDB / TiKV | 每次 Raft commit | `raftstore.sync-log` | 是 |
| OceanBase | 每次 Paxos commit | clog 自动 | 是 |
| YugabyteDB | 每次 Raft commit | `--durable_wal_write` | 是 |
| Greenplum | 每次 commit | 同 PG | 是 |
| TimescaleDB | 每次 commit | 同 PG | 是 |
| QuestDB | commit 时 | `cairo.commit.mode` (sync/nosync/async) | 是 |
| H2 | 每次 commit | `WRITE_DELAY` | 是（默认 500ms） |
| HSQLDB | 取决于 mode | `WRITE_DELAY` 0/false=每次 | 是 |
| Derby | 每次 commit | `derby.storage.logSwitchInterval` 等 | 部分 |
| MonetDB | 周期性 + commit | 内部 | 部分 |
| CrateDB | 每次 commit | `index.translog.durability` (request/async) | 是 |
| Vertica | 每次 commit | -- | 否 |
| SAP HANA | 每次 commit | savepoint 间隔 | 否 |
| Informix | 取决于日志模式 | unbuffered/buffered logging | 是 |
| Exasol | 内部 | -- | 否 |
| Firebird | 默认 forced writes ON | `ALTER DATABASE SET FORCED WRITES` | 是 |
| InfluxDB 1.x | 每次 commit | `wal-fsync-delay` | 是 |
| Snowflake | 托管 | -- | -- |
| BigQuery | 托管 | -- | -- |
| Redshift | 托管 | -- | -- |
| Yellowbrick | 内部 | -- | -- |
| Databend | 取决于 meta | -- | -- |
| Teradata | TJ 每次 commit | 内部 | 否 |
| StarRocks/Doris | edit log 每次 commit | `meta_delay_toleration_second` | 是 |
| SingleStore | 内存 + 周期 snapshot | `snapshot-trigger-size` | 是 |
| Materialize | persist 周期 flush | -- | -- |
| RisingWave | hummock 周期 | `barrier_interval_ms` | -- |
| Flink | checkpoint 周期 | `execution.checkpointing.interval` | -- |

> 注：标记"是（不安全）"表示关闭 fsync 后崩溃可能丢数据，仅用于测试或可重建数据集。

### 3. 同步 vs 异步 commit

| 引擎 | 同步 commit | 异步 commit | 备注 |
|------|------------|------------|------|
| PostgreSQL | 默认 | `synchronous_commit = off` | 5 个等级 |
| MySQL | 默认 | `innodb_flush_log_at_trx_commit = 0` | -- |
| MariaDB | 默认 | 同上 | -- |
| Oracle | `COMMIT WRITE WAIT` | `COMMIT WRITE NOWAIT BATCH` | 10g+ |
| SQL Server | 默认 | `DELAYED_DURABILITY = ALLOWED/FORCED` | 2014+ |
| DB2 | 默认 | -- | 通过 LOGBUFSZ 缓冲 |
| SQLite | `PRAGMA synchronous=FULL` | `synchronous=OFF/NORMAL` | -- |
| DuckDB | 默认 | -- | 不暴露 async |
| ClickHouse | -- | 默认异步 | `wait_for_async_insert` 控制 |
| CockroachDB | 默认 | -- | Raft commit 必同步 |
| TiDB | 默认 | -- | -- |
| YugabyteDB | 默认 | `durable_wal_write=false` 不安全 | -- |
| OceanBase | 默认 | -- | Paxos commit |
| SAP HANA | 默认 | `commit_write_wait_for_async_logger` | -- |
| Vertica | 默认 | -- | -- |
| Greenplum | 默认 | 继承 PG | -- |
| TimescaleDB | 默认 | 继承 PG | -- |
| Informix | unbuffered logging | buffered logging | 数据库属性 |
| Firebird | forced writes | 关闭 forced writes | -- |
| H2 | 默认 | `WRITE_DELAY=500` 默认 | 默认其实是异步 |
| HSQLDB | `SET WRITE_DELAY FALSE` | 默认 500ms 异步 | -- |
| Derby | 默认 | -- | -- |
| QuestDB | -- | 默认异步 | -- |
| InfluxDB | -- | 默认异步 | -- |
| MonetDB | -- | 默认异步 | -- |
| CrateDB | `request` | `async` | -- |
| StarRocks/Doris | 默认 | -- | edit log 同步 |
| SingleStore | -- | 默认 | snapshot 异步 |
| Snowflake/BigQuery/Redshift | 不暴露 | -- | -- |

### 4. 组提交（Group Commit）

组提交把多个并发事务的 fsync 合并成一次系统调用，是 OLTP 高 TPS 的关键。

| 引擎 | 组提交 | 配置 | 备注 |
|------|--------|------|------|
| PostgreSQL | 隐式 | `commit_delay`、`commit_siblings` | WAL writer 自动批 |
| MySQL InnoDB | 显式 | binlog 三阶段 group commit (5.6+) | flush/sync/commit 三阶段 |
| MariaDB | 显式 | 5.5+ binlog group commit | -- |
| Oracle | 默认 | LGWR adaptive group commit | 11g+ |
| SQL Server | 隐式 | 内部 log block flush | -- |
| DB2 | 隐式 | `MAXAPPLS` + log buffer | -- |
| DuckDB | 隐式 | -- | 单写者 |
| CockroachDB | 是 | Raft batching + Pebble batch commit | -- |
| TiDB | 是 | TiKV `raftstore.apply-pool-size` | -- |
| YugabyteDB | 是 | Raft batching | -- |
| OceanBase | 是 | clog batching | -- |
| Greenplum | 是 | 继承 PG | -- |
| TimescaleDB | 是 | 继承 PG | -- |
| Vertica | 是 | -- | -- |
| SAP HANA | 是 | `group_commit_*` 参数 | -- |
| Informix | 是 | LBU 缓冲 | -- |
| MonetDB | -- | -- | 不需要 |
| Firebird | -- | -- | 单写者瓶颈 |
| H2 | 是（异步） | -- | -- |
| HSQLDB | 是（异步） | -- | -- |
| Derby | 是 | -- | -- |
| ClickHouse | 是（async insert） | `async_insert=1`、`wait_for_async_insert` | 21.11+ |
| Spark/Flink/Trino/Presto | -- | -- | 不适用 |
| Snowflake/BigQuery 等托管 | 是 | 不暴露 | -- |

### 5. WAL 压缩

| 引擎 | WAL 压缩 | 算法 | 引入版本 |
|------|---------|------|---------|
| PostgreSQL | 全页镜像压缩 | pglz / lz4 / zstd | 9.5 / 15+ (lz4/zstd) |
| MySQL InnoDB | -- | -- | 不直接压缩 redo |
| MariaDB | -- | -- | -- |
| Oracle | redo 不压缩，归档可压缩 | basic/medium/high | 11g+ |
| SQL Server | log backup compression | -- | 2008+ 仅备份 |
| DB2 | -- | -- | -- |
| SQLite | -- | -- | -- |
| DuckDB | -- | -- | -- |
| CockroachDB | snappy | -- | 默认 |
| TiDB | snappy/lz4/zstd | RocksDB WAL 不压缩，Raft snapshot 压缩 | -- |
| YugabyteDB | -- | -- | -- |
| OceanBase | clog 压缩 | -- | -- |
| Greenplum | 继承 PG 15+ lz4/zstd | -- | -- |
| TimescaleDB | 继承 PG | -- | -- |
| SAP HANA | 是 | 内部 | -- |
| Informix | -- | -- | -- |
| ClickHouse | 不适用 | -- | -- |
| QuestDB | -- | -- | -- |
| H2/HSQLDB/Derby | -- | -- | -- |
| Snowflake/BigQuery 等 | 托管 | -- | -- |

### 6. WAL 归档 / 日志传送（用于复制）

| 引擎 | 归档 | 流式复制 | 逻辑复制 |
|------|------|---------|---------|
| PostgreSQL | `archive_command` / `archive_library` | 是 (流式 WAL) | 是 (10+) |
| MySQL | binlog 归档 | binlog 复制 | row-based binlog |
| MariaDB | binlog | 是 | 是 |
| Oracle | `LOG_ARCHIVE_DEST_n` | Data Guard | GoldenGate / LogMiner |
| SQL Server | log shipping / Always On | log shipping、AG | CDC、Replication |
| DB2 | archive logging | HADR | Q Replication |
| SQLite | -- | -- | -- |
| DuckDB | -- | -- | -- |
| ClickHouse | -- | ReplicatedMergeTree (ZK/Keeper) | -- |
| CockroachDB | 内置 | Raft | CDC changefeed |
| TiDB | 内置 | Raft | TiCDC |
| OceanBase | 内置 | Paxos | OBCDC |
| YugabyteDB | 内置 | Raft | xCluster |
| Greenplum | 是 | 是 | -- |
| TimescaleDB | 继承 PG | 是 | 是 |
| QuestDB | 是 (4.0+) | -- | -- |
| MonetDB | -- | -- | -- |
| CrateDB | translog | shard 复制 | -- |
| Vertica | 是 | 是 | -- |
| SAP HANA | 是 | System Replication | -- |
| Informix | 是 | HDR/RSS | -- |
| Firebird | nbackup | -- | -- |
| H2/HSQLDB/Derby | -- | -- | -- |
| Teradata | 是 | -- | -- |
| Snowflake | 自动 | 跨区域 replication | -- |
| BigQuery | 自动 | 跨区域 replication | -- |
| Redshift | 自动 | -- | -- |
| Spanner | 自动 | 跨区域 | CDC |
| Materialize | -- | -- | source/sink |
| RisingWave | -- | -- | -- |
| Databend | -- | -- | -- |
| Yellowbrick | 是 | -- | -- |
| Firebolt | 托管 | -- | -- |
| Databricks (Delta) | -- | Deep Clone | -- |
| Hive ACID | -- | -- | -- |
| Spark/Trino/Presto/Flink/Athena/Impala | 不适用 | -- | -- |

### 7. Checkpoint 触发条件

Checkpoint 是把脏页刷盘从而**截断 WAL** 的过程。触发条件通常是时间和大小的组合。

| 引擎 | 时间触发 | 大小触发 | 默认间隔 |
|------|---------|---------|---------|
| PostgreSQL | `checkpoint_timeout` | `max_wal_size` | 5 分钟 / 1GB |
| MySQL InnoDB | -- | redo log 75% 满 | 自适应 + 连续 |
| MariaDB | 同 InnoDB | -- | -- |
| SQLite (WAL) | -- | `wal_autocheckpoint` 1000 页 | -- |
| Oracle | `LOG_CHECKPOINT_TIMEOUT` | `LOG_CHECKPOINT_INTERVAL` | `FAST_START_MTTR_TARGET` 自动 |
| SQL Server | recovery interval | indirect checkpoint `TARGET_RECOVERY_TIME` | 1 分钟 / 60 秒 |
| DB2 | `SOFTMAX` 百分比 | `LOGFILSIZ` 触发 | -- |
| DuckDB | `checkpoint_threshold` | 16 MiB 默认 | -- |
| CockroachDB | Pebble 自动 | -- | -- |
| TiDB / TiKV | RocksDB flush + compaction | -- | -- |
| OceanBase | minor + major freeze | 内存达阈值 | -- |
| YugabyteDB | RocksDB flush | -- | -- |
| Greenplum | 继承 PG | -- | -- |
| TimescaleDB | 继承 PG | -- | -- |
| Vertica | -- | -- | mergeout 周期 |
| SAP HANA | savepoint 间隔 5 分钟 | -- | -- |
| Informix | `CKPTINTVL` | physical log 满 | -- |
| Firebird | -- | -- | 不适用 |
| H2 | 自动 chunk merge | -- | MVStore |
| HSQLDB | `SET FILES LOG SIZE` | -- | -- |
| Derby | log switch | -- | -- |
| MonetDB | 周期 | -- | -- |
| CrateDB | translog 触发 Lucene commit | -- | -- |
| QuestDB | -- | -- | -- |
| Snowflake/BigQuery/Redshift/Spanner | 托管 | -- | -- |
| InfluxDB | TSM 文件 rollover | -- | -- |
| Materialize/RisingWave/Flink | barrier checkpoint | -- | 流处理 |
| 其它（计算引擎） | 不适用 | -- | -- |

### 8. Fuzzy vs Sharp Checkpoint

- **Sharp checkpoint**：所有事务暂停，刷光全部脏页，截断日志。简单但有抖动。
- **Fuzzy checkpoint**：不停服务，渐进刷脏页；checkpoint 起止之间的 LSN 范围都需要 redo replay。

| 引擎 | 类型 | 备注 |
|------|------|------|
| PostgreSQL | Fuzzy | 8.3+ spread checkpoint |
| MySQL InnoDB | Fuzzy | 持续刷脏 + adaptive flushing |
| Oracle | Fuzzy | incremental checkpointing |
| SQL Server | Sharp（自动）/ Fuzzy（indirect） | 2012+ indirect 是 fuzzy |
| DB2 | Fuzzy | SOFTMAX |
| SQLite | Sharp | WAL checkpoint 一次性 |
| DuckDB | Sharp | 单写者 |
| Firebird | Sharp | 简单 |
| H2 | Sharp | -- |
| Derby | Sharp | -- |
| HSQLDB | Sharp | -- |
| SAP HANA | Sharp savepoint | 5 分钟 |
| Informix | Fuzzy（11+）/ Sharp（早期） | -- |
| MonetDB | Sharp | -- |
| CockroachDB / TiDB / YugabyteDB | LSM compaction（连续） | 没有传统 checkpoint 概念 |
| ClickHouse | -- | merge 是 compaction，非 checkpoint |
| Vertica | -- | mergeout |
| Snowflake/BigQuery/Spanner 等托管 | 内部 | -- |

### 9. Full Page Writes（torn page 防护）

写一页 8KB 时，如果只写了部分（被电源/崩溃中断），数据库无法仅靠 redo 恢复——redo 是物理变更增量，需要一个完整基线。**full page write** 在 checkpoint 后第一次修改某页时把整页写入 WAL，作为 redo 基线。

| 引擎 | full page writes | 替代方案 | 备注 |
|------|----------------|---------|------|
| PostgreSQL | `full_page_writes=on`（默认） | -- | 8KB 页 |
| MySQL InnoDB | 是 | doublewrite buffer | 16KB 页 |
| MariaDB | 是 | doublewrite | -- |
| Oracle | -- | log block 512B/4KB 原子写 + media recovery | -- |
| SQL Server | -- | torn page detection / page checksum + page protection | -- |
| DB2 | -- | -- | -- |
| SQLite | -- | journal/WAL 完整页 | rollback journal 即原子页 |
| DuckDB | -- | -- | block-based MVCC |
| Firebird | careful write | 数据页原子写 | -- |
| 大多数 LSM 引擎（CRDB/TiKV/YB/RocksDB） | 不需要 | LSM 永远 append-only | -- |
| ClickHouse / DuckDB / 列存类 | 不需要 | immutable parts | -- |

> 关键事实：full page writes 是 PostgreSQL WAL 量大的主要原因。在 checkpoint 后第一次修改的页都会被完整写入 WAL，因此 checkpoint 越频繁，WAL 越多；checkpoint 越稀疏，WAL 越少但崩溃恢复越慢。

### 10. WAL 段 / 块大小

| 引擎 | 段大小 (segment) | 块大小 (block) |
|------|----------------|---------------|
| PostgreSQL | 默认 16 MB（编译期 `--with-wal-segsize`，11+ initdb 可调） | 8 KB |
| MySQL InnoDB | 8.0.30+ 可在线调整，redo log 文件 4MB-512MB | 512 B (log block) |
| MariaDB | 同上 | 512 B |
| Oracle | redo log file 可定义（典型 50-200 MB） | OS block size |
| SQL Server | VLF 大小由 log 文件大小决定 | 512 B / 4 KB |
| DB2 | LOGFILSIZ × 4 KB | 4 KB |
| SQLite | WAL 文件无段，单文件 | 页大小 (1KB-64KB) |
| DuckDB | WAL 文件无段 | 256 KB block |
| CockroachDB | Pebble WAL 默认 64 MB | -- |
| TiDB | RocksDB WAL 64 MB | -- |
| YugabyteDB | per tablet WAL segment 64 MB | -- |
| Greenplum | 64 MB（默认） | 32 KB |
| TimescaleDB | 16 MB（继承 PG） | 8 KB |
| SAP HANA | log segment 1 GB | -- |
| Informix | logical log file 可配置 | -- |
| Firebird | -- | 8 KB |
| H2 | chunk 大小自动 | -- |

### 11. 页缓存 / Buffer Pool 大小

虽然不是 WAL 直接配置，但 buffer pool 大小决定脏页量与 checkpoint 压力。

| 引擎 | 配置项 | 默认 |
|------|--------|------|
| PostgreSQL | `shared_buffers` | 128 MB |
| MySQL InnoDB | `innodb_buffer_pool_size` | 128 MB |
| MariaDB | 同上 | -- |
| SQLite | `PRAGMA cache_size` | 2000 页 |
| Oracle | `DB_CACHE_SIZE` / `SGA_TARGET` | 自动 |
| SQL Server | `max server memory` | 系统大部分 |
| DB2 | bufferpool size | -- |
| DuckDB | `memory_limit` | 80% RAM |
| ClickHouse | `mark_cache_size`、`uncompressed_cache_size` | -- |
| CockroachDB | `--cache` | 25% RAM |
| TiKV | `storage.block-cache.capacity` | 45% RAM |
| YugabyteDB | `--memory_limit_hard_bytes` | -- |
| OceanBase | memstore + KV cache | -- |
| Greenplum | shared_buffers per segment | -- |
| Vertica | 内存配额 | -- |
| SAP HANA | 全内存 | 全机 |
| Exasol | 全内存 | 全机 |
| Informix | BUFFERPOOL | -- |
| Firebird | DefaultDbCachePages | 2048 |
| H2 | `CACHE_SIZE` | -- |
| HSQLDB | `SET FILES CACHE SIZE` | -- |
| QuestDB | -- | mmap |

## 详细引擎实现

### PostgreSQL：教科书式的 WAL

PostgreSQL 从 7.1（2001 年）起引入 WAL，是开源数据库中 WAL 实现最完整、文档最详尽的范本。核心参数：

```sql
-- 显示当前 WAL 配置
SHOW wal_level;            -- minimal / replica / logical
SHOW synchronous_commit;   -- off / local / remote_write / on / remote_apply
SHOW fsync;                -- on / off
SHOW full_page_writes;     -- on / off
SHOW wal_compression;      -- off / pglz / lz4 / zstd
SHOW checkpoint_timeout;   -- 默认 5min
SHOW max_wal_size;         -- 默认 1GB
SHOW min_wal_size;         -- 默认 80MB
SHOW checkpoint_completion_target; -- 默认 0.9
SHOW archive_mode;         -- off / on / always
SHOW archive_command;      -- shell 模板
```

**wal_level** 决定记录的内容多寡：

- `minimal`（默认 9.6 之前）：只记录崩溃恢复必需的内容；`CREATE TABLE ... AS`、`COPY` 等可绕过 WAL（使用 wal-skipping 优化）。
- `replica`（默认 9.6+）：记录足够支撑物理流复制和 PITR 的内容。
- `logical`（10+）：额外记录 schema 变更等，以支持逻辑解码。

**checkpoint_timeout** 默认 5 分钟。`max_wal_size` 是软上限：当未完成 checkpoint 期间产生的 WAL 量接近这个值时，会强制触发 checkpoint。`checkpoint_completion_target=0.9` 表示 PG 会把 checkpoint 的 IO 在 90% 的间隔内分摊（spread checkpoint），避免周期性抖动。

**archive_command** 是把已切换的 WAL 段（默认 16 MB）拷贝到归档存储的 shell 命令模板：

```bash
archive_command = 'test ! -f /backup/wal/%f && cp %p /backup/wal/%f'
```

`%p` 是源路径，`%f` 是文件名。返回 0 才算成功；失败时 PG 会重试同一个文件，避免段被回收。15+ 引入了 `archive_library`，可以加载 C 模块直接归档（避免 fork 开销）。

**wal_compression** 在 9.5 引入时只支持 pglz（PostgreSQL 自带的轻量算法）；15 增加 lz4 与 zstd。压缩对象是 full page image，对于大 buffer pool + 高写入场景能减少 30%-70% 的 WAL 体积。

**full_page_writes**：默认 on，绝大多数情况不应关闭。关闭后如果存储不能保证页原子写入（例如普通 ext4 + 8KB 页），崩溃后可能出现无法恢复的数据损坏。某些企业存储（NVMe 4K 原子写、ZFS 8K block）天然提供原子页写入，理论上可以关。

### MySQL InnoDB：三套日志的复杂协奏

InnoDB 的"日志"实际上是三套独立的子系统：

1. **redo log**（物理日志）：保证 D。文件曾经叫 `ib_logfile0/1`，8.0.30 起改为 `#innodb_redo/#ib_redoN` 多文件，可在线 `SET GLOBAL innodb_redo_log_capacity = ...`。
2. **undo log**（逻辑日志）：保证 A 和 I（MVCC 多版本）。存储在 undo tablespace。
3. **binlog**（逻辑日志）：保证复制和 PITR。InnoDB 之外的 server 层。

**innodb_flush_log_at_trx_commit** 控制 redo log 刷盘策略：

| 值 | write | fsync | 崩溃丢失上限 | ACID 兼容 |
|---|-------|-------|------------|----------|
| 0 | 每秒 | 每秒 | 1 秒事务 | 否 |
| 1 | 每次 commit | 每次 commit | 0（默认） | 是 |
| 2 | 每次 commit | 每秒 | OS 崩溃约 1 秒；DB 崩溃 0 | 否 |

值 2 是性能与安全的折中：MySQL 进程崩溃不会丢数据（因为 write 已经到 OS 缓存），但内核 panic 或断电仍会丢约 1 秒内的事务。

**sync_binlog** 是 server 层的对应参数：

- `sync_binlog=0`：依赖 OS 刷盘。
- `sync_binlog=1`：每次事务后 fsync binlog（默认）。
- `sync_binlog=N`：每 N 次 commit fsync 一次。

只有 `innodb_flush_log_at_trx_commit=1` AND `sync_binlog=1` 才是真正的 ACID。任何一个降级都会破坏 D。

**innodb_doublewrite**：full page write 的 MySQL 等价物，但实现完全不同。InnoDB 把脏页先写到 doublewrite buffer（系统表空间的连续 128 页区域），fsync，然后再写到目标位置。崩溃后如果发现某页 partial write，从 doublewrite buffer 恢复。8.0.20+ 把 doublewrite buffer 移到独立文件，并支持并行。

**innodb_io_capacity**：告诉 InnoDB 这台机器的 IOPS 能力，控制后台刷脏速率。HDD 设 200，SATA SSD 设 2000-5000，NVMe 设 10000-20000。`innodb_io_capacity_max` 是上限。

**8.0.30 redo log 在线 resize**：之前要修改 redo log 大小必须 stop server、删除文件、改配置、重启。8.0.30 引入了 `innodb_redo_log_capacity` 全局变量，可在运行时调整，InnoDB 会在后台扩展或收缩 `#innodb_redo/` 中的文件数量。

```sql
-- 在线调整 redo log 总容量
SET GLOBAL innodb_redo_log_capacity = 4 * 1024 * 1024 * 1024;  -- 4 GB
```

### Oracle：LGWR 与 Instance Recovery

Oracle 的 redo log 由 **LGWR (Log Writer)** 进程写入。redo log 组织为 **groups** 和 **members**：

- 至少两个 redo log group（循环使用）。
- 每个 group 可以有多个 member（镜像，写到不同物理设备）。
- LGWR 同时写所有 member，实现多路复用。

```sql
-- 查看 redo log 配置
SELECT group#, members, bytes/1024/1024 mb, status FROM v$log;
SELECT group#, member FROM v$logfile;

-- 添加 redo log group
ALTER DATABASE ADD LOGFILE GROUP 4 
    ('/disk1/redo04a.log', '/disk2/redo04b.log') SIZE 200M;

-- 切换 log（强制归档当前 log）
ALTER SYSTEM SWITCH LOGFILE;
```

**LOG_ARCHIVE_DEST_n**：Oracle 最多支持 31 个归档目的地，可以是本地路径或远程 standby：

```sql
ALTER SYSTEM SET LOG_ARCHIVE_DEST_1='LOCATION=/arch MANDATORY';
ALTER SYSTEM SET LOG_ARCHIVE_DEST_2='SERVICE=standby_db ASYNC';
```

**FAST_START_MTTR_TARGET**（10g+）：以"秒"为单位指定崩溃恢复目标时长，Oracle 自动调节 checkpoint 频率使得崩溃后 redo replay 不超过这个时间。设为 0 关闭，典型值 60-300 秒。

```sql
ALTER SYSTEM SET FAST_START_MTTR_TARGET = 60;
-- 估算的恢复时间
SELECT estimated_mttr, target_mttr FROM v$instance_recovery;
```

**COMMIT 选项**：

```sql
COMMIT WRITE WAIT IMMEDIATE;   -- 同步、立即（默认）
COMMIT WRITE NOWAIT BATCH;     -- 异步、批量（最快，可能丢失最近的事务）
```

### SQL Server：LDF 与 DELAYED_DURABILITY

SQL Server 的事务日志是 `.ldf` 文件，内部按 **VLF (Virtual Log File)** 划分。VLF 的数量和大小由 LDF 的初始大小和增长方式决定，过多的小 VLF（数千个）是经典性能问题。

**RECOVERY MODEL**：

- `FULL`：所有操作完整记录，支持 PITR。需要定期 log backup。
- `SIMPLE`：checkpoint 后日志可立即截断，不能 PITR。
- `BULK_LOGGED`：bulk insert/select into 等批量操作只记录最小信息，介于两者之间。

```sql
ALTER DATABASE mydb SET RECOVERY FULL;
ALTER DATABASE mydb SET RECOVERY SIMPLE;
```

**LOG_REUSE_WAIT_DESC**：诊断为什么日志不能截断的关键视图字段：

```sql
SELECT name, log_reuse_wait_desc FROM sys.databases;
-- 常见值: NOTHING, CHECKPOINT, LOG_BACKUP, ACTIVE_TRANSACTION,
--        REPLICATION, AVAILABILITY_REPLICA, OLDEST_PAGE, ...
```

**Indirect Checkpoint**（2012+）：传统 SQL Server checkpoint 是基于 recovery interval（分钟）的；indirect 用 `TARGET_RECOVERY_TIME`（秒）作为目标，连续刷脏，减少抖动。2016+ 新建数据库默认开启 60 秒。

```sql
ALTER DATABASE mydb SET TARGET_RECOVERY_TIME = 60 SECONDS;
```

**DELAYED_DURABILITY**（2014+）：把"提交后等 fsync"改为"提交后立即返回，日志由 LOG_FLUSHER 后台批量刷"。本质上是用 ACID 的 D 换 TPS：

```sql
ALTER DATABASE mydb SET DELAYED_DURABILITY = ALLOWED;
-- 然后单事务可以请求延迟持久化
COMMIT TRAN WITH (DELAYED_DURABILITY = ON);

-- 或强制整个数据库延迟持久化
ALTER DATABASE mydb SET DELAYED_DURABILITY = FORCED;
```

崩溃后丢失的数据上限是 LOG_FLUSHER 的批间隔（默认毫秒级），但理论上是有损的。适合可重做工作流（ETL 中间表）。

### DB2：Circular vs Archive Logging

DB2 的事务日志有两种模式：

- **Circular logging**（默认）：固定数量的主日志文件循环使用。不支持 PITR 和在线备份。
- **Archive logging**：日志填满后归档到二级位置，支持 PITR、在线备份、HADR。

```sql
UPDATE DB CFG FOR mydb USING LOGARCHMETH1 'DISK:/log_archive';
UPDATE DB CFG FOR mydb USING LOGPRIMARY 13 LOGSECOND 12 LOGFILSIZ 1024;
```

**SOFTMAX**（已废弃，旧版本使用）：以"百分比"指定一次 checkpoint 后多少日志填满前要发起下一次 checkpoint。新版本改用 `PAGE_AGE_TRGT_MCR` 控制脏页年龄。

### ClickHouse：没有传统 redo log

ClickHouse MergeTree 引擎依赖**不可变 part**：每次 insert 创建新 part，后台 merge 把小 part 合并成大 part。崩溃恢复靠 part 目录的原子 rename 和元数据。

但是有几种"准 WAL"：

1. **MergeTree write-ahead log**（in-memory parts 时使用）：临时支持，主要是 21.x 中实验性的 InMemory part。
2. **ReplicatedMergeTree** 用 ZooKeeper / Keeper 作为分布式协调日志。
3. **Async insert**（21.11+）：客户端写入先到 buffer，达到大小或时间阈值再 flush 成 part。`fsync_after_insert=0` 默认不 fsync，速度极快但崩溃可能丢数据。

ClickHouse 不适合需要严格 D 的 OLTP 场景；其设计哲学是"批量入库 + 分析查询"。

### CockroachDB / TiDB / YugabyteDB：Raft Log per Range

这三个 NewSQL 都基于 Raft，每个 range/region/tablet 维护一份独立的 Raft log。单写事务的提交需要：

1. Leader 把 Raft log entry 写到本地 storage WAL（Pebble/RocksDB）。
2. 复制给 follower，达到多数派（quorum）确认。
3. Apply 到状态机（即数据存储）。

存储引擎本身（Pebble/RocksDB）也有自己的 WAL，因此实际上是**双层 WAL**：Raft log 和 storage engine WAL。后者负责崩溃后状态机恢复，前者负责跨节点一致性。

CockroachDB 在 19.x 之后用 Pebble 替代 RocksDB（LSM-tree 实现，Go 原生）。Pebble WAL 默认 64 MB 段，组提交批量 fsync。

```bash
# CockroachDB 关键参数
cockroach start --max-disk-temp-storage=...
              --cache=25%
# 通过 cluster setting 调整
SET CLUSTER SETTING kv.raft_log.disable_synchronization_unsafe = false;
```

YugabyteDB 的 tablet 同时维护一个 Raft WAL 目录和一个 RocksDB（regular + intents 两个 RocksDB），每个都有自己的 WAL。`--durable_wal_write=true` 是默认值，关闭后崩溃可能丢数据。

### Firebird：Forced Writes 而非传统 WAL

Firebird 历史上没有真正的 WAL。它的 ACID 机制是：

1. **Careful Write**：写顺序由事务管理器精心安排，确保即使崩溃也能从数据文件直接恢复。
2. **Forced Writes**：默认 ON，每次写都直接 fsync 数据页。可以关闭以提升性能（`ALTER DATABASE SET FORCED WRITES OFF`）。
3. **MVCC 行版本**：旧版本和新版本同时存在于同一个数据页，由垃圾回收异步清理。

Firebird 2.x 之后引入 **nbackup** 增量备份机制，提供了一种半 WAL 风格的 page-level changeset 记录。

## PostgreSQL synchronous_commit 五个等级

PostgreSQL 的 `synchronous_commit` 是同类配置中最细致的一个，从 9.1 引入到现在演化出 5 个等级（值 `on` 是默认）：

| 等级 | 本地 fsync | 远程 receive | 远程 write | 远程 fsync | 远程 apply |
|------|-----------|------------|-----------|-----------|-----------|
| `off` | 异步 | -- | -- | -- | -- |
| `local` | 是 | -- | -- | -- | -- |
| `remote_write` | 是 | 是 | 是 | -- | -- |
| `on`（默认） | 是 | 是 | 是 | 是 | -- |
| `remote_apply` | 是 | 是 | 是 | 是 | 是 |

含义说明：

- **off**：commit 后立即返回。WAL writer 后台进程会以 `wal_writer_delay`（默认 200ms）周期 fsync。最坏丢失约 3 × 200ms = 600ms 的事务。**注意**：off 不会破坏数据库一致性，只会丢失最近的事务；这与 `fsync=off` 不同。
- **local**：忽略所有同步副本，只保证本地 fsync。当主从复制不可用或允许临时降级时使用。
- **remote_write**：等待至少一个同步备库收到 WAL 并 `write()` 到 OS 缓存（不等 fsync）。备库 OS crash 会丢，但备库进程崩溃不会丢。
- **on**：等待至少一个同步备库 fsync 完成。这是默认值，保证主备双 fsync 后才返回。
- **remote_apply**：等待备库 fsync 并 apply（即查询能在备库上看到这次提交）。延迟最大但对一致性查询最严格。

```sql
-- 全局设置
ALTER SYSTEM SET synchronous_commit = 'remote_apply';

-- 单事务覆盖（适用于异构工作负载）
BEGIN;
SET LOCAL synchronous_commit = 'off';
INSERT INTO audit_log VALUES (...);  -- 允许丢失
COMMIT;
```

混合使用是常见模式：审计/日志类表用 `off`，订单/账户类用 `on` 或 `remote_apply`。

## MySQL innodb_flush_log_at_trx_commit 三档对比

下面用一个最直观的表格说明三种值的语义差异：

| 场景 | 值 0 | 值 1（默认） | 值 2 |
|------|------|------------|------|
| MySQL 进程 crash | 丢最多 1 秒 | 不丢 | 不丢 |
| OS panic / 断电 | 丢最多 1 秒 | 不丢 | 丢最多 1 秒 |
| ACID | 否 | 是 | 否 |
| 性能（典型 OLTP TPS） | 100% | 30%-50% | 80%-95% |
| 适用场景 | 测试 / 可重建数据 | 生产订单系统 | 中间表 / 日志表 |

值 2 之所以介于 0 和 1 之间，是因为 OS 接管了 buffer 后只要 OS 不挂，commit 就不会丢；但 OS 挂了之后没有 fsync 兜底，仍然有 1 秒窗口。

最佳实践组合（生产 OLTP）：

```ini
[mysqld]
innodb_flush_log_at_trx_commit = 1
sync_binlog                    = 1
innodb_doublewrite             = ON
innodb_flush_method            = O_DIRECT
innodb_io_capacity             = 5000
innodb_io_capacity_max         = 10000
innodb_redo_log_capacity       = 4G
binlog_group_commit_sync_delay = 100   -- 微秒，攒批
```

降级组合（数据可重建场景）：

```ini
innodb_flush_log_at_trx_commit = 2
sync_binlog                    = 1000
innodb_doublewrite             = OFF
```

## SQLite PRAGMA synchronous 与 WAL 模式

SQLite 的持久化由两个正交维度决定：journal mode 和 synchronous level。

**journal_mode**：

- `DELETE`（默认 < 3.7.0）：传统 rollback journal，事务前先写 journal，commit 时删除。
- `TRUNCATE`：与 DELETE 类似，但不删除文件，只 truncate 到 0。
- `PERSIST`：journal header 写 0 表示无效，避免 OS 元数据写。
- `MEMORY`：journal 在内存里，崩溃丢数据。
- `WAL`（3.7.0+）：现代 WAL 模式，读不阻塞写、写不阻塞读，速度显著提升。
- `OFF`：完全无 journal，不安全。

**synchronous**：

- `OFF` (0)：不 fsync，不安全。
- `NORMAL` (1)：在 WAL 模式下足够安全（commit 不 fsync，只在 checkpoint 时 fsync），rollback journal 模式下不够。
- `FULL` (2)：默认；每次 commit fsync。
- `EXTRA` (3)：FULL + 额外 fsync 目录元数据，最强保证。

```sql
PRAGMA journal_mode = WAL;
PRAGMA synchronous = NORMAL;
PRAGMA wal_autocheckpoint = 1000;  -- 1000 页触发自动 checkpoint
```

WAL 模式下，写入会先 append 到 `*-wal` 文件，定期 checkpoint 把 wal 内容应用到主数据库文件。`*-shm` 是共享内存文件，存放索引。**WAL + NORMAL** 是 99% 移动应用与桌面应用的最佳组合。

## DuckDB

DuckDB 0.5（2022）之前没有 WAL，单文件数据库依赖关闭时刷盘。0.5+ 引入 WAL 支持崩溃恢复：每次事务 commit 写入 `<db>.wal` 文件，到达 `checkpoint_threshold`（默认 16 MiB）时触发 checkpoint 把 WAL 应用到主文件。

```sql
SET checkpoint_threshold = '1GB';
PRAGMA force_checkpoint;
```

DuckDB 是单写者多读者，因此不需要 group commit；但其列存 + 块级压缩使得 checkpoint 成本远低于行存 OLTP。

## 关键发现

1. **没有 SQL 标准**：WAL 是纯实现细节。"WAL"这个术语本身是 PostgreSQL 的发明，其他引擎叫 redo log、transaction log、translog 等等。但 ARIES（1992）确立的 redo + undo + WAL 协议是绝大多数关系数据库的共同祖先。

2. **fsync 是 ACID 的命门**：没有 fsync 的 commit 不是真正的 commit。`innodb_flush_log_at_trx_commit=2` 和 `synchronous_commit=local` 看似相似，实际语义截然不同——前者本地不 fsync，后者本地 fsync 但忽略远程。

3. **PostgreSQL 的 synchronous_commit 五个等级是同类中最细致的**：从 `off` 到 `remote_apply`，覆盖了从极致性能到极致一致性的所有取舍点。其他引擎大多只有"同步/异步"二元选择。

4. **MySQL 三套日志的复杂性**：innodb redo + undo + binlog 三套日志各有目的。要保证 ACID 必须同时 `innodb_flush_log_at_trx_commit=1` AND `sync_binlog=1`，缺一不可。

5. **MySQL 8.0.30 redo log 在线 resize 是重大改进**：之前调整 redo log 大小必须停服改文件。现在通过 `innodb_redo_log_capacity` 全局变量在线生效，是云原生场景的关键能力。

6. **Oracle FAST_START_MTTR_TARGET 是 declarative checkpoint 的代表**：用户只需指定"我能容忍多长时间的崩溃恢复"，Oracle 自动调节 checkpoint 频率，比手工调 `checkpoint_timeout`/`max_wal_size` 友好得多。其他数据库（SQL Server `TARGET_RECOVERY_TIME`、DB2 `PAGE_AGE_TRGT_MCR`）跟进了类似设计。

7. **SQL Server DELAYED_DURABILITY 是显式破坏 ACID 的命名最诚实的方案**：参数名直接告诉用户这会"延迟持久化"。其他引擎的 async commit 往往用更隐晦的命名。

8. **PostgreSQL full_page_writes 是 WAL 量大的主因**：checkpoint 后第一次修改页要完整写入 WAL 作为 redo 基线。这导致 WAL 体积约为修改字节数的 5-20 倍。InnoDB 用 doublewrite buffer 解决同样的 torn page 问题，但走的不是 redo log 而是单独区域。

9. **LSM 引擎不需要 full page writes**：CockroachDB/TiDB/YugabyteDB/RocksDB/Pebble 因为 SSTable 是 immutable 写一次，不存在 in-place update 的 partial write 问题。这是 LSM 的隐藏优势之一。

10. **分布式数据库是双层 WAL**：Raft log + storage engine WAL。Raft log 跨节点一致性，storage WAL 本地崩溃恢复。两者都需要 fsync，因此典型分布式 OLTP 的 fsync 次数远多于单机。

11. **ClickHouse 没有传统 WAL**：MergeTree 靠不可变 part 和原子 rename 实现崩溃一致性，不适合严格 OLTP。21.11+ 的 async insert 进一步弱化了持久化承诺，换取极致写入吞吐。

12. **Firebird 是反例**：从设计起就没有传统 WAL，靠 careful write + forced writes + MVCC。简单但限制了高并发能力。

13. **SQLite WAL 模式是嵌入式数据库的革命**：3.7.0（2010）引入后，WAL 模式让 SQLite 真正可以在多读一写场景下保持高吞吐。`WAL + NORMAL` 是绝大多数移动 App 的默认选择。

14. **DuckDB 0.5 才有 WAL**：作为 OLAP 嵌入式引擎，DuckDB 早期不需要崩溃恢复。0.5+ 引入 WAL 后才能支持长事务和崩溃安全。

15. **云原生数仓全部隐藏 WAL**：Snowflake、BigQuery、Redshift、Spanner、Athena、Firebolt 完全不暴露 WAL 配置。用户得到的是承诺的 SLA（"99.999% 持久性"），而非具体参数。

16. **托管的代价**：失去 WAL 配置权意味着失去性能微调能力。Snowflake/BigQuery 用户无法在"丢一秒数据换 10× TPS"和"完全 ACID"之间做选择，只能选服务等级。

17. **Group commit 是高 TPS 的关键**：单线程 fsync 大约能做 1000-10000 IOPS，group commit 能将多个并发事务合并成一次 fsync，把 TPS 提升一个数量级。MySQL 5.6+ binlog group commit 是经典案例。

18. **WAL 压缩在大 buffer pool 场景收益最大**：PostgreSQL 15 引入 lz4/zstd WAL 压缩，对于 full page writes 占主导的工作负载能减少 30%-70% 的 WAL 量。redo log 压缩较少见，因为 InnoDB 没有 full page write（用 doublewrite 替代）。

19. **流式引擎用 checkpoint 代替 WAL**：Flink、Materialize、RisingWave 没有传统 WAL；它们用周期 barrier checkpoint 把状态序列化到对象存储。语义与 WAL 等价，但实现完全不同。

20. **fsync 不可被替代**：所有"高性能 NoSQL"或"内存数据库"的高 TPS 都来自跳过或推迟 fsync。没有任何技术能让"已 fsync 的 commit"快过"未 fsync 的 commit"——只有摩尔定律改进 SSD 才能整体提速。

## 参考资料

- PostgreSQL: [Reliability and the Write-Ahead Log](https://www.postgresql.org/docs/current/wal.html)
- PostgreSQL: [WAL Configuration](https://www.postgresql.org/docs/current/wal-configuration.html)
- PostgreSQL: [synchronous_commit](https://www.postgresql.org/docs/current/runtime-config-wal.html#GUC-SYNCHRONOUS-COMMIT)
- MySQL: [InnoDB Redo Log](https://dev.mysql.com/doc/refman/8.0/en/innodb-redo-log.html)
- MySQL: [innodb_flush_log_at_trx_commit](https://dev.mysql.com/doc/refman/8.0/en/innodb-parameters.html#sysvar_innodb_flush_log_at_trx_commit)
- MySQL: [Doublewrite Buffer](https://dev.mysql.com/doc/refman/8.0/en/innodb-doublewrite-buffer.html)
- Oracle: [Managing the Redo Log](https://docs.oracle.com/en/database/oracle/oracle-database/19/admin/managing-the-redo-log.html)
- Oracle: [FAST_START_MTTR_TARGET](https://docs.oracle.com/en/database/oracle/oracle-database/19/refrn/FAST_START_MTTR_TARGET.html)
- SQL Server: [Database Checkpoints](https://learn.microsoft.com/en-us/sql/relational-databases/logs/database-checkpoints-sql-server)
- SQL Server: [Control Transaction Durability](https://learn.microsoft.com/en-us/sql/relational-databases/logs/control-transaction-durability)
- DB2: [Database logging](https://www.ibm.com/docs/en/db2/11.5?topic=logging-database)
- SQLite: [Write-Ahead Logging](https://www.sqlite.org/wal.html)
- SQLite: [PRAGMA synchronous](https://www.sqlite.org/pragma.html#pragma_synchronous)
- DuckDB: [Persistent Storage](https://duckdb.org/docs/connect/overview)
- ClickHouse: [Asynchronous Inserts](https://clickhouse.com/docs/en/optimize/asynchronous-inserts)
- CockroachDB: [Pebble Storage Engine](https://www.cockroachlabs.com/docs/stable/cockroach-start.html)
- TiDB: [TiKV Configuration File](https://docs.pingcap.com/tidb/stable/tikv-configuration-file)
- YugabyteDB: [Durability Settings](https://docs.yugabyte.com/preview/reference/configuration/yb-tserver/)
- Mohan, C. et al. "ARIES: A Transaction Recovery Method Supporting Fine-Granularity Locking and Partial Rollbacks Using Write-Ahead Logging" (1992), ACM TODS
- Gray, J. and Reuter, A. "Transaction Processing: Concepts and Techniques" (1992)
