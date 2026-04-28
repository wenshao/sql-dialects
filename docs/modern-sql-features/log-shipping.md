# 日志传送 (Log Shipping)

很多人把"日志传送"和"流复制"混为一谈。它们都依赖 WAL/redo/binlog，但实现路径根本不同：**流复制**通过持久网络连接把字节流推给副本（或副本主动拉取），延迟在毫秒级；**日志传送**则等到一个完整的日志段（PostgreSQL 16MB 的 WAL 段、SQL Server 的事务日志备份文件、Oracle 的归档 redo log）写满后，把它作为一个文件**复制**到备机的归档目录，再由备机的 `restore_command` 顺序回放。这种"以文件为单位"的传输方式是 21 世纪初最早的 warm standby 解决方案，也是今天 WAL 归档 + PITR 的物理基础。本文系统梳理 45+ 数据库引擎的日志传送实现：PostgreSQL 自 8.0 (2005) 引入的 `archive_command` + `restore_command`、SQL Server 自 2000 版起的 Log Shipping (sp_add_log_shipping*)、Oracle 8i 的 FAL_CLIENT/FAL_SERVER 机制、DB2 的 LOGARCHMETH 双通道，以及 Barman / pgBackRest / wal-g 等生态工具如何把"复制文件"这件简单的事做到生产可用。

> 这是一篇写给 DBA、SRE 和引擎开发者的深度参考。本文聚焦"按段传送原始 WAL/redo 文件"的 warm standby 实现，与 `wal-archiving.md`（PITR 与归档完整性）、`logical-decoding.md`（行级事件解码）、`logical-replication-gtid.md`（DDL 级发布订阅）形成互补。日志传送**不是 CDC，不是逻辑复制**——它发送的是物理字节，不解析事务、不重写为 SQL，备机看到的是和主库完全一致的二进制副本。

## 日志传送：定义、与流复制的关系，以及和逻辑复制的本质区别

要理解日志传送，必须先把它和三种容易混淆的机制划清界限：

1. **流复制（Streaming Replication）**：源端通过长连接（PostgreSQL 的 walsender 协议、MySQL 的 binlog dump 协议、Oracle Data Guard 的 LGWR SYNC/ASYNC、SQL Server AlwaysOn 的 endpoint）把 WAL/redo 字节实时推送给备机。延迟可低至几毫秒，但需要稳定的网络连接，源备网络抖动会立刻表现为复制滞后。
2. **日志传送（Log Shipping）**：源端把**写满的整个日志段**作为文件单位（filesystem 文件、对象存储对象、归档介质），通过 `cp`/`scp`/`rsync`/`s3 cp` 等任意外部工具复制到备机能访问到的位置；备机周期性扫描或被动接收，发现新文件就 replay。延迟以"段切换间隔 + 复制时间"为粒度，通常 30 秒到几分钟。优点是**对网络要求极低**——只要文件能传过去就行，断网恢复后断点续传。
3. **逻辑复制（Logical Replication）/ CDC**：源端把 WAL/binlog **解码**为行级事件（INSERT/UPDATE/DELETE 的列值），发给下游。下游可以是异构数据库、Kafka、搜索引擎。延迟视下游而定，但语义上是"应用层重做"，不是字节副本。

| 维度 | 流复制 | 日志传送 | 逻辑复制 |
|------|--------|---------|---------|
| 传输单位 | 字节流 | 整个日志段文件 | 行级事件（已解码） |
| 网络要求 | 长连接、低抖动 | 任意（一次性 cp） | 长连接，但中断可恢复 |
| 延迟 | 毫秒 | 30 秒 - 数分钟 | 秒级 |
| 备机用途 | hot standby (可读) | warm standby (恢复中) | 同构/异构同步 |
| 内容损耗 | 无 | 无（与主库二进制一致） | 仅可见列、仅 DML |
| 跨大版本 | 否（必须同版本） | 否（必须同版本） | 是（典型用法） |
| DDL 自动同步 | 是 | 是 | 多数引擎不完整 |
| 跨架构（x86↔ARM） | 否（多数引擎不支持） | 否 | 是 |
| 跨字节序 | 否 | 否 | 是 |
| 主库故障对备机的影响 | 立刻知晓（连接断） | 不知晓（直到下次 fetch 失败） | 立刻知晓 |
| 反压 | 主库感知 | 主库不感知 | 主库感知 |

**为什么日志传送至今仍重要？** 即便流复制已成主流，日志传送依然在三类场景中不可替代：

- **跨数据中心、跨机房的容灾**：源备之间没有稳定 VPN / 专线，但有共享对象存储或 NFS。
- **WAL 归档的副产品**：既然你已经把 WAL 段归档到 S3 用于 PITR，那么让另一个集群从 S3 拉取就近恢复几乎零额外成本。
- **流复制 + 日志传送双保险**：流复制做实时同步、日志传送做断网兜底。这是金融、电信生产环境最常见的"双轨"模式（PostgreSQL 高可用最佳实践、Oracle Data Guard Maximum Performance 都是这个思路）。

## 没有 SQL 标准

和 WAL 本身一样，日志传送完全是实现定义的，**ISO/IEC 9075 标准从未涉及**。各引擎从术语到机制都不同：

- **PostgreSQL** 称之为 *log shipping* / *file-based standby*，由 `archive_command` 推、`restore_command` 拉构成闭环。
- **SQL Server** 把它做成显式产品功能：*Log Shipping*，由三个 SQL Agent 作业（backup、copy、restore）协作。
- **Oracle** 称之为 *Managed Recovery* + *FAL (Fetch Archive Log)*，配合 Data Guard 或直接手工 `RECOVER MANAGED STANDBY DATABASE`。
- **DB2** 称之为 *log shipping standby* 或 *HADR with log archive*，依赖 `LOGARCHMETH1/2`。
- **MySQL/MariaDB** 没有"日志传送"这个产品名，但通过 *binlog backup + relay log replay* 可以模拟；社区一般直接走流复制。
- **Snowflake / BigQuery / Spanner** 完全托管，不暴露日志传送概念。

| 引擎 | 官方术语 |
|------|---------|
| PostgreSQL | Log Shipping / Archive Recovery / File-based Standby |
| SQL Server | Log Shipping (产品功能名) |
| Oracle | Managed Recovery + FAL |
| DB2 | Log Shipping Standby / HADR |
| MySQL | Binary Log Backup / Manual Failover |
| MariaDB | 同 MySQL |
| Informix | HDR (High-availability Data Replication) |
| Sybase ASE | Replication via Log Transfer Manager (LTM) |
| Teradata | Standby + Permanent Journal apply |
| SAP HANA | System Replication ASYNC log shipping mode |

## 支持矩阵（45+ 引擎）

### 1. 文件级日志传送（按段复制）

| 引擎 | 原生支持 | 推送方式 | 拉取方式 | 起始版本 |
|------|---------|---------|---------|---------|
| PostgreSQL | 是 | archive_command | restore_command | 8.0 (2005) |
| MySQL | 模拟 | 外部 cp/rsync binlog | mysqlbinlog \| mysql | 5.0+ (binlog) |
| MariaDB | 模拟 | 外部 cp/rsync | mysqlbinlog | 早期 |
| SQLite | 否 | -- | -- | -- |
| Oracle | 是 | LOG_ARCHIVE_DEST_n LOCATION | FAL_SERVER 拉 / 外部脚本 | 8i (1998) |
| SQL Server | 是 | BACKUP LOG → file share | RESTORE LOG WITH NORECOVERY | 2000 |
| DB2 | 是 | LOGARCHMETH1 DISK:/share | db2 rollforward | v8 (2003) |
| Snowflake | 内建 | 隐藏 | 隐藏 | GA |
| BigQuery | 内建 | 隐藏 | 隐藏 | GA |
| Redshift | 内建 | 自动快照 | RESTORE FROM | GA |
| DuckDB | 否 | -- | -- | -- |
| ClickHouse | 部分 | ReplicatedMergeTree (基于 ZooKeeper) | -- | 20.x+ |
| Trino | -- | 计算引擎 | -- | -- |
| Presto | -- | 计算引擎 | -- | -- |
| Spark SQL | -- | 计算引擎 | -- | -- |
| Hive | -- | 不适用 | -- | -- |
| Flink SQL | -- | Checkpoint (非 PITR) | -- | -- |
| Databricks | 内建 | Delta Lake transaction log | -- | GA |
| Teradata | 是 | 归档到 mass storage | ARC 还原 | 早期 |
| Greenplum | 是 | 继承 PG (per segment) | 继承 PG | 5.0+ |
| CockroachDB | 模拟 | BACKUP INTO + revision_history | RESTORE FROM | 21.1+ |
| TiDB | 模拟 | br log start (持续推 S3) | br restore point | 5.4+ (2022) |
| OceanBase | 是 | OBBackup archive log | OBBackup restore | 3.x+ |
| YugabyteDB | 部分 | 基于 Raft + snapshot schedule | yb-admin restore | 2.14+ |
| SingleStore | 是 | log backup → blob | RESTORE | 7.0+ |
| Vertica | 是 | vbr.py copy | vbr.py restore | 9.0+ |
| Impala | -- | 依赖 HMS | -- | -- |
| StarRocks | 部分 | BACKUP TO repo | RESTORE FROM | 2.5+ |
| Doris | 部分 | BACKUP/RESTORE | -- | 1.2+ |
| MonetDB | 否 | 仅 dump | -- | -- |
| CrateDB | 部分 | snapshot to repository | restore snapshot | 4.0+ |
| TimescaleDB | 是 | 继承 PG | 继承 PG | 继承 PG |
| QuestDB | 部分 | 文件复制 | -- | 7.x+ |
| Exasol | 是 | EXAoperation backup | EXAoperation restore | 6.x+ |
| SAP HANA | 是 | log backup → backint / file | log replay | 1.0+ |
| Informix | 是 | ontape -a / ON-Bar | ontape -r | 早期 |
| Sybase ASE | 是 | DUMP TRAN | LOAD TRAN | 早期 |
| Firebird | 部分 | nbackup + replication | nbackup -r | 2.5+ |
| H2 | 否 | -- | -- | -- |
| HSQLDB | 否 | -- | -- | -- |
| Derby | 否 | -- | -- | -- |
| Amazon Athena | -- | 计算引擎 | -- | -- |
| Azure Synapse | 是 | 基于 SQL Server 底层 | 基于 SQL Server | GA |
| Google Spanner | 内建 | 隐藏 | 隐藏 | GA |
| Materialize | -- | -- | -- | -- |
| RisingWave | -- | -- | -- | -- |
| InfluxDB | 部分 | influx backup | influx restore | 2.x+ |
| DatabendDB | 部分 | 对象存储增量 | 时间点查询 | GA |
| Yellowbrick | 是 | 基于 PG | 基于 PG | GA |
| Firebolt | 内建 | 自动 time travel | 隐藏 | GA |

> 统计：约 22 个引擎提供生产级文件级日志传送，约 8 个托管系统隐藏在产品背后。

### 2. 推送/拉取占位符与命令钩子

| 引擎 | 推送钩子 | 拉取钩子 | 占位符 | 说明 |
|------|---------|---------|-------|------|
| PostgreSQL | archive_command | restore_command | %p (路径) %f (文件名) %r (最早需保留段) | shell 命令，必须返回 0 |
| PostgreSQL 15+ | archive_library | (同上) restore_command | (库内 API) | 动态加载 C 库 |
| Oracle | LOG_ARCHIVE_DEST_n | FAL_SERVER / FAL_CLIENT | %t (thread) %s (sequence) %r (resetlogs) | 由 ARCH/RFS 进程使用 |
| SQL Server | BACKUP LOG (调度作业) | RESTORE LOG (调度作业) | -- | 由三个作业链协调 |
| DB2 | LOGARCHMETH1/2 | db2 rollforward | -- | 双通道 |
| MySQL | -- (无原生 hook) | -- | -- | 需外部脚本 |
| Informix | ALARMPROGRAM | restore | -- | shell 脚本 |
| Sybase | log_dump_path | load tran | -- | -- |

PostgreSQL 的占位符是最经典的设计：

- `%p` — WAL 段在 `pg_wal/` 中的相对路径，archive_command 用来定位源文件。
- `%f` — WAL 段文件名（24 字节十六进制，如 `000000010000000000000042`）。
- `%r` — restore_command 中表示当前恢复目标允许丢弃的最早段，方便归档清理。

```ini
# postgresql.conf - 主库
archive_mode = on
archive_command = 'rsync -aq %p standby:/mnt/wal_archive/%f'

# postgresql.conf / postgresql.auto.conf - 备库
restore_command = 'cp /mnt/wal_archive/%f %p'
recovery_end_command = 'rm -f /mnt/wal_archive/%r.*'
```

Oracle 的占位符更复杂，因为 Oracle 支持多个线程（RAC）和多个化身（incarnation）：

```sql
ALTER SYSTEM SET log_archive_format = 'arch_%t_%s_%r.arc' SCOPE=SPFILE;
-- %t = thread, %s = sequence, %r = resetlogs id
ALTER SYSTEM SET log_archive_dest_1 = 'LOCATION=/u01/arch MANDATORY';
ALTER SYSTEM SET log_archive_dest_2 = 'SERVICE=standby_db ARCH';
```

### 3. FAL（Fetch Archive Log）服务器机制

Oracle 独特的"拉缺失日志"能力。当备库发现归档日志中存在序号空缺（gap），不是被动等待主库再次发送，而是**主动通过 FAL_SERVER 拉取缺失的日志**：

| 引擎 | gap detection | gap resolution | 起始版本 |
|------|---------------|----------------|---------|
| Oracle | 是 (V$ARCHIVE_GAP) | FAL_CLIENT/FAL_SERVER 自动 | 8i (1998) |
| PostgreSQL | 否（按序号 restore_command） | 通过共享归档自然解决 | 8.0+ |
| SQL Server | 是（log chain LSN 检查） | 手工补齐缺失 .trn | 2000+ |
| DB2 | 是（rollforward gap） | 手工 db2 rollforward | v8+ |
| MySQL | 是（binlog file:pos 检查） | 主从复制不会自动补 | 早期 |
| MariaDB | 是（GTID 检查） | 是（GTID 自动 catch-up） | 10.0+ |

Oracle 的 FAL 配置：

```sql
-- 主库
ALTER SYSTEM SET FAL_SERVER = 'standby_db' SCOPE=BOTH;
ALTER SYSTEM SET FAL_CLIENT = 'primary_db' SCOPE=BOTH;

-- 备库
ALTER SYSTEM SET FAL_SERVER = 'primary_db' SCOPE=BOTH;
ALTER SYSTEM SET FAL_CLIENT = 'standby_db' SCOPE=BOTH;

-- 检测 gap
SELECT * FROM V$ARCHIVE_GAP;
-- THREAD#  LOW_SEQUENCE#  HIGH_SEQUENCE#
-- 1        1023           1027
-- 表示线程 1 的归档日志 1023-1027 缺失
```

发现 gap 时备库会通过 net service name 连到 FAL_SERVER（通常就是主库），用 RFS 协议拉缺失段。这避免了"主库已 truncate 该段、备库永远 catch-up 不上"的死锁。

### 4. SQL Server Log Shipping 的三作业架构

SQL Server 把日志传送做成显式产品功能，由三个 SQL Agent 作业组成：

| 作业 | 部署位置 | 工作内容 | 默认间隔 |
|------|---------|---------|---------|
| Backup Job | 主库 | `BACKUP LOG ... TO ...` 到共享路径 | 15 分钟 |
| Copy Job | 备库 | 从共享路径 `xcopy` 到本地待恢复目录 | 15 分钟 |
| Restore Job | 备库 | `RESTORE LOG ... WITH NORECOVERY/STANDBY` | 15 分钟 |

```sql
-- 主库：启用 Log Shipping
EXEC msdb.dbo.sp_add_log_shipping_primary_database
    @database = N'AdventureWorks',
    @backup_directory = N'\\fileserver\logship\AW',
    @backup_share = N'\\fileserver\logship\AW',
    @backup_job_name = N'LSBackup_AdventureWorks',
    @backup_retention_period = 4320,       -- 分钟
    @monitor_server = N'MONITOR\SQL',
    @monitor_server_security_mode = 1;

-- 备库：注册 secondary
EXEC msdb.dbo.sp_add_log_shipping_secondary_primary
    @primary_server = N'PROD-SQL01',
    @primary_database = N'AdventureWorks',
    @backup_source_directory = N'\\fileserver\logship\AW',
    @backup_destination_directory = N'D:\Logship\Copy',
    @copy_job_name = N'LSCopy_PROD-SQL01_AdventureWorks',
    @restore_job_name = N'LSRestore_PROD-SQL01_AdventureWorks',
    @file_retention_period = 4320,
    @monitor_server = N'MONITOR\SQL',
    @monitor_server_security_mode = 1;

EXEC msdb.dbo.sp_add_log_shipping_secondary_database
    @secondary_database = N'AdventureWorks',
    @primary_server = N'PROD-SQL01',
    @primary_database = N'AdventureWorks',
    @restore_delay = 0,
    @restore_mode = 1,             -- 1 = STANDBY (read-only), 0 = NORECOVERY
    @disconnect_users = 1,         -- 必要时踢掉 read-only 用户
    @restore_threshold = 45,
    @threshold_alert_enabled = 1;
```

### 5. RPO（数据丢失目标）

| 引擎 | 默认日志传送 RPO | 推流复制 RPO | 同步复制 RPO |
|------|----------------|-------------|-------------|
| PostgreSQL | archive_timeout（默认 0=关闭，建议 60s） | 几毫秒 | 0 (synchronous_commit=on) |
| Oracle | 一个 redo log group 切换间隔 | 几毫秒 | 0 (Maximum Protection) |
| SQL Server | 15 分钟 (默认 backup interval) | 几毫秒 | 0 (AlwaysOn synchronous) |
| DB2 | 一个 log file 切换间隔 | 几毫秒 | 0 (HADR SYNC) |
| MySQL | binlog_expire_logs_seconds + 备份间隔 | 几毫秒 | 0 (semisync) |

PostgreSQL 默认 `archive_timeout = 0` 意味着归档不会主动切段，活跃度低的库可能数小时没有归档。生产环境建议 `archive_timeout = 60`（最多丢 60 秒数据）。

### 6. RTO（恢复时间目标）

| 引擎 | warm standby 切换 | hot standby 切换 |
|------|------------------|-----------------|
| PostgreSQL | 数秒（promote） | 几秒 (read-only 直接 promote) |
| Oracle Data Guard | 数秒（switchover） | 数秒 (failover) |
| SQL Server Log Shipping | 30秒-几分钟 (RESTORE WITH RECOVERY + DNS 切换) | 数秒 (AlwaysOn) |
| DB2 HADR | 数秒 (TAKEOVER HADR) | 数秒 |

### 7. 备机可读性（standby 是否可查询）

| 引擎 | 日志传送中可读 | 模式 |
|------|--------------|------|
| PostgreSQL | 是 (PG 9.0+ Hot Standby) | hot_standby = on |
| Oracle | 是 (Active Data Guard) | OPEN READ ONLY WITH APPLY |
| SQL Server | 是 (STANDBY mode) | RESTORE WITH STANDBY |
| DB2 | 是 (HADR Reads on Standby) | DB2_HADR_ROS |
| MySQL relay | 是（直接当从库） | 主从架构 |

SQL Server 的 STANDBY 模式特殊：每次 `RESTORE LOG` 时连接会被踢掉（`@disconnect_users = 1`），还原期间数据库不可查询。这种"只读但定期断线"的模式不适合 24×7 报表场景，是 Log Shipping 相比 AlwaysOn 的主要劣势。

### 8. 监控视图与状态查询

| 引擎 | 视图 / 命令 | 关键指标 |
|------|------------|---------|
| PostgreSQL | `pg_stat_archiver` | last_archived_wal, failed_count |
| PostgreSQL | `pg_last_wal_replay_lsn()` | 备库回放进度 |
| PostgreSQL | `pg_last_xact_replay_timestamp()` | 备库回放时间戳 |
| Oracle | `V$ARCHIVED_LOG` | 归档日志列表 |
| Oracle | `V$ARCHIVE_GAP` | 缺失序号区间 |
| Oracle | `V$DATAGUARD_STATUS` | DG 状态 |
| SQL Server | `msdb..log_shipping_monitor_history_detail` | 历史明细 |
| SQL Server | `msdb..log_shipping_monitor_alert` | 阈值告警 |
| DB2 | `db2 list history rollforward` | 回滚前进历史 |
| DB2 | `db2pd -hadr` | HADR 状态 |
| MySQL | `SHOW SLAVE STATUS` (8.0+ `SHOW REPLICA STATUS`) | Seconds_Behind_Master |

### 9. 与流复制的协同

| 引擎 | 同时启用流复制和日志传送 | 优先级 |
|------|------------------------|-------|
| PostgreSQL | 是（标准最佳实践） | 流复制优先，日志传送兜底 |
| Oracle Data Guard | 是（多种 redo transport mode） | LGWR SYNC > LGWR ASYNC > ARCH |
| SQL Server | Log Shipping 与 AlwaysOn 互斥（同一 DB 不可同时） | -- |
| SQL Server | 不同 DB 可分别用 | -- |
| DB2 | HADR + log shipping 可并存（异构 standby） | HADR 优先 |
| MySQL | 流复制 + binlog 备份 | 流复制 + 备份兜底 |

PostgreSQL 推荐"流复制 + 日志传送"双轨模式：

```ini
# 备库 postgresql.conf
primary_conninfo = 'host=primary port=5432 user=replica'
restore_command = 'cp /mnt/wal_archive/%f %p'
# 流复制断开时，备库自动 fallback 到 restore_command
```

这样备库连接断开时不会立刻 stuck，而是从共享归档继续 catch-up，连接恢复后又切回流式。

### 10. 工具生态

| 工具 | 引擎 | 作用 | 维护方 |
|------|------|------|-------|
| pgBackRest | PostgreSQL | archive-push / archive-get + 备份 | Crunchy Data (2013+) |
| wal-g | PostgreSQL/MySQL | wal-push / wal-fetch + 备份 | Yandex (2017+) |
| Barman | PostgreSQL | barman cron + cron get-wal | EDB (2011+) |
| repmgr | PostgreSQL | failover 协调 + 流复制管理 | EDB |
| Patroni | PostgreSQL | etcd-backed HA + 调用归档工具 | Zalando |
| Percona XtraBackup | MySQL | 物理备份 + binlog 拉取 | Percona |
| MariaDB mariabackup | MariaDB | XtraBackup fork | MariaDB Foundation |
| Oracle RMAN | Oracle | 备份/归档管理一体化 | Oracle |
| Oracle Data Guard Broker | Oracle | DG 配置自动化 | Oracle |
| IBM Spectrum Protect (TSM) | DB2 | 归档介质 | IBM |
| Litestream | SQLite | WAL 镜像到 S3 | Ben Johnson (2021+) |

## PostgreSQL：最经典的文件级日志传送

PostgreSQL 自 8.0 (2005 年 1 月) 引入 `archive_mode` + `archive_command` 后，文件级日志传送成为业界第一个开源的 warm standby 标准。9.0 (2010) 引入 streaming replication 之后，两种机制并存至今。

### 主库配置

```ini
# postgresql.conf
wal_level = replica
archive_mode = on
archive_command = '
    set -e
    test ! -f /mnt/wal_archive/%f
    cp %p /mnt/wal_archive/%f.tmp
    sync -f /mnt/wal_archive/%f.tmp
    mv /mnt/wal_archive/%f.tmp /mnt/wal_archive/%f
'
archive_timeout = 60          # 强制每 60s 切段，避免低活跃时延迟过高
max_wal_size = 4GB
```

`archive_command` 是 shell 字符串，PostgreSQL 在每个 WAL 段写满后用 `system()` 调用它。返回 0 才认为归档成功，否则**无限重试**（带指数退避）。这意味着：

- 命令必须**幂等**（重复执行不出错）。
- 命令应该**原子写**（先写 tmp 再 rename，避免半文件）。
- 命令必须**异地复制**（本地 cp 没有容灾意义）。

经典反例：

```bash
# 错误 1：不检测目标已存在
archive_command = 'cp %p /mnt/wal/%f'
# 重启时如果同名文件已部分存在，可能覆盖正确数据。

# 错误 2：使用 mv 而非 cp
archive_command = 'mv %p /mnt/wal/%f'
# pg_wal/ 中的源文件被移走会破坏 PostgreSQL 内部状态。

# 错误 3：忘记 sync
archive_command = 'cp %p /mnt/wal/%f'
# 系统崩溃时已写但未刷盘的归档可能丢失。
```

### 备库配置（PG 11 及更早：recovery.conf）

```ini
# recovery.conf （位于 PGDATA/，PG 11 及以下）
standby_mode = 'on'
restore_command = 'cp /mnt/wal_archive/%f %p'
recovery_target_timeline = 'latest'
trigger_file = '/tmp/promote_me'    # touch 该文件即 promote
```

### 备库配置（PG 12+：postgresql.auto.conf + signal 文件）

PG 12 把 recovery.conf 合并到 postgresql.conf 后，备库的"启动模式"靠两个空文件区分：

```ini
# postgresql.auto.conf
restore_command = 'cp /mnt/wal_archive/%f %p'
recovery_target_timeline = 'latest'
```

```bash
touch $PGDATA/standby.signal       # 持续 replay，等待 promote
# 或
touch $PGDATA/recovery.signal      # 一次性 PITR 到目标后 promote
```

### archive_timeout 的设计权衡

```
archive_timeout = 0    : 禁用，活跃低时可能数小时不归档（丢数据风险大）
archive_timeout = 60   : 每 60 秒强制切段，最多丢 60 秒数据
archive_timeout = 30   : 每 30 秒切段，丢失更少但小段过多消耗 inode

---
副作用：每次切段会写一个完整的 16MB 段（即使只有几 KB 数据），
归档存储会有大量"几乎空"的段。生产环境推荐配合 archive_command 自动压缩。
```

### restore_command 的工作模式

PostgreSQL 备库启动后：

1. 从最近的 base backup 恢复出数据文件。
2. 调用 `restore_command` 拉第一个 WAL 段（参数 `%f` 由 PostgreSQL 内部递增计算）。
3. 段就位后，PostgreSQL replay 直到段尾。
4. 接着调用 `restore_command` 拉下一段。
5. 当 `restore_command` 返回非零时（通常意味着段还不存在），如果有 `standby.signal`，备库等待若干秒重试；否则结束恢复进入 promoted 状态。

```bash
restore_command = '
    if test -f /mnt/wal_archive/%f.gz; then
        gzip -dc /mnt/wal_archive/%f.gz > %p
    elif test -f /mnt/wal_archive/%f; then
        cp /mnt/wal_archive/%f %p
    else
        exit 1     # 文件还不存在，让 PG 等待
    fi
'
```

### archive_library（PG 15+）

PG 15 引入 `archive_library`，把归档钩子从 shell 命令改为可加载的 C 库，避免每段都 fork+exec：

```ini
# postgresql.conf
archive_mode = on
archive_library = 'basic_archive'
basic_archive.archive_directory = '/mnt/wal_archive'
```

`basic_archive` 是官方 contrib，功能等价于 `cp`。第三方工具如 pgBackRest 和 wal-g 已陆续提供自己的 archive_library 版本。在高 TPS 场景下（每秒切多个 WAL 段），shell 调用的 fork/exec 开销可能占总 CPU 的 5%-10%，archive_library 把这部分消除。

### 与流复制的混合：兜底归档

PostgreSQL 9.0 起的标准最佳实践是**主库同时开归档 + 备库同时启用流和 restore_command**：

```ini
# 备库 postgresql.auto.conf
primary_conninfo = 'host=primary port=5432 user=replicator password=...'
restore_command = 'cp /mnt/wal_archive/%f %p'
recovery_target_timeline = 'latest'
```

```bash
touch $PGDATA/standby.signal
```

工作流：

1. 启动时备库先 base backup 恢复，然后调用 `restore_command` 拉至归档中最新段。
2. 切到流复制（`primary_conninfo` 建立 walreceiver 连接）。
3. 流连接断开时（网络抖动、主库重启），备库回到 `restore_command` 模式继续 replay。
4. 流恢复后又切回流式。

这种"双轨"模式让备库可以**任意时间断网**几小时甚至几天，恢复后自动 catch-up，无需重做 base backup。

### pg_receivewal：流式归档（替代 archive_command）

PostgreSQL 9.2 引入的 `pg_receivewal`（旧名 `pg_receivexlog`）允许从主库**流式拉 WAL** 到本地，作为归档的替代或补充：

```bash
pg_receivewal -D /mnt/wal_archive -h primary -U replicator \
    --slot=archive_slot --synchronous
```

特点：

- 通过物理复制槽（`--slot`）保证主库不会回收未归档的段。
- `--synchronous` 让 pg_receivewal 充当同步副本，主库提交时等其 fsync 落盘。
- 段写入归档目录，下游备库的 `restore_command` 直接消费。
- 比 `archive_command` 延迟低（流式而非段切换才推送）。

## SQL Server Log Shipping 内部架构

SQL Server 自 2000 版（Enterprise Edition）起把 Log Shipping 做成显式产品功能。2005 改造为 GUI + sp_add_log_shipping_* 系列 SP，沿用至今。

### 基本结构：3 作业 + 1 监控

```
+-------------+              +--------------+              +-------------+
|  Primary    |              |  File Share  |              |  Secondary  |
|             |              |              |              |             |
|  [Backup    |---BACKUP--->[ AW_log_*.trn ]<---xcopy------|  [Copy      |
|   Job]      |   LOG       |              |              |   Job]      |
|             |             |              |              |             |
|             |             |              |              |  [Restore   |
|             |             |              |              |   Job]      |
|             |             |              |              |             |
|             |    metadata reports         |             |  metadata   |
|             |---------------------------->|<------------|  reports    |
|             |                             |                            |
+-------------+        +-------------+      +-------------+
                       |  Monitor    |
                       |  Server     |
                       +-------------+
```

### Backup Job（主库）

由 `sp_add_log_shipping_primary_database` 创建，调用：

```sql
EXEC master.sys.sp_add_log_shipping_primary_database
    @database = N'AdventureWorks',
    @backup_directory = N'\\fileserver\logship\AW',
    @backup_share = N'\\fileserver\logship\AW',
    @backup_job_name = N'LSBackup_AdventureWorks',
    @backup_retention_period = 4320;        -- 保留 3 天
```

实际作业执行：

```sql
DECLARE @LS_BackUpDateTime datetime = GETDATE();
DECLARE @backup_file_name NVARCHAR(1000) =
    '\\fileserver\logship\AW\AdventureWorks_'
    + CONVERT(NVARCHAR(20), @LS_BackUpDateTime, 112)
    + '_'
    + REPLACE(CONVERT(NVARCHAR(20), @LS_BackUpDateTime, 108), ':', '')
    + '.trn';

BACKUP LOG [AdventureWorks]
TO DISK = @backup_file_name
WITH COMPRESSION, CHECKSUM, RETAINDAYS = 3;

-- 上报到 monitor server
EXEC master.sys.sp_log_shipping_history_step ...
```

### Copy Job（备库）

由 `sp_add_log_shipping_secondary_primary` 注册，使用 `sqllogship.exe` 工具从源 share 拷到本地：

```sql
EXEC master.sys.sp_add_log_shipping_secondary_primary
    @primary_server = N'PROD-SQL01',
    @primary_database = N'AdventureWorks',
    @backup_source_directory = N'\\fileserver\logship\AW',
    @backup_destination_directory = N'D:\Logship\Copy',
    @copy_job_name = N'LSCopy_PROD-SQL01_AdventureWorks',
    @copy_job_id = ...
```

每次作业触发，sqllogship 会：

1. 扫描 source 目录获得文件列表。
2. 对比本地已拷贝列表（记录在 msdb..log_shipping_secondary_databases）。
3. xcopy 新文件到本地。
4. 上报 monitor。

### Restore Job（备库）

```sql
EXEC master.sys.sp_add_log_shipping_secondary_database
    @secondary_database = N'AdventureWorks',
    @primary_server = N'PROD-SQL01',
    @primary_database = N'AdventureWorks',
    @restore_delay = 0,            -- 是否延迟恢复（用于防误操作）
    @restore_mode = 1,              -- 1 = STANDBY, 0 = NORECOVERY
    @disconnect_users = 1,          -- 还原前踢用户
    @restore_threshold = 45,        -- 超过 45 分钟未恢复触发告警
    @threshold_alert_enabled = 1;
```

每次作业：

```sql
RESTORE LOG [AdventureWorks]
FROM DISK = N'D:\Logship\Copy\AdventureWorks_20240115100000.trn'
WITH FILE = 1,
     NORECOVERY,         -- 或 STANDBY = 'D:\Logship\AW.tuf'
     STATS = 5;
```

`STANDBY` 模式会创建一个 *undo file* (.tuf)，存放未提交事务的反操作；这样数据库可以以 read-only 状态打开，下次还原时再 redo undo。`disconnect_users = 1` 是必须的——还原期间任何持锁连接都会让 RESTORE 失败。

### 切换（手工 failover）

```sql
-- 备库
RESTORE LOG [AdventureWorks]
FROM DISK = N'D:\Logship\Copy\final.trn'
WITH RECOVERY;          -- 应用最后一个段并打开

-- DNS 或应用配置切换 endpoint 指向备库
```

### Log Shipping vs AlwaysOn AG

| 维度 | Log Shipping | AlwaysOn AG (同步) |
|------|--------------|-------------------|
| 起始版本 | 2000 | 2012 |
| 最大延迟 | 15 分钟（默认） | 几毫秒 |
| 自动 failover | 否 | 是 |
| read-only 备机 | STANDBY 模式（断线频繁） | 持续可读 |
| 多副本 | 多 secondary | 最多 8 secondary |
| 跨 OS | 是（同 SQL Server 版本） | 是（2017+） |
| 配置复杂度 | 低（向导即可） | 中（需 Windows 集群或 Linux Pacemaker） |
| 许可需求 | Standard 即可 | Enterprise (sync) 或 Standard (async) |

Log Shipping 至今仍是低预算、低运维场景的首选。

## Oracle FAL_CLIENT/FAL_SERVER 与 ARCH 进程

Oracle 的 standby 体系自 8i (1998) 起就成熟，比 PG 早了 7 年。基础假设：

- 主库的 LGWR 把 redo 写到 online redo log。
- 一组 online redo log 写满后，**ARCn** 进程（Archive process）把它复制到归档目的地。
- 备库的 **RFS**（Remote File Server）进程接收远端归档，写入备库的归档目录。
- 备库的 **MRP**（Managed Recovery Process）replay 归档。

### 配置归档目的地

```sql
-- 主库
ALTER SYSTEM SET log_archive_dest_1 =
    'LOCATION=/u01/app/oracle/arch MANDATORY';
ALTER SYSTEM SET log_archive_dest_2 =
    'SERVICE=standby_db ARCH ASYNC NOAFFIRM
     VALID_FOR=(ONLINE_LOGFILES, PRIMARY_ROLE)
     DB_UNIQUE_NAME=standby';
ALTER SYSTEM SET log_archive_format = 'arch_%t_%s_%r.arc';
ALTER DATABASE ARCHIVELOG;

-- redo transport mode 选择
-- ARCH (默认): 段切换后 ARCn 推送，最大延迟 = redo log 切换间隔
-- LGWR ASYNC: LGWR 实时异步推送，毫秒延迟
-- LGWR SYNC: LGWR 同步等待 standby ack（Maximum Protection）
```

### 备库的 MRP 进程

```sql
-- 备库 mount 模式启动
STARTUP MOUNT;
ALTER DATABASE RECOVER MANAGED STANDBY DATABASE
    USING CURRENT LOGFILE          -- 从备库的 standby redo log 直接 replay
    DISCONNECT FROM SESSION;

-- 实时 read-only（Active Data Guard 选项）
ALTER DATABASE OPEN READ ONLY;
ALTER DATABASE RECOVER MANAGED STANDBY DATABASE USING CURRENT LOGFILE DISCONNECT;
```

### FAL：自动补 gap

```sql
-- 主备双向配置
ALTER SYSTEM SET FAL_SERVER = 'standby_db' SCOPE=BOTH;   -- 主库
ALTER SYSTEM SET FAL_SERVER = 'primary_db' SCOPE=BOTH;   -- 备库

-- 备库视图：检测 gap
SELECT * FROM V$ARCHIVE_GAP;

-- gap 出现时 RFS 会通过 FAL_SERVER (net service name) 主动拉缺失段
-- 全过程自动，无需 DBA 干预
```

FAL 的关键创新：**备库**主动连源端拉，而不是源端推。这样即使源端归档进程崩溃、网络断流，备库一旦恢复就能 catch-up。

### Log Apply Services 模式

| 模式 | 含义 | 备机可读 |
|------|------|--------|
| Redo Apply | replay 归档 redo（物理 standby） | Active Data Guard (READ ONLY WITH APPLY) |
| SQL Apply | LogMiner 解析后 SQL 重放（逻辑 standby） | 是，可写非复制对象 |
| Snapshot Standby | 物理 standby 暂时改为读写测试库 | 是 |

日志传送对应 **Redo Apply**。

## DB2 LOGARCHMETH：双通道归档

DB2 自 v8 (2003) 提供 `LOGARCHMETH1` 和 `LOGARCHMETH2`，两个通道可同时归档到不同目的地：

```bash
# 切换到 archive logging
db2 update db cfg for SAMPLE using LOGARCHMETH1 'DISK:/db2/archlog1'
db2 update db cfg for SAMPLE using LOGARCHMETH2 'TSM'
db2 update db cfg for SAMPLE using LOGINDEXBUILD ON

# 必须做一次完整备份（切换日志模式后强制）
db2 backup db SAMPLE online to /backup include logs
```

LOGARCHMETH 取值：

| 取值 | 含义 |
|------|------|
| `OFF` | 不归档，circular logging |
| `LOGRETAIN` | 仅本地保留（已废弃，等价于 OFF + 手工拷贝） |
| `DISK:<path>` | 归档到本地路径 |
| `USEREXIT` | 调用 db2uext2 用户出口（旧版） |
| `VENDOR:<lib>` | 调用厂商 .so 库 |
| `TSM[:<options>]` | IBM Spectrum Protect (Tivoli) |

### Log Shipping Standby（手工配置）

DB2 没有"Log Shipping"产品名，但通过共享归档目录可实现：

```bash
# 主库归档
db2 update db cfg for SAMPLE using LOGARCHMETH1 'DISK:/share/archlog'

# 备库定期 rollforward（不打开数据库）
db2 restore db SAMPLE from /share/full taken at 20240101120000 replace existing
db2 rollforward db SAMPLE to end of logs and stop
# 不打开，保持 RESTORE_PENDING 状态

# 切换时
db2 rollforward db SAMPLE complete
db2 activate db SAMPLE
```

### HADR：DB2 的流复制

DB2 v8.2 (2004) 引入 HADR (High Availability Disaster Recovery)：

```bash
# 主库
db2 update db cfg for SAMPLE using HADR_LOCAL_HOST primary HADR_LOCAL_SVC 50001 \
    HADR_REMOTE_HOST standby HADR_REMOTE_SVC 50001 HADR_REMOTE_INST db2inst1 \
    HADR_TIMEOUT 120 HADR_SYNCMODE NEARSYNC

db2 start hadr on db SAMPLE as primary

# 切换
db2 takeover hadr on db SAMPLE
```

HADR 与 LOGARCHMETH 可并存——HADR 实时同步、LOGARCHMETH 兜底归档。

## MySQL 的 binlog 备份：模拟日志传送

MySQL 没有"日志传送"产品，但可以通过 binlog 备份 + 在备机定期 mysqlbinlog replay 模拟：

```bash
# 主库：binlog 配置
log_bin = /var/log/mysql/mysql-bin
server_id = 1
binlog_format = ROW
sync_binlog = 1
binlog_expire_logs_seconds = 604800   # 7 天

# 主库：定时拷贝 binlog 到共享目录
mysqlbinlog --read-from-remote-server --raw --stop-never \
    --host=primary --user=repl --password=... \
    --result-file=/share/binlog/ mysql-bin.000123

# 备库：周期性 replay（不能直接当流复制用，因为 mysqlbinlog 是单连接、单事务并发）
ls /share/binlog/mysql-bin.* | sort | while read f; do
    mysqlbinlog --start-position=... --stop-datetime='...' "$f" | mysql
done
```

实际上业界更倾向"做主从复制 + 加 binlog 异地归档"：

```sql
-- 主从配置（流复制）
CHANGE MASTER TO
    MASTER_HOST='primary',
    MASTER_PORT=3306,
    MASTER_USER='repl',
    MASTER_PASSWORD='...',
    MASTER_AUTO_POSITION=1;
START SLAVE;

-- binlog 异地归档（cron + rsync 或 wal-g for MySQL）
*/5 * * * * rsync -aq /var/log/mysql/mysql-bin.* archive-host:/binlog-archive/
```

mariabackup（MariaDB）和 Percona XtraBackup（MySQL）扮演的是"全量物理备份"角色，配合 binlog 实现 PITR，但仍不构成原生的"自动文件级日志传送"。

## ClickHouse、CockroachDB、TiDB 的"分布式日志传送"

### ClickHouse ReplicatedMergeTree

ClickHouse 的复制不是基于"日志传送"——而是基于 ZooKeeper 协调的元数据 + part 复制：

```sql
CREATE TABLE events_local ON CLUSTER my_cluster (
    event_id UInt64, ...
) ENGINE = ReplicatedMergeTree(
    '/clickhouse/tables/{shard}/events',
    '{replica}'
)
ORDER BY event_id;
```

每次插入触发一个 part 文件，元信息写入 ZK，副本节点检测到后从源节点拉 part。这更像"part-shipping"而非"WAL-shipping"，但在工程意义上等价：实现了 warm standby。

### CockroachDB BACKUP INTO + revision_history

```sql
-- 启用持续备份
BACKUP INTO 's3://mybucket/backups?AUTH=implicit'
    WITH revision_history;

-- 增量
BACKUP INTO LATEST IN 's3://mybucket/backups'
    WITH revision_history;

-- 恢复到任意时间点（PITR，等价于"已传送日志的回放"）
RESTORE FROM LATEST IN 's3://mybucket/backups'
    AS OF SYSTEM TIME '2024-01-15 10:00:00'
    WITH encryption_passphrase='mysecret';
```

CockroachDB 的"日志传送"实际上是把 KV 多版本数据本身导出。

### TiDB BR + log backup

TiDB 5.4 (2022) 推出的 PITR 由 BR 工具实现，TiKV 节点直接把变更日志推到 S3：

```bash
tiup br log start --task-name=my-pitr \
    --pd "pd:2379" \
    --storage "s3://my-bucket/pitr-log"

tiup br log status --pd "pd:2379"

tiup br restore point --pd "new-pd:2379" \
    --full-backup-storage "s3://my-bucket/full" \
    --storage "s3://my-bucket/pitr-log" \
    --restored-ts "2024-01-15 10:00:00 +0800"
```

每个 TiKV 节点直接 push，避免单点瓶颈，这是"分布式日志传送"的现代演化。

## SAP HANA System Replication 的 ASYNC log shipping

HANA 自 1.0 SPS 04 起提供 System Replication：

```ini
# 主系统 global.ini
[system_replication]
mode = primary
operation_mode = logreplay
```

```ini
# 副本系统
[system_replication]
mode = sync                       # 或 syncmem / async
operation_mode = logreplay        # 或 delta_datashipping
```

HANA 的 ASYNC 模式本质就是日志传送：log buffer 写满或定时切换后压缩传输到副本。

## Informix HDR 与 Sybase Log Transfer Manager

### Informix HDR (High-availability Data Replication)

Informix 自 1995 起的 HDR 是最早的商用日志传送产品之一：

```bash
# 主库
onmode -d primary secondary_server

# 备库
onmode -d secondary primary_server

# 状态查询
onstat -g dri verbose
```

HDR 默认是同步模式，但通过 `DRINTERVAL` 可配置成异步（类似日志传送）：

```bash
# onconfig
DRINTERVAL 30          # 每 30 秒 flush 一次
DRTIMEOUT 30
DRAUTO 0               # 主备失联后是否自动 standalone
```

### Sybase ASE Log Transfer Manager

Sybase ASE（现 SAP ASE）的复制服务器（Replication Server）由 LTM (Log Transfer Manager) 进程从 ASE 源库读 transaction log 并发给 RepAgent，最后写入目标。这其实是逻辑复制（解析 SQL），但底层"按段读 log 文件"的机制和日志传送非常相似。

## Litestream：SQLite 的日志传送方案

SQLite 没有原生归档，但 Ben Johnson 2021 年开源的 Litestream 把 WAL 模式的 SQLite **WAL 文件**实时推到 S3/SFTP/file，实现了零修改的 PITR：

```yaml
# /etc/litestream.yml
dbs:
  - path: /var/lib/myapp/data.db
    replicas:
      - type: s3
        bucket: my-sqlite-backups
        path: data
        access-key-id: ...
        secret-access-key: ...
        retention: 72h
        sync-interval: 1s
```

```bash
# 启动 daemon
litestream replicate

# 恢复到指定时间
litestream restore -timestamp 2024-01-15T10:00:00Z \
    -o /tmp/restored.db s3://my-sqlite-backups/data
```

Litestream 把 SQLite 自身的 WAL 当作"日志段"，每秒级别上传 delta，实现了几乎与 PostgreSQL 相同的 RPO 但只用 SQLite 单文件特性。

## 文件级 PITR vs 流式 PITR

PG 提供两种 PITR 路径，理解它们的差别有助于选型：

### 文件级 PITR（基于 archive_command + restore_command）

```
[ Primary ]
    | archive_command (cp/scp/s3)
    v
[ /mnt/wal_archive/000000010000000000000042 ]
[ /mnt/wal_archive/000000010000000000000043 ]
    |
    | restore_command (pull on standby start)
    v
[ Standby ] -- replay --> [ promoted to read/write ]
```

- 优点：归档与备机解耦，断网不影响双方。
- 缺点：粒度是整段（16MB），最小延迟受 archive_timeout 限制。
- 适用：跨地域容灾、对象存储归档场景。

### 流式 PITR（基于 streaming + recovery）

```
[ Primary ] -- walsender (libpq) --> [ Standby walreceiver ]
                                            |
                                            v
                                      replay in-memory
```

- 优点：延迟毫秒级，备机始终接近最新状态。
- 缺点：网络抖动会让备机滞后；需要 replication slot 防 WAL 回收。
- 适用：同机房/低延迟链路下的 hot standby。

### 混合模式（生产最佳实践）

```
[ Primary ] --(1) walsender ---> [ Standby walreceiver ]
                                        ^
            (2) archive_command          | fallback
            v                            | restore_command
       [ /mnt/wal_archive/ ] ------------+
```

- 流复制为主，archive 为辅。
- 备机断流后用 restore_command 自动 catch-up。
- 主库突然失联时，已归档的段可在第三方机器恢复。

## SQL Server Log Shipping vs Oracle Data Guard：商用对比

| 维度 | SQL Server Log Shipping | Oracle Data Guard |
|------|------------------------|-------------------|
| 起始版本 | SQL Server 2000 | Oracle 8i (1998) |
| 抗网络抖动 | 是（基于 share） | 是（FAL 自动补 gap） |
| 默认 RPO | 15 分钟 | 0-几秒 (依 transport mode) |
| 自动 failover | 否（需脚本或 SCM cluster） | 是（Fast-Start Failover） |
| 多目标 | 多 secondary | 多 standby (最多 30) |
| 备机可读 | STANDBY mode | Active Data Guard |
| 备机可改 | 否 | Snapshot Standby 可暂时改 |
| 跨平台 | 否 | 否（但跨 OS：HP-UX↔Linux 等） |
| 商业模型 | Standard Edition 即可 | Enterprise + Data Guard 选项 |

## 关键发现

### 1. 日志传送的"段切换"是延迟的根源

PostgreSQL 默认 16MB 段，1KB 写入需要 16MB 才填满。即便有 archive_timeout，也只能强制切到当前段（写入空白填充），仍然不是连续流。**延迟下限 ≈ 段切换间隔 + 复制时间**。

```
PostgreSQL: 16MB / 切段时间 + cp 时间
SQL Server: backup interval (默认 15min)
Oracle: redo log group 容量 / LGWR 写入速度
DB2: log file 容量 / fillrate
```

引擎实现者的优化方向：

- **partial segment shipping**：段未写满也能传（pgBackRest 的 archive-async 会切分）。
- **streaming archiver**：把 walsender 协议本身作为归档（pg_receivewal）。
- **tail-log shipping**：主库故障时最后一个未提交段也能传给备机（SQL Server log tail backup）。

### 2. archive_command 的可靠性是整个体系的命门

PostgreSQL 的 archive_command 失败会无限重试，pg_wal 塞满后 checkpoint 阻塞，最终数据库停机。这意味着：

- 命令必须**幂等**（重复执行不破坏已归档段）。
- 命令必须**原子**（先 tmp 后 rename）。
- 命令必须**异地**（本地 cp 没有容灾意义）。
- 命令必须**fast-fail**（云存储抖动应该快速返回错误，让 PG 重试时退避）。

实际生产环境推荐使用 pgBackRest / wal-g 这类经过实战验证的工具，而非自写 cp 命令。

### 3. FAL 模式（备机主动拉）比 push 模式更鲁棒

Oracle 的 FAL 设计远早于 PG 的流复制（1998 vs 2010），核心创新是**备机主动检测 gap、主动拉**。这种"反向轮询"模式比"主库推"更鲁棒：

- 主库归档进程崩溃，备机依然可以从其它路径拉。
- 主库网络分区，备机不会一直 stuck，可以从任何归档源恢复。
- 主备角色变更（switchover）时不需要重新建立 push 通道。

PostgreSQL 后来通过 streaming replication slot 部分弥补，但 FAL 的"任何备机都可以从任何归档源拉"灵活性 PG 至今没有完全实现。

### 4. SQL Server Log Shipping 的"3 作业架构"是分布式系统教材级设计

把 backup、copy、restore 三个动作显式分离到三个 SQL Agent 作业，意味着：

- **解耦**：copy 失败不会拖累 backup，restore 滞后不会卡住 copy。
- **独立调度**：每个作业可有自己的频率、错误处理、告警阈值。
- **可观测**：monitor server 能精确告诉你瓶颈在哪一环。
- **可扩展**：一个 primary 可对应多个 secondary，每个 secondary 独立的 copy/restore 作业。

代价是配置稍复杂，但 GUI 向导和 sp_add_log_shipping_* 系列 SP 把这部分屏蔽得很好。

### 5. DB2 双通道归档（LOGARCHMETH1 + LOGARCHMETH2）的工程哲学

LOGARCHMETH1 和 LOGARCHMETH2 可以同时指向 DISK 和 TSM，两个通道独立写。这种"双重保险"理念在其他引擎几乎找不到：

- 即便磁盘归档目录损坏，TSM 仍有副本。
- 即便 TSM 服务挂掉，磁盘归档还在。
- 一个通道慢不会拖累另一个（异步并行）。

代价是 2x 的 I/O 和存储。但对金融、电信场景这是值得的。

### 6. 文件级日志传送的"幂等续传"设计很关键

cp 失败 / 网络中断后重试，必须保证：

- 部分上传的文件不会被认为完整（`file.tmp` → `file` rename 模式）。
- 已上传的文件不会被覆盖（`test ! -f` 前置检查）。
- 元数据先写日志再 rename（防止半状态）。

pgBackRest 的 archive-async 模式甚至支持多进程并发上传 + 全局锁防覆盖，是工程上的标杆。

### 7. 日志传送 + 流复制的"双轨制"是 21 世纪的事实标准

无论 PostgreSQL（流 + archive）、Oracle（LGWR ASYNC + ARCH）、DB2（HADR + LOGARCHMETH）、SQL Server（AlwaysOn + Log Shipping），所有生产级商用部署都是"流为主、归档为辅"的双轨：

- 流复制保证低 RPO/RTO。
- 归档保证 WAL 不丢、跨地域容灾、PITR 能力。
- 任一通道故障，另一通道继续工作。

新生代分布式数据库（CockroachDB、TiDB、YugabyteDB、OceanBase）也都内置了双轨，只是把命名换成了"raft replication + log backup to object storage"。

### 8. 云原生时代日志传送的形态变化

传统日志传送：cp 到 NFS / SMB share。
云原生日志传送：archive_command 直接 PUT 到 S3 / GCS / Azure Blob。

| 维度 | 传统 share | 云对象存储 |
|------|-----------|-----------|
| 一致性 | 文件系统 POSIX | 最终一致或强一致 |
| 持久性 | RAID 副本 | 11 个 9（3 AZ 内自动复制） |
| 延迟 | LAN ms | WAN 50-200ms |
| 成本 | 高（专业存储） | 极低（$0.023/GB/月 标准层） |
| 单点 | NFS 头是单点 | 无 |

云存储的高延迟可以通过 archive_async / 并发上传缓解；高持久性让 RAID 备份过时；低成本让 365 天历史归档成为可能。但云存储的"最终一致性"特性在某些边界场景仍需注意（如 list 操作可能不立刻看到刚 PUT 的对象）。

### 9. 嵌入式数据库的日志传送：Litestream 的启发

Litestream 把 SQLite 的 WAL 实时推到 S3，证明了"任何 WAL-based 数据库 + 任何对象存储 = 日志传送 PITR"的通用模式。这条思路启发了：

- DuckDB 社区讨论过类似的 wal-shipping（目前 DuckDB 还没有真正的 WAL）。
- H2 / HSQLDB 等嵌入式数据库的备份方案。
- 客户端本地数据库（Mobile SQLite、IndexedDB 等）的云同步。

### 10. 引擎实现者的设计建议

对于正在设计新引擎的开发者：

1. **WAL 段大小要可配置**：16MB（PG）/ 50MB（MySQL binlog）/ 1GB（Oracle redo log）各有道理。低活跃库希望小段（更频繁切换、更低 RPO），高活跃库希望大段（减少元数据开销）。
2. **archive hook 提供两套接口**：shell 命令（兼容性）+ 动态库（性能）。PG 15 的 archive_library 就是这个思路。
3. **占位符设计要面向未来**：除了文件名 / 路径，还应包含线程 / shard / partition 编号，方便分布式扩展。
4. **gap detection 内置**：备机要有视图查询缺失段（V$ARCHIVE_GAP），不要让 DBA 手工 diff。
5. **文件命名要含足够元数据**：序号 / 时间线 / 化身 / 校验和。便于离线分析、跨集群迁移。
6. **支持双通道归档**：DB2 的 LOGARCHMETH1/2 是被低估的优秀设计。
7. **archive_timeout 默认要打开**：默认关闭（PG）会让低活跃用户惊讶地发现自己几小时未归档。
8. **监控视图必备**：归档延迟、失败次数、当前 LSN、回放位置、gap 列表。
9. **PITR 目标多种粒度**：时间戳（用户友好）、LSN/SCN（精确）、命名标记（DBA 主动打点）。
10. **partial segment shipping 是未来**：传统"段写满才传"的设计会限制 RPO 下限，新引擎应考虑流式归档（pg_receivewal、TiDB log backup 都已经在做）。

## 总结对比矩阵

### 各引擎日志传送核心能力对比

| 引擎 | 文件级日志传送 | gap 自动恢复 | 备机可读 | 双通道归档 | 工具生态 |
|------|--------------|------------|---------|----------|---------|
| PostgreSQL | 是 (8.0+) | 通过共享 | Hot Standby | 否（手工） | pgBackRest/wal-g/Barman |
| Oracle | 是 (8i+) | FAL 自动 | Active DG | 是（多 DEST_n） | RMAN/DG Broker |
| SQL Server | 是 (2000+) | 否（手工补） | STANDBY mode | 否 | 原生 + 监控服务器 |
| DB2 | 是 (v8+) | 是（rollforward） | HADR ROS | 是（METH1/2） | TSM/Spectrum Protect |
| MySQL | 模拟 | 否 | 流复制副库 | 否 | xtrabackup + 外部脚本 |
| MariaDB | 模拟 | GTID 部分 | 流复制副库 | 否 | mariabackup + GTID |
| Informix | HDR | 是 | HDR Read-Only | 否 | ontape/ON-Bar |
| Sybase ASE | 是 | 否 | 是 | 否 | Replication Server |
| SAP HANA | 是 | 是 | 是 | 否 | backint |
| Snowflake | 内建 | 内建 | 透明 | -- | 无 |
| BigQuery | 内建 | 内建 | 透明 | -- | 无 |
| CockroachDB | 模拟 | 内建 | 集群多副本 | -- | 内建 |
| TiDB | 模拟 (5.4+) | 内建 | TiFlash | -- | BR |
| YugabyteDB | 部分 | 内建 | 集群副本 | -- | yb-admin |

### 场景选型建议

| 场景 | 推荐方案 | 原因 |
|------|---------|------|
| PG 跨地域 warm standby | archive_command + restore_command + S3 | 标准方案，低 RPO 60s |
| PG 同机房 hot standby | 流复制为主 + 归档兜底 | 业内最佳实践 |
| Oracle 金融容灾 | Data Guard Maximum Availability | LGWR SYNC + FAL |
| SQL Server 低预算容灾 | Log Shipping (Standard Edition) | 不需要 Enterprise |
| SQL Server 24×7 hot standby | AlwaysOn AG (Enterprise) | 持续可读、自动 failover |
| DB2 跨数据中心 | HADR + LOGARCHMETH 双通道 | 双重保险 |
| MySQL 容灾 | 主从复制 + binlog 异地归档 | 流为主、归档为辅 |
| 多云对象存储归档 | wal-g + S3/GCS/Azure | 多云原生 |
| 嵌入式 SQLite 容灾 | Litestream + S3 | 零修改部署 |
| 分布式 NewSQL | 内置 BACKUP INTO + revision_history | 声明式简单 |
| Kubernetes PG | Patroni + pgBackRest + S3 | 云原生标准栈 |

## 参考资料

- PostgreSQL: [Log-Shipping Standby Servers](https://www.postgresql.org/docs/current/warm-standby.html)
- PostgreSQL: [Continuous Archiving and Point-in-Time Recovery](https://www.postgresql.org/docs/current/continuous-archiving.html)
- PostgreSQL: [Archive Modules (15+)](https://www.postgresql.org/docs/current/archive-modules.html)
- PostgreSQL: [pg_receivewal](https://www.postgresql.org/docs/current/app-pgreceivewal.html)
- pgBackRest: [User Guide - Archive Push/Get](https://pgbackrest.org/user-guide.html#archive)
- wal-g: [PostgreSQL Configuration](https://github.com/wal-g/wal-g/blob/master/docs/PostgreSQL.md)
- Barman: [Configuration Reference](https://docs.pgbarman.org/)
- SQL Server: [About Log Shipping](https://learn.microsoft.com/en-us/sql/database-engine/log-shipping/about-log-shipping-sql-server)
- SQL Server: [sp_add_log_shipping_primary_database](https://learn.microsoft.com/en-us/sql/relational-databases/system-stored-procedures/sp-add-log-shipping-primary-database-transact-sql)
- SQL Server: [sp_add_log_shipping_secondary_primary](https://learn.microsoft.com/en-us/sql/relational-databases/system-stored-procedures/sp-add-log-shipping-secondary-primary-transact-sql)
- Oracle: [Data Guard Concepts and Administration](https://docs.oracle.com/en/database/oracle/oracle-database/19/sbydb/index.html)
- Oracle: [FAL_CLIENT and FAL_SERVER](https://docs.oracle.com/en/database/oracle/oracle-database/19/refrn/FAL_CLIENT.html)
- Oracle: [Managed Recovery Process](https://docs.oracle.com/en/database/oracle/oracle-database/19/sbydb/log-apply-services-for-oracle-data-guard.html)
- DB2: [Configuring database logging](https://www.ibm.com/docs/en/db2/11.5?topic=logging-configuring-database)
- DB2: [HADR Overview](https://www.ibm.com/docs/en/db2/11.5?topic=availability-high-disaster-recovery-hadr)
- MySQL: [Backup and Recovery Using mysqlbinlog](https://dev.mysql.com/doc/refman/8.0/en/mysqlbinlog-backup.html)
- MariaDB: [mariabackup](https://mariadb.com/kb/en/mariabackup/)
- SAP HANA: [System Replication](https://help.sap.com/docs/SAP_HANA_PLATFORM/4e9b18c116aa42fc84c7dbfd02111aba/afac7100bb571014bb05c1bf48a4d0b3.html)
- Informix: [High-Availability Data Replication](https://www.ibm.com/docs/en/informix-servers/14.10?topic=replication-high-availability-data-overview)
- Litestream: [How it Works](https://litestream.io/how-it-works/)
- TiDB: [PITR Architecture](https://docs.pingcap.com/tidb/stable/br-pitr-guide)
- CockroachDB: [Take and Restore Encrypted Backups](https://www.cockroachlabs.com/docs/stable/take-and-restore-encrypted-backups.html)
- YugabyteDB: [Point-in-time Recovery](https://docs.yugabyte.com/preview/manage/backup-restore/point-in-time-recovery/)
- Mohan, C. et al. "ARIES: A Transaction Recovery Method Supporting Fine-Granularity Locking and Partial Rollbacks Using Write-Ahead Logging" (1992), ACM TODS
- Lomet, D. "Recovery Performance Comparison Through Reduction of Log Volume" (1996), VLDB
