# 组提交 (Group Commit)

把成百上千个事务的 fsync 合并为一次磁盘刷写——组提交是 OLTP 引擎获得高 TPS 的最关键优化之一，也是延迟与吞吐之间最经典的权衡。本文系统对比 45+ 数据库引擎的组提交、批量提交、binlog group commit 与 Raft batch commit。

## 为什么组提交是 OLTP 性能的分水岭

一个事务从 `COMMIT` 到磁盘上"绝对不丢"，至少要经过这样几步：

1. 修改对应的 redo / WAL 记录被追加到日志缓冲区。
2. 日志缓冲区在 commit 时被 `write()` 到 OS 页缓存。
3. `fsync()` / `fdatasync()` 强制 OS 把日志页缓存刷到磁盘控制器。
4. 磁盘控制器把数据从其 DRAM cache 写到非易失介质（除非禁用 write cache 或开启 FUA）。

第 3 步是整个流程中最昂贵的部分：单次 fsync 在 SATA SSD 上约 100 微秒到 1 毫秒，机械盘上 5–15 毫秒，NVMe 上 20–50 微秒。如果每个事务都独占一次 fsync，那么吞吐就被磁盘的 IOPS 上限锁死——机械盘只有几百 TPS，SATA SSD 也不过几千 TPS。

组提交（Group Commit）的核心思想是：**让多个并发事务共享一次 fsync**。在某个事务即将 fsync 之前，先短暂等待几微秒到几毫秒，把同一时间窗口内排队的其他事务一起带上，只调用一次 `fsync()` 把整段日志一次性刷盘，然后唤醒所有事务返回客户端。

这个想法在 1980 年代由 Jim Gray 等人在 IMS Fast Path 和 IBM System R 上首先提出，后来被 ARIES 论文（Mohan 1992）系统化，到 21 世纪几乎所有支持 OLTP 的引擎都内建了某种形式的组提交：

- 当并发度从 1 升到 100 时，组提交可以让 TPS 提升 50–100 倍而不改变 fsync 频率。
- 单事务延迟会从纯 fsync 时间增加到 "等待窗口 + fsync 时间"，**通常仅高出几百微秒**。
- 一次 fsync 写入 1 字节和写入 64 KB 在 SSD 上耗时几乎一样，组提交几乎是"免费的吞吐"。

组提交也带来若干新的工程挑战：

- **延迟下限**：等待窗口（如 PostgreSQL 的 `commit_delay` 或 InnoDB 的 binlog 等待）会增加单事务最小延迟。
- **公平性与饥饿**：高优先级事务可能被低优先级事务的等待拖慢。
- **日志顺序与可见性**：不同事务的 commit LSN 必须有正确的全序，对复制和恢复都至关重要。
- **多阶段同步**：对于 MySQL 这类同时维护 redo log + binlog 的系统，必须保证两个日志的提交顺序一致——这是著名的 "binlog group commit" 三阶段算法。

## 没有 SQL 标准

SQL 标准只定义了 ACID 的语义（COMMIT 后修改必须持久），完全没有规定 fsync 频率、commit 等待窗口、binlog 与 redo 的协调或多副本协议。组提交是 100% 的实现细节：

- PostgreSQL 用 `commit_delay`（微秒级 sleep）加 `commit_siblings`（最小并发事务数阈值）控制是否启用 sleep-based group commit；同时 WAL writer 后台线程隐式批刷。
- MySQL InnoDB 称之为 **group commit**，5.6 之后变为 binlog 三阶段（flush / sync / commit）；MariaDB 类似，从 5.5 起独立实现 binlog group commit。
- Oracle 称之为 **fast commit**，由 LGWR 进程隐式批刷 redo；commit 时根据 `COMMIT WRITE` 子句选择 `IMMEDIATE/BATCH`、`WAIT/NOWAIT`。
- SQL Server 没有显式 group commit 配置，2014+ 用 **delayed durability** 在每事务级别延后 fsync。
- DB2 早期版本用 `MINCOMMIT` 控制最小批量大小，9.x 后改为隐式自适应。
- SQLite **没有** group commit：单写者（serialized write）模型下，事务串行进入。
- ClickHouse 用 `async_insert`（21.11+）批量化插入，不是传统意义的组提交。
- 分布式数据库（CockroachDB / TiDB / YugabyteDB / OceanBase / Spanner）都在 Raft / Paxos 层做日志批量化；TiDB 还在 2PC pre-commit 阶段批量化。

下面用 11 张支持矩阵覆盖 45+ 数据库的组提交细节。

## 支持矩阵

### 1. 原生组提交支持

| 引擎 | 是否原生支持 | 实现方式 | 引入版本 |
|------|------------|---------|---------|
| PostgreSQL | 是 | WAL writer 隐式批 + `commit_delay` 显式 sleep | 7.0 隐式 / 8.3 commit_delay 重写 |
| MySQL InnoDB | 是 | redo group commit + binlog 三阶段 group commit | 5.6 (2013) |
| MariaDB | 是 | binlog group commit + Mariabackup 协调 | 5.5 (2012) |
| Oracle | 是 | LGWR fast commit + adaptive batching | v6+ (1988) |
| SQL Server | 部分 | 内部 log block flush；显式按事务用 delayed durability | 2014 (delayed durability) |
| DB2 | 是 | 隐式 + `MINCOMMIT` 旧机制 | V8 (旧机制) / 9.5+ 隐式 |
| Sybase ASE | 是 | private log cache + group commit | 12.5+ |
| Informix | 是 | logical log buffer + LBU 缓冲 | 7.x+ |
| Firebird | 部分 | careful write 不支持真正 group commit | 2.x 起 forced writes 可调 |
| Derby | 是 | append-only log writer 隐式批 | 早期 |
| H2 | 是（异步） | `WRITE_DELAY` 默认 500ms 异步批 | 早期 |
| HSQLDB | 是（异步） | `WRITE_DELAY` 默认 500ms | 早期 |
| SQLite | 否 | 单写者模型，无并发可批 | 不支持 |
| DuckDB | 否 | 单写者，无 group commit | 不支持 |
| MonetDB | 隐式 | persist log 周期 flush | -- |
| Vertica | 是 | commit log 隐式批 | 早期 |
| Greenplum | 是 | 继承 PG | 继承 |
| TimescaleDB | 是 | 继承 PG | 继承 |
| Citus | 是 | 继承 PG | 继承 |
| QuestDB | 是 | 异步 commit 模式 | 6.0+ |
| CrateDB | 是 | translog batch | -- |
| ClickHouse | 异步插入 | `async_insert=1` 批量化 | 21.11+ |
| StarRocks | edit log 异步 | FE BDB JE 隐式批 | -- |
| Doris | edit log 异步 | 同 StarRocks | -- |
| SAP HANA | 是 | `group_commit_*` 显式参数 | -- |
| Teradata | 是 | TJ + DBC 内部批 | 早期 |
| Exasol | 内部 | 不暴露 | -- |
| SingleStore | 是 | snapshot + log shipping 批 | 7.0+ |
| Cassandra | 是 | commit log group commit / batch | 早期 |
| ScyllaDB | 是 | seastar shard-local commit log batch | -- |
| MongoDB (WT) | 是 | journal 批量 fsync | WT 引擎 |
| RocksDB | 是 | WriteBatch + GroupCommit | -- |
| LevelDB | 部分 | 串行写入但有 batch 接口 | -- |
| FoundationDB | 是 | TLog 批量化 | -- |
| CockroachDB | 是 | Raft batching + Pebble batch commit | v1.0+ |
| TiDB | 是 | 2PC pre-commit batching + TiKV Raft batch | 1.0+ |
| TiKV | 是 | Raft AppendEntries batch | 1.0+ |
| YugabyteDB | 是 | Raft batching | -- |
| OceanBase | 是 | Paxos clog batching | -- |
| Spanner | 是 | Paxos batching at TabletServer | -- |
| Snowflake | 托管 | 隐式批 | -- |
| BigQuery | 托管 | 隐式批 | -- |
| Redshift | 托管 | 继承 PG fork | -- |
| Yellowbrick | 内部 | 类 PG | -- |
| Materialize | 持续 | persist 批 | -- |
| RisingWave | barrier-based | barrier interval 控制 | -- |
| Databend | 是 | meta service Raft 批 | -- |
| Firebolt | 托管 | -- | -- |
| Azure Synapse | 类 SQL Server | 不暴露 | -- |
| InfluxDB | 是 | WAL 异步批 | 1.x+ |
| ClickHouse Keeper | 是 | Raft 批 (NuRaft) | 21.10+ |

> 关键观察：行存 OLTP 几乎全部支持组提交；分析型云数仓将其作为**实现细节隐藏**；分布式数据库则把组提交从单机 fsync 上升到了 Raft / Paxos 日志批量复制。SQLite 和 DuckDB 因单写者模型无 group commit，但 DuckDB 通过单事务批量 commit 模拟相似效果。

### 2. 是否可配置等待窗口

| 引擎 | 配置项 | 默认值 | 单位 | 备注 |
|------|--------|--------|------|------|
| PostgreSQL | `commit_delay` | 0 | 微秒 | 0 = 不主动 sleep（仅 WAL writer 隐式批） |
| PostgreSQL | `commit_siblings` | 5 | 事务数 | 至少这么多并发事务时才启用 sleep |
| MySQL InnoDB | `binlog_group_commit_sync_delay` | 0 | 微秒 | 0 = 不等 |
| MySQL InnoDB | `binlog_group_commit_sync_no_delay_count` | 0 | 事务数 | 即使 delay 时间未到也立即触发 |
| MariaDB | `binlog_commit_wait_usec` | 100000 | 微秒 | 等待窗口 |
| MariaDB | `binlog_commit_wait_count` | 0 | 事务数 | 触发阈值 |
| Oracle | `commit_logging` / `commit_write` | `WAIT, IMMEDIATE` | -- | 会话/事务级 |
| SQL Server | (无显式窗口) | -- | -- | delayed durability 是 per-txn 异步刷 |
| DB2 | `MINCOMMIT` | 1 | 事务数 | 9.5+ 隐式不再使用 |
| SAP HANA | `[persistence] group_commit_async_wait_time` | -- | 微秒 | -- |
| H2 | `WRITE_DELAY` | 500 | 毫秒 | -- |
| HSQLDB | `SET WRITE_DELAY` | 500ms | 毫秒/false | false=每次同步 |
| QuestDB | `cairo.commit.mode` | nosync | -- | sync/nosync/async |
| CrateDB | `index.translog.sync_interval` | 5s | -- | -- |
| ClickHouse | `async_insert_busy_timeout_ms` | 200 | 毫秒 | 批量插入等待 |
| ClickHouse | `async_insert_max_data_size` | 10MB | 字节 | 批量插入大小阈值 |
| TiKV | `raftstore.raft-base-tick-interval` | 1s | -- | Raft 心跳/批触发 |
| CockroachDB | `kv.raft.command.target_batch_size` | 256 KiB | 字节 | -- |
| YugabyteDB | `--yb_max_batch_size` | -- | -- | 客户端批 |
| OceanBase | `clog_aggregation_batch_size` | -- | -- | -- |

> 注：**显式可配置等待窗口的引擎只有 PostgreSQL、MySQL/MariaDB、Oracle、HANA、H2、HSQLDB、QuestDB、CrateDB、ClickHouse**。其他大多数引擎采用"自适应"或"批到队列空"策略，不暴露具体窗口。

### 3. 组提交 + 同步复制

当事务必须等待其他副本 fsync 才能返回时，组提交带来的吞吐放大效果在多副本场景下尤其明显。

| 引擎 | 组提交是否跨副本 | 同步复制配置 | 备注 |
|------|----------------|------------|------|
| PostgreSQL | 是 | `synchronous_commit = remote_apply/remote_write/on/local/off` | WAL sender 也批刷 |
| MySQL (semi-sync) | 是 | `rpl_semi_sync_master_enabled` | 5.7+ ack 后才 group commit 完成 |
| MySQL Group Replication | 是 | `group_replication_consistency` | XCom Paxos 批 |
| MariaDB Galera | 是 | `wsrep_sync_wait` | 同步复制 |
| Oracle Data Guard | 是 | `LOG_ARCHIVE_DEST_n SYNC AFFIRM` | LGWR 远程 affirm |
| SQL Server AG | 是 | synchronous-commit availability mode | 主备 hardened |
| DB2 HADR | 是 | `HADR_SYNCMODE` (SYNC/NEARSYNC/ASYNC) | -- |
| CockroachDB | 是 | Raft 多副本，多数派 ack | -- |
| TiDB | 是 | TiKV 多 Raft，多数派 ack | -- |
| YugabyteDB | 是 | 同 TiDB Raft 模型 | -- |
| OceanBase | 是 | Paxos 多数派 | -- |
| Spanner | 是 | Paxos quorum + TrueTime | -- |
| ScyllaDB / Cassandra | 部分 | LWT 用 Paxos；普通写多数派 ack | quorum 配置 |
| Greenplum | 否 | Standby master 异步 | -- |
| TimescaleDB | 同 PG | 同 PG | -- |
| Vertica | 是 | k-safety 内部协调 | -- |
| SAP HANA | 是 | System Replication SYNC/SYNCMEM/ASYNC | -- |
| Teradata | 是 | DBC log + AMP fallback | -- |
| Snowflake | 自动 | 跨 AZ 多副本元数据 | 不暴露 |
| BigQuery | 自动 | 跨 zone | 不暴露 |
| Spanner | 自动 | -- | -- |
| Materialize | -- | persist 多副本 | -- |
| MongoDB (replica set) | 是 | `w: majority` | journal + replication |
| Cassandra | -- | quorum / LOCAL_QUORUM | -- |
| Redis (AOF) | 不适用 | -- | -- |

> 关键观察：在分布式 OLTP 中，组提交不再是"刷一次磁盘的优化"，而是"刷一次 Raft log + 批量 AppendEntries 网络包 + 多数派 ack 协调"。CockroachDB / TiDB 把这层做到了物理批和逻辑批两个层次。

### 4. binlog 组提交（MySQL/MariaDB 专属）

binlog group commit 是 MySQL 5.6+ 引入的著名工程实现，解决了 redo log 与 binlog **两阶段提交不能同时批量化** 的难题。

| 阶段 | 锁名称 | 工作内容 | 单线程？ |
|------|-------|---------|---------|
| Flush | `LOCK_log` | 把当前 leader 队列中所有事务的 binlog cache 写入 binlog 文件（不 fsync） | 是 |
| Sync | `LOCK_sync` | 对 binlog 文件做 fsync（如果 sync_binlog 触发） | 是 |
| Commit | `LOCK_commit` | 按 binlog 顺序提交 InnoDB 内部事务（释放行锁、写 trx commit） | 是 |

每个阶段都有独立的等待队列和 leader-follower 协议：第一个进入 flush 阶段的事务成为 leader，其余事务入队，leader 一次性处理所有人的 binlog。这样 N 个事务的 fsync 被合并为 **1 次** binlog fsync + 1 次 redo fsync。

| 阶段相关参数 | 含义 | 默认 |
|-------------|-----|------|
| `binlog_group_commit_sync_delay` | flush 后人为等待的微秒数 | 0 |
| `binlog_group_commit_sync_no_delay_count` | 即使 delay 未到也立即触发的事务数 | 0 |
| `sync_binlog` | binlog fsync 频率 (0/1/N) | 1 |
| `innodb_flush_log_at_trx_commit` | redo fsync 频率 (0/1/2) | 1 |
| `binlog_order_commits` | 是否按 binlog 顺序提交 InnoDB | ON |

配置上将 `sync_binlog=1` + `innodb_flush_log_at_trx_commit=1` 同时打开是最严格的 D，组提交在该配置下意义最大——把 N 次 fsync 压成 2 次（redo 一次 + binlog 一次）。

## 各引擎组提交深入

### MySQL InnoDB：从 5.0 到 8.0 的演进

```sql
-- 查看当前组提交相关参数
SHOW VARIABLES LIKE 'binlog_group_commit_%';
SHOW VARIABLES LIKE 'sync_binlog';
SHOW VARIABLES LIKE 'innodb_flush_log_at_trx_commit';

-- 高吞吐 OLTP 推荐
SET GLOBAL binlog_group_commit_sync_delay = 1000;          -- 1ms 等待
SET GLOBAL binlog_group_commit_sync_no_delay_count = 16;    -- 或 16 个事务

-- 严格持久化 + 组提交（推荐生产）
SET GLOBAL sync_binlog = 1;
SET GLOBAL innodb_flush_log_at_trx_commit = 1;

-- 不安全配置（可能丢秒级数据，吞吐最高）
SET GLOBAL sync_binlog = 0;
SET GLOBAL innodb_flush_log_at_trx_commit = 2;
```

历史背景：

- **5.0/5.1**：早期 MySQL 5.0/5.1 的 binlog 与 InnoDB 通过 prepare/commit 两阶段协调，`prepare_commit_mutex` 串行化所有提交，吞吐被锁死在数百 TPS。这就是 Mark Callaghan 在 2010 年前后 Facebook MySQL 团队大量记录的"binlog group commit lost"问题。
- **5.6 (2013)**：官方实现新的三阶段（flush/sync/commit）binlog group commit，去掉了 `prepare_commit_mutex`。在 ssd 上 fsync TPS 从 ~500 跃升到 5000+。这是 InnoDB 历史上最重要的性能里程碑之一。
- **5.7**：增加 `binlog_group_commit_sync_delay`，允许人为延后触发 flush 来吸收更多事务。
- **8.0**：与 redo log 改为 link buffer + dirty page list 结合，配合 8.0.30 的 redo log 多文件，进一步降低 LOCK_log 临界区。

### MariaDB binlog group commit（5.5，早于 MySQL 官方）

MariaDB 在 2012 年的 5.5 版本就实现了 binlog group commit，比 MySQL 5.6 早了一年。Kristian Nielsen 的 [MariaDB binlog group commit](https://mariadb.com/kb/en/group-commit-for-the-binary-log/) 设计文档详述了 leader-follower 协议。

```sql
-- MariaDB 等效配置
SET GLOBAL binlog_commit_wait_usec = 100000;      -- 100ms 等待
SET GLOBAL binlog_commit_wait_count = 0;           -- 0 = 不限事务数

-- MariaDB 还支持基于 GTID 的并行复制，与 group commit 配合
SET GLOBAL slave_parallel_mode = 'optimistic';
SET GLOBAL slave_parallel_threads = 8;
```

### PostgreSQL：commit_delay + commit_siblings + WAL writer

PostgreSQL 的组提交分两层：

1. **后台 WAL writer**：始终按周期 `wal_writer_delay`（默认 200ms）批量 flush WAL。多个事务的 WAL 被自动批刷。
2. **commit_delay**：在事务即将 fsync 之前主动 sleep 一段微秒，希望吸收更多事务。仅当当前并发事务数 ≥ `commit_siblings` 时启用。

```sql
-- 查看当前配置
SHOW commit_delay;        -- 默认 0 微秒
SHOW commit_siblings;     -- 默认 5
SHOW wal_writer_delay;    -- 默认 200ms

-- 高并发 OLTP 调优（仅在 SSD 上推荐）
ALTER SYSTEM SET commit_delay = 100;       -- 100 微秒
ALTER SYSTEM SET commit_siblings = 5;      -- 至少 5 个并发
SELECT pg_reload_conf();
```

`commit_delay` 是 PostgreSQL 7.0 (2000) 引入的参数，但早期实现有 bug（`pg_usleep` 精度不足）。8.3 重写后真正可用，但因为现代 SSD 的 fsync 已经很快（< 100 微秒），多数情况下 `commit_delay = 0` 加 WAL writer 隐式批就够了。

### Oracle：LGWR fast commit

Oracle 的 LGWR (Log Writer) 进程从 v6（1988）就实现了 fast commit / piggy-back commit：
- LGWR 每 3 秒、redo log buffer 1/3 满、或事务 commit 时唤醒。
- 唤醒时把 log buffer 中所有 redo（含已 commit 和未 commit）一次性写盘。
- 多事务 commit 共享一次 fsync。

```sql
-- 会话级或事务级控制 commit 行为
COMMIT WRITE WAIT IMMEDIATE;     -- 默认：同步刷盘
COMMIT WRITE WAIT BATCH;         -- 等待 LGWR 下一个 batch
COMMIT WRITE NOWAIT IMMEDIATE;   -- 异步：发起刷盘但不等
COMMIT WRITE NOWAIT BATCH;       -- 完全异步（最快但可丢秒级）

-- 系统级默认（11g+）
ALTER SYSTEM SET commit_logging = BATCH;
ALTER SYSTEM SET commit_wait = NOWAIT;
```

注意：`COMMIT WRITE NOWAIT` 提供与 SQL Server `DELAYED_DURABILITY` 相同的语义。如果发生崩溃，最近的事务可能在 LGWR 还未刷盘时丢失，但能换来 5–10 倍吞吐提升。

### SQL Server：Delayed Durability（2014+）

SQL Server 没有传统意义的 commit window，但 2014 引入 **delayed durability**：每个事务可以选择在 commit 时不等 fsync，先返回客户端，等 log buffer 满或 1ms 后再批刷。

```sql
-- 数据库级别启用
ALTER DATABASE MyDB SET DELAYED_DURABILITY = ALLOWED;

-- 事务级别选择
BEGIN TRANSACTION;
UPDATE Orders SET Status = 'Done' WHERE OrderID = 1;
COMMIT WITH (DELAYED_DURABILITY = ON);

-- 强制所有事务都 delayed
ALTER DATABASE MyDB SET DELAYED_DURABILITY = FORCED;
```

行为特征：
- 每个事务的 commit 不再立即 fsync，而是 buffer。
- 后台 log writer 当 buffer 满（60 KB）或定时器触发时一次性刷盘。
- **崩溃时未刷盘的事务会被丢失**，但已 ACK 给客户端。
- 适用场景：需要极高 TPS，且少量近期数据丢失可接受（如 IoT 写入、审计日志）。

### DB2：MINCOMMIT 与隐式自适应

DB2 V8 之前需要手动设置 `MINCOMMIT` 控制最小批：

```sql
-- 早期 DB2（已废弃）
UPDATE DB CFG FOR mydb USING MINCOMMIT 5;
-- 等待至少 5 个 commit 才一起 fsync
```

9.5+ 之后改为隐式自适应：根据当前并发度和 IOPS 自动决定批大小，不再暴露参数。`LOGBUFSZ`（log buffer 大小）仍可调，影响每次 batch 能容纳多少事务。

### CockroachDB：Raft batch + Pebble batch

CockroachDB 把组提交做到了两层：

1. **Pebble WAL batch**：每个 store 的 Pebble（RocksDB fork）有 batch commit 队列，多个写请求合并为一次 WAL fsync。
2. **Raft batching**：每个 range 的 leader 收到多个客户端写请求后，合并成一个 AppendEntries 包发给 follower，follower 也用 batch 写 Raft log。

```toml
# cockroach 启动参数（部分）
--max-go-routines=1000
--engine=pebble
# 在线集群参数
SET CLUSTER SETTING kv.raft.command.target_batch_size = '256 KiB';
SET CLUSTER SETTING kv.raft.command.max_size = '64 MiB';
```

效果：单 SSD 节点单 range 的 OLTP TPS 可以从无 batch 时的 ~500 提升到 batch 时的 5000+。

### TiDB：2PC pre-commit batching

TiDB 的写路径经过 PD (Placement Driver) → TiKV，使用 Percolator 风格的 2PC：

1. **Prewrite 阶段**：客户端把所有要写的 key 发给各 region 的 leader，leader 先写 lock。
2. **Commit 阶段**：客户端发起 commit_ts，leader 写入 commit 标记，回复客户端。

TiDB 在两阶段都做了批量化：
- Prewrite 时 TiKV 把同一 region 的多个 key 合并为一次 batch put。
- Raft 层把多个 prewrite/commit 合并为一个 AppendEntries。
- 客户端的多个事务可以共享同一次 PD timestamp 请求（async commit 优化）。

```sql
-- TiDB 客户端可调
SET tidb_async_commit = 1;
SET tidb_enable_1pc = 1;             -- 单 region 1PC 优化
-- TiKV 端调优
-- raftstore.apply-pool-size = 4
-- raftstore.store-pool-size = 4
-- raftstore.notify-capacity = 40960
```

### YugabyteDB：Raft batching

YugabyteDB 与 CockroachDB / TiDB 类似，每个 tablet 有 Raft 日志。tablet leader 把多个客户端写请求合并为一个 Raft 日志条目（或一组连续条目）批量复制。

### OceanBase：Paxos clog batching

OceanBase 的 commit log（clog）使用 Multi-Paxos，在 leader 端批量化：

```sql
-- OceanBase 系统配置
ALTER SYSTEM SET clog_aggregation_buffer_amount = 4;
ALTER SYSTEM SET clog_max_unconfirmed_log_count = 1500;
```

clog 在 follower 端持久化时也使用批 fsync，是 OB 高吞吐的关键。

### Spanner：Paxos batching

Spanner 在每个 tablet（split）的 Paxos leader 上批量化客户端写：
- TabletServer 收到客户端写请求后入 batch 队列。
- 每隔几毫秒或队列达阈值时触发一次 Paxos prepare/accept。
- 一次 Paxos round 提交 N 个事务的 mutation，N 通常在几十到几百。

Spanner 论文（2012）指出：典型 Spanner 部署下 batch size 8–32，吞吐 1000–10000 TPS per tablet。

### SQLite：单写者，无 group commit

SQLite 的 serialized 事务模型决定了它没有 group commit：
- WAL 模式：reader 不阻塞 writer，但同一时刻只允许一个 writer。
- rollback journal 模式：写事务排他锁。
- 多个客户端的事务串行进入 → 没有"多个事务同时等待 fsync"的场景。

```sql
-- SQLite 仅能调整每事务 fsync 强度
PRAGMA synchronous = OFF;     -- 0 = 不 fsync（不安全）
PRAGMA synchronous = NORMAL;  -- 1 = WAL 模式下每次 commit 不 fsync
PRAGMA synchronous = FULL;    -- 2 = 默认，每次 commit fsync
PRAGMA synchronous = EXTRA;   -- 3 = WAL frame + dir 都 fsync
```

如果业务希望"批量插入",只能在应用层把多个 INSERT 合并到一个事务里，由单次 fsync 持久化：

```sql
BEGIN;
INSERT INTO logs VALUES (...);
INSERT INTO logs VALUES (...);
INSERT INTO logs VALUES (...);
-- ... 1000 个 INSERT
COMMIT;  -- 单次 fsync 提交所有
```

### DuckDB：单写者，但用 batch 模拟

DuckDB 与 SQLite 类似的单写者模型，但因为 DuckDB 主要是分析型负载（少 commit、多查询），不需要传统 group commit。WAL 在 commit 时一次性 fsync。

### ClickHouse：async insert（21.11+）

ClickHouse 的 OLAP 模型本身不需要传统 OLTP 的 fsync-per-commit。但用户场景中常见"高频小批量插入"导致 part 数爆炸，21.11 引入了 **async insert**：

```sql
-- 启用 async insert
SET async_insert = 1;
SET wait_for_async_insert = 1;            -- 等服务端确认
SET async_insert_busy_timeout_ms = 200;   -- 最长等 200ms
SET async_insert_max_data_size = 1000000; -- 攒 1MB
```

ClickHouse 服务端会把多个客户端的 INSERT 合并到一个 part，再批量写入磁盘和 ZooKeeper/Keeper（如果是 ReplicatedMergeTree）。这是 ClickHouse 版本的"组提交"。

### ClickHouse Keeper：Raft batch

ClickHouse 21.10 引入的 Keeper（NuRaft 实现）也使用 Raft batching，多个客户端的元数据写合并为一个 Raft 条目。

## MySQL binlog group commit 深入剖析

binlog group commit 是工程界研究最多、文档最详尽的 group commit 实现之一。下面详细拆解其内部状态机。

### 三阶段 leader-follower 协议

```
事务 T 调用 ha_commit_trans()
    ↓
进入 stage1: FLUSH（持有 LOCK_log）
    ↓
    leader = first thread to enter
    leader 收集等待队列中所有 follower 的 binlog cache
    leader 把所有 binlog 写入 binlog 文件 (write 不 fsync)
    ↓
进入 stage2: SYNC（持有 LOCK_sync）
    ↓
    leader 决定是否 fsync (sync_binlog 触发条件)
    leader 调 fsync_binlog_file()
    所有 follower 的 binlog 一次 fsync 持久化
    ↓
进入 stage3: COMMIT（持有 LOCK_commit）
    ↓
    leader 按 binlog 顺序逐个 commit InnoDB 事务
    InnoDB 写 trx commit log + 释放行锁
    ↓
所有事务返回客户端
```

每个事务进入某阶段时，先尝试 acquire 该阶段的 lock：成功则成为 leader，失败则将自己挂入该阶段的 follower 队列等待 leader 唤醒。

### 关键参数与触发条件

```
binlog_group_commit_sync_delay = D 微秒
binlog_group_commit_sync_no_delay_count = N 事务

leader 在 SYNC 阶段触发 fsync 的条件：
1. 累计等待时间 ≥ D 微秒，或
2. 累计 follower 数 ≥ N 个，或
3. 没有更多 follower 进入

D=0 表示完全不等，每个 leader 立即 fsync（高 TPS 但批小）
D=1000, N=16 表示等 1ms 或 16 个事务先到，再统一 fsync
```

### Mark Callaghan 的基准测试历史

Mark Callaghan（前 Facebook MySQL 团队）在 2010–2014 年发表了大量关于 binlog group commit 的基准测试：

- **5.5 vs 5.6**：在 16 核 SSD 服务器上，sysbench OLTP 写入 TPS 从 5.5 的 ~3000 跃升到 5.6 的 ~25000，主要归功于 group commit。
- **`prepare_commit_mutex` 的影响**：5.0/5.1 的这个互斥锁让 binlog 启用时（`sync_binlog=1`）TPS 锁死在 ~500，是当时 MySQL 复制的最大瓶颈。
- **延迟成本**：组提交把 P99 延迟从单事务 fsync 时间增加约 200–500 微秒，但 P50 延迟几乎不变。

### 与 InnoDB redo log 的协调

binlog group commit 解决了 binlog 的批量化，但 InnoDB redo log 的 fsync 由 InnoDB 自己控制：

```
事务 T 流水：
  1. SQL 执行，写 InnoDB undo + 修改 buffer pool 页
  2. trx prepare：写 InnoDB redo log，标 prepared
  3. binlog group commit (上面三阶段)
     - flush: 写 binlog
     - sync: fsync binlog (1 次)
     - commit: 写 InnoDB trx commit log，释放锁
  4. 返回客户端

InnoDB redo log 在阶段 2 和 3.commit 都被写入，
但 fsync 是由独立的 innodb_flush_log_at_trx_commit 控制：
  =0: 每秒 fsync 一次（不安全）
  =1: 每个 commit fsync（默认，安全）
  =2: 每个 commit write，每秒 fsync（中庸）
```

InnoDB redo log 内部也有 group commit：多个事务的 redo log 在同一次 fsync 中持久化（即便每个事务都开 `=1`）。

## PostgreSQL commit_delay 调优

PostgreSQL 的 `commit_delay` 是一个微妙的参数，错误使用会导致延迟增加而吞吐没变化。下面是调优指南。

### 何时该启用

只有在以下条件**全部满足**时才考虑 `commit_delay > 0`：

1. **硬件 fsync 较慢**：fsync 时间显著（> 200 微秒）。这通常意味着传统 SAS/SATA SSD 或机械盘。NVMe SSD 上启用通常无收益。
2. **并发度足够**：同时有 5+ 个事务在等 fsync。`commit_siblings` 默认 5。
3. **写入压力高**：TPS 接近 fsync IOPS 上限。低 TPS 时 commit_delay 仅增加延迟。

### 调优步骤

```sql
-- 1. 测量 fsync 时间
SELECT pg_test_fsync();    -- 命令行工具，需安装

-- 2. 观察当前 WAL writer 行为
SELECT * FROM pg_stat_wal;
-- 关键字段:
--   wal_buffers_full: wal buffer 满次数
--   wal_write_time: 累计 wal write 时间
--   wal_sync_time: 累计 fsync 时间

-- 3. 试验性配置
ALTER SYSTEM SET commit_delay = 50;        -- 50 微秒
ALTER SYSTEM SET commit_siblings = 5;
SELECT pg_reload_conf();

-- 4. 跑 pgbench 对比
-- pgbench -c 32 -j 8 -T 60 testdb
```

### 经验值

| 硬件 | commit_delay | 备注 |
|------|-------------|------|
| 机械盘（HDD） | 5000–10000 微秒 | 5–10 ms，大幅吸收事务 |
| SAS/SATA SSD | 100–500 微秒 | -- |
| NVMe SSD | 0（不启用） | fsync < 50 微秒，等待无意义 |
| 网络存储（EBS/PD） | 200–1000 微秒 | 视延迟而定 |

### 与 synchronous_commit 的协同

```sql
-- 异步 commit + commit_delay 通常无意义（异步本来就批）
SET synchronous_commit = off;

-- 同步 commit + commit_delay = 真正的 group commit
SET synchronous_commit = on;
SET commit_delay = 100;

-- remote_apply (流复制副本应用后才返回) + commit_delay = 极大吸收
SET synchronous_commit = remote_apply;
SET commit_delay = 500;
```

## 组提交的副作用与权衡

### 延迟下限 vs 吞吐上限

组提交的核心权衡是 latency floor vs throughput ceiling：

```
无 group commit：
  单事务延迟 = fsync 时间（如 100 微秒）
  最大 TPS = 1 / fsync 时间 = 10000 TPS
  注意：仅指单连接连续 commit；多连接并发时也受 fsync IOPS 上限制约。

有 group commit (delay=200 微秒，每批 32 事务)：
  单事务延迟 = delay + fsync 时间 = 300 微秒
  最大 TPS = 32 / fsync 时间 = 320000 TPS（理论上限）
  实际 TPS 受 CPU、锁、锁竞争限制，可能 50000–100000

权衡：
  如果业务对 P99 延迟敏感（< 200 微秒），不启用或设小 delay
  如果业务追求吞吐（> 50000 TPS），延迟可以忍受 1–5 ms，启用大 delay
```

### 公平性与饥饿

leader-follower 协议中，leader 处理 follower 的工作时自己要付出 CPU。如果某个事务的 binlog 特别大（如 10 MB 大事务），它作为 leader 会让所有 follower 等待长时间——可能造成短小事务被饥饿。

MySQL 5.7 之后的 binlog 优化在一定程度缓解了这个问题（leader 在 flush 阶段释放 LOCK_log 后，下一个事务可以并发进入 flush），但根本上无法完全消除。

### 复制延迟的连锁

主库的 group commit 把 N 个事务一次性写入 binlog 后发送给 slave。slave 收到后在 IO thread 写本地 relay log，再由 SQL thread 应用。如果主库 batch 很大，slave 的 IO/SQL thread 可能积压，导致延迟增加。

这就是为什么 MySQL 5.7+ 引入 **logical clock** 的并行复制：基于主库 binlog 中的 last_committed 字段，slave 可以并行应用属于同一 commit batch 的事务。

```sql
-- slave 端启用并行复制（与 group commit 协同）
SET GLOBAL slave_parallel_type = 'LOGICAL_CLOCK';
SET GLOBAL slave_parallel_workers = 8;
```

### 与崩溃恢复的交互

组提交不影响崩溃恢复的正确性：每个事务在 fsync 之前已写入完整的 redo log + binlog。崩溃后：
- 已 fsync 的 batch 中所有事务都恢复（visible）。
- 未 fsync 的 batch 中所有事务都丢失（即便已写入 OS 页缓存）。

但**部分崩溃下可能出现 binlog 与 redo log 不一致**：例如 binlog fsync 完但 InnoDB 在 commit 阶段崩溃。MySQL 的 crash recovery 会扫描 binlog 找 prepared 但未 commit 的 InnoDB 事务，按 binlog 顺序补 commit 它们。这就是 5.6 引入 binlog group commit 时同时设计的 XA-style 崩溃恢复协议。

### 可观察性

各引擎都暴露了组提交相关的统计指标：

```sql
-- MySQL 5.7+
SHOW GLOBAL STATUS LIKE 'Binlog_group_commits';
SHOW GLOBAL STATUS LIKE 'Binlog_commits';
-- 平均 batch 大小 = Binlog_commits / Binlog_group_commits

-- PostgreSQL
SELECT * FROM pg_stat_wal;
-- wal_records / wal_fpi / wal_bytes / wal_buffers_full / wal_write / wal_sync

-- Oracle
SELECT name, value FROM v$sysstat
WHERE name IN ('redo writes', 'redo write time', 'redo synch writes');
-- 平均每次 redo write 包含的事务数

-- SQL Server
SELECT * FROM sys.dm_io_virtual_file_stats(NULL, NULL)
WHERE database_id = DB_ID('mydb');
```

## 设计争议与最佳实践

### 大事务的 leader 问题

leader 持有锁的时间和它需要 flush 的 binlog 大小成正比。一个 100MB 的大事务作为 leader，会让 follower 等待 100MB binlog 写入磁盘的时间（~ 100ms 在 SSD 上）。

**最佳实践**：避免单个事务超过 10MB binlog，尽量拆分大事务。MySQL 8.0 的 `binlog_transaction_dependency_tracking` 可以按 writeset 而非 commit_order 标 last_committed，进一步提升并行复制度。

### 多日志流的协调

支持多 binlog 流的引擎（如 MariaDB Galera、TiDB）需要协调跨流的 commit 顺序。MariaDB 的 wsrep 把 group commit 和集群 certification 协调起来，TiDB 用 PD 全局 timestamp 给所有 region 的 commit_ts 排序。

### NVMe 时代是否还需要 group commit？

NVMe SSD 的 fsync 已经下到 20–50 微秒，单线程 fsync TPS 可达 20000+。这让一些工程师质疑 group commit 是否还有必要。

实测显示：
- **单磁盘 NVMe**：group commit 收益 2–5 倍（仍可观）。
- **PMem (Optane)**：fsync < 5 微秒，group commit 收益 < 50%（变小）。
- **网络存储（EBS gp3 / Azure Premium）**：fsync 仍在 200–1000 微秒，group commit 收益 5–20 倍（仍很大）。

结论：在 NVMe + 本地存储下 group commit 收益变小但不消失；在云上和远程存储下仍是关键优化。

### 与同步复制的乘数效应

当事务必须等多副本 ack 才能返回（synchronous replication）时，每次 fsync 的延迟从 100 微秒变为 1–10 ms（网络往返）。这时 group commit 的收益从 N 倍变成 N×10 倍，是分布式数据库高吞吐的关键。

## 实现建议（给引擎开发者）

### 1. 三阶段队列管理

实现 group commit 的核心数据结构：

```
struct CommitStage {
    mutex: Mutex,
    leader_signal: ConditionVariable,
    follower_queue: LockFreeQueue<Transaction>,
}

struct GroupCommitQueue {
    flush: CommitStage,
    sync:  CommitStage,
    commit: CommitStage,
}

fn group_commit(txn: Transaction):
    enqueue(flush.follower_queue, txn)
    if try_lock(flush.mutex):
        // I am leader of FLUSH
        followers = drain(flush.follower_queue)
        flush_to_log_file(followers)
        unlock(flush.mutex)
        signal_followers(followers, NEXT_STAGE_SYNC)
    else:
        wait(txn.signal)

    enqueue(sync.follower_queue, txn)
    if try_lock(sync.mutex):
        // I am leader of SYNC
        followers = drain(sync.follower_queue)
        if should_fsync():
            fsync(log_fd)
        unlock(sync.mutex)
        signal_followers(followers, NEXT_STAGE_COMMIT)
    else:
        wait(txn.signal)

    // ... commit stage 类似
```

要点：
- **lock-free queue**：follower 入队应当是 lock-free（如 Treiber stack 或 Michael-Scott queue），避免成为新瓶颈。
- **batch 大小限制**：单个 leader 处理过大的 batch 会导致延迟尖峰，应有上限（如 1000 事务或 1 GB binlog）。
- **leader 转交**：leader 完成自己的工作后，应当唤醒一个新 follower 成为下一阶段的 leader。

### 2. 与 fsync 实现的配合

```
fsync(fd) 在 Linux 上的成本：
  - SATA SSD: 100-1000 微秒
  - NVMe: 20-100 微秒  
  - PMem: 1-5 微秒
  - 远程存储 (EBS): 200-2000 微秒

优化方向：
  1. 优先 fdatasync（不刷 metadata），减少 30-50% 时间
  2. 预分配 log 文件（如 PG WAL 16MB 段），避免 metadata 改动
  3. 用 io_uring (Linux 5.1+) 异步发起 fsync，由 leader 轮询完成
  4. 对块大小敏感：fsync 一段 4KB 和 4MB 在 SSD 上耗时几乎一样
```

### 3. 与 OS 页缓存的协调

```
传统 fsync 流程：write() 入页缓存 → fsync 触发刷盘
问题：
  - 页缓存可能 cache miss 导致 read amplification
  - dirty page 累积可能触发 OS 自动 flush

最佳实践：
  - O_DIRECT 绕过页缓存（Oracle / MySQL 推荐）
  - O_DSYNC 写入即同步（PostgreSQL 可选）
  - mmap + msync（部分内存数据库使用）
```

### 4. 自适应等待窗口

固定的 `commit_delay` 在不同负载下表现差异大，自适应方案：

```
观察指标：
  - 当前 fsync 队列长度 Q
  - 上次 fsync 的延迟 L
  - 上次 batch 大小 B

自适应策略：
  if Q > threshold_high:
    delay = 0  // 高并发，立即触发，靠并发吸收
  elif L > threshold_high:
    delay = small  // fsync 慢，多等也无收益
  elif B < threshold_low:
    delay = large  // batch 太小，等更多事务
  else:
    delay = current  // 稳定区间

需要持续基于 EWMA 调整，避免抖动。
```

### 5. 公平性保护

避免大事务作为 leader 长时间持锁：

```
batch_pruning：
  leader 处理 follower 时检查 follower 总大小
  if total_size > MAX_BATCH_SIZE:
    把超出部分留给下个 leader

priority_lane：
  把短事务（writeset < 1KB）和大事务（> 10MB）分开队列
  防止大事务阻塞小事务
```

### 6. 跨副本组提交（Raft / Paxos）

```
Raft AppendEntries 批量化：
  leader 维护 pending 队列
  每隔几毫秒（或队列达阈值）触发一次 AppendEntries
  AppendEntries 包含多个事务的 log entries
  follower 收到后批量 fsync 本地 Raft log

注意点：
  - 网络包大小限制（典型 64KB MTU 后 IP 分片成本高）
  - follower 的 fsync 延迟决定 ack 时间
  - 多数派 ack 后 leader 才能 commit
  - leader 也需要本地 fsync (除非 follower 数足够)
```

CockroachDB / TiKV 都使用类似的实现，区别在于 batch 触发条件和 raft 提案大小限制。

### 7. 指标暴露

暴露给运维的关键指标：

```
metrics:
  group_commit.batch_size_p50:   typical batch
  group_commit.batch_size_p99:   tail batch
  group_commit.latency_p50:      single txn commit latency
  group_commit.latency_p99:      tail commit latency
  group_commit.fsync_per_sec:    actual fsync IOPS
  group_commit.txn_per_fsync:    amplification ratio
  group_commit.queue_depth:      live follower queue length
```

`txn_per_fsync` 是最关键的健康指标：值 < 2 说明组提交几乎没起作用（可能 commit_delay 设错了或并发不够）。

## 总结对比矩阵

### 组提交能力总览

| 能力 | PostgreSQL | MySQL | MariaDB | Oracle | SQL Server | DB2 | CockroachDB | TiDB | YugabyteDB | OceanBase | SAP HANA |
|------|-----------|-------|---------|--------|-----------|-----|-------------|------|-----------|-----------|----------|
| 原生 group commit | 是 | 是 | 是 | 是 | 部分 | 是 | 是 | 是 | 是 | 是 | 是 |
| 显式等待窗口 | 是 | 是 | 是 | 是 | 否 | 旧版 | 否 | 否 | 否 | 否 | 是 |
| binlog/复制日志批 | -- | 是 | 是 | -- | -- | -- | Raft | Raft | Raft | Paxos | -- |
| 与同步复制协同 | 是 | 是 | 是 | 是 | 是 | 是 | 是 | 是 | 是 | 是 | 是 |
| Per-txn 控制 | -- | -- | -- | 是 | 是 (DD) | -- | -- | -- | -- | -- | -- |

### 引擎选型建议

| 场景 | 推荐引擎/配置 | 原因 |
|------|------------|------|
| 高 TPS OLTP（机械盘） | PG `commit_delay=5000` 或 MySQL `binlog_group_commit_sync_delay=2000` | 大幅吸收 fsync |
| 高 TPS OLTP（NVMe） | 默认配置即可 | fsync 已快 |
| 强一致复制 | MySQL semi-sync + group commit / PG `synchronous_commit=on` | 多副本批 |
| 灵活持久化 | Oracle `COMMIT WRITE` 子句 / SQL Server `DELAYED_DURABILITY` | 事务级控制 |
| 分布式 OLTP | CockroachDB / TiDB / OceanBase | Raft/Paxos 自动批 |
| 流式插入 | ClickHouse `async_insert=1` | 攒批合并 part |
| 低延迟（< 1ms） | PG `commit_delay=0` + WAL writer | 只用隐式批 |
| 单机批量导入 | SQLite/DuckDB 单事务包大批 INSERT | 单写者无组提交 |

## 参考资料

- Gray, Jim. "Notes on Data Base Operating Systems" (1978), Lecture Notes in Computer Science
- Mohan, C. et al. "ARIES: A Transaction Recovery Method Supporting Fine-Granularity Locking and Partial Rollbacks Using Write-Ahead Logging" (1992), ACM TODS
- DeWitt, D.J. et al. "Implementation Techniques for Main Memory Database Systems" (1984)
- PostgreSQL: [commit_delay / commit_siblings](https://www.postgresql.org/docs/current/runtime-config-wal.html#GUC-COMMIT-DELAY)
- PostgreSQL: [synchronous_commit](https://www.postgresql.org/docs/current/runtime-config-wal.html#GUC-SYNCHRONOUS-COMMIT)
- MySQL: [Binary Logging Options and Variables](https://dev.mysql.com/doc/refman/8.0/en/replication-options-binary-log.html#sysvar_binlog_group_commit_sync_delay)
- MySQL Server Team Blog: [Group Commit in 5.6](https://mysqlserverteam.com/binary-log-group-commit-in-mysql-5-6/)
- Mark Callaghan: [MySQL group commit benchmarks](https://smalldatum.blogspot.com/)
- MariaDB: [Group Commit for the Binary Log](https://mariadb.com/kb/en/group-commit-for-the-binary-log/)
- Kristian Nielsen blog series: MariaDB binlog group commit design (2011-2012)
- Oracle: [COMMIT Statement](https://docs.oracle.com/en/database/oracle/oracle-database/19/sqlrf/COMMIT.html)
- Oracle: [Tuning Redo Log](https://docs.oracle.com/en/database/oracle/oracle-database/19/tgdba/instance-tuning-using-performance-views.html)
- SQL Server: [Control Transaction Durability](https://learn.microsoft.com/en-us/sql/relational-databases/logs/control-transaction-durability)
- DB2: [MINCOMMIT configuration parameter](https://www.ibm.com/docs/en/db2)
- SAP HANA: [Group Commit Configuration](https://help.sap.com/docs/SAP_HANA_PLATFORM)
- CockroachDB blog: [Consistency, Speed, and Scale: Why CockroachDB Uses Raft](https://www.cockroachlabs.com/blog/)
- TiDB: [TiDB Optimistic and Pessimistic Transaction](https://docs.pingcap.com/tidb/stable/transaction-overview)
- YugabyteDB: [DocDB Architecture](https://docs.yugabyte.com/preview/architecture/docdb/)
- OceanBase: [Multi-Paxos in OceanBase](https://www.oceanbase.com/docs/)
- Spanner Paper: Corbett, J.C. et al. "Spanner: Google's Globally Distributed Database" (2012), OSDI
- ClickHouse: [Asynchronous Inserts](https://clickhouse.com/docs/en/optimize/asynchronous-inserts)
- SQLite: [Pragma synchronous](https://www.sqlite.org/pragma.html#pragma_synchronous)
- 相关文章: [WAL / Redo 日志与持久化配置](wal-checkpoint-durability.md)
- 相关文章: [WAL 归档](wal-archiving.md)
- 相关文章: [崩溃恢复机制](crash-recovery.md)
- 相关文章: [逻辑复制与 GTID](logical-replication-gtid.md)
