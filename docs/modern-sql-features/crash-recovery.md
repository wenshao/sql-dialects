# 崩溃恢复 (Crash Recovery)

数据库突然断电、内核 panic、kill -9 进程崩溃——这一刻数据库的真正水平才被检验。一个能在 5 秒内恢复服务的引擎和一个需要 30 分钟回放日志的引擎，在金融、电商、物联网场景中是两种完全不同的产品。崩溃恢复时间是可用性 SLA 的硬约束：99.99% 可用性一年只允许 52 分钟停机，恢复速度直接决定了能否达成目标。

## 为什么恢复时间决定可用性

可用性 SLA 与年度允许停机时间的关系：

| SLA | 年停机 | 月停机 | 单次容忍恢复时间 |
|-----|-------|-------|----------------|
| 99% | 87.6 小时 | 7.3 小时 | 数小时 |
| 99.9% | 8.76 小时 | 43.8 分钟 | 数十分钟 |
| 99.99% | 52.6 分钟 | 4.38 分钟 | 数分钟 |
| 99.999% | 5.26 分钟 | 26.3 秒 | 秒级 |

崩溃恢复有两个组成部分：

1. **故障检测时间** (FDT)：从崩溃发生到监控系统决定切换或重启
2. **实例恢复时间** (IRT)：进程重启后日志回放、回滚未提交事务、重建内存结构所需时间

本文聚焦第二部分——实例恢复算法本身。要追溯到 1992 年 IBM Almaden 研究中心 C. Mohan 等人发表的 ARIES (Algorithms for Recovery and Isolation Exploiting Semantics) 论文：基于 WAL (Write-Ahead Logging) 和 LSN (Log Sequence Number)，定义了 Analysis / Redo / Undo 三阶段的标准恢复模型。今天几乎所有主流关系数据库的恢复机制都可以追溯到 ARIES，或者其简化变体。

## 没有 SQL 标准

SQL 标准（ISO/IEC 9075）只规定 ACID 中的 D（Durability）必须保证已提交事务在故障后仍然存在，但不规定如何实现。崩溃恢复完全是引擎实现细节：

- **算法选择**：ARIES、纯 Redo（无 Undo Pass，因为 MVCC）、物理日志、物理-逻辑日志、Raft 日志回放
- **检查点策略**：模糊检查点 (fuzzy checkpoint) vs 完整检查点 (full checkpoint)
- **并行度**：单线程串行 vs 多线程并行回放
- **粒度**：页级 vs 行级 vs 分区级
- **可观测性**：进度报告 vs 黑盒等待

不同引擎的实现差异巨大，恢复时间从 100 毫秒到数小时不等，对运维和容灾架构有深远影响。

## 支持矩阵

### 恢复算法分类

| 引擎 | 算法 | 日志类型 | Undo 段 | 粒度 |
|------|------|---------|---------|------|
| PostgreSQL | 纯 Redo (MVCC) | 物理-逻辑 (XLOG) | 否 | 页级 |
| MySQL InnoDB | ARIES-like | 物理-逻辑 (Redo) + Undo | 是 | 页级 |
| MariaDB | ARIES-like (InnoDB) | 物理-逻辑 + Undo | 是 | 页级 |
| SQLite | 回滚日志 / WAL | 物理页镜像 | 回滚日志 | 页级 |
| Oracle | ARIES-like | 物理-逻辑 (Redo) + Undo 表空间 | 是 | 块级 |
| SQL Server | ARIES | 物理-逻辑 + Undo 内联 | 内联 | 页级 |
| DB2 | ARIES (原创) | 物理-逻辑 + Undo | 是 | 页级 |
| Snowflake | 不可变文件 | 元数据日志 (FoundationDB) | 否 | 微分区 |
| BigQuery | 不可变文件 | 元数据日志 (Spanner) | 否 | 文件 |
| Redshift | 纯 Redo (基于 PG 8.0) | 物理-逻辑 | 简化 | 块级 |
| DuckDB | WAL 单文件 | 物理-逻辑 | 否 | 块级 |
| ClickHouse | 不可变 part + part 日志 | part 操作日志 | 否 | part 级 |
| Trino | 无（计算层无状态） | -- | -- | -- |
| Presto | 无（计算层无状态） | -- | -- | -- |
| Spark SQL | 元数据回放 | Hive Metastore / Delta Log | 否 | 文件 |
| Hive | 元数据回放 | Metastore | 否 | 文件 |
| Flink SQL | Checkpoint + 状态后端 | RocksDB 增量快照 | 否 | 算子级 |
| Databricks | Delta Log JSON | Delta Lake 事务日志 | 否 | 文件 |
| Teradata | Transient Journal + Permanent Journal | 物理-逻辑 | 是 | 行级 |
| Greenplum | 纯 Redo (PG 内核) | XLOG | 否 | 页级 |
| CockroachDB | Raft 日志回放 | Raft + RocksDB WAL | 否 | range 级 |
| TiDB | Raft 日志回放 | Raft + RocksDB WAL | MVCC | region 级 |
| OceanBase | Paxos 日志回放 | clog (commit log) | 是 | 分区级 |
| YugabyteDB | Raft 日志回放 | Raft + DocDB WAL | MVCC | tablet 级 |
| SingleStore | 快照 + 日志 | 行存 redo + 列存段日志 | 否 | 段级 |
| Vertica | Epoch + WOS/ROS | epoch 日志 | 否 | 投影级 |
| Impala | 无（共享存储） | -- | -- | -- |
| StarRocks | 元数据日志 + tablet | edit log + Tablet WAL | 否 | tablet 级 |
| Doris | 元数据日志 + tablet | bdbje edit log + Tablet WAL | 否 | tablet 级 |
| MonetDB | WAL | 物理-逻辑 | 否 | BAT 级 |
| CrateDB | Lucene + translog | translog (物理-逻辑) | 否 | shard 级 |
| TimescaleDB | 纯 Redo (PG 内核) | XLOG | 否 | chunk 级 |
| QuestDB | Append-only + WAL | 物理-逻辑 (列文件) | 否 | 列级 |
| Exasol | 持续 checkpoint | 物理快照 | 否 | block 级 |
| SAP HANA | Savepoint + Redo | 物理-逻辑 | Undo 段 | 页级 |
| Informix | ARIES-like | 物理-逻辑 + Undo | 是 | 页级 |
| Firebird | Careful Write + Shadow | 强制写 + 影子文件 | 否 (MVCC) | 页级 |
| H2 | MVStore / PageStore WAL | 物理-逻辑 | 否 (MVCC) | 块级 |
| HSQLDB | 脚本日志 | SQL 语句重做 | 否 | 语句级 |
| Derby | ARIES-like | 物理-逻辑 + Undo | 是 | 页级 |
| Amazon Athena | 无（共享存储） | -- | -- | -- |
| Azure Synapse | 分布式 SQL Server / Parquet | 物理-逻辑 / 元数据 | 否 | 不一 |
| Google Spanner | Paxos 日志回放 | Paxos + Colossus | MVCC | split 级 |
| Materialize | 持久化 dataflow | timely dataflow + 持久化 | 否 | 算子级 |
| RisingWave | Hummock LSM + barrier | barrier 对齐快照 | 否 | actor 级 |
| InfluxDB (IOx) | Parquet + WAL | 物理-逻辑 | 否 | partition 级 |
| Databend | Fuse engine 元数据 | Snapshot 链 | 否 | block 级 |
| Yellowbrick | 基于 PG 内核 | XLOG + 列存 SST | 否 | shard 级 |
| Firebolt | 不可变文件 + 元数据 | 元数据日志 | 否 | F3 段级 |

### 实例恢复 vs 介质恢复

- **实例恢复 (Instance Recovery)**：进程崩溃后，从最后一个检查点回放 WAL 到当前末尾，回滚未提交事务，**不需要外部备份**。
- **介质恢复 (Media Recovery)**：磁盘损坏或文件丢失，从备份恢复后，**应用归档日志**追到崩溃点。

| 引擎 | 实例恢复 | 介质恢复 | 自动触发 | 触发者 |
|------|---------|---------|---------|--------|
| Oracle | 是 | 是 (RECOVER DATABASE) | 启动时 | SMON 进程 |
| PostgreSQL | 是 | 是 (PITR) | 启动时 | startup 进程 |
| SQL Server | 是 | 是 (RESTORE LOG) | 启动时 | recovery 线程 |
| MySQL InnoDB | 是 | 是 (binlog point-in-time) | 启动时 | 主线程 |
| DB2 | 是 | 是 (ROLLFORWARD) | 启动时 | db2agent |
| Snowflake | 否 (不可变) | Time Travel | 透明 | 服务层 |
| BigQuery | 否 (不可变) | Time Travel (7 天) | 透明 | 服务层 |
| Redshift | 是 | 快照恢复 | 启动时 | 集群管理 |
| DuckDB | 是 | 否 (单文件) | 打开时 | 主线程 |
| ClickHouse | 是 (per-part) | 备份恢复 | 启动时 | 主线程 |
| Spark SQL | 否 (无状态) | 元数据恢复 | -- | -- |
| Flink SQL | 是 (checkpoint) | 是 (savepoint) | 启动时 | JobManager |
| Teradata | 是 | 是 (ARC) | 启动时 | RSG |
| CockroachDB | 是 (Raft 回放) | 备份恢复 | 启动时 | node startup |
| TiDB | 是 (Raft 回放) | BR 备份恢复 | 启动时 | TiKV |
| OceanBase | 是 (Paxos 回放) | 物理备份 | 启动时 | observer |
| YugabyteDB | 是 (Raft 回放) | 备份恢复 | 启动时 | tserver |
| Spanner | 是 (Paxos 回放) | Backup/Restore | 透明 | 服务层 |
| SingleStore | 是 | 备份恢复 | 启动时 | leaf 节点 |
| Vertica | 是 (epoch) | 备份恢复 | 启动时 | spread |
| SAP HANA | 是 | 是 (log replay) | 启动时 | nameserver |
| Firebird | 是 (sweep) | 是 (gbak restore) | 启动时 | superserver |
| SQLite | 是 (journal) | 否 | 打开时 | first writer |

### Analysis / Redo / Undo 三阶段实现

| 引擎 | Analysis | Redo | Undo | 三阶段名称 |
|------|---------|------|------|-----------|
| Oracle | 是 | 是 | 是 (后台) | Cache Recovery / Transaction Recovery |
| SQL Server | 是 | 是 | 是 | Analysis / Redo / Undo |
| DB2 | 是 | 是 | 是 | Analysis / Redo / Undo (ARIES 原始) |
| MySQL InnoDB | 是 | 是 | 是 (后台) | scan / apply / rollback |
| PostgreSQL | 隐式 | 是 | 否 (MVCC) | startup recovery |
| SQLite (rollback) | 否 | 否 | 是 | journal rollback |
| SQLite (WAL) | 是 | 是 | 否 | wal replay |
| Derby | 是 | 是 | 是 | 同 ARIES |
| Informix | 是 | 是 | 是 | logical recovery |
| Firebird | 否 | 否 | 否 (MVCC + careful write) | sweep |
| H2 (MVStore) | 隐式 | 是 | 否 | open-time replay |
| Teradata | 是 | 是 | 是 (TJ rollback) | restart recovery |
| SAP HANA | 是 | 是 | 是 | log replay |
| MonetDB | 隐式 | 是 | 否 (commit-flush) | wal replay |

### 高级恢复特性

| 引擎 | 模糊检查点 | 并行恢复 | 增量恢复 | PITR | 进度报告 |
|------|----------|---------|---------|------|---------|
| Oracle | 是 | 是 (PR0N 进程) | 是 | 是 (RMAN) | V$RECOVERY_PROGRESS |
| PostgreSQL | 是 | 启动进程串行 | -- | 是 (recovery_target_*) | pg_stat_progress_recovery (16+) |
| SQL Server | 是 | 是 (2005 EE+) | 是 (Accelerated DB Recovery 2019+) | 是 | sys.dm_exec_requests |
| MySQL InnoDB | 是 | 是 (并行 redo apply 8.0+) | -- | binlog 重放 | 错误日志百分比 |
| DB2 | 是 | 是 | 是 (in-flight LSN) | 是 (ROLLFORWARD) | db2pd -recovery |
| MariaDB | 是 | 是 (10.5+) | -- | binlog 重放 | 错误日志 |
| SQLite | 否 | 否 | 否 | 否 | 否 |
| Snowflake | -- | -- | -- | Time Travel | -- |
| Redshift | 是 | 是 | -- | 快照 | STV_RECENTS |
| DuckDB | 是 | 否 | -- | 否 | 否 |
| ClickHouse | -- | 是 (per-part 并行) | 是 | 备份 | system.replication_queue |
| Spark SQL | -- | -- | -- | Delta time travel | Spark UI |
| Flink SQL | 增量 checkpoint | 是 | 是 | 是 (savepoint) | Flink Web UI |
| Databricks | -- | 是 (Delta) | 是 | Time Travel | -- |
| Teradata | 是 | 是 | 是 | 是 (PJ) | 是 |
| Greenplum | 是 | segment 并行 | -- | 是 | -- |
| CockroachDB | Raft snapshot | 是 (range 并行) | 是 | 是 (AS OF SYSTEM TIME) | crdb_internal |
| TiDB | RocksDB checkpoint | 是 (region 并行) | 是 | 是 (BR + GC safepoint) | TiKV metrics |
| OceanBase | 是 | 是 (分区并行) | 是 | 是 | 是 |
| YugabyteDB | RocksDB checkpoint | 是 (tablet 并行) | 是 | 是 | tserver UI |
| SingleStore | 是 | 是 | 是 | 是 | INFORMATION_SCHEMA |
| Vertica | epoch | 是 (节点并行) | 是 | epoch 恢复 | 是 |
| StarRocks | 是 | 是 (tablet 并行) | -- | 备份 | -- |
| Doris | 是 | 是 (tablet 并行) | -- | 备份 | -- |
| MonetDB | 否 | 否 | -- | 否 | 否 |
| TimescaleDB | 是 | 启动进程 | -- | 是 (PG 继承) | 是 |
| QuestDB | -- | 是 (列并行) | -- | 备份 | -- |
| Exasol | 持续 | 是 (节点并行) | -- | 备份 | 是 |
| SAP HANA | savepoint | 是 | 是 | 是 (log replay) | M_RECOVERY_PROGRESS |
| Informix | 是 | 是 (PDQ) | 是 | 是 | onstat -l |
| Firebird | 否 (careful write) | 否 | -- | 是 (nbackup) | 否 |
| H2 | 是 (MVStore) | 否 | -- | 否 | 否 |
| HSQLDB | 否 | 串行 | 否 | 否 | 否 |
| Derby | 是 | 否 | -- | 否 | 否 |
| Spanner | 是 | 是 (split 并行) | 是 | 是 (Backup/Restore) | -- |
| Materialize | 是 | 是 (dataflow) | 是 | -- | -- |
| RisingWave | barrier | 是 (actor 并行) | 是 | -- | -- |
| InfluxDB | 是 | 是 (partition 并行) | -- | 备份 | -- |
| Databend | snapshot 链 | 是 | -- | Time Travel | -- |
| Yellowbrick | 是 | 是 (shard 并行) | -- | 是 | -- |
| Firebolt | -- | -- | -- | -- | -- |

### Oracle FAST_START_MTTR_TARGET 类参数

| 引擎 | 参数 | 含义 | 默认值 |
|------|------|------|-------|
| Oracle | `FAST_START_MTTR_TARGET` | 期望实例恢复秒数 | 0 (禁用) |
| Oracle | `FAST_START_PARALLEL_ROLLBACK` | 并行回滚度 | LOW |
| SQL Server | `recovery interval` | 期望恢复分钟数 | 0 (动态) |
| MySQL | `innodb_max_dirty_pages_pct` | 脏页阈值（间接控制） | 90 |
| MySQL | `innodb_io_capacity` | 后台刷盘速率 | 200 |
| MySQL | `innodb_force_recovery` | 强制恢复级别 0-6 | 0 |
| PostgreSQL | `checkpoint_timeout` | 检查点间隔 | 5min |
| PostgreSQL | `max_wal_size` | WAL 最大尺寸 (间接) | 1GB |
| DB2 | `SOFTMAX` (LOGFILSIZ) | 软检查点频率 | -- |
| DB2 | `NUM_IOCLEANERS` | 清页线程数 | AUTOMATIC |
| SAP HANA | `log_segment_size_mb` | 日志段大小 | -- |
| OceanBase | `enable_smooth_leader_switch` | 平滑切主 | true |

### MVCC 与实例恢复的交互

| 引擎 | MVCC 模型 | Undo Pass 必要性 | 长事务影响 |
|------|----------|----------------|----------|
| PostgreSQL | tuple 多版本 (heap) | 否 | XID wraparound 风险 |
| Oracle | Undo 段构建快照 | 是 (后台延迟) | ORA-01555 snapshot too old |
| MySQL InnoDB | Undo log + 隐藏列 | 是 (后台 purge) | history list 膨胀 |
| SQL Server (RCSI) | tempdb 版本存储 | 是 | tempdb 膨胀 |
| Firebird | 行内多版本 | 否 (sweep 异步) | OAT 滞后 |
| CockroachDB | KV 多版本 (HLC ts) | 否 (GC 后台) | -- |
| TiDB | KV 多版本 (TSO) | 否 (GC 后台) | -- |
| YugabyteDB | DocDB 多版本 | 否 (compaction) | -- |
| Spanner | 不可变历史 | 否 (GC) | -- |
| H2 (MVStore) | block 多版本 | 否 | -- |

## 详细引擎分析

### Oracle: ARIES 衍生 + Instance Recovery

Oracle 是 ARIES 思想最完整的商业实现之一，将三阶段恢复内化为产品特性。

**触发与执行流程**：

1. 实例崩溃后，DBA 执行 `STARTUP`（或自动）
2. SGA 重建后，**SMON (System Monitor) 后台进程**接管恢复
3. SMON 从控制文件读取最后检查点位置 (Checkpoint SCN)
4. 从联机重做日志 (online redo log) 中**前滚 (Roll Forward)**：将所有已提交和未提交的更改应用到数据文件
5. **打开数据库**（这一步至关重要：Oracle 在 Undo Pass 之前已经允许业务连接）
6. SMON 在后台**回滚 (Roll Back)** 未提交事务，使用 Undo 表空间中的镜像
7. 业务事务如果碰到被锁住的行，可以通过 Undo 段获取一致读，或等待回滚完成

**Cache Recovery 与 Transaction Recovery 分离**：Oracle 把 ARIES 的 Redo 阶段称为 Cache Recovery（必须完成才能开库），把 Undo 阶段称为 Transaction Recovery（后台异步）。这种分离让 Oracle 实现了"开库即可用"的语义。

**FAST_START_MTTR_TARGET**：

```sql
ALTER SYSTEM SET FAST_START_MTTR_TARGET=60;  -- 期望 60 秒内完成 Cache Recovery
```

设置后，Oracle 自适应地控制 DBWR 的刷盘速率和检查点频率，使得任何时刻崩溃后 Cache Recovery 都能在目标时间内完成。可以通过 `V$INSTANCE_RECOVERY` 视图查看预测：

```sql
SELECT TARGET_MTTR, ESTIMATED_MTTR, RECOVERY_ESTIMATED_IOS
FROM V$INSTANCE_RECOVERY;
```

**并行恢复**：通过 `RECOVERY_PARALLELISM` 参数或 `PARALLEL` 子句启用。Oracle 派生 PR0N (Parallel Recovery slave) 进程并行回放重做日志：

```sql
RECOVER DATABASE PARALLEL 8;
```

每个 PR0N 处理不同的数据文件或重做线程，受限于重做日志的串行依赖（同一块的修改必须按 LSN 顺序）。

**FAST_START_PARALLEL_ROLLBACK** 控制 Undo Pass 的并行度，可设置 `LOW / HIGH / FALSE`，HIGH 模式使用 4×CPU_COUNT 个 SMON 后台从属进程并行回滚长事务。

### PostgreSQL: 纯 Redo 恢复，无 Undo Pass

PostgreSQL 的恢复机制是 ARIES 的简化版，因为它的 MVCC 模型让 Undo Pass 变得不必要——这是一个深刻的架构选择。

**为什么不需要 Undo**：

PostgreSQL 把每个 tuple 的多版本直接存放在 heap 中，并通过 `xmin / xmax` 元组头部字段标记可见性。当一个事务被 abort，**它写入的 tuple 仍然留在数据文件里**，只是 xmin 对应的事务被标记为 ABORTED，后续读取通过可见性检查自动跳过。VACUUM 后台进程负责真正回收空间。

这意味着崩溃恢复只需要做一件事：**把 WAL 从最后一个检查点回放到末尾**。回放完成后，所有未提交事务的更改在物理上仍然存在，但通过 commit log (`pg_xact`) 中的 ABORTED 状态标记成不可见。无需逐行回滚。

**恢复流程**：

1. postmaster 启动 `startup` 子进程
2. startup 读取 `pg_control` 中的 checkpoint 位置
3. 从该位置开始打开 WAL 段文件，逐条解析 XLOG 记录
4. 对每条 XLOG_HEAP/XLOG_BTREE 等记录，调用对应的 `_redo()` 函数应用到 buffer pool
5. 回放到 WAL 末尾后，写一个新的 checkpoint，启动 checkpointer / bgwriter
6. postmaster 接受连接

**单线程瓶颈**：截至 PG 16，startup 进程仍然单线程回放 WAL（社区有多个并行 redo 的提案）。这导致大写入负载下崩溃恢复时间线性增长，常见的缓解手段是缩短 `checkpoint_timeout` 或增大 `max_wal_size`。

**进度可观测性**：PostgreSQL 16 引入了 `pg_stat_progress_recovery` 视图（更准确地说是 backup recovery 进度），可以在 standby 启动期间观察 LSN 推进。

### SQL Server: 经典 ARIES 实现 + Accelerated Database Recovery

SQL Server 的恢复模型是 ARIES 在商业数据库中最教科书化的实现，明确把恢复分成 **Analysis / Redo / Undo** 三个阶段，并在错误日志中分别报告。

**三种恢复模式 (Recovery Model)**：

| 模式 | 日志范围 | 备份能力 | 恢复粒度 |
|------|---------|---------|---------|
| `FULL` | 所有操作完整记录 | 完整 + 差异 + 日志 | PITR 到任意秒 |
| `BULK_LOGGED` | bulk 操作最小日志 | 完整 + 差异 + 日志 (有限制) | PITR (bulk 操作前后) |
| `SIMPLE` | 自动截断 | 完整 + 差异 | 仅恢复到最近备份 |

```sql
ALTER DATABASE MyDB SET RECOVERY FULL;
```

**并行恢复**：SQL Server 2005 Enterprise Edition 起，恢复阶段可以多线程并行回放不同数据库 / 不同日志记录。`recovery interval` 参数（分钟）控制检查点频率，但默认是 0（动态自适应）。

**Accelerated Database Recovery (ADR)**：SQL Server 2019 引入，是对 ARIES 模型的重大变革：

- 引入 **Persistent Version Store (PVS)** 直接存储行版本（类似 PostgreSQL 的 in-place MVCC）
- **sLog**：内存中的二级日志，只记录非版本化操作
- 崩溃恢复时只需回放最近的 sLog，**无需扫描完整事务日志**
- 大事务的回滚变成瞬时（标记为 aborted，PVS 中的旧版本立即可见）

ADR 把回滚时间从 O(事务大小) 降到 O(1)，是过去十年关系数据库恢复领域的重要创新。

### MySQL InnoDB: ARIES-like + 强制恢复级别

InnoDB 的恢复同样是 ARIES 的衍生：双写缓冲 (doublewrite buffer) 防止页损坏 + redo log 物理-逻辑日志 + undo log 段。

**恢复流程**：

1. 启动时读取 `ib_logfile*`（8.0 起为 `#innodb_redo` 目录）
2. 找到最后一个 checkpoint LSN
3. 扫描 redo log 找到所有需要恢复的事务（Analysis）
4. 应用 redo 到 buffer pool（Redo）
5. 通过 undo log 回滚未提交事务（Undo，部分后台执行）
6. Purge 线程清理 history list

**innodb_force_recovery 0-6 级**：

```sql
-- my.cnf
[mysqld]
innodb_force_recovery = 3
```

| 级别 | 行为 | 数据损坏风险 |
|------|------|------------|
| 0 | 正常恢复 | 无 |
| 1 | SRV_FORCE_IGNORE_CORRUPT：忽略页损坏 | 低 |
| 2 | SRV_FORCE_NO_BACKGROUND：不启动 master / purge 线程 | 低 |
| 3 | SRV_FORCE_NO_TRX_UNDO：跳过事务回滚 | 中（未提交事务被当作已提交） |
| 4 | SRV_FORCE_NO_IBUF_MERGE：跳过插入缓冲合并 | 中（二级索引可能损坏） |
| 5 | SRV_FORCE_NO_UNDO_LOG_SCAN：跳过 undo log 扫描 | 高（事务历史丢失） |
| 6 | SRV_FORCE_NO_LOG_REDO：跳过 redo log 回放 | 极高（最近写入完全丢失） |

≥ 4 时 InnoDB 进入只读模式，必须 `mysqldump` 导出后重建实例。这是数据库陷入"启动即崩溃"循环时的最后救命稻草。

**并行 redo apply**：MySQL 8.0 引入 redo log 的多线程应用（之前是单线程）。redo 记录按 page no 分发到多个 apply 线程，相同页的记录串行处理，不同页的记录并行处理。

### IBM DB2: ARIES 的发源地

DB2 是 ARIES 的原始实现者（C. Mohan 在 IBM Almaden 工作），其恢复机制至今仍然是最严格遵循论文描述的：

- **Analysis Pass**：从最后一个 checkpoint 向前扫描，建立 Transaction Table（活动事务）和 Dirty Page Table（脏页 + recLSN）
- **Redo Pass**：从 Dirty Page Table 中最小的 recLSN 开始重放，物理或逻辑应用每条日志
- **Undo Pass**：对 Transaction Table 中的活动事务，按 LSN 倒序回滚，写入 CLR (Compensation Log Record) 防止恢复中再次崩溃时重复回滚

**循环日志 vs 归档日志**：

```
LOGRETAIN=OFF (循环日志)：仅支持崩溃恢复
LOGARCHMETH1=DISK:/path (归档日志)：支持 ROLLFORWARD 介质恢复 + PITR
```

```sql
-- 介质恢复 + PITR
ROLLFORWARD DATABASE mydb TO 2026-04-13-10.30.00 USING LOCAL TIME;
```

**并行恢复**：DB2 自动并行化 Redo 和 Undo，并行度受 `NUM_IOCLEANERS` 和 buffer pool 数量控制。`db2pd -recovery` 命令可以实时查看恢复进度。

### ClickHouse: per-part 恢复

ClickHouse 的恢复模型完全不同于传统 OLTP——基于**不可变 part** 和 part 操作日志。

**MergeTree 表的恢复**：

1. 启动时扫描 `data/<db>/<table>/` 目录下所有 part 子目录
2. 每个 part 有自己的元数据 (`columns.txt`, `checksums.txt`, `count.txt`)
3. 校验 checksums，如果损坏移动到 `detached/` 子目录（**保留数据，等待人工干预**）
4. 重放 part 操作日志（mutation 日志、merge 日志），完成进行中的合并

**ReplicatedMergeTree 的恢复**：

1. 连接 ZooKeeper / Keeper，读取期望的 part 列表
2. 对比本地实际存在的 part
3. 缺失的 part 从其他副本拉取
4. 多余的 part 移动到 detached
5. 通过 `system.replication_queue` 报告进度

**detached parts 机制**：是 ClickHouse 恢复的精髓——任何无法识别的 part 都被隔离而非删除，DBA 可以手动 `ATTACH PART` 恢复：

```sql
ALTER TABLE my_table ATTACH PART '20260413_1_1_0';
```

### CockroachDB: Raft 日志回放

CockroachDB 不存在传统意义上的"实例恢复"，因为每个 range 是一个独立的 Raft 状态机。

**节点重启流程**：

1. 节点启动，打开本地 RocksDB（或 Pebble）存储
2. RocksDB 自身完成 WAL 回放
3. 对每个本地 range 副本，从 Raft 日志的 last applied index 继续 apply
4. 联系其他副本，如果本节点不是 leader，通过心跳重新加入
5. 如果是 leader 但 lease 已过期，参加新的 lease 选举
6. 慢副本通过 Raft snapshot 一次性追平

**range lease recovery**：lease 是 CockroachDB 的强一致读优化，崩溃后 lease holder 可能改变，导致短暂的延迟尖峰。可以通过 `crdb_internal.ranges` 视图查看 lease 持有情况。

### TiDB: TiKV Raft + RocksDB

TiDB 的实例恢复发生在 TiKV 层（SQL 层 tidb-server 是无状态的）：

1. tikv-server 启动，打开 KV RocksDB 和 Raft RocksDB
2. RocksDB WAL 回放（物理层恢复）
3. 对每个 region 副本，从 Raft applied index 继续应用日志
4. PD 检测到节点上线，调度可能的 region 重平衡
5. 通过 GC safepoint 协调 MVCC 数据清理

TiDB 的 MVCC 是基于 timestamp 的（TSO 全局时钟），事务回滚通过 GC 后台清理，**没有传统意义的 Undo Pass**。

### SQLite: 回滚日志 vs WAL

SQLite 是少数提供两种完全不同恢复机制的引擎：

**Rollback Journal 模式 (默认)**：

1. 写事务开始前，先把要修改的页**完整复制**到 `<db>-journal` 文件
2. fsync 日志文件
3. 修改主数据库文件
4. fsync 主文件
5. 删除日志文件 = commit

崩溃恢复时：下一次打开数据库的进程发现 `<db>-journal` 存在，把日志中的页**回滚**到主数据库文件，然后删除日志。这是纯 Undo 模型，没有 Redo。

**WAL 模式**：

```sql
PRAGMA journal_mode=WAL;
```

1. 修改不再原地写入主文件，而是追加到 `<db>-wal`
2. 读者通过 `<db>-shm` 共享内存中的 wal-index 找到最新版本
3. checkpoint 操作把 wal 内容合并回主文件

崩溃恢复时：下一次连接重建 wal-index（从 wal 文件扫描），然后正常使用。WAL 文件中已提交的事务会在下次 checkpoint 时合并；未提交事务通过帧头中的 `commit-frame` 标记被忽略。这是 **Redo 模型**（已提交的事务通过 wal 帧"重做"到主文件）。

### Firebird: Forced Write + Shadow

Firebird 的恢复机制独树一帜，建立在其多版本并发控制 (MGA, Multi-Generational Architecture) 之上：

- **Careful Write**：所有页修改按特定顺序刷盘，使得崩溃后页本身保持一致（某种"写时复制"语义）
- **MVCC**：未提交版本和已提交版本同时存在，通过事务状态判断可见性
- **Sweep**：后台进程定期清理 OAT (Oldest Active Transaction) 之前的废弃版本
- **Shadow**：可选的同步副本文件，提供基本的介质恢复

崩溃后启动：扫描 TIP (Transaction Inventory Pages)，把活动事务标记为 dead，无需回放日志。代价是大量"垃圾"版本积累在数据文件中，需要 sweep 清理。

## ARIES 算法三阶段深度剖析

ARIES (Algorithms for Recovery and Isolation Exploiting Semantics) 由 C. Mohan 等人于 1992 年发表（《ACM TODS》Vol 17, No 1）。其核心是 **WAL + LSN + 模糊检查点 + 三阶段恢复**。

### 关键不变量

1. **WAL Rule**：日志记录必须先于对应的数据页刷盘 (Write-Ahead Logging)
2. **Force-at-Commit**：事务提交时，其所有日志记录必须已经持久化
3. **每页 PageLSN**：每个数据页头部记录"最后修改它的日志的 LSN"，用于幂等回放

### 三阶段算法

#### Analysis Pass（分析阶段）

目标：重建崩溃时刻的内存元数据。

```
input: last checkpoint LSN
state:
  TT = Transaction Table       -- 活动事务的 LastLSN
  DPT = Dirty Page Table       -- 脏页的 RecLSN（最早未刷盘的修改）

scan log forward from checkpoint:
  for each log record:
    if record is BEGIN TRANSACTION:
      add txn to TT
    if record is COMMIT / ABORT:
      remove txn from TT
    if record is UPDATE:
      update TT[txn].LastLSN = record.LSN
      if page not in DPT:
        DPT[page] = record.LSN  -- RecLSN = 第一次修改它的日志位置
```

输出：TT 列出需要 Undo 的事务，DPT 给出 Redo 的起点（最小 RecLSN）。

#### Redo Pass（重做阶段）

目标：把数据库前滚到崩溃时刻的物理状态。

```
start_lsn = min(DPT.RecLSN)
scan log forward from start_lsn:
  for each UPDATE record:
    page = fetch(record.page_id)
    if page.PageLSN >= record.LSN:
      skip  -- 已经包含该修改，幂等
    else:
      apply(record, page)
      page.PageLSN = record.LSN
```

ARIES 的关键创新是 **Repeating History**：所有事务（包括未提交的）的更改都会被重做。这简化了崩溃-恢复-崩溃的多重故障处理。

#### Undo Pass（回滚阶段）

目标：回滚 TT 中的所有未提交事务。

```
losers = set of LastLSNs from TT
while losers is not empty:
  pick max LSN from losers  -- 倒序处理
  fetch log record at that LSN
  if record is UPDATE:
    apply inverse to page
    write CLR (Compensation Log Record) with UndoNxtLSN = record.PrevLSN
    losers.replace(LSN, record.PrevLSN)
  if record is BEGIN TRANSACTION:
    losers.remove
```

**CLR 的妙处**：CLR 是 redo-only 的（没有对应的 Undo），它的 UndoNxtLSN 指向下一个需要回滚的记录。如果 Undo Pass 中再次崩溃，重启后下一次 Analysis 会发现 CLR，跳过已经回滚的部分，**不会重复 Undo**。

### 模糊检查点 (Fuzzy Checkpoint)

完整检查点要求所有脏页都刷盘后才记录 checkpoint，对系统冲击大。ARIES 使用模糊检查点：

```
1. write CHECKPOINT_BEGIN log record
2. snapshot TT and DPT (in memory)
3. write CHECKPOINT_END containing TT and DPT
4. update master record: last_checkpoint_lsn = CHECKPOINT_BEGIN.LSN
```

注意：**没有强制刷盘任何数据页**。脏页继续异步刷盘。恢复时从 CHECKPOINT_BEGIN 之后开始 Analysis，需要的 DPT/TT 信息从 CHECKPOINT_END 中读取。

这个简单的优化让检查点对在线事务的影响降到最低，是 ARIES 被广泛采纳的关键。

## PostgreSQL 基于 MVCC 的恢复：为什么省掉了 Undo Pass

PostgreSQL 的恢复算法比 ARIES 更简单，理解这种差异有助于把握"MVCC 与 Undo"的本质权衡。

### 在数据布局层面的根本差异

```
ARIES (Oracle / SQL Server / DB2 / InnoDB):
  data file:
    page A: row(id=1, name="Alice")  -- 当前版本
  undo segment:
    undo entry: { row_id=1, before_image="Bob" }

PostgreSQL:
  data file:
    page A: 
      tuple 1: (id=1, name="Bob",   xmin=100, xmax=101)
      tuple 2: (id=1, name="Alice", xmin=101, xmax=0)
```

PostgreSQL 在同一个 heap 页面里保留新旧版本，xmin/xmax 字段标记每个版本的事务可见性。可见性检查从 commit log (`pg_xact`) 查询事务状态。

### 崩溃场景

假设事务 T101 把 Alice 改成 Charlie，但还没提交时崩溃：

**ARIES 引擎**：
1. Redo Pass 重做了"Alice → Charlie"的变更
2. Undo Pass 必须读 undo log，把 Charlie 改回 Alice
3. **必须执行 Undo**，否则数据是错的

**PostgreSQL**：
1. WAL 回放重做了一个新 tuple `(name="Charlie", xmin=101, xmax=0)`
2. T101 的状态在 `pg_xact` 中没有 COMMITTED 标记
3. 后续读取看到这个 tuple 时，调用 `XidIsInProgress(101)` 或 `XidDidCommit(101)`，判定为 ABORTED，**自动跳过**
4. VACUUM 后台回收物理空间

### 优势与代价

**优势**：

- 恢复算法极简，不需要 Undo Pass 的复杂状态管理
- 大事务的回滚是 O(1)，不需要逐行撤销（只需在 pg_xact 中标记 ABORTED）
- 不需要维护 undo segment，少一个共享资源

**代价**：

- 数据文件膨胀（dead tuple 物理占用空间，直到 VACUUM）
- VACUUM 成本高，长期不 vacuum 导致性能退化和空间放大
- **XID wraparound 风险**：32 位事务号回卷必须靠 VACUUM 推进 frozen XID
- 每个 tuple 多 24 字节头部开销
- 写放大严重：UPDATE 操作变成 DELETE + INSERT 两个物理操作

这是 PostgreSQL 历史上多次社区争论的焦点。EnterpriseDB 主导的 zheap 项目曾试图引入 in-place 更新 + undo segment，让 PG 也能像 Oracle 那样高效更新，但因复杂度过高未能并入主线。SQL Server 2019 的 ADR（Accelerated Database Recovery）反向走了类似 PostgreSQL 的路：引入 Persistent Version Store 实现 O(1) 大事务回滚。

## 检查点与恢复时间的关系

崩溃恢复时间的根本决定因素是 **"最后一个检查点到崩溃时刻之间的 WAL 量"**。检查点越频繁，恢复越快，但运行期 I/O 压力越大。这是一个经典的权衡，每个引擎都有自己的策略。

### 检查点触发机制对比

| 引擎 | 时间触发 | 大小触发 | 自适应 | 预测模型 |
|------|---------|---------|--------|---------|
| Oracle | LOG_CHECKPOINT_INTERVAL | LOG_CHECKPOINT_TIMEOUT | FAST_START_MTTR_TARGET | 基于 IOPS 估算 |
| PostgreSQL | checkpoint_timeout (5min) | max_wal_size (1GB) | checkpoint_completion_target | 启发式 |
| SQL Server | recovery interval | 自动 | 是 | 基于脏页数 |
| MySQL InnoDB | innodb_log_file_size 70% | innodb_max_dirty_pages_pct | innodb_adaptive_flushing | 基于负载 |
| DB2 | SOFTMAX | LOGFILSIZ | NUM_IOCLEANERS AUTO | 是 |
| SAP HANA | savepoint interval (5min) | log buffer | -- | -- |

### 检查点开销与恢复时间的反比关系

```
恢复时间 ≈ (WAL 量自最后检查点) / (回放速率)

强制完整检查点：
  - 运行期开销：脏页全部刷盘 → I/O 尖峰
  - 恢复时间：~0（启动即可用）
  - 适用：维护窗口、计划重启

模糊检查点：
  - 运行期开销：~10% 持续 I/O
  - 恢复时间：取决于 dirty page 数量
  - 适用：在线 OLTP

无检查点（极端）：
  - 运行期开销：0
  - 恢复时间：O(WAL 总量)
  - 适用：仅短生命周期实验
```

### 估算恢复时间的公式

Oracle 在 `V$INSTANCE_RECOVERY` 中给出预测值，背后的核心公式是：

```
ESTIMATED_MTTR = LOG_BLKS_NEEDED / RECOVERY_REDO_RATE
              + DIRTY_BUFFERS / RECOVERY_WRITE_RATE
```

PostgreSQL 没有内建预测，但可以通过下列经验公式估算：

```
recovery_time ≈ wal_size_since_checkpoint / sequential_read_speed
              + apply_overhead_per_record × record_count
```

实测中，PostgreSQL 单线程 WAL 回放速率通常在 **50-150 MB/s**（取决于硬件和负载类型），意味着 8GB 的 WAL 段需要约 **1-3 分钟** 完整回放。这是 PG 高负载场景下提倡缩短 `checkpoint_timeout` 的原因。

## 双写缓冲与页损坏防护

崩溃恢复的隐藏前提是：**数据页本身没有撕裂 (torn page)**。在 4KB 文件系统页 + 16KB 数据库页的常见配置下，断电可能导致一个 16KB 页只刷到一半，剩下一半还是旧数据——这种"撕裂页"会让 redo 从其上重做时计算出错误的结果。

各引擎的防护机制：

| 引擎 | 机制 | 开销 | 是否可关闭 |
|------|------|------|----------|
| MySQL InnoDB | doublewrite buffer | 2× 写放大 | innodb_doublewrite=OFF |
| PostgreSQL | full_page_writes (FPW) | 检查点后第一次写整页到 WAL | full_page_writes=off |
| Oracle | 块校验 + 重做 | CRC 校验 | DB_BLOCK_CHECKSUM=OFF |
| SQL Server | TORN_PAGE_DETECTION / CHECKSUM | 校验和 | SET PAGE_VERIFY NONE |
| DB2 | DB2_PARALLEL_IO + checksum | 校验和 | 不建议 |
| SQLite | 同步写顺序 + journal | 严格 fsync | -- |

PostgreSQL 的 full_page_writes 是默认开启的：检查点之后，每个被修改的页第一次写入 WAL 时会把**整页内容**写进去（而不只是变化部分）。崩溃恢复时如果遇到 FPI (Full Page Image) 记录，直接用它覆盖整页，从而绕过任何撕裂。代价是 WAL 量在检查点后立即激增（"checkpoint storm"），这正是 `checkpoint_completion_target = 0.9` 试图缓解的现象。

InnoDB 的 doublewrite buffer 走另一条路：所有脏页先顺序写到双写缓冲区（128 个连续页），fsync，再写到最终位置。崩溃恢复时如果发现某个页校验失败，从双写缓冲区找到该页的副本恢复。代价是写放大 2 倍——但 NVMe SSD 上影响较小。

## 网络分区与脑裂场景下的恢复

分布式数据库的"崩溃恢复"还要处理网络分区：节点重启时可能发现自己已经被剔除集群、被替代为新副本、或者落后太多。

### CockroachDB / TiDB 的 Raft 重连

```
node restart sequence:
  1. open local store, replay RocksDB WAL
  2. for each range replica:
       a. read raft log, find applied index
       b. send heartbeat to peers
       c. if leader is alive: become follower, catch up via append entries
       d. if too far behind: receive Raft snapshot
  3. report to gossip / PD
```

如果落后超过 Raft snapshot 阈值，节点会直接接收一个完整快照，跳过逐条日志回放。这把"恢复时间"从无界 WAL 回放变成有界的快照传输。

### Spanner 的 Paxos 恢复

Spanner 的恢复机制利用了 TrueTime API：每个节点重启后，必须等待 TrueTime 不确定区间过去（commit-wait），然后才能服务读请求，确保不会读到不一致的过去版本。

### OceanBase 的平滑切主

OceanBase 通过 Paxos 在分区维度提供高可用，崩溃后的恢复路径是：

1. 检测 leader 失效（心跳超时）
2. 发起 Paxos prepare，选出新 leader
3. 新 leader apply 自己 commit log 中所有 majority confirmed 的日志
4. 接受新写请求

`enable_smooth_leader_switch` 参数让计划内的重启可以提前转移 leader，避免 RTO 抖动。

## 应用层应对策略

崩溃恢复时间是数据库的内部属性，但应用层有必要的应对手段：

### 健康检查与重连

- **连接池**：必须区分"连接断开"和"数据库不可用"两种状态。HikariCP / pgbouncer / ProxySQL 都有 health-check 机制，只把恢复后的新连接发给应用
- **重试策略**：指数退避 + jitter，避免 thundering herd 在恢复瞬间冲击
- **熔断器**：Hystrix / resilience4j 类组件检测连续失败，让应用降级而不是反复试连

### Read Replica 的故障转移

主库恢复期间，把读流量切到副本是最常见的可用性策略：

| 引擎 | 自动 failover | 工具 | 提升时间 |
|------|--------------|------|---------|
| PostgreSQL | 第三方 | Patroni / repmgr / pg_auto_failover | 5-30s |
| MySQL | 第三方 | MHA / Orchestrator | 5-30s |
| MySQL | 是 | InnoDB Cluster + MySQL Router | <10s |
| Oracle | 是 | Data Guard Fast-Start Failover | <30s |
| SQL Server | 是 | Always On Availability Groups | <10s |
| DB2 | 是 | HADR + TSA | <30s |
| CockroachDB | 是 | 内建（无单一 leader） | 瞬时 |
| TiDB | 是 | 内建（Raft） | <10s |

### 应用感知的两阶段恢复

最先进的实践是利用 Oracle "Open Database before Transaction Recovery" 或 SQL Server ADR 这种"先开库再回滚"的特性，让应用在读 90% 数据的同时容忍少量被锁住的行：

```sql
-- Oracle 19c+
ALTER SYSTEM SET FAST_START_MTTR_TARGET=30;  -- Cache Recovery 30s 内
-- Open Database 后业务可用，Undo Pass 后台进行
```

这种模式下，**业务感知的恢复时间** = Cache Recovery 时间，而不是完整 Cache + Transaction Recovery 时间，可以将 RTO 缩短一个数量级。

## PITR (Point-in-Time Recovery) 简要对比

详细 PITR 语法请参见 `backup-restore-syntax.md`。本节聚焦 PITR 与崩溃恢复的关系。

PITR = 介质恢复 + 截断到指定时间点。它需要：
- 某个基线（完整备份或快照）
- 该基线之后的所有 WAL/redo/binlog
- 一个停止条件（时间、LSN、命名 restore point、事务 ID）

| 引擎 | 停止条件 | 实现机制 |
|------|---------|---------|
| Oracle | SCN / TIME / SEQUENCE / 命名还原点 | RMAN UNTIL |
| PostgreSQL | recovery_target_time / lsn / xid / name | recovery.signal |
| SQL Server | STOPAT / STOPATMARK / STOPBEFOREMARK | RESTORE LOG |
| MySQL | binlog 位置 / 时间戳 | mysqlbinlog \| mysql |
| DB2 | TIMESTAMP / END OF LOGS | ROLLFORWARD ... TO |
| MariaDB | binlog GTID / 时间戳 | mariadb-binlog |
| CockroachDB | AS OF SYSTEM TIME | RESTORE FROM ... AS OF |
| TiDB | TSO / 时间戳 | BR + GC safepoint |
| Snowflake | TIMESTAMP / OFFSET / STATEMENT | Time Travel + UNDROP |

## 关键发现

1. **三种恢复哲学**：传统 ARIES 派（Oracle / SQL Server / DB2 / InnoDB / Derby / Informix），MVCC 简化派（PostgreSQL / Firebird / H2 / 分布式 NewSQL），不可变文件派（Snowflake / BigQuery / ClickHouse / Delta / Iceberg）。三者代表了 50 年来数据库存储引擎演进的三条主线。

2. **ARIES 仍然是事实标准**：几乎所有传统 OLTP 引擎的恢复算法都可以追溯到 1992 年的 ARIES 论文。Analysis / Redo / Undo 三阶段、PageLSN、CLR、模糊检查点这些概念被反复实现。

3. **MVCC 的双刃剑**：PostgreSQL 通过把多版本放在 heap 中，让恢复算法极简（无 Undo Pass）。代价是 VACUUM 必须及时跟进，否则陷入空间膨胀和 XID wraparound 危机。

4. **Oracle 的 FAST_START_MTTR_TARGET 至今独一无二**：能根据声明式 SLA 自动调节检查点频率，是商业数据库可用性工程的典范。SQL Server 的 `recovery interval` 是类似思想但较弱。

5. **SQL Server 2019 ADR 是过去十年最大创新**：通过 Persistent Version Store 把大事务回滚降到 O(1)，与 PostgreSQL 的 MVCC 在哲学上殊途同归。

6. **MySQL innodb_force_recovery 是最后救命稻草**：6 个级别从温和到激进。≥4 时数据库进入只读，必须导出重建。运维必须在重启前充分理解每个级别的代价。

7. **分布式数据库的崩溃恢复是 Raft/Paxos 日志回放**：CockroachDB / TiDB / YugabyteDB / Spanner / OceanBase 都把单机恢复推给底层 KV 存储（RocksDB/Pebble/DocDB），上层只关心一致性日志的 apply index 推进。

8. **Stream-first 系统通过 Checkpoint 恢复**：Flink / Materialize / RisingWave 没有传统 WAL，靠定期持久化算子状态 + 重放数据源实现恢复。Flink 的 incremental checkpoint 只持久化 RocksDB SST 增量，恢复时间与吞吐不成线性关系。

9. **ClickHouse 的 detached parts 是优雅的容错设计**：损坏的 part 被隔离而不是删除，DBA 可以人工 ATTACH。这种"宁可保留也不破坏"的思路在 OLAP 引擎中越来越普遍。

10. **PITR 与崩溃恢复是同一机制的两种触发**：崩溃恢复回放到 WAL 末尾，PITR 回放到指定时间点。区别在于是否需要外部备份基线和停止条件。

11. **并行恢复在 2010 年后才普及**：SQL Server 2005 是第一个商业实现，MySQL 直到 8.0 才支持并行 redo apply，PostgreSQL 截至 16 版本仍然是单线程 startup。这反映了恢复算法并行化的工程难度。

12. **进度报告是新的 SLA 维度**：Oracle V$RECOVERY_PROGRESS、SQL Server DMV、PostgreSQL 16 的 pg_stat_progress_recovery、Flink 的 Web UI 都把恢复进度暴露给运维。在 99.99% SLA 场景下，"还需要多久"和"是否在恢复"同等重要。

13. **SQLite 的双模式是嵌入式数据库的智慧**：Rollback Journal 优先保证简单（纯 Undo），WAL 模式优化并发读写（Redo）。两种模式覆盖了从单写事务到高并发场景。

14. **崩溃恢复时间不可观测的引擎正在被淘汰**：在云原生时代，黑盒等待已经不可接受。Materialize / RisingWave / Flink 这一代流式系统从设计之初就提供细粒度的恢复进度。

## 参考资料

- C. Mohan, et al. "ARIES: A Transaction Recovery Method Supporting Fine-Granularity Locking and Partial Rollbacks Using Write-Ahead Logging." ACM TODS, Vol. 17, No. 1, 1992.
- Oracle: [Instance Recovery and FAST_START_MTTR_TARGET](https://docs.oracle.com/en/database/oracle/oracle-database/19/admin/managing-instance-recovery.html)
- PostgreSQL: [WAL Internals](https://www.postgresql.org/docs/current/wal-internals.html)
- SQL Server: [Database Recovery Process](https://learn.microsoft.com/en-us/sql/relational-databases/backup-restore/restore-and-recovery-overview-sql-server)
- SQL Server: [Accelerated Database Recovery](https://learn.microsoft.com/en-us/sql/relational-databases/accelerated-database-recovery-concepts)
- MySQL: [InnoDB Recovery](https://dev.mysql.com/doc/refman/8.0/en/innodb-recovery.html)
- MySQL: [innodb_force_recovery](https://dev.mysql.com/doc/refman/8.0/en/forcing-innodb-recovery.html)
- DB2: [Crash Recovery](https://www.ibm.com/docs/en/db2/11.5?topic=recovery-crash)
- SQLite: [Atomic Commit](https://www.sqlite.org/atomiccommit.html)
- SQLite: [WAL Mode](https://www.sqlite.org/wal.html)
- ClickHouse: [Data Replication](https://clickhouse.com/docs/en/engines/table-engines/mergetree-family/replication)
- CockroachDB: [Raft, Leases, and Replication](https://www.cockroachlabs.com/docs/stable/architecture/replication-layer.html)
- TiDB: [TiKV Recovery](https://tikv.org/docs/dev/deep-dive/scalability/raftstore/)
- Flink: [Checkpointing](https://nightlies.apache.org/flink/flink-docs-stable/docs/ops/state/checkpoints/)
