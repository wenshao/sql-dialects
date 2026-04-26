# 快照导出 (Snapshot Export)

"我要把这张 5TB 的订单表用 16 个并发线程一次性导出到 S3，但每一行都必须来自同一时刻、同一一致性视图。" —— 这看似矛盾的需求，正是快照导出（Snapshot Export）要解决的核心问题。从 PostgreSQL 9.2 引入 `pg_export_snapshot()` 起，"导出一个一致性快照、共享给多个会话、让并行 dump 工具可以协同工作" 就成了现代数据库的必备能力。今天，并行 `pg_dump`、`mydumper`、CDC 工具初始化、零停机迁移、跨可用区备份，全部依赖快照导出这一基础原语。

## 为什么需要快照导出

设想一个常见场景：把生产数据库（10TB、500 张表）一次性导出到对象存储，作为下游数据湖的初始物化。如果只用单个会话跑 `pg_dump`，吞吐量被单核 CPU 和单 TCP 流的带宽锁死，需要 ~36 小时。如果开 16 个并发会话，每个会话独立 `START TRANSACTION` —— 看似快了，但 16 个会话各自看到的"快照时刻"是不同的，导出的 16 份数据彼此不一致，有的表 A 在事务 T1 之前、有的表 B 在 T1 之后，下游做 JOIN 时会出现"幽灵记录"。

**快照导出**就是答案：会话 0 调用 `pg_export_snapshot()` 拿到一个快照标识符（如 `00000003-0000001B-1`），通过文件、消息或参数传给会话 1..15；这些后续会话调用 `SET TRANSACTION SNAPSHOT '<snapshot_id>'` 把自己的事务"锚定"到同一时刻。从那一刻起，16 个会话看到的可见性视图（xmin/xmax/xip_list）完全相同，并行导出的 16 份数据可以无缝拼接成一个一致的整体。

**典型用途**：

1. **并行逻辑备份**：`pg_dump --jobs=16` 内部第一个会话调用 `pg_export_snapshot()`，其他 15 个 worker 用 `SET TRANSACTION SNAPSHOT` 锚定，拼接出一致的 `--format=directory` 备份。`mydumper` / `mysqldump --single-transaction` / `mongodump` 等工具都用类似机制。
2. **CDC 工具的初始全量同步**：Debezium、Maxwell、Canal、Flink CDC 在订阅 binlog/WAL 之前，必须先 dump 出一份"快照初值"。这个初值必须与 binlog/WAL 的某个特定 LSN/位置严格对齐，否则会出现重复或丢失。PostgreSQL 的 `CREATE_REPLICATION_SLOT ... USE_SNAPSHOT` 把复制槽创建与快照导出原子化，CDC 工具拿到 slot 同时拿到一致快照。
3. **零停机迁移**：从 MySQL 5.7 迁到 8.0，先用 `mysqldump --single-transaction --master-data=2` 拿一个一致快照（同时记录 binlog 位置），导入新库；然后基于记录的 binlog 位置启动复制，追平所有增量。
4. **跨可用区/跨云备份**：把一致快照分发到多个对象存储区域，每个区域的并行 worker 独立工作，整体大幅缩短 RTO。
5. **分析型 ETL 的初值物化**：把 OLTP 的全量数据物化到 Snowflake / BigQuery / ClickHouse，初值必须一致；之后增量同步通过 CDC 累加。
6. **逻辑复制订阅的 initial sync**：PostgreSQL 逻辑复制创建 publication 时自动导出快照，subscriber 用此快照初始化目标表，再切换到 streaming。

姊妹文章：[系统版本控制查询 (System-Versioned Queries)](./system-versioned-queries.md) 关注 "如何查询历史时刻的数据"，本文关注 "如何把当前时刻冻结成可分发的快照"；[WAL 归档与 PITR](./wal-archiving.md) 关注崩溃恢复的物理日志流。这三者共同构成现代数据库的"时间维度" 工具集。

## 没有 SQL 标准

SQL:2011 / SQL:2016 / SQL:2023 都不涉及快照导出。这是数据库实现的"事务可见性"原语，必然受到 MVCC 实现细节的强约束：

- **PostgreSQL** 的快照是 `(xmin, xmax, xip[])` 三元组，可以序列化成文本传给其他会话。
- **Oracle** 的快照是 SCN（System Change Number），全局单调递增；任何会话用 `AS OF SCN n` 都能复现。
- **MySQL InnoDB** 的快照是 read view（trx_id list），通过 `START TRANSACTION WITH CONSISTENT SNAPSHOT` 在会话内创建，但不能跨会话传递；`mydumper` 用 `FLUSH TABLES WITH READ LOCK` 间接同步。
- **CockroachDB / TiDB** 的快照是 HLC（Hybrid Logical Clock）时间戳，任何会话用 `AS OF SYSTEM TIME` / `AS OF TIMESTAMP` 都能精确复现。
- **Snowflake** 的快照是 micro-partition 的不可变指针，CLONE 操作"瞬间"创建零拷贝快照表。
- **BigQuery** 的快照是表元数据的 snapshot，通过 `FOR SYSTEM_TIME AS OF` 暴露。

虽然没有标准，主流引擎都已经形成了"快照可被命名、可被分发、可被多会话共享"的事实约定。

## 支持矩阵

### 1. pg_export_snapshot 等价能力（导出可分发的快照标识）

| 引擎 | 原生导出快照 | API/语法 | 共享方式 | 版本 |
|------|------------|---------|---------|------|
| PostgreSQL | 是 | `pg_export_snapshot()` → text id | `SET TRANSACTION SNAPSHOT '<id>'` | 9.2 (2012) |
| MySQL | 间接 | `START TRANSACTION WITH CONSISTENT SNAPSHOT` | 同会话内事务一致；不可跨会话直接传 | InnoDB 4.0+；5.6 添加与 binlog 位点对齐的增强 |
| MariaDB | 间接 | 同 MySQL | 同 MySQL | 10.1+ |
| SQLite | 否 | -- | 无并行需求；BEGIN IMMEDIATE | -- |
| Oracle | 是 | 当前 SCN 通过 `DBMS_FLASHBACK.GET_SYSTEM_CHANGE_NUMBER()` 获取 | `AS OF SCN n` 在任意会话复现 | 9i (2001) |
| SQL Server | 部分 | `BEGIN TRANSACTION` + 数据库快照 (`CREATE DATABASE ... AS SNAPSHOT OF`) | 通过快照数据库名共享 | 2005+ |
| DB2 | 部分 | `CURRENT COMMIT` 隔离 + Flashback Query | LBAC 与 Time Travel 表 | 10.1+ |
| Snowflake | 是 | `CLONE` (zero-copy) 或 Time Travel `AT/BEFORE` | 通过克隆表名 / TIMESTAMP 共享 | GA |
| BigQuery | 是 | `CREATE SNAPSHOT TABLE` 或 `FOR SYSTEM_TIME AS OF ts` | 通过 snapshot 表 / 时间戳共享 | GA |
| Redshift | 部分 | 自动/手动 cluster snapshot | snapshot id 仅用于 restore，不能跨会话共享给查询 | GA |
| DuckDB | 否 | 进程内 MVCC，单会话快照 | 暂不支持跨会话快照 | -- |
| ClickHouse | 部分 | `BACKUP` / 物化视图 + part 不可变 | 通过 PARTITION 名 / 备份名 | 22.x+ |
| Trino/Presto | 部分 | 仅对 Iceberg/Delta 等 ACID 连接器：`FOR VERSION AS OF` | 通过 snapshot id 共享 | 398+ |
| Spark SQL | 部分 | Delta/Iceberg：`VERSION AS OF` / `TIMESTAMP AS OF` | 通过 version/timestamp 共享 | 3.3+ |
| Hive | 部分 | Iceberg 表：`FOR SYSTEM_VERSION AS OF` | 通过 snapshot id | Hive 4 |
| Flink SQL | 部分 | Hybrid source 的 initial offset；Iceberg snapshot | 通过 snapshot 元数据 | 1.13+ |
| Databricks | 是 | Delta `DESCRIBE HISTORY` + `VERSION AS OF` | 通过 version | GA |
| Teradata | 是 | `SAVEPOINT` + `BACKUP/ARC` 的 ACL | 通过备份元数据 | 早期 |
| Greenplum | 是 | 继承 PG `pg_export_snapshot()` | 同 PG | 5.0+ |
| CockroachDB | 是 | `AS OF SYSTEM TIME` 接受任意 HLC 时间戳 | 通过时间戳共享 | 1.1+ |
| TiDB | 是 | `tidb_snapshot` 会话变量；`AS OF TIMESTAMP` | 通过 TS 共享 | 4.0+ |
| OceanBase | 是 | `AS OF SCN / TIMESTAMP`（兼容 Oracle Flashback） | 通过 SCN 共享 | 2.2+ |
| YugabyteDB | 部分 | 内部 MVCC，但未暴露 `SET TRANSACTION SNAPSHOT` | -- | -- |
| SingleStore | 部分 | `BACKUP DATABASE ... TO S3` 是一致快照 | 通过备份名 | 7.0+ |
| Vertica | 是 | `AT EPOCH` / `AT TIME` epoch 快照 | 通过 epoch 编号 | 9.0+ |
| Impala | 部分 | 仅 Iceberg：`FOR SYSTEM_VERSION AS OF` | 通过 snapshot id | 4.0+ |
| StarRocks | 部分 | Iceberg/Paimon 外表 + `BACKUP/RESTORE` | 通过 snapshot id | 2.5+ |
| Doris | 部分 | `BACKUP/RESTORE` + Iceberg | 通过 backup 名 | 1.2+ |
| MonetDB | 否 | -- | 无 | -- |
| CrateDB | 部分 | Lucene-style snapshot repository | 通过 snapshot 名 | 4.0+ |
| TimescaleDB | 是 | 继承 PG | 同 PG | 继承 PG |
| QuestDB | 部分 | `SNAPSHOT PREPARE/COMPLETE` | 通过文件系统快照 | 7.x+ |
| Exasol | 是 | EXAoperation backup | 通过 backup id | 6.x+ |
| SAP HANA | 是 | `BACKUP DATA SNAPSHOT PREPARE` | 通过 snapshot id | 1.0+ |
| Informix | 是 | `ontape` snapshot | 通过 tape label | 早期 |
| Firebird | 部分 | `nbackup` 增量；事务级快照 | 通过 backup 文件 | 2.5+ |
| H2 | 否 | -- | -- | -- |
| HSQLDB | 否 | -- | -- | -- |
| Derby | 否 | `SYSCS_BACKUP_DATABASE` | 通过备份目录 | -- |
| Amazon Athena | 部分 | 仅 Iceberg：`FOR SYSTEM_VERSION AS OF` | 通过 snapshot id | GA |
| Azure Synapse | 是 | `CREATE DATABASE ... AS SNAPSHOT OF` | 通过快照库名 | GA |
| Google Spanner | 是 | `STRONG` / `EXACT_STALENESS` / `MIN_READ_TIMESTAMP` 读 API | 通过 read timestamp | GA |
| Materialize | 部分 | 基于 source 的 offset 快照 | 通过 source frontier | -- |
| RisingWave | 部分 | State backend snapshot | 通过 snapshot id | 1.x+ |
| InfluxDB (SQL) | 部分 | `influxd backup` | 通过 backup 名 | 2.x+ |
| DatabendDB | 是 | 基于对象存储的 immutable snapshot | 通过 snapshot id | GA |
| Yellowbrick | 是 | 继承 PG `pg_export_snapshot()` | 同 PG | GA |
| Firebolt | 是 | 自动 time travel | 通过时间戳 | GA |
| MaxCompute | 部分 | 时间旅行查询 | 通过时间 | GA |
| ADB for PostgreSQL | 是 | 继承 PG | 同 PG | GA |
| ADB for MySQL | 间接 | 同 MySQL | 同 MySQL | GA |

> 统计：约 22 个引擎提供"可跨会话/可分发"的快照导出原语；约 14 个引擎通过备份/克隆/Time Travel 间接达成；约 9 个引擎不支持。

### 2. SET TRANSACTION SNAPSHOT 等价能力（导入快照、加入到既有快照）

| 引擎 | 加入既有快照 | 语法 | 备注 |
|------|------------|------|------|
| PostgreSQL | 是 | `SET TRANSACTION SNAPSHOT '<id>'` | 必须在 `BEGIN ISOLATION LEVEL REPEATABLE READ` 后第一个语句 |
| MySQL | 否 | -- | InnoDB 快照不能跨会话传 |
| Oracle | 是（间接） | `SET TRANSACTION READ ONLY; SELECT ... AS OF SCN n` | 任意会话用 SCN 复现 |
| SQL Server | 否（直接） | `SELECT * FROM SnapshotDB.dbo.Tbl` | 通过快照数据库名访问 |
| Snowflake | 是 | `SELECT * FROM tbl AT(TIMESTAMP => ts)` | 任意会话用时间戳复现 |
| BigQuery | 是 | `SELECT * FROM tbl FOR SYSTEM_TIME AS OF ts` | 7 天内 |
| CockroachDB | 是 | `SET TRANSACTION AS OF SYSTEM TIME ts` | 任意 HLC 时间戳 |
| TiDB | 是 | `SET @@tidb_snapshot = ts` 或 `AS OF TIMESTAMP ts` | 全会话效果 |
| OceanBase | 是 | `AS OF SCN / TIMESTAMP` | Oracle 兼容 |
| Vertica | 是 | `AT EPOCH n` | 全会话 |
| Spanner | 是 | `READ_TIMESTAMP` | API/SDK |
| Trino/Presto | 是（连接器级） | `SELECT ... FOR VERSION AS OF v` | Iceberg/Delta |
| Spark SQL | 是 | `SELECT ... TIMESTAMP AS OF ts` | Delta/Iceberg/Hudi |

### 3. CDC 复制槽 / Binlog 起点 + 快照原子化

CDC 工具的核心难点：**初始全量快照** 必须与 **后续增量日志** 在同一个时刻对齐。

| 引擎 | 原子化创建复制槽 + 快照 | 工具 | 版本 |
|------|----------------------|------|------|
| PostgreSQL | 是 | `CREATE_REPLICATION_SLOT ... LOGICAL ... USE_SNAPSHOT` | 9.4+ |
| MySQL | 间接 | `START TRANSACTION WITH CONSISTENT SNAPSHOT` + `SHOW MASTER STATUS` 同事务内 | 5.6+ |
| Oracle | 是 | LogMiner / GoldenGate 内部对齐 SCN | 早期 |
| SQL Server | 是 | CDC 表 + LSN | 2008+ |
| MongoDB | 是 | `$changeStream` resume token | 3.6+ |
| CockroachDB | 是 | `CREATE CHANGEFEED ... WITH initial_scan, cursor` | 21.1+ |
| TiDB | 是 | TiCDC + BR 工具协同 | 4.0+ |
| OceanBase | 是 | OCI 初始 + LogProxy | 3.x+ |
| Debezium 通用框架 | 视上游引擎而定 | snapshot.mode = initial / never / when_needed | 1.x+ |
| Maxwell | MySQL only | bootstrap | -- |
| Canal | MySQL only | dump + position | -- |
| Flink CDC | 视上游引擎 | hybrid source: snapshot + binlog | 2.x+ |

### 4. 并行逻辑 dump 工具支持

| 工具 | 支持引擎 | 并行机制 | 快照原语 |
|------|---------|---------|----------|
| `pg_dump --jobs=N` | PostgreSQL | `pg_export_snapshot()` + N worker `SET TRANSACTION SNAPSHOT` | 9.3+ 内置 |
| `pg_dumpall` | PostgreSQL | 串行（多库） | 不需要 |
| `mysqldump` | MySQL | `--single-transaction` 单线程 | InnoDB consistent snapshot |
| `mydumper` | MySQL/MariaDB | N worker + `FLUSH TABLES WITH READ LOCK` 同步 | 短暂全局锁 + binlog position |
| `mongodump --numParallelCollections=N` | MongoDB | 并行集合 | snapshot oplog |
| `mongodump --oplog` | MongoDB | 单进程并行 + oplog 追平 | snapshot + oplog 起点 |
| `pg_dump --snapshot=<id>` | PostgreSQL | 用户提供快照 | 用于多 dump 协调 |
| `wal-g backup-push` | PostgreSQL | 物理 base backup（非逻辑） | start_backup LSN |
| `pgBackRest backup` | PostgreSQL | 物理 + WAL 归档 | start_backup LSN |
| `Snowflake CLONE` | Snowflake | 零拷贝克隆 | micro-partition 元数据 |
| `BigQuery EXPORT DATA` | BigQuery | BQ 内部并行 | 自动一致 |
| `cockroach dump` | CockroachDB | 单线程（已 deprecated） | snapshot |
| `BACKUP INTO` | CockroachDB / TiDB / OB | 分布式并行 | global snapshot |
| `snowflake.export.s3` | Snowflake | 内部并行 | clone 快照 |
| `mongoimport / mongoexport` | MongoDB | 用户级 | 不保证一致 |
| `xtrabackup --parallel` | MySQL/MariaDB | InnoDB 文件级并行 | redo log apply |
| `mariabackup --parallel` | MariaDB | xtrabackup fork | 同 |
| `OBLOADER / OBDUMPER` | OceanBase | 多线程 + SCN | global snapshot |
| `BR (Backup & Restore)` | TiDB | 分布式并行 | global TS |
| `CR (Change Replication)` | TiDB | TiCDC initial scan | global TS |

### 5. 物理快照（VFS / 文件系统）

| 引擎 | 文件系统快照配合 | 一致性 | 备注 |
|------|----------------|-------|------|
| PostgreSQL | LVM / ZFS / EBS snapshot | crash-consistent | 需 `pg_start_backup()` 标记 |
| MySQL | LVM / ZFS / EBS | crash-consistent | 需 `FLUSH TABLES WITH READ LOCK` |
| Oracle | RMAN level + storage snapshot | physical-consistent | begin/end backup |
| SQL Server | VSS (Volume Shadow Copy) | application-consistent | VSS Writer |
| MongoDB | LVM / ZFS / EBS | application-consistent | `db.fsyncLock()` |
| ClickHouse | hard link snapshot | physical-consistent | parts 不可变 |
| Cassandra | nodetool snapshot | per-node | hard link |
| Etcd | snapshot save | physical-consistent | raft log |

## PostgreSQL 深度剖析：pg_export_snapshot 的内部机制

PostgreSQL 9.2 (2012) 引入 `pg_export_snapshot()`，至今仍是行业内"快照导出"最严谨的实现之一。理解它有助于理解所有现代数据库的快照模型。

### 1. 快照的物理结构

PostgreSQL 的 MVCC 通过给每行 tuple 打上 `xmin`（创建该行的事务 ID）和 `xmax`（删除/更新该行的事务 ID）实现。对于一个快照来说，可见性判断的关键三元组是：

```
typedef struct SnapshotData {
    TransactionId xmin;        // 此快照能看到的最小活跃 xid
    TransactionId xmax;        // 此快照创建时的下一个 xid（不可见上界）
    TransactionId *xip;        // 创建快照时的活跃事务列表
    uint32 xcnt;               // xip 数组长度
    ...
} SnapshotData;
```

**可见性判断**（简化）：

```
visible(tuple):
    if tuple.xmin >= snapshot.xmax: return false   // 创建在快照之后
    if tuple.xmin in snapshot.xip[]:  return false  // 创建于快照创建时仍在飞的事务
    if tuple.xmin < snapshot.xmin and tuple.xmax == 0: return true
    if tuple.xmax >= snapshot.xmax: return true     // 删除发生在快照之后
    if tuple.xmax in snapshot.xip[]:  return true
    return false  // 已被在快照之前提交的事务删除
```

只要 `(xmin, xmax, xip[])` 三元组完全相同，两个会话看到的可见性就完全相同。这是快照可"导出"的理论基础。

### 2. 快照导出的实现

```sql
-- 会话 A：开启 REPEATABLE READ 事务后导出快照
BEGIN ISOLATION LEVEL REPEATABLE READ;
SELECT pg_export_snapshot();
-- 返回类似：00000003-0000001B-1
--                    \________/ \_/
--                     PID/xid    序号

-- 此时 PG 后端会把当前事务的 SnapshotData 写入磁盘文件
-- 路径：$PGDATA/pg_snapshots/<snapshot_id>
-- 文件内容（文本）：
--   xmin:32768
--   xmax:32770
--   xcnt:1
--   xip:32769
--   subxcnt:0
--   suboverflowed:0
--   rec:0
--   takenDuringRecovery:0
```

```sql
-- 会话 B：导入相同的快照
BEGIN ISOLATION LEVEL REPEATABLE READ;
SET TRANSACTION SNAPSHOT '00000003-0000001B-1';
-- 之后所有 SELECT 看到的可见性与会话 A 完全一致
```

约束条件：

1. **必须在事务最开始**：`SET TRANSACTION SNAPSHOT` 必须是 `BEGIN ISOLATION LEVEL REPEATABLE READ;`（或 `SERIALIZABLE`）后的第一个语句，否则报错。
2. **导出会话必须保持事务开启**：会话 A 一旦 `COMMIT`/`ROLLBACK`，快照文件就被清理，会话 B 的 `SET TRANSACTION SNAPSHOT` 会失败。
3. **两会话隔离级别要兼容**：`REPEATABLE READ` 导出 → 任意 RR/Serializable 都能用；`SERIALIZABLE` 导出 → 只有 SERIALIZABLE 能用（且失去 SSI 序列化保证）。
4. **同一数据库**：快照不能跨数据库使用。

### 3. pg_dump --jobs 内部流程

```bash
# 用户执行
pg_dump --jobs=8 --format=directory mydb -f /backup/mydb.dir
```

内部流程（PostgreSQL 9.3+）：

```
1. 主进程连接 → BEGIN ISOLATION LEVEL REPEATABLE READ;
2. 主进程 → SELECT pg_export_snapshot() → 拿到 snapshot_id
3. 主进程 → 查询元数据（pg_class、pg_attribute 等），生成 schema dump
4. 主进程 fork 8 个 worker 进程
5. 每个 worker 各自连接：
     BEGIN ISOLATION LEVEL REPEATABLE READ;
     SET TRANSACTION SNAPSHOT '<snapshot_id>';
6. 主进程根据表大小做负载均衡，把表分配给 8 个 worker：
     worker 1 → table_a, table_d (最大的两张)
     worker 2 → table_b, table_e
     ...
7. 每个 worker 用 COPY ... TO STDOUT 把数据导到 /backup/mydb.dir/<oid>.dat.gz
8. 所有 worker 完成 → 主进程 COMMIT；→ 快照文件被清理
```

**关键观察**：

- 整个过程中，所有 9 个会话（1 主 + 8 worker）看到的数据完全一致，即使期间有大量 INSERT/UPDATE。
- 主进程的 `pg_export_snapshot()` 是这整个机制的"锚点"，没有它就无法做并行 dump。
- `--format=directory` 是必须的，因为只有目录格式才能并行写入；`--format=plain`（默认）和 `--format=custom` 都是单进程。

### 4. 逻辑复制 + 快照导出的协同

PostgreSQL 9.4 在 `CREATE_REPLICATION_SLOT` 上引入 `EXPORT_SNAPSHOT` / `USE_SNAPSHOT` / `NOEXPORT_SNAPSHOT` 三选一选项，把"创建复制槽" 和 "导出快照" 原子化：

```
-- 复制协议（不在普通 SQL 中）
CREATE_REPLICATION_SLOT my_slot LOGICAL pgoutput EXPORT_SNAPSHOT;

-- 返回：slot_name | consistent_point | snapshot_name
--       my_slot   | 0/16C58E0        | 00000003-0000001B-1
```

这样 CDC 工具（如 Debezium）就能：

1. 创建 slot 拿到 snapshot_id 和 LSN（consistent_point）
2. 用 snapshot_id 在多个 worker 中并行 dump 全量数据
3. 完成后，从 LSN 开始 streaming WAL 增量

整个过程中，**全量 + 增量**严格无缝拼接，不会有重复也不会有丢失。

### 5. 快照的过期与清理

```sql
-- 查看当前活跃的导出快照
SELECT * FROM pg_prepared_xacts;  -- 不直接显示快照
-- 实际上需要查 $PGDATA/pg_snapshots 目录

-- 强制清理（管理员）
SELECT pg_terminate_backend(pid) FROM pg_stat_activity
WHERE backend_xmin IS NOT NULL AND state = 'idle in transaction';
```

**陷阱**：长时间不提交的导出会话会持有一个 `xmin horizon`，阻止 VACUUM 清理已删除的行版本，导致表膨胀。生产环境必须监控 `pg_stat_activity.backend_xmin` 和 `xact_start`。

## MySQL 并行逻辑 dump：mydumper 深度剖析

MySQL InnoDB 的 `START TRANSACTION WITH CONSISTENT SNAPSHOT` 早在 4.0 即已存在，5.6 又添加了与 binlog 位点对齐的增强，提供了**会话内**的一致性快照，但**不能跨会话共享**。这就是 `mydumper`（2010 年由 Domas Mituzas (MySQL/Sun) 与 Mark Leith、Andrew Hutchings 创建，后由 Max Bubenick、David Ducos 维护）解决的核心问题。

### 1. mydumper 的并行模型

```bash
mydumper --threads=8 --outputdir=/backup/mydb \
         --host=db1 --user=admin --password=*** \
         --triggers --events --routines
```

内部流程：

```
1. 主线程连接 MySQL，立即执行：
     SET SESSION wait_timeout = 2147483; -- 防止超时
     SET SESSION net_write_timeout = 2147483;
     LOCK INSTANCE FOR BACKUP;            -- 8.0+ 替代 FTWRL
     # 或老版本：
     FLUSH TABLES WITH READ LOCK;          -- 阻止所有写入

2. 主线程：SHOW MASTER STATUS / SHOW BINARY LOG STATUS
     -- 记录 binlog 文件名和位置（为后续 CDC 用）

3. 主线程 fork 8 个 worker 线程，每个 worker 各自：
     START TRANSACTION WITH CONSISTENT SNAPSHOT;
     -- InnoDB 各自创建快照，但因为此时没有写入（FTWRL 已锁），
     -- 所有 worker 看到的快照视图完全一致

4. 主线程 → UNLOCK TABLES;  (在 worker 都完成 START TX 之后)
     -- 释放全局锁，允许写入恢复
     -- 此时各 worker 已锁定快照，看不到新的写入

5. 主线程把表列表分配给 8 个 worker：
     worker 1 → tbl_a (chunked into 100 sub-tasks of 100K rows each)
     worker 2 → tbl_b
     ...

6. 每个 worker 用 SELECT ... INTO OUTFILE / mysql_store_result + 自定义编码
     写到 /backup/mydb/<schema>.<tbl>.<chunk>.sql.gz

7. 全部完成 → 各 worker COMMIT;
```

### 2. 关键技术点

**(a) 短暂的全局读锁**：FTWRL 会阻塞所有写入。生产数据库要在写入低谷做 mydumper，或用 `--lock-all-tables` 减少锁范围。

**(b) MySQL 8.0 的 `LOCK INSTANCE FOR BACKUP`**：相比 FTWRL 更轻量，只阻塞 DDL 不阻塞 DML，因为 InnoDB consistent snapshot 已经能屏蔽 DML 影响。

**(c) `--rows=N` 表分块**：对单个大表进一步分块，多个 worker 可以并行处理同一张表的不同主键范围。

```bash
mydumper --rows=1000000 --threads=8 ...
# 每张表被切成 100 万行的 chunk，worker 抢占式处理
```

**(d) `--less-locking`**：减少锁持有时间的实验性选项；对 8.0+ 推荐使用 `--no-locks` + `--use-savepoints`。

**(e) CDC 同步点**：`metadata` 文件包含 binlog 位置，下游 CDC 工具可据此从精确位置开始订阅。

### 3. mysqldump 的对比

```bash
# mysqldump 单进程版本
mysqldump --single-transaction --master-data=2 \
          --all-databases > backup.sql
```

`--single-transaction`：

- 内部执行 `START TRANSACTION WITH CONSISTENT SNAPSHOT`，整个 dump 过程是单事务。
- 对 InnoDB 表完美工作，不需要锁。
- 对 MyISAM/Memory 表不生效，仍需 `--lock-tables`。

`--master-data=2`：

- 在 dump 文件开头写入注释格式的 `CHANGE MASTER TO` 语句，记录 binlog 起点。
- `=1` 写入可执行的 `CHANGE MASTER`；`=2` 写入注释，用户自行决定。

**性能对比**：1 TB 数据库，mysqldump 单线程 ~24 小时；mydumper 8 线程 ~3 小时；xtrabackup 物理备份 ~45 分钟。

## 各引擎语法详解

### PostgreSQL（标准实现）

```sql
-- 会话 A：导出快照
BEGIN ISOLATION LEVEL REPEATABLE READ;
SELECT pg_export_snapshot();
-- 返回：00000003-0000001B-1

-- 会话 B：导入快照（必须立即执行）
BEGIN ISOLATION LEVEL REPEATABLE READ;
SET TRANSACTION SNAPSHOT '00000003-0000001B-1';

-- 会话 A 和 B 现在看到的所有表数据完全一致
SELECT count(*) FROM huge_table;  -- 两边返回相同值

-- 完成后会话 A 必须 COMMIT 或 ROLLBACK 来释放快照
COMMIT;

-- 不正确的做法：缺少 BEGIN
SET TRANSACTION SNAPSHOT '...';   -- 错误：没有活跃事务

-- 不正确的做法：READ COMMITTED 不能导入
BEGIN ISOLATION LEVEL READ COMMITTED;
SET TRANSACTION SNAPSHOT '...';   -- 错误：隔离级别不兼容

-- 命令行 pg_dump 自动管理
pg_dump --jobs=8 --format=directory mydb -f /backup
```

### MySQL（会话内一致快照）

```sql
-- 单会话一致性快照
START TRANSACTION WITH CONSISTENT SNAPSHOT;
-- 此事务内所有 SELECT 看到的是事务开始那一刻的数据
SELECT count(*) FROM tbl_a;
SELECT count(*) FROM tbl_b;     -- 与 tbl_a 同一时刻
COMMIT;

-- 不能跨会话传递：
-- MySQL 没有 SET TRANSACTION SNAPSHOT 语法
-- 多会话一致性必须靠 FTWRL + 各自 START TX 同步

-- mysqldump 实战
mysqldump --single-transaction --master-data=2 \
          --routines --triggers --events \
          --all-databases | gzip > /backup/full.sql.gz

-- mydumper 实战
mydumper --threads=16 --rows=500000 \
         --outputdir=/backup/mydb \
         --host=db1 --user=root --password=*** \
         --less-locking
```

### Oracle（基于 SCN 的快照模型）

```sql
-- 会话 A：获取当前 SCN
SELECT DBMS_FLASHBACK.GET_SYSTEM_CHANGE_NUMBER FROM DUAL;
-- 返回：12345678

-- 会话 B（任意时刻）：使用 SCN 复现快照
SELECT * FROM orders AS OF SCN 12345678;

-- 整个事务用 SCN
SET TRANSACTION READ ONLY;
-- 或者
ALTER SESSION SET FLASHBACK_QUERY_VERSION = 12345678;
SELECT * FROM orders;
SELECT * FROM customers;   -- 与上一个查询同一 SCN

-- 用时间戳（内部转 SCN）
SELECT * FROM orders AS OF TIMESTAMP TO_TIMESTAMP('2026-04-25 10:00:00', 'YYYY-MM-DD HH24:MI:SS');

-- expdp 用 FLASHBACK_SCN
expdp scott/tiger FULL=Y FLASHBACK_SCN=12345678 DUMPFILE=full.dmp

-- expdp 用 FLASHBACK_TIME
expdp scott/tiger FULL=Y FLASHBACK_TIME="\"TO_TIMESTAMP('2026-04-25 10:00:00', 'YYYY-MM-DD HH24:MI:SS')\"" DUMPFILE=full.dmp

-- 注意：SCN 必须在 UNDO_RETENTION 窗口内（默认 900s），否则 ORA-01555 snapshot too old
```

### SQL Server（数据库快照模式）

```sql
-- 创建数据库快照（基于 sparse file 的 copy-on-write）
CREATE DATABASE MyDB_Snapshot_20260425
  ON (NAME = MyDB_Data, FILENAME = 'D:\snapshots\MyDB_20260425.ss')
AS SNAPSHOT OF MyDB;

-- 任意会话查询快照
SELECT * FROM MyDB_Snapshot_20260425.dbo.Orders;

-- 注意：
-- 1. 快照与原库共享数据页，写入时 copy-on-write 复制到 sparse file
-- 2. 快照不能 DROP/ALTER 原库（除非先删快照）
-- 3. 完成后 DROP DATABASE MyDB_Snapshot_20260425;

-- 备份方式
BACKUP DATABASE MyDB TO DISK = 'D:\backup\MyDB.bak'
  WITH FORMAT, INIT, COMPRESSION, CHECKSUM;

-- VSS 应用一致性快照（通过 PowerShell / SQL Writer）
-- vssadmin create shadow /for=D:
```

### CockroachDB（HLC 时间戳快照）

```sql
-- 任意会话用 AS OF SYSTEM TIME 复现快照
SELECT * FROM orders AS OF SYSTEM TIME '2026-04-25 10:00:00';

-- 使用偏移
SELECT * FROM orders AS OF SYSTEM TIME '-30s';     -- 30 秒前
SELECT * FROM orders AS OF SYSTEM TIME '-5m';      -- 5 分钟前

-- 整个事务锚定快照
BEGIN AS OF SYSTEM TIME '2026-04-25 10:00:00';
SELECT count(*) FROM tbl_a;
SELECT count(*) FROM tbl_b;
COMMIT;

-- 当前时间戳（用作快照锚点）
SELECT cluster_logical_timestamp();   -- HLC 时间戳，可拷贝给其他会话

-- 并行 SELECT 复制
-- 多个进程独立连接，每个执行：
-- BEGIN AS OF SYSTEM TIME '<同一时间戳>';
-- SELECT * FROM tbl_X WHERE ...
-- 全部数据一致

-- BACKUP 内部使用全局快照
BACKUP DATABASE mydb INTO 's3://backups/full' AS OF SYSTEM TIME '-10s';

-- CHANGEFEED 初始 + 增量
CREATE CHANGEFEED FOR TABLE orders INTO 'kafka://...'
WITH initial_scan, cursor = '<HLC_TS>';
```

### TiDB（基于 TS 的快照）

```sql
-- 会话变量方式
SET @@tidb_snapshot = '2026-04-25 10:00:00';
SELECT * FROM orders;     -- 读取 10:00:00 时刻的数据
SELECT * FROM customers;
SET @@tidb_snapshot = '';  -- 清除，恢复读最新

-- AS OF TIMESTAMP（5.0+）
SELECT * FROM orders AS OF TIMESTAMP '2026-04-25 10:00:00';

-- AS OF TIMESTAMP NOW() - INTERVAL
SELECT * FROM orders AS OF TIMESTAMP NOW() - INTERVAL 30 SECOND;

-- 整个事务
START TRANSACTION READ ONLY AS OF TIMESTAMP '2026-04-25 10:00:00';
SELECT ...;
COMMIT;

-- 获取当前 TSO
SELECT TIDB_CURRENT_TSO();   -- 5.4+

-- BR 工具（备份恢复）使用全局 TSO
br backup full --pd "pd1:2379" --storage "s3://backups/full" \
   --backupts $(date -u '+%Y-%m-%d %H:%M:%S')

-- TiCDC initial scan
cdc cli changefeed create --pd=pd1:2379 \
   --sink-uri="kafka://kafka1:9092/topic" \
   --start-ts=$(tiup ctl:v6.5.0 pd -u pd1:2379 tso 2026-04-25T10:00:00+08:00)
```

### Snowflake（CLONE + Time Travel）

```sql
-- Zero-copy clone：瞬间创建快照表
CREATE TABLE orders_snapshot_20260425 CLONE orders;
-- 不复制数据，只复制元数据指针；后续修改 copy-on-write

-- Time Travel 直接查询历史
SELECT * FROM orders AT(TIMESTAMP => '2026-04-25 10:00:00'::TIMESTAMP);
SELECT * FROM orders AT(OFFSET => -60*5);   -- 5 分钟前
SELECT * FROM orders BEFORE(STATEMENT => '01b1234-...');  -- 某个语句之前

-- 整库克隆
CREATE DATABASE mydb_snapshot CLONE mydb;
-- 也是零拷贝

-- 整 schema 克隆
CREATE SCHEMA mydb.snapshot_20260425 CLONE mydb.public;

-- 注意：Time Travel 默认 1 天（标准版）/ 90 天（企业版）
ALTER TABLE orders SET DATA_RETENTION_TIME_IN_DAYS = 30;

-- 与 EXPORT 配合
COPY INTO @s3stage/snapshot_20260425/
  FROM (SELECT * FROM orders AT(TIMESTAMP => '2026-04-25 10:00:00'::TIMESTAMP))
  FILE_FORMAT = (TYPE = PARQUET);
```

### BigQuery（Snapshot Tables + System Time）

```sql
-- 创建快照表
CREATE SNAPSHOT TABLE mydataset.orders_snapshot_20260425
CLONE mydataset.orders FOR SYSTEM_TIME AS OF '2026-04-25 10:00:00';

-- 直接查询历史
SELECT * FROM mydataset.orders FOR SYSTEM_TIME AS OF '2026-04-25 10:00:00';

-- 默认 7 天 time travel 窗口
-- 企业版可配置 2-7 天

-- EXPORT DATA + Time Travel
EXPORT DATA OPTIONS (
  uri = 'gs://mybucket/orders_*.parquet',
  format = 'PARQUET',
  overwrite = true)
AS
SELECT * FROM mydataset.orders FOR SYSTEM_TIME AS OF '2026-04-25 10:00:00';
```

### Vertica（Epoch 快照）

```sql
-- 查看当前 epoch
SELECT GET_CURRENT_EPOCH();   -- 返回：12345

-- 任意会话用 AT EPOCH 查询
SELECT * FROM orders AT EPOCH 12345;

-- 时间方式
SELECT * FROM orders AT TIME '2026-04-25 10:00:00';

-- 整事务
SET SESSION TIME ZONE 'UTC';
SELECT * FROM orders AT EPOCH LATEST;   -- 最近的 epoch（一致性快照）

-- 并行备份（vbr.py）
/opt/vertica/bin/vbr -t backup -c full_backup.ini
# 内部协调多节点 epoch 一致性
```

### MariaDB（与 MySQL 类似 + System-Versioned）

```sql
-- 会话内一致快照（同 MySQL）
START TRANSACTION WITH CONSISTENT SNAPSHOT;
SELECT * FROM orders;
COMMIT;

-- mariabackup（fork 自 xtrabackup）
mariabackup --backup --target-dir=/backup/full \
            --user=root --password=***

mariabackup --prepare --target-dir=/backup/full

-- 系统版本控制表 + AS OF
CREATE TABLE orders (
  id INT, amount DECIMAL,
  PERIOD FOR SYSTEM_TIME (start_ts, end_ts)
) WITH SYSTEM VERSIONING;

SELECT * FROM orders FOR SYSTEM_TIME AS OF '2026-04-25 10:00:00';
```

### OceanBase（Oracle 兼容的 SCN 模型）

```sql
-- 当前 SCN
SELECT DBMS_FLASHBACK.GET_SYSTEM_CHANGE_NUMBER FROM DUAL;

-- AS OF SCN
SELECT * FROM orders AS OF SCN 12345678;

-- AS OF TIMESTAMP
SELECT * FROM orders AS OF TIMESTAMP '2026-04-25 10:00:00';

-- OBLOADER 并行导出
obloader -h obproxy -P 2883 -u root -t mydb \
   --table orders --threads 16 \
   --output /backup/orders.csv

-- OBDUMPER 整库导出
obdumper -h obproxy -P 2883 -u root -D mydb \
   --threads 32 --output /backup/full
```

### DB2（Currently Committed + Flashback）

```sql
-- 设置隔离级别为 CS + currently committed（默认在 9.7+）
SELECT * FROM orders;     -- 看的是已提交快照

-- 系统时态表
CREATE TABLE orders (
  id INT, amount DECIMAL,
  sys_start TIMESTAMP(12) NOT NULL GENERATED ALWAYS AS ROW BEGIN,
  sys_end TIMESTAMP(12) NOT NULL GENERATED ALWAYS AS ROW END,
  trans_start TIMESTAMP(12) GENERATED ALWAYS AS TRANSACTION START ID,
  PERIOD SYSTEM_TIME (sys_start, sys_end)
);

ALTER TABLE orders ADD VERSIONING USE HISTORY TABLE orders_history;

SELECT * FROM orders FOR SYSTEM_TIME AS OF '2026-04-25 10:00:00';

-- db2move（并行 export）
db2move mydb export -tn 'ORDERS,CUSTOMERS' -c -aw

-- db2 backup online
db2 backup db mydb online to /backup compress include logs
```

### Spanner（Read Timestamp）

```sql
-- 强一致读（最新数据）
@{strong_read=true}
SELECT * FROM Orders;

-- 边界陈旧读
@{max_staleness=10}
SELECT * FROM Orders;       -- 至多 10 秒前的数据

-- 精确时间戳读
@{read_timestamp='2026-04-25T10:00:00Z'}
SELECT * FROM Orders;

-- 通过 API（多会话共享时间戳）
client.snapshot(read_timestamp=specific_ts).execute_sql("SELECT * FROM Orders")
```

### Trino / Presto（连接器级快照）

```sql
-- Iceberg 表
SELECT * FROM iceberg.mydb.orders FOR VERSION AS OF 12345678;
SELECT * FROM iceberg.mydb.orders FOR TIMESTAMP AS OF TIMESTAMP '2026-04-25 10:00:00';

-- Delta Lake
SELECT * FROM delta.mydb.orders FOR TIMESTAMP AS OF '2026-04-25 10:00:00';

-- 创建快照
CALL iceberg.system.create_branch('iceberg.mydb.orders', 'snapshot_20260425');
```

### ClickHouse（Part 不可变 + BACKUP）

```sql
-- 物化的"快照"：BACKUP 内部使用 hard link，瞬间完成
BACKUP DATABASE mydb TO Disk('s3', 'snapshot_20260425/');

-- 部分恢复
RESTORE DATABASE mydb_restored FROM Disk('s3', 'snapshot_20260425/');

-- 利用 ReplicatedMergeTree 的 part 不可变性
-- 用户级"快照"：SELECT 时通过 FINAL 强制看 merged 视图
SELECT * FROM orders FINAL;

-- 没有 SQL 语法的跨会话快照导出
```

## 实战场景：CDC 工具初始化

### Debezium for PostgreSQL（理想范式）

```yaml
# Debezium connector 配置
{
  "name": "pg-orders-connector",
  "config": {
    "connector.class": "io.debezium.connector.postgresql.PostgresConnector",
    "database.hostname": "pg1",
    "database.port": "5432",
    "database.user": "debezium",
    "database.password": "***",
    "database.dbname": "mydb",
    "plugin.name": "pgoutput",
    "slot.name": "debezium",
    "publication.name": "dbz_publication",
    "snapshot.mode": "initial",
    "snapshot.fetch.size": "10240",
    "snapshot.locking.mode": "none",
    "snapshot.isolation.mode": "repeatable_read"
  }
}
```

内部流程：

```
1. 第一次启动：
   - Debezium 连 PG，CREATE PUBLICATION ...
   - CREATE_REPLICATION_SLOT debezium LOGICAL pgoutput EXPORT_SNAPSHOT
   - 拿到 snapshot_id 和 LSN
   - 用 snapshot_id 在 N 个 worker 中并行 SELECT 全量
   - 全量完成后，从 LSN 开始 streaming WAL 增量
2. 后续重启：
   - 直接从最后 ack 的 LSN 继续 streaming
3. 失败恢复：
   - 重置 slot，重新 snapshot；或从 metadata store 的 LSN 续
```

### Debezium for MySQL

```yaml
{
  "snapshot.mode": "initial",
  "snapshot.locking.mode": "minimal",   # 最小化 FTWRL
  "snapshot.fetch.size": "10240"
}
```

流程类似 mydumper：FTWRL → SHOW MASTER STATUS → START TX WITH CONSISTENT SNAPSHOT → 多 worker dump → 释放锁 → 从 binlog 位置续。

### Maxwell

```bash
maxwell --user='maxwell' --password='***' \
        --host='mysql1' --producer=kafka \
        --bootstrap.servers=kafka1:9092 \
        --kafka_topic=maxwell

# 命令行触发 bootstrap（即初始 snapshot）
maxwell-bootstrap --database mydb --table orders
```

### Flink CDC（Hybrid Source）

```sql
-- Flink SQL CDC 表（Hybrid Source: snapshot + binlog）
CREATE TABLE orders_cdc (
  id INT,
  amount DECIMAL(10,2),
  PRIMARY KEY (id) NOT ENFORCED
) WITH (
  'connector' = 'mysql-cdc',
  'hostname' = 'mysql1',
  'port' = '3306',
  'username' = 'flink',
  'password' = '***',
  'database-name' = 'mydb',
  'table-name' = 'orders',
  'scan.startup.mode' = 'initial',          -- 先 snapshot 再 binlog
  'scan.incremental.snapshot.enabled' = 'true',
  'scan.incremental.snapshot.chunk.size' = '8096',
  'server-id' = '5400-5408'
);
```

Flink CDC 2.x 的"增量快照"算法（Netflix DBLog 论文）做到了：

- **无锁快照**：不需要 FTWRL，避免阻塞写入。
- **并行 + 一致**：把表按主键切成多个 chunk，多个 worker 并行 dump；每个 chunk 完成后追平 binlog 该窗口的所有变更。
- **断点续传**：任意时刻失败可从 chunk 边界续。

## 实战场景：跨数据中心数据库迁移

### 零停机迁移：MySQL 5.7 → MySQL 8.0

```bash
# 步骤 1：mydumper 拿一致快照 + 记录 binlog 位置
mydumper --threads=16 --rows=1000000 \
         --outputdir=/backup/migration \
         --host=mysql57 --user=root \
         --less-locking

# /backup/migration/metadata 文件包含 binlog 信息：
# Started dump at: 2026-04-25 10:00:00
# SHOW MASTER STATUS:
#   Log: mysql-bin.000123
#   Pos: 567890
#   GTID: 3E11FA47-71CA-11E1-9E33-C80AA9429562:1-12345

# 步骤 2：myloader 导入到目标库
myloader --threads=16 --directory=/backup/migration \
         --host=mysql80 --user=root

# 步骤 3：基于 binlog 位置启动复制
mysql> CHANGE MASTER TO
       MASTER_HOST='mysql57',
       MASTER_USER='repl',
       MASTER_PASSWORD='***',
       MASTER_LOG_FILE='mysql-bin.000123',
       MASTER_LOG_POS=567890;
mysql> START SLAVE;

# 或者用 GTID
mysql> CHANGE MASTER TO
       MASTER_HOST='mysql57', MASTER_USER='repl', MASTER_PASSWORD='***',
       MASTER_AUTO_POSITION=1;
mysql> START SLAVE;

# 步骤 4：等待复制追平 (Seconds_Behind_Master = 0)，切换 traffic
```

### 零停机迁移：PostgreSQL 跨集群

```bash
# 步骤 1：在源库创建逻辑复制 publication 和 slot（带 snapshot）
psql -h pg-old -d mydb -c "CREATE PUBLICATION migration FOR ALL TABLES;"

# 步骤 2：用 pg_dump --jobs 并行 dump（用 publication 的 snapshot）
# 现代做法：直接用 pg_basebackup + 逻辑复制，或用 pg_dump 的快照
pg_dump --jobs=16 --format=directory --no-owner --no-acl \
        --snapshot=$(echo "...") \
        -h pg-old mydb -f /backup/migration

# 步骤 3：在目标库恢复
pg_restore --jobs=16 -d mydb -h pg-new /backup/migration

# 步骤 4：在目标库创建 subscription（自动从 snapshot 之后续）
psql -h pg-new -d mydb -c "
CREATE SUBSCRIPTION migration_sub
CONNECTION 'host=pg-old dbname=mydb user=repl password=***'
PUBLICATION migration
WITH (copy_data = false);    -- 不重新 copy，因为 pg_dump 已做
"

# 步骤 5：等待追平后切换
```

## 实战场景：分析型 ETL 初值物化

```sql
-- Snowflake 接收 PostgreSQL 全量 + 增量

-- 1. 在 PG 拿快照 + 启 CDC
psql -d mydb << EOF
BEGIN ISOLATION LEVEL REPEATABLE READ;
SELECT pg_export_snapshot();
-- 假设返回：00000003-0000001B-1
EOF

-- 2. 用快照 ID 并行导出到 S3
pg_dump --jobs=32 --format=directory --snapshot=00000003-0000001B-1 \
        -h pg-prod mydb -f - | aws s3 cp - s3://datalake/initial_load/

-- 3. Snowflake COPY INTO 加载
COPY INTO mydb.orders FROM @s3_stage/initial_load/orders/
  FILE_FORMAT = (TYPE = PARQUET);

-- 4. 启动 CDC 工具，从 PG snapshot 之后的 LSN 续
-- (Debezium / Decoderbufs / wal2json / Confluent JDBC)
```

## 关键发现 / Key Findings

### 1. 快照导出是并行 dump 的**必要条件**

没有可分发的快照原语，并行逻辑 dump 工具就无法做到一致性。这就是 PostgreSQL `pg_export_snapshot` / Oracle SCN / CockroachDB HLC / TiDB TSO 等机制存在的根本原因。MySQL 没有跨会话快照分发机制，`mydumper` 只能用 FTWRL "短暂全局锁 + 各自 START TX" 间接同步，相对脆弱。

### 2. PostgreSQL 模型最严谨，但有"长事务"陷阱

`pg_export_snapshot` 设计极其简洁：把内存中的 SnapshotData 序列化成文件。但有副作用：**导出会话必须保持事务开启直到所有 worker 完成**，长时间的 idle in transaction 会抑制 VACUUM，造成表膨胀和复制延迟。生产环境必须监控并设置 `idle_in_transaction_session_timeout`。

### 3. 全局时间戳模型（HLC/SCN/TSO）是分布式数据库的最优解

CockroachDB / Spanner / TiDB / OceanBase 都采用"全局时间戳" 作为快照锚点。优势：

- **无状态共享**：时间戳是数字，可拷贝、可序列化、可跨会话。
- **天然分布式**：每个节点本地决定可见性，不需要"通知"其他会话。
- **可预测**：用户可以指定"3 秒前的快照"，无需 RPC 协调。

PostgreSQL 也在向这个方向发展（`commit_ts` 已经支持 commit timestamp tracking）。

### 4. CDC 的"snapshot 与 binlog/WAL 起点对齐"是工程难点

PostgreSQL 9.4 的 `CREATE_REPLICATION_SLOT ... USE_SNAPSHOT` 把这两步原子化，是行业标杆。MySQL 通过 `FTWRL + SHOW MASTER STATUS + START TX` 间接达成，需要短暂全局锁；MongoDB 的 oplog + snapshot 模式较为优雅；Debezium / Maxwell / Canal / Flink CDC 都封装了这些复杂性。Flink CDC 2.x 的"增量快照"算法（DBLog）甚至做到了无锁并行快照，是最先进的实现。

### 5. Snowflake 的 CLONE 是"快照"的极致形态

零拷贝克隆把"快照"从"数据复制"变成"元数据指针"，瞬间完成、零额外存储成本。这彻底改变了快照的经济学：原本 1 TB 表的快照需要 1 TB 额外空间，CLONE 后是 0 字节（直到对克隆做修改才 copy-on-write）。Databricks Delta Lake、Iceberg、Hudi 等湖仓格式纷纷效仿，因为它们的底层数据就是不可变 Parquet 文件。

### 6. 物理快照 vs 逻辑快照的差异

| 维度 | 物理快照（VFS/Storage） | 逻辑快照（pg_export_snapshot） |
|------|----------------------|---------------------------|
| 速度 | 极快（元数据） | 取决于事务 setup |
| 一致性 | crash-consistent | application-consistent |
| 跨引擎 | 通用 | 引擎特定 |
| 用途 | base backup / 灾难恢复 | dump / CDC / 分析 |
| 与查询配合 | 需要 mount + start engine | 直接 SQL 查询 |

生产环境通常**两者结合**：物理快照（如 EBS snapshot）做 base backup + WAL 归档做 PITR；逻辑快照（pg_export_snapshot）配合 pg_dump 做并行逻辑备份和 CDC 初始化。

### 7. mydumper / Flink CDC / pg_dump --jobs 是"快照导出"在不同生态的旗帜实现

- **pg_dump --jobs**（PostgreSQL 9.3，2013）：第一个把 `pg_export_snapshot` 用到生产级并行 dump 的工具，定义了行业范式。
- **mydumper**（2010）：在 MySQL 没有跨会话快照原语的情况下，用 FTWRL + 多线程实现并行一致 dump，比 mysqldump 快 5-10 倍。
- **Flink CDC 2.x（2021）**：基于 Netflix DBLog 论文实现"无锁增量快照"，把传统的"FTWRL + dump + binlog 续传"流程升级为"chunk-by-chunk + per-chunk binlog catch-up"，对生产负载几乎无影响。

### 8. 商业引擎与开源引擎的差距正在缩小

10 年前，"快照导出"是商业数据库（Oracle Flashback / SQL Server Snapshot Database）的差异化能力。今天，PostgreSQL / MySQL / CockroachDB / TiDB 都有了对等甚至更先进的实现（CRDB 的 HLC 模型 / TiDB 的 TSO 模型）。云原生数据库（Snowflake / BigQuery / Spanner）通过托管平台把这些复杂性完全隐藏，用户感觉不到。

### 9. 对 SQL 标准化的呼声

虽然 SQL:2023 仍未涉及"导出快照"，但事实标准已经形成：

- `BEGIN ISOLATION LEVEL REPEATABLE READ` + `pg_export_snapshot()` + `SET TRANSACTION SNAPSHOT '<id>'` 这套 PostgreSQL 模型最有可能被未来标准化。
- `AS OF TIMESTAMP / SCN / SYSTEM TIME` 已经是事实通用语法，被 Oracle / TiDB / OceanBase / CockroachDB / BigQuery 共同采用。

未来 SQL 标准很可能借鉴这两套模型，定义 `EXPORT SNAPSHOT` / `SET TRANSACTION SNAPSHOT` 标准语法。

### 10. 对引擎开发者的建议

- **MVCC 引擎**应当从一开始就设计"快照导出"原语：把 SnapshotData 序列化成 ID + 提供 SET 语法。这是并行 dump、CDC、ETL 的基础设施。
- **优先采用全局时间戳模型**：HLC / SCN / TSO 的可序列化、可分发、可预测特性远优于"内存中状态"模型。
- **CDC 集成**：考虑提供"创建 slot 同时拿 snapshot" 的原子化原语，参考 PG `CREATE_REPLICATION_SLOT ... USE_SNAPSHOT`。
- **湖仓格式**应当全面支持 Time Travel 查询（FOR VERSION/TIMESTAMP AS OF），这是云原生分析的基础语义。
- **监控**：暴露快照持有时长、xmin horizon、长事务影响 VACUUM 的指标，避免无声的性能退化。

## 参考资料

- PostgreSQL: [pg_export_snapshot](https://www.postgresql.org/docs/current/functions-admin.html#FUNCTIONS-SNAPSHOT-SYNCHRONIZATION)
- PostgreSQL: [SET TRANSACTION SNAPSHOT](https://www.postgresql.org/docs/current/sql-set-transaction.html)
- PostgreSQL: [pg_dump --jobs](https://www.postgresql.org/docs/current/app-pgdump.html)
- PostgreSQL: [CREATE_REPLICATION_SLOT](https://www.postgresql.org/docs/current/protocol-replication.html)
- MySQL: [START TRANSACTION WITH CONSISTENT SNAPSHOT](https://dev.mysql.com/doc/refman/8.0/en/commit.html)
- MySQL: [mysqldump --single-transaction](https://dev.mysql.com/doc/refman/8.0/en/mysqldump.html)
- mydumper: [GitHub mydumper/mydumper](https://github.com/mydumper/mydumper)
- Oracle: [Flashback Query (AS OF SCN/TIMESTAMP)](https://docs.oracle.com/en/database/oracle/oracle-database/19/adfns/flashback.html)
- SQL Server: [Database Snapshots](https://learn.microsoft.com/en-us/sql/relational-databases/databases/database-snapshots-sql-server)
- CockroachDB: [AS OF SYSTEM TIME](https://www.cockroachlabs.com/docs/stable/as-of-system-time.html)
- TiDB: [Stale Read / AS OF TIMESTAMP](https://docs.pingcap.com/tidb/stable/stale-read)
- Snowflake: [CLONE](https://docs.snowflake.com/en/sql-reference/sql/create-clone), [Time Travel](https://docs.snowflake.com/en/user-guide/data-time-travel)
- BigQuery: [Snapshot Tables](https://cloud.google.com/bigquery/docs/table-snapshots-intro), [FOR SYSTEM_TIME AS OF](https://cloud.google.com/bigquery/docs/time-travel)
- Spanner: [Read Timestamps](https://cloud.google.com/spanner/docs/timestamp-bounds)
- Debezium: [Snapshot Configuration](https://debezium.io/documentation/reference/stable/connectors/postgresql.html#postgresql-snapshots)
- Flink CDC: [Incremental Snapshot Algorithm](https://github.com/ververica/flink-cdc-connectors/wiki/Design-Of-MySQL-CDC-Connector)
- Netflix DBLog: ["DBLog: A Watermark Based Change-Data-Capture Framework"](https://arxiv.org/abs/2010.12597) (2020)
- Vertica: [Epoch Management](https://www.vertica.com/docs/latest/HTML/Content/Authoring/AdministratorsGuide/Managing/Epochs/EpochManagement.htm)
