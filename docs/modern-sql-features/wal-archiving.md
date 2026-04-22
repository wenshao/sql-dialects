# WAL 归档与 PITR (WAL Archiving and Point-in-Time Recovery)

数据丢失的代价远超人们的想象。一个 OLTP 系统如果在崩溃后只能恢复到上一次全量备份，那么从备份点到崩溃点之间的所有事务——分钟级、小时级甚至天级——都会永久消失。要实现真正的 **RPO = 0**（零数据丢失），唯一的办法就是让每一条提交的事务日志都被持久地保存到备份存储。这就是 **WAL 归档（WAL Archiving）** 的核心目的。基于归档日志的 **PITR (Point-In-Time Recovery)** 允许数据库管理员把状态恢复到任意指定的时间点、LSN 或事务 ID，是金融、电信、医疗系统不可或缺的能力。

本文系统对比 45+ 数据库引擎的 WAL 归档机制、PITR 实现和生态工具（pgBackRest / wal-g / Barman 等）。这是一篇写给 DBA、SRE 和引擎开发者的深度参考。本文侧重于归档与恢复的配置与流程，WAL 的写入、刷盘和 checkpoint 请参考姊妹文章 `wal-checkpoint-durability.md`。

## 为什么 WAL 归档是 PITR 的基石

一个典型的生产数据库恢复链路是这样的：

1. **每周或每天做一次全量备份（base backup）**：快照当前所有数据文件。
2. **持续归档 WAL 段（continuous archiving）**：每当一个 WAL 段（PostgreSQL 是 16MB）写满，就把它复制到一个独立的、异地的、可靠的存储位置。
3. **崩溃发生时**：先恢复最近的 base backup，然后 replay 从该备份点开始的所有 WAL 段，最后 replay 到归档里最后一条事务（或用户指定的时间点）。

如果 WAL 归档是实时的、同步的，理论上 RPO 可以逼近 0（仅丢失最后一个正在写入但还未归档的段，或者干脆同步到备用存储做零丢失）。这和只做全量快照的 RPO = 备份间隔 是天壤之别。

**PITR 的关键能力**：

- **恢复到任意时间点**：例如"把数据库恢复到昨天下午 3:15:00 误删除表之前"。
- **恢复到任意 LSN / 事务 ID**：例如"恢复到事务 XID=12345 提交之前"。
- **命名恢复点**：在做危险操作前 `CREATE RESTORE POINT`，事后可以精确回滚。
- **多时间线（timeline）**：恢复后产生新的时间线分支，避免覆盖原有 WAL 流。

## 没有 SQL 标准

和 WAL 本身一样，**WAL 归档和 PITR 完全是实现定义的，SQL 标准不涉及**。不同引擎的术语、配置、工具链差异巨大：

- PostgreSQL 称之为 **WAL archiving** / **continuous archiving**。
- MySQL 称之为 **binary log（binlog）**，更偏向逻辑日志；物理备份依赖 xtrabackup/mysqlbackup。
- Oracle 称之为 **ARCHIVELOG mode** + **RMAN (Recovery Manager)**。
- SQL Server 称之为 **transaction log backup** + **FULL / BULK_LOGGED recovery model**。
- DB2 称之为 **archive logging**（对应 LOGRETAIN / USEREXIT / DISK / VENDOR / TSM）。
- Snowflake 把这一切隐藏在 **Time Travel + Fail-safe** 之后。
- BigQuery / Spanner 完全托管，用户不感知。
- CockroachDB / TiDB 用 **BACKUP ... INTO s3://...** + **changefeed/CDC** + 各自的 PITR 实现。

术语名词不同，但核心机制一致：**持久化日志流 + 全量快照 + 回放 = PITR**。

## 支持矩阵

### 1. 连续归档支持

| 引擎 | 原生连续归档 | 机制 | 成熟度 | 版本 |
|------|-------------|------|-------|------|
| PostgreSQL | 是 | archive_mode + archive_command / archive_library | 生产级 | 8.0+ (2005) |
| MySQL | 部分 | binlog (需外部工具归档) | 生产级 | 5.0+ |
| MariaDB | 部分 | binlog + mariabackup | 生产级 | 10.0+ |
| SQLite | 否 | 需应用层 .dump 或 litestream | 替代 | -- |
| Oracle | 是 | ARCHIVELOG mode + RMAN | 生产级 | v7+ |
| SQL Server | 是 | Transaction Log Backup (FULL recovery) | 生产级 | 2000+ |
| DB2 | 是 | LOGARCHMETH1/2 (DISK/USEREXIT/VENDOR/TSM) | 生产级 | v7+ |
| Snowflake | 内建 | Time Travel (1-90天) + Fail-safe (7天) | 透明 | GA |
| BigQuery | 内建 | Automatic point-in-time recovery (7 天) | 透明 | GA |
| Redshift | 内建 | 自动快照 + manual snapshot | 透明 | GA |
| DuckDB | 否 | 无原生归档，可做 snapshot | 替代 | -- |
| ClickHouse | 部分 | ReplicatedMergeTree log + backup 命令 | 生产级 | 20.x+ |
| Trino | -- | 计算引擎无日志 | -- | -- |
| Presto | -- | 计算引擎无日志 | -- | -- |
| Spark SQL | -- | 依赖 Delta/Iceberg 的 time travel | -- | -- |
| Hive | 部分 | ACID 表通过 HDFS 快照 | 有限 | Hive 3 |
| Flink SQL | -- | Checkpoint + savepoint（非 PITR） | -- | -- |
| Databricks | 内建 | Delta Lake time travel | 透明 | GA |
| Teradata | 是 | Permanent Journal (PJ) + ARC utility | 生产级 | 早期 |
| Greenplum | 是 | 继承 PG archive_command，per segment | 生产级 | 5.0+ |
| CockroachDB | 是 | BACKUP INTO ... WITH revision_history | 生产级 | 21.1+ |
| TiDB | 是 | BR tool + PITR (log backup) | 生产级 | 5.4+ (2022) |
| OceanBase | 是 | OBBackup + archive log | 生产级 | 3.x+ |
| YugabyteDB | 是 | PITR via yb-admin, 基于 WAL GC 策略 | 生产级 | 2.14+ |
| SingleStore | 是 | Incremental backup + log backup | 生产级 | 7.0+ |
| Vertica | 是 | vbr.py + replica | 生产级 | 9.0+ |
| Impala | -- | 依赖 HMS | -- | -- |
| StarRocks | 部分 | BACKUP/RESTORE，无 PITR | 有限 | 2.5+ |
| Doris | 部分 | BACKUP/RESTORE，3.x PITR | 发展中 | 3.0+ |
| MonetDB | 否 | 仅全量 dump | -- | -- |
| CrateDB | 部分 | Lucene snapshot + repository | 生产级 | 4.0+ |
| TimescaleDB | 是 | 继承 PG | 生产级 | 继承 PG |
| QuestDB | 部分 | Replication + snapshot | 有限 | 7.x+ |
| Exasol | 是 | EXAoperation backup | 生产级 | 6.x+ |
| SAP HANA | 是 | Log backup + data backup + backint | 生产级 | 1.0+ |
| Informix | 是 | ontape / ON-Bar | 生产级 | 早期 |
| Firebird | 部分 | nbackup + replication | 有限 | 2.5+ |
| H2 | 否 | 无归档，仅 BACKUP TO | -- | -- |
| HSQLDB | 否 | 无归档 | -- | -- |
| Derby | 否 | 无归档，仅 SYSCS_BACKUP_DATABASE | -- | -- |
| Amazon Athena | -- | 计算引擎 | -- | -- |
| Azure Synapse | 是 | 基于 SQL Server / Spark 底层 | 生产级 | GA |
| Google Spanner | 内建 | PITR (1小时-7天) | 透明 | GA |
| Materialize | 部分 | 基于源系统（upstream）的 offset | -- | -- |
| RisingWave | 部分 | State backend snapshot | 有限 | 1.x+ |
| InfluxDB | 部分 | influx backup | 有限 | 2.x+ |
| DatabendDB | 部分 | 对象存储上的增量 | 有限 | GA |
| Yellowbrick | 是 | 基于 PG + 对象存储 | 生产级 | GA |
| Firebolt | 内建 | 自动 time travel | 透明 | GA |

> 统计：约 26 个引擎提供生产级连续归档，约 10 个引擎通过"托管隐藏"提供 PITR，剩余主要是计算引擎或嵌入式数据库（无需归档）。

### 2. archive_command / archive_library 风格配置

| 引擎 | 配置方式 | 示例 | 备注 |
|------|---------|------|------|
| PostgreSQL | archive_command / archive_library | `cp %p /mnt/wal/%f` / `basic_archive` | 15+ 引入 archive_library |
| MySQL | log_bin + purge_binary_logs | 外部 cp / rsync / xtrabackup copy-back | 不支持直接 archive hook |
| Oracle | LOG_ARCHIVE_DEST_n + LOG_ARCHIVE_FORMAT | 多达 31 个目的地 | RMAN 可管理归档删除 |
| SQL Server | BACKUP LOG TO DISK/URL | SQL Agent job 定时执行 | 必须显式调度 |
| DB2 | LOGARCHMETH1 / LOGARCHMETH2 | USEREXIT / DISK:/path / TSM / VENDOR | 双通道冗余归档 |
| Informix | LOGFILES + ALARMPROGRAM | ontape -a / ON-Bar | 类似 LOGARCHMETH |
| Teradata | ARC utility | ARCHIVE DATA TABLES | 主要离线 |
| CockroachDB | BACKUP INTO '...' WITH incremental_location | `s3://bucket/{db}/inc` | 声明式 |
| TiDB | br log start --storage s3://... | 后台持续推 | 5.4+ |

PostgreSQL 的 `archive_command` 是最经典的范式：

```sql
-- postgresql.conf
wal_level = replica              -- 或 logical
archive_mode = on
archive_command = 'test ! -f /mnt/wal_archive/%f && cp %p /mnt/wal_archive/%f'
archive_timeout = 60             -- 每 60s 强制切段，避免活跃低时归档延迟
```

占位符 `%p` 是 WAL 段的完整路径，`%f` 是文件名。命令必须返回 0（成功），否则 PostgreSQL 会无限重试，直到 WAL 目录塞满触发紧急停机。因此**归档命令的可靠性和幂等性至关重要**。

PG 15 引入的 archive_library 机制改用动态加载的 C 库，避免 shell 每次 fork/exec 的开销：

```sql
-- postgresql.conf
archive_mode = on
archive_library = 'basic_archive'   -- 或 'pgbackrest'
basic_archive.archive_directory = '/mnt/wal_archive'
```

### 3. 归档到云对象存储（S3 / GCS / Azure Blob）

| 引擎 | 原生 S3 支持 | 原生 GCS | 原生 Azure | 常用工具 |
|------|-------------|---------|-----------|---------|
| PostgreSQL | 通过工具 | 通过工具 | 通过工具 | pgBackRest, wal-g, barman-cloud |
| MySQL | 部分（MEB） | 通过工具 | 通过工具 | MySQL Enterprise Backup, xtrabackup --storage |
| Oracle | RMAN + OSB | GCP plugin | Azure plugin | RMAN, OSB cloud module |
| SQL Server | 是（BACKUP TO URL） | 间接 | 是（原生） | BACKUP TO URL（Azure Blob） |
| DB2 | TSM / VENDOR | TSM / VENDOR | TSM / VENDOR | IBM Spectrum Protect |
| Snowflake | 内建 | 内建 | 内建 | 无需显式配置 |
| BigQuery | -- | 内建 | -- | 无需显式配置 |
| Redshift | 是（快照到 S3） | -- | -- | AWS 控制台 |
| CockroachDB | 是 | 是 | 是 | 声明式 URL |
| TiDB | 是 | 是 | 是 | BR tool |
| OceanBase | 是 | 是 | 是 | OBBackup |
| YugabyteDB | 是 | 是 | 是 | yb-admin |
| SingleStore | 是 | 是 | 是 | 内建 |
| Vertica | 是 | 是 | 是 | vbr.py 配置 |
| CrateDB | 是 | 是 | 是 | s3 repository |
| ClickHouse | 是 | 是 | 是 | BACKUP TO S3(...) |
| Exasol | 是 | 是 | 是 | EXAoperation |
| SAP HANA | Backint | Backint | Backint | Backint interface |

SQL Server 的原生 `BACKUP TO URL` 值得特别说明：

```sql
-- 创建访问凭证
CREATE CREDENTIAL [https://myaccount.blob.core.windows.net/mycontainer]
    WITH IDENTITY = 'SHARED ACCESS SIGNATURE',
    SECRET = 'sv=2020-...';

-- 全量备份到 Azure Blob
BACKUP DATABASE AdventureWorks
TO URL = 'https://myaccount.blob.core.windows.net/mycontainer/AdventureWorks.bak'
WITH COMPRESSION, ENCRYPTION (ALGORITHM = AES_256, SERVER CERTIFICATE = BackupCert);

-- 事务日志备份（实现持续归档）
BACKUP LOG AdventureWorks
TO URL = 'https://myaccount.blob.core.windows.net/mycontainer/AdventureWorks_log.trn';
```

### 4. 压缩支持

| 引擎 | WAL/Log 归档压缩 | 算法 | 备注 |
|------|------------------|------|------|
| PostgreSQL | 通过工具 | gzip/zstd/lz4（取决于工具） | 原生 archive_command 需手动 pipe |
| pgBackRest | 是 | gzip/lz4/zstd | 原生配置 compress-type |
| wal-g | 是 | brotli/lz4/lzma/zstd | 原生配置 WALG_COMPRESSION_METHOD |
| Barman | 是 | gzip/bzip2/custom | compression 配置 |
| MySQL | 部分 | binlog_transaction_compression (8.0.20+) | 需 MySQL 8.0+ |
| Oracle | 是 | RMAN BASIC/LOW/MEDIUM/HIGH | 企业版 Advanced Compression |
| SQL Server | 是 | BACKUP ... WITH COMPRESSION | 2008+ |
| DB2 | 是 | INCLUDE LOGS + COMPRESS | BACKUP 命令 |
| CockroachDB | 是 | gzip/snappy（取决于云） | 自动 |
| TiDB | 是 | zstd | BR tool |
| ClickHouse | 是 | lz4/zstd（part 自带） | MergeTree 自身压缩 |

### 5. 备份加密

| 引擎 | 原生加密 | 算法 | 密钥管理 |
|------|---------|------|---------|
| PostgreSQL (pgBackRest) | 是 | AES-256-CBC | 配置文件/KMS |
| wal-g | 是 | AES-256 + libsodium | 环境变量/KMS |
| MySQL Enterprise Backup | 是 | AES-256 | keyring |
| Oracle RMAN | 是 | AES128/AES192/AES256 | TDE wallet |
| SQL Server | 是 | AES128/AES192/AES256/Triple DES | 证书或非对称密钥 |
| DB2 | 是 | AES256 | 本地 keystore |
| Snowflake | 内建 | AES-256 | 自动托管 |
| CockroachDB | 是 | AES-256 | --encryption-passphrase 或 KMS |
| TiDB | 是 | AES256 | BR --crypter.method |
| BigQuery | 内建 | 不可配置 | GCP KMS |

### 6. PITR 粒度

| 引擎 | 时间戳 | LSN/序号 | 事务 ID | 命名恢复点 | 时间线分支 |
|------|-------|---------|---------|-----------|-----------|
| PostgreSQL | 是（recovery_target_time） | 是（recovery_target_lsn） | 是（recovery_target_xid） | 是（recovery_target_name） | 是 |
| MySQL | 是（--stop-datetime） | 是（--stop-position） | 是（GTID 范围） | 否 | 否 |
| Oracle | 是（UNTIL TIME） | 是（UNTIL SCN） | 是（UNTIL SEQUENCE） | 是（RESTORE POINT） | 是（Incarnation） |
| SQL Server | 是（STOPAT） | 是（STOPATMARK） | 否 | 是（BEGIN TRAN WITH MARK） | -- |
| DB2 | 是（RECOVER DATABASE TO） | 是（ROLLFORWARD TO） | 否 | -- | -- |
| Snowflake | 是（AT TIMESTAMP） | 是（AT STATEMENT） | 是（BEFORE STATEMENT） | -- | -- |
| BigQuery | 是（FOR SYSTEM_TIME AS OF） | -- | -- | -- | -- |
| CockroachDB | 是（AS OF SYSTEM TIME） | 是（HLC timestamp） | -- | -- | -- |
| TiDB | 是（--restored-ts） | 是（--start-ts / --end-ts） | -- | -- | -- |
| OceanBase | 是（UNTIL TIME） | 是（UNTIL SCN） | -- | -- | -- |
| YugabyteDB | 是（--restore-time） | 是（hybrid_time） | -- | 是（SNAPSHOT SCHEDULE） | -- |
| Spanner | 是（AS OF TIMESTAMP） | -- | -- | -- | -- |

### 7. 归档删除与保留策略

| 引擎 | 保留策略机制 | 示例 |
|------|-------------|------|
| PostgreSQL | pg_archivecleanup 或工具内置 | `pg_archivecleanup /mnt/wal 000000010000000000000015` |
| pgBackRest | repo1-retention-full / retention-archive | `retention-full=7` |
| wal-g | delete retain FULL N | `wal-g delete retain FULL 7` |
| Barman | retention_policy | `REDUNDANCY 3` 或 `RECOVERY WINDOW OF 7 DAYS` |
| MySQL | expire_logs_days / binlog_expire_logs_seconds | `binlog_expire_logs_seconds = 604800` |
| Oracle | CONFIGURE RETENTION POLICY | `RECOVERY WINDOW OF 7 DAYS` 或 `REDUNDANCY 2` |
| Oracle | DELETE OBSOLETE / CROSSCHECK | RMAN 命令 |
| SQL Server | msdb..sp_delete_backuphistory | 配合 Maintenance Plan |
| DB2 | NUM_DB_BACKUPS + REC_HIS_RETENTN | 自动清理 |
| CockroachDB | BACKUP ... AS OF SYSTEM TIME + 生命周期规则 | 云存储 bucket policy |
| TiDB | br log truncate --until-ts | 显式裁剪 |
| Snowflake | DATA_RETENTION_TIME_IN_DAYS | `ALTER TABLE ... SET DATA_RETENTION_TIME_IN_DAYS=7` |

### 8. 恢复目标语法

| 引擎 | 典型恢复命令 |
|------|-------------|
| PostgreSQL (12-) | `recovery.conf`: `recovery_target_time = '2024-01-15 10:00:00'` |
| PostgreSQL (12+) | `postgresql.auto.conf`: `recovery_target_time = '2024-01-15 10:00:00'` + `standby.signal`/`recovery.signal` |
| MySQL | `mysqlbinlog --stop-datetime='2024-01-15 10:00:00' binlog.000123 \| mysql` |
| Oracle | `RMAN> RESTORE DATABASE; RECOVER DATABASE UNTIL TIME "TO_DATE('2024-01-15 10:00:00','YYYY-MM-DD HH24:MI:SS')";` |
| SQL Server | `RESTORE LOG db FROM DISK='...' WITH STOPAT='2024-01-15T10:00:00'` |
| DB2 | `ROLLFORWARD DATABASE db TO 2024-01-15-10.00.00 USING LOCAL TIME AND STOP` |
| Snowflake | `SELECT * FROM t AT (TIMESTAMP => '2024-01-15 10:00:00'::TIMESTAMP_NTZ)` |
| BigQuery | `SELECT * FROM t FOR SYSTEM_TIME AS OF TIMESTAMP '2024-01-15 10:00:00'` |
| CockroachDB | `RESTORE FROM '...' AS OF SYSTEM TIME '2024-01-15 10:00:00'` |
| TiDB | `br restore point --restored-ts "2024-01-15 10:00:00" --full-backup-storage s3://...` |
| YugabyteDB | `yb-admin restore_snapshot_schedule <schedule_id> "2024-01-15 10:00:00"` |
| Spanner | `SELECT * FROM t FOR SYSTEM_TIME AS OF TIMESTAMP '2024-01-15T10:00:00Z'` |

### 9. 并行恢复

| 引擎 | 并行 WAL 回放 | 并行备份 | 备注 |
|------|--------------|---------|------|
| PostgreSQL | 否（单线程 startup 进程） | 是 | 一直是历史瓶颈，16+ 引入部分并行化 |
| pgBackRest | 流式（恢复过程） | 是（--process-max） | 多进程 restore |
| MySQL | 是（--slave-parallel-workers） | 是 | 基于事务并行回放 |
| Oracle | 是（RECOVER PARALLEL） | 是（CHANNEL） | RMAN 多通道 |
| SQL Server | 是（自动） | 是（多 stripe） | 基于 dirty page 并行 |
| DB2 | 是（PARALLELISM） | 是 | ROLLFORWARD DB PARALLELISM N |
| CockroachDB | 是 | 是 | 天然分布式 |
| TiDB | 是 | 是（--concurrency） | BR 多线程 |

### 10. 监控与验证

| 引擎 | 归档延迟视图 | 验证命令 |
|------|-------------|---------|
| PostgreSQL | `pg_stat_archiver` | `pg_verifybackup`, `pg_waldump` |
| MySQL | `SHOW MASTER STATUS`, `SHOW BINARY LOGS` | `mysqlbinlog --verify-binlog-checksum` |
| Oracle | `V$ARCHIVED_LOG`, `V$RECOVERY_FILE_DEST` | RMAN> `VALIDATE BACKUPSET`, `CROSSCHECK` |
| SQL Server | `sys.dm_database_replica_states`, `msdb..backupset` | `RESTORE VERIFYONLY FROM ...` |
| DB2 | `db2 list history backup` | `db2 restore db ... test` |
| CockroachDB | `SHOW BACKUPS IN '...'` | `SHOW BACKUP ... WITH privileges` |
| TiDB | `br log status --storage s3://...` | `br debug backupmeta` |

### 11. 增量 / 差异备份

| 引擎 | 增量 | 差异 | 机制 |
|------|------|------|------|
| PostgreSQL (pgBackRest) | 是 | 是 | 基于 block checksum |
| PostgreSQL (wal-g) | 是 | -- | delta backups |
| PostgreSQL (barman) | 是 | 是 | rsync + hardlink 或 incremental |
| PostgreSQL 17 | 是（原生） | -- | pg_basebackup --incremental |
| MySQL (xtrabackup) | 是 | 是 | LSN 比较 |
| Oracle RMAN | 是（多级 0-N） | 是 | Block Change Tracking |
| SQL Server | 是（log） | 是（DIFFERENTIAL） | 差异位图 |
| DB2 | 是 | 是 | delta/incremental |
| CockroachDB | 是 | -- | BACKUP INTO LATEST |
| TiDB | 是 | -- | BR incremental |
| Snowflake | 自动 | 自动 | micro-partitions 天然增量 |

## 引擎深度剖析

### PostgreSQL：archive_command / archive_library / PITR

PostgreSQL 是所有 WAL 归档讨论的黄金参照。自 8.0（2005）引入 archive_mode 以来，其模型几乎定义了业界标准。

#### 基础归档

```ini
# postgresql.conf
wal_level = replica              # replica 或 logical
archive_mode = on
archive_command = '
    test ! -f /mnt/wal_archive/%f
    && cp %p /mnt/wal_archive/%f
    && sync -f /mnt/wal_archive/%f
'
archive_timeout = 60             # 强制切段，避免长时间未归档
max_wal_size = 4GB
min_wal_size = 512MB
```

设置后重启 PostgreSQL，`pg_stat_archiver` 视图会显示累计归档信息：

```sql
SELECT archived_count, last_archived_wal, last_archived_time,
       failed_count,   last_failed_wal,   last_failed_time
FROM pg_stat_archiver;
```

#### archive_library（PG 15+）

PG 15 为了解决 `archive_command` 每次 fork+exec 的开销（在高 TPS 下可能拖累整体性能），引入 `archive_library`，把归档逻辑放进一个可共享加载的 C 库：

```ini
archive_mode = on
archive_library = 'basic_archive'
basic_archive.archive_directory = '/mnt/wal_archive'
```

`basic_archive` 是官方 contrib 模块，功能等价于 `cp`。第三方工具如 pgBackRest、wal-g 未来也会提供自己的 archive_library 实现。

#### 全量备份 + WAL replay

经典流程：

```bash
# 1. 全量备份
pg_basebackup -D /backup/base -Fp -Xstream -P -R

# 2. 崩溃发生后，在新机器恢复
tar xf /backup/base.tar.gz -C /data/pgdata
cp -r /backup/pg_wal/* /data/pgdata/pg_wal/

# 3. 配置恢复目标（PG 12+ 使用 postgresql.auto.conf）
cat >> /data/pgdata/postgresql.auto.conf <<EOF
restore_command = 'cp /mnt/wal_archive/%f %p'
recovery_target_time = '2024-01-15 10:00:00+08'
recovery_target_action = 'promote'
EOF

# 4. 创建 recovery.signal 触发恢复模式
touch /data/pgdata/recovery.signal

# 5. 启动（PG 会 replay WAL 到目标时间后 promote）
pg_ctl -D /data/pgdata start
```

#### recovery.conf 的消亡（PG 12）

PG 11 之前所有恢复参数都在 `recovery.conf`：

```ini
# recovery.conf (PG 11 及更早)
restore_command = 'cp /mnt/wal_archive/%f %p'
recovery_target_time = '2024-01-15 10:00:00'
recovery_target_action = 'promote'
standby_mode = 'on'        # 或 off
```

PG 12（2019）把这些参数全部合并到 `postgresql.conf` / `postgresql.auto.conf`，并用两个空文件作为模式触发：

- `recovery.signal` → 以恢复模式启动，replay 到指定目标后 promote。
- `standby.signal` → 以 standby 模式持续 replay，直到手动 promote 或触发 failover。

这一改动对升级 PITR 脚本影响巨大——大量第三方工具（Patroni、pgBackRest、wal-g）在 12 版本发布的那段时间全部需要双版本适配代码。

#### 归档的灾难场景

`archive_command` 失败时 PostgreSQL 的行为是**无限重试**（带指数退避）：

```
2024-01-15 10:00:00 LOG:  archive command failed with exit code 1
2024-01-15 10:00:01 LOG:  failed process was:
cp pg_wal/000000010000000000000042 /mnt/wal_archive/000000010000000000000042
2024-01-15 10:00:01 WARNING: archiving write-ahead log file "000000010000000000000042" failed too many times, will try again later
```

如果 WAL 目录塞满（默认无上限），checkpoint 会被阻塞，最终可能导致数据库只读甚至停机。生产环境必须监控：

```sql
SELECT now() - last_archived_time AS lag,
       (pg_current_wal_lsn() - '0/0')::numeric / 1024 / 1024 AS wal_size_mb
FROM pg_stat_archiver;
```

### MySQL：binlog + xtrabackup

MySQL 的归档故事截然不同——它没有原生的"archive_command"机制，而是把重担交给了 binlog（二进制日志）+ 外部物理备份工具。

#### binlog 基础

```ini
# my.cnf
log_bin = /var/log/mysql/mysql-bin
server_id = 1
binlog_format = ROW              # ROW / STATEMENT / MIXED
sync_binlog = 1                   # 每提交 fsync，等价于 fsync per commit
binlog_expire_logs_seconds = 604800   # 7 天
binlog_row_image = FULL
```

binlog 默认只保存在本地磁盘——**并不自动归档到远程**。生产环境通常靠：

1. **定时 rsync / aws s3 sync**：简单但有 Δt 的风险窗口。
2. **专用复制从库**：让 slave 一直 online 接收 binlog。
3. **MySQL Enterprise Backup（MEB）**：商业版，支持 `--incremental` 和 S3 存储。
4. **Percona XtraBackup**：开源物理备份，配合 binlog 做 PITR。

#### 典型 PITR 流程（xtrabackup）

```bash
# 1. 全量 + 增量备份
xtrabackup --backup --target-dir=/backup/full
xtrabackup --backup --target-dir=/backup/inc1 --incremental-basedir=/backup/full

# 2. prepare 并合并
xtrabackup --prepare --apply-log-only --target-dir=/backup/full
xtrabackup --prepare --apply-log-only --target-dir=/backup/full --incremental-dir=/backup/inc1
xtrabackup --prepare --target-dir=/backup/full

# 3. 恢复到新实例
systemctl stop mysql
xtrabackup --copy-back --target-dir=/backup/full
chown -R mysql:mysql /var/lib/mysql
systemctl start mysql

# 4. 确定全量备份对应的 binlog 位点
cat /backup/full/xtrabackup_binlog_info
# mysql-bin.000123  12345  a8b2c3d4-...

# 5. 回放 binlog 到目标时间
mysqlbinlog --start-position=12345 --stop-datetime='2024-01-15 10:00:00' \
    mysql-bin.000123 mysql-bin.000124 mysql-bin.000125 | mysql -uroot -p
```

#### GTID 模式的优势

开启 GTID (Global Transaction ID) 后可以用更精确的范围：

```bash
mysqlbinlog --skip-gtids=false \
    --include-gtids='a8b2c3d4-...:1-1000' \
    mysql-bin.000123 | mysql
```

### Oracle：ARCHIVELOG + RMAN

Oracle 在这方面是业界最成熟的，RMAN（Recovery Manager）+ ARCHIVELOG mode + Data Guard 构成的体系可能是目前功能最完备的商用方案。

#### 开启 ARCHIVELOG

```sql
-- 以 SYSDBA 登录
SHUTDOWN IMMEDIATE;
STARTUP MOUNT;
ALTER DATABASE ARCHIVELOG;
ALTER DATABASE OPEN;

-- 配置归档目的地（可多达 31 个）
ALTER SYSTEM SET log_archive_dest_1='LOCATION=/u01/app/oracle/arch MANDATORY';
ALTER SYSTEM SET log_archive_dest_2='LOCATION=/u02/arch_mirror OPTIONAL';
ALTER SYSTEM SET log_archive_dest_3='SERVICE=standby_db LGWR SYNC AFFIRM';
ALTER SYSTEM SET log_archive_format='arch_%t_%s_%r.arc';

-- 验证
ARCHIVE LOG LIST;
```

#### RMAN 全量 + 增量备份

```bash
rman target /

RMAN> CONFIGURE CONTROLFILE AUTOBACKUP ON;
RMAN> CONFIGURE RETENTION POLICY TO RECOVERY WINDOW OF 7 DAYS;
RMAN> CONFIGURE BACKUP OPTIMIZATION ON;
RMAN> CONFIGURE DEVICE TYPE DISK PARALLELISM 4;

# 周日全量
RMAN> BACKUP INCREMENTAL LEVEL 0 DATABASE PLUS ARCHIVELOG;

# 每天增量
RMAN> BACKUP INCREMENTAL LEVEL 1 CUMULATIVE DATABASE PLUS ARCHIVELOG;

# 清理
RMAN> CROSSCHECK BACKUP;
RMAN> DELETE NOPROMPT OBSOLETE;
RMAN> DELETE NOPROMPT EXPIRED BACKUP;
```

#### RMAN PITR 深度示例

假设 `2024-01-15 10:15:00` 有个 DBA 误删除了生产表：

```bash
rman target /

RMAN> SHUTDOWN IMMEDIATE;
RMAN> STARTUP MOUNT;

RMAN> RUN {
    ALLOCATE CHANNEL c1 DEVICE TYPE DISK;
    ALLOCATE CHANNEL c2 DEVICE TYPE DISK;
    ALLOCATE CHANNEL c3 DEVICE TYPE DISK;
    ALLOCATE CHANNEL c4 DEVICE TYPE DISK;

    SET UNTIL TIME "TO_DATE('2024-01-15 10:14:59', 'YYYY-MM-DD HH24:MI:SS')";
    RESTORE DATABASE;
    RECOVER DATABASE;

    RELEASE CHANNEL c1;
    RELEASE CHANNEL c2;
    RELEASE CHANNEL c3;
    RELEASE CHANNEL c4;
};

-- 以 resetlogs 打开新化身（incarnation）
RMAN> ALTER DATABASE OPEN RESETLOGS;
```

也可以用 SCN（System Change Number）精确恢复：

```bash
RMAN> SET UNTIL SCN 12345678;
RMAN> RESTORE DATABASE;
RMAN> RECOVER DATABASE;
```

或用日志序号：

```bash
RMAN> SET UNTIL SEQUENCE 4567 THREAD 1;
```

#### 命名恢复点（Restore Point）

```sql
-- 危险操作前先创建 restore point
CREATE RESTORE POINT before_schema_change GUARANTEE FLASHBACK DATABASE;

-- 如果出错，闪回到 restore point
SHUTDOWN IMMEDIATE;
STARTUP MOUNT;
FLASHBACK DATABASE TO RESTORE POINT before_schema_change;
ALTER DATABASE OPEN RESETLOGS;

-- 清理
DROP RESTORE POINT before_schema_change;
```

#### CROSSCHECK 与 DELETE OBSOLETE

RMAN 的 CROSSCHECK 会核对控制文件里记录的备份与实际存在的文件，标记丢失为 EXPIRED；DELETE OBSOLETE 按保留策略删除过期备份：

```bash
RMAN> CROSSCHECK BACKUP;
RMAN> CROSSCHECK ARCHIVELOG ALL;
RMAN> DELETE NOPROMPT EXPIRED BACKUP;
RMAN> DELETE NOPROMPT OBSOLETE;
```

### SQL Server：Transaction Log Backup

SQL Server 的 PITR 完全依赖 recovery model：

- **FULL**：所有事务都记录，log 可备份；支持 PITR。
- **BULK_LOGGED**：批量操作最小日志（减少 log volume），仍支持 PITR 但精度受限。
- **SIMPLE**：checkpoint 后自动截断 log；**无 log backup、无 PITR**。

```sql
-- 切换到 FULL recovery model
ALTER DATABASE AdventureWorks SET RECOVERY FULL;

-- 全量备份（开启 log chain）
BACKUP DATABASE AdventureWorks
TO DISK = 'D:\Backup\AW_full.bak'
WITH COMPRESSION, CHECKSUM;

-- 定期事务日志备份（如每 15 分钟）
BACKUP LOG AdventureWorks
TO DISK = 'D:\Backup\AW_log_202401151000.trn'
WITH COMPRESSION, CHECKSUM;

-- 差异备份（可选，缩短恢复时间）
BACKUP DATABASE AdventureWorks
TO DISK = 'D:\Backup\AW_diff.bak'
WITH DIFFERENTIAL, COMPRESSION;
```

#### PITR 恢复

```sql
-- 1. 恢复全量（NORECOVERY 保持还原状态）
RESTORE DATABASE AdventureWorks
FROM DISK = 'D:\Backup\AW_full.bak'
WITH NORECOVERY, REPLACE;

-- 2. 恢复差异
RESTORE DATABASE AdventureWorks
FROM DISK = 'D:\Backup\AW_diff.bak'
WITH NORECOVERY;

-- 3. 应用 log 备份到目标时间
RESTORE LOG AdventureWorks
FROM DISK = 'D:\Backup\AW_log_202401151000.trn'
WITH STOPAT = '2024-01-15T10:14:59', RECOVERY;
```

#### BACKUP TO URL（Azure Blob）

```sql
CREATE CREDENTIAL [https://myacc.blob.core.windows.net/mycontainer]
    WITH IDENTITY = 'SHARED ACCESS SIGNATURE',
    SECRET = 'sv=2020-...';

BACKUP LOG AdventureWorks
TO URL = 'https://myacc.blob.core.windows.net/mycontainer/log.trn'
WITH COMPRESSION, ENCRYPTION(
    ALGORITHM = AES_256,
    SERVER CERTIFICATE = BackupCert);
```

### DB2：LOGARCHMETH1 / LOGARCHMETH2

DB2 是少数支持**双通道并发归档**的引擎：LOGARCHMETH1 和 LOGARCHMETH2 可以同时指向不同的存储，实现冗余。

```bash
# 从 circular（不归档）切到 archive logging
db2 update db cfg for sample using LOGARCHMETH1 DISK:/db2/archlog1
db2 update db cfg for sample using LOGARCHMETH2 TSM

# 立即做一次全量备份（切换日志模式必须）
db2 backup db sample online to /backup include logs

# PITR 恢复
db2 restore db sample from /backup taken at 20240115100000
db2 rollforward db sample to 2024-01-15-10.14.59 using local time
db2 rollforward db sample stop
```

LOGARCHMETH 值支持：

- `OFF` / `LOGRETAIN` — 不归档 / 仅保留
- `DISK:<path>` — 归档到本地路径
- `USEREXIT` — 旧版 shell hook
- `VENDOR:<lib>` — 第三方存储（如 IBM TSM）
- `TSM[:<options>]` — IBM Spectrum Protect

### Snowflake：Time Travel + Fail-safe

Snowflake 把所有底层细节隐藏了。用户看到的是：

- **Time Travel**：可配置 1-90 天（企业版），期间可以查询任意历史点。
- **Fail-safe**：Time Travel 过期后额外 7 天，只能通过 Support 恢复。

```sql
-- 配置保留期
ALTER TABLE orders SET DATA_RETENTION_TIME_IN_DAYS = 30;

-- 时间点查询
SELECT * FROM orders AT (TIMESTAMP => '2024-01-15 10:00:00'::TIMESTAMP_NTZ);

-- SCN 点之前
SELECT * FROM orders BEFORE (STATEMENT => '01b3d9f2-...');

-- 克隆历史数据
CREATE TABLE orders_restore CLONE orders
    AT (TIMESTAMP => DATEADD(HOUR, -24, CURRENT_TIMESTAMP()));

-- 恢复被删除的表
UNDROP TABLE orders;
```

背后 Snowflake 维护 micro-partition 的 immutable 历史版本 + metadata 时间索引。用户无法也无需配置 archive_command。

### BigQuery：自动 PITR

BigQuery 提供 7 天自动 PITR，无需任何配置：

```sql
-- 时间点查询
SELECT * FROM dataset.orders
FOR SYSTEM_TIME AS OF TIMESTAMP '2024-01-15 10:00:00 UTC';

-- 克隆表
CREATE TABLE dataset.orders_restore
CLONE dataset.orders FOR SYSTEM_TIME AS OF
TIMESTAMP_SUB(CURRENT_TIMESTAMP(), INTERVAL 24 HOUR);
```

背后是 Capacitor 列存 + Spanner 元数据，所有写入天然保留历史版本 7 天。

### CockroachDB：BACKUP INTO + AS OF SYSTEM TIME

CockroachDB 用声明式的 BACKUP 命令 + 多版本存储实现 PITR：

```sql
-- 首次全量备份
BACKUP INTO 's3://mybucket/backups?AUTH=implicit'
    WITH revision_history, encryption_passphrase='mysecret';

-- 增量备份（基于 LATEST 全量）
BACKUP INTO LATEST IN 's3://mybucket/backups'
    WITH revision_history, encryption_passphrase='mysecret';

-- PITR 恢复
RESTORE FROM LATEST IN 's3://mybucket/backups'
    AS OF SYSTEM TIME '2024-01-15 10:00:00'
    WITH encryption_passphrase='mysecret';

-- 查询历史
SELECT * FROM orders AS OF SYSTEM TIME '-1h';
```

`revision_history` 选项让备份保留每个 key 的多版本，从而支持 PITR 到备份区间内的任意时间。

### TiDB：BR + PITR（5.4+）

TiDB 5.4（2022）正式发布 PITR，由 BR（Backup & Restore）工具 + 持续日志备份组成：

```bash
# 1. 启动日志流备份
tiup br log start --task-name=my-pitr-task \
    --pd "pd-host:2379" \
    --storage "s3://my-bucket/pitr-log?access-key=...&secret-access-key=..."

# 2. 定期全量（通常每周）
tiup br backup full --pd "pd-host:2379" \
    --storage "s3://my-bucket/full-2024-01-14"

# 3. 查看状态
tiup br log status --pd "pd-host:2379"

# 4. PITR 恢复到指定时间
tiup br restore point --pd "new-pd-host:2379" \
    --full-backup-storage "s3://my-bucket/full-2024-01-14" \
    --storage "s3://my-bucket/pitr-log" \
    --restored-ts "2024-01-15 10:00:00 +0800"
```

TiDB 的 PITR 基于 TiKV 的 CDC 事件流，由 TiKV 节点直接推送变更日志到 S3，避免了传统数据库"集中归档"的单点瓶颈。

### MariaDB：mariabackup

mariabackup 是 MariaDB 从 XtraBackup fork 出的物理备份工具：

```bash
# 全量
mariabackup --backup --target-dir=/backup/full

# 增量
mariabackup --backup --target-dir=/backup/inc1 \
    --incremental-basedir=/backup/full

# prepare
mariabackup --prepare --target-dir=/backup/full
mariabackup --prepare --target-dir=/backup/full \
    --incremental-dir=/backup/inc1

# 恢复
mariabackup --copy-back --target-dir=/backup/full

# binlog 回放（同 MySQL）
mysqlbinlog --stop-datetime='2024-01-15 10:00:00' mysql-bin.* | mysql
```

### YugabyteDB：PITR via Snapshot Schedule

YugabyteDB 2.14+ 提供声明式 PITR：

```bash
# 创建快照计划（每小时一次，保留 3 天）
yb-admin --master_addresses=master:7100 \
    create_snapshot_schedule 1 72 mydb

# 查看计划
yb-admin --master_addresses=master:7100 list_snapshot_schedules

# 恢复到指定时间点
yb-admin --master_addresses=master:7100 \
    restore_snapshot_schedule <schedule_id> "2024-01-15 10:00:00"
```

YB 的实现依赖 RocksDB 的 history retention + Raft WAL 的定时 snapshot。

## PostgreSQL archive_command 实战

### 最原始方案：cp

```bash
archive_command = 'test ! -f /mnt/wal_archive/%f && cp %p /mnt/wal_archive/%f'
```

问题：

- 没有压缩（PG 默认 WAL 段 16MB，一天可能上百 GB）。
- 没有加密。
- 没有对云存储的支持。
- 如果 `/mnt/wal_archive` 不是真正异地的，地震火灾同归于尽。
- `cp` 结束后没有 `fsync`，重启时仍可能丢失最后几个段。

改进：

```bash
archive_command = '
    set -e
    test ! -f /mnt/wal_archive/%f
    cp %p /mnt/wal_archive/%f.tmp
    sync -f /mnt/wal_archive/%f.tmp
    mv /mnt/wal_archive/%f.tmp /mnt/wal_archive/%f
'
```

### pgBackRest（Crunchy Data, 2013）

pgBackRest 是社区公认的"PG 备份事实标准"：

```ini
# /etc/pgbackrest/pgbackrest.conf
[global]
repo1-path=/var/lib/pgbackrest
repo1-retention-full=7
repo1-retention-archive=14
repo1-cipher-pass=my-very-long-passphrase
repo1-cipher-type=aes-256-cbc
compress-type=zst
compress-level=3
process-max=4
start-fast=y

[prod]
pg1-path=/var/lib/postgresql/15/main
pg1-port=5432
```

```ini
# postgresql.conf
archive_mode = on
archive_command = 'pgbackrest --stanza=prod archive-push %p'
```

常用命令：

```bash
# 初始化 stanza
pgbackrest --stanza=prod stanza-create

# 全量
pgbackrest --stanza=prod --type=full backup

# 增量
pgbackrest --stanza=prod --type=incr backup

# PITR 恢复
pgbackrest --stanza=prod \
    --type=time --target='2024-01-15 10:00:00+08' \
    restore

# 验证归档完整性
pgbackrest --stanza=prod check
pgbackrest --stanza=prod --archive-async=y info
```

pgBackRest 对象存储（S3）示例：

```ini
[global]
repo1-type=s3
repo1-s3-bucket=my-pg-backup
repo1-s3-endpoint=s3.amazonaws.com
repo1-s3-region=us-east-1
repo1-s3-key-type=auto
repo1-cipher-type=aes-256-cbc
repo1-cipher-pass=my-very-long-passphrase
```

### wal-g（Wild Apricot/Citus, 2017）

wal-g 由 Citus 团队（现已并入 Microsoft/Azure）开发，以极简和云原生著称：

```bash
export WALG_S3_PREFIX="s3://my-pg-backup/cluster1"
export AWS_REGION="us-east-1"
export WALG_COMPRESSION_METHOD=brotli
export WALG_UPLOAD_CONCURRENCY=16
export WALG_DELTA_MAX_STEPS=6
export WALG_LIBSODIUM_KEY="..."
```

```ini
# postgresql.conf
archive_mode = on
archive_command = 'wal-g wal-push %p'
restore_command = 'wal-g wal-fetch %f %p'
```

关键命令：

```bash
# 全量
wal-g backup-push /var/lib/postgresql/15/main

# 列出备份
wal-g backup-list

# PITR（启动前在 recovery 目标设置）
export WALG_PITR_TS='2024-01-15T10:00:00Z'
wal-g backup-fetch /var/lib/postgresql/15/main LATEST
# 然后配置 restore_command 并启动 PG

# 删除过期
wal-g delete retain FULL 7 --confirm
```

### wal-e（Heroku, 2012）

wal-e 是 wal-g 的前身，由 Heroku 开源。现已基本被 wal-g 取代（Python → Go），但仍在少量存量系统中运行：

```bash
archive_command = 'envdir /etc/wal-e.d/env /usr/local/bin/wal-e wal-push %p'
```

### Barman（2ndQuadrant, 2011）

Barman 是 PG 最早的专业备份工具，由 2ndQuadrant（现 EDB）维护：

```ini
# /etc/barman.d/prod.conf
[prod]
description = "Production PG"
ssh_command = ssh postgres@pg1
conninfo = host=pg1 user=barman dbname=postgres
backup_method = rsync
parallel_jobs = 4
reuse_backup = link
compression = gzip
retention_policy = RECOVERY WINDOW OF 7 DAYS
archiver = on
streaming_archiver = on
slot_name = barman
```

命令：

```bash
barman cron                 # 由 cron 调用，处理归档
barman backup prod          # 全量备份
barman list-backup prod
barman recover --target-time "2024-01-15 10:00:00" prod latest /recovery
```

Barman 的独特之处：支持 `rsync + hardlink` 增量（效率极高）和 `streaming_archiver`（通过 replication slot 接收实时 WAL，降低 archive_command 延迟）。

## Oracle RMAN PITR 深度剖析

### 化身（Incarnation）的概念

每次 `RESETLOGS`（PITR 后必须）会产生一个新的数据库 incarnation。Oracle 可以在不同 incarnation 之间跳转：

```sql
RMAN> LIST INCARNATION;

List of Database Incarnations
DB Key  Inc Key DB Name  DB ID            STATUS  Reset SCN  Reset Time
------- ------- -------- ---------------- ------- ---------- ----------
1       1       ORCL     1234567890       PARENT  1          2023-01-01
2       2       ORCL     1234567890       PARENT  1500000    2023-06-15
3       3       ORCL     1234567890       CURRENT 2800000    2024-01-15

-- 可以恢复到旧化身
RMAN> RESET DATABASE TO INCARNATION 2;
RMAN> RESTORE DATABASE UNTIL SCN 2000000;
RMAN> RECOVER DATABASE UNTIL SCN 2000000;
RMAN> ALTER DATABASE OPEN RESETLOGS;
```

### 表级 PITR（Table Recovery）

Oracle 12c 引入了 RMAN 的表级 PITR，不用整库回滚：

```bash
RMAN> RECOVER TABLE scott.emp
    UNTIL TIME "TO_DATE('2024-01-15 10:00:00','YYYY-MM-DD HH24:MI:SS')"
    AUXILIARY DESTINATION '/tmp/aux'
    REMAP TABLE scott.emp:emp_recovered;
```

RMAN 会自动：

1. 在 `/tmp/aux` 创建辅助实例。
2. 恢复该实例到指定时间。
3. Data Pump export 目标表。
4. 导入到目标库（重命名为 `emp_recovered`）。
5. 清理辅助实例。

### 块级恢复（Block Media Recovery）

```bash
RMAN> RECOVER DATAFILE 7 BLOCK 12345;
-- 或从 V$DATABASE_BLOCK_CORRUPTION 自动恢复
RMAN> RECOVER CORRUPTION LIST;
```

只恢复坏块，不影响其他用户访问。

## 归档存储的选型

### 对象存储 vs 块存储

| 维度 | 本地磁盘 / NFS | 对象存储 (S3/GCS/Azure) | 磁带库 (TSM/OSB) |
|------|----------------|------------------------|-----------------|
| 成本 | 中 | 低（冷存储 $0.004/GB/月） | 极低（冷归档） |
| 耐久性 | 99.9%（单盘） | 99.999999999%（11 个 9） | 99.9%+ |
| 延迟 | ms | 10-100ms | 秒-分钟 |
| 带宽 | 1-10GB/s | 1GB/s（多连接可 5+） | 100-500MB/s |
| 异地 | 需额外同步 | 天然异地 + 跨 Region | 异地 + 离线 |
| 运维 | 高（自管硬件） | 低（全托管） | 中（专用设备） |

对于 99% 的生产数据库，S3/GCS/Azure Blob 已经是最优选择。

### 存储生命周期策略（示例：AWS S3）

```json
{
    "Rules": [{
        "Status": "Enabled",
        "Filter": { "Prefix": "wal-archive/" },
        "Transitions": [
            { "Days": 7,  "StorageClass": "STANDARD_IA" },
            { "Days": 30, "StorageClass": "GLACIER_IR" },
            { "Days": 90, "StorageClass": "DEEP_ARCHIVE" }
        ],
        "Expiration": { "Days": 365 }
    }]
}
```

这样一年内数据成本可以降低 80% 以上。但要注意：GLACIER 类的**读取需要 minutes-hours 的 retrieval time**，不适合紧急恢复时使用。通常只把超过恢复窗口的归档迁移到冷层。

### 写入幂等性

无论用哪种工具，归档命令**必须**是幂等的：

- 如果 `/mnt/wal_archive/000000010000000000000042` 已存在，重复上传应返回成功或原子覆盖。
- S3 自带幂等（重复 PUT 覆盖），但要避免"上传一半网络断"导致部分内容写入；推荐用 Multipart Upload。
- pgBackRest / wal-g 的 archive-push 都内置了幂等逻辑，检测到同名段时会校验 content hash。

## 监控要点

生产环境至少监控以下指标：

### PostgreSQL

```sql
-- 归档延迟（最后一次归档到现在的时间）
SELECT now() - last_archived_time AS archive_lag FROM pg_stat_archiver;

-- 未归档的 WAL 大小
SELECT pg_wal_lsn_diff(pg_current_wal_lsn(), last_archived_wal::pg_lsn)
FROM pg_stat_archiver;

-- 归档失败次数
SELECT failed_count FROM pg_stat_archiver;

-- WAL 目录占用（可能提示归档 stuck）
SELECT pg_size_pretty(sum(size)) FROM pg_ls_waldir();
```

### Oracle

```sql
-- 归档进度
SELECT thread#, MAX(sequence#) FROM v$archived_log
WHERE applied = 'YES' GROUP BY thread#;

-- Fast Recovery Area 占用
SELECT name, space_limit/1024/1024/1024 AS gb_limit,
       space_used/1024/1024/1024 AS gb_used,
       number_of_files
FROM v$recovery_file_dest;
```

### MySQL

```sql
SHOW MASTER STATUS;
SHOW BINARY LOGS;

-- 观察 Binlog Cache 命中率（间接反映 log 产生速率）
SHOW STATUS LIKE 'Binlog_%';
```

## 关键权衡与设计争议

### 同步 vs 异步归档

- **同步（archive_timeout=0 + 前端等待归档完成）**：RPO = 0，但每次 commit 延迟 ++，吞吐 ↓。
- **异步（archive_timeout=60s）**：RPO ≈ 60s，吞吐不受影响。

真正的 RPO = 0 通常由 **同步复制（synchronous_standby_names）** 配合归档实现——同步 standby 保证至少有两份 commit，归档负责长期保存。

### archive_command 的故障隔离

archive_command 失败会阻塞 WAL recycling，最终可能撑爆磁盘。建议：

1. **归档目标独立于主存储**（独立挂载点或对象存储）。
2. **archive_command 有超时控制**（用 `timeout 30s cp ...`）。
3. **WAL 目录可用空间监控**（至少保留 10GB buffer）。
4. **紧急情况下的 disable 命令**：`ALTER SYSTEM SET archive_mode = off`（需要重启，慎用）或 `archive_command = '/bin/true'`（立即生效但会丢失归档）。

### PITR 粒度 vs 归档频率

- 归档到 S3 的延迟约 100ms-1s，理论上 PITR 精度可达秒级。
- 但如果 archive_timeout 设得太长（比如 1 小时），最后一段未归档期间的事务无法 PITR。
- 启用 streaming_archiver（pgBackRest 的 archive-push 流模式、Barman 的 streaming_archiver）可以把 PITR 精度降到秒级。

### 大事务的归档放大效应

一个大的 `VACUUM FULL` 或批量 `UPDATE` 可能瞬间产生几十 GB WAL：

- 归档带宽被占满，普通 WAL 段堆积。
- S3 上传费用激增（虽然 S3 PUT 便宜，但 10GB/s 持续写可能撞到 rate limit）。
- 建议大事务分批 + 单独 archive_command 限流（如 `pv -L 50M`）。

### 归档校验与恢复演练

**没有经过恢复演练的备份不叫备份**。工程实践：

1. 每周自动从最新备份恢复到隔离测试环境。
2. 执行若干预定义 SQL 校验数据。
3. 记录恢复时间（RTO）指标。
4. 定期（每季度）做完整 PITR 演练到任意时间点。

### 密钥轮换的复杂性

加密备份的密钥轮换是个棘手问题：

- 旧密钥加密的归档不能被新密钥读取。
- 轮换后必须保留所有历史密钥，直到对应的归档过期。
- pgBackRest 用 `repo1-cipher-pass`，轮换需要 re-encrypt 或等归档自然过期。
- wal-g 用 libsodium + envelope encryption，理论上可以只轮换 master key。
- Oracle TDE 用 keystore，密钥 merge 流程成熟但操作复杂。

## 对引擎开发者的建议

### 1. archive_command 应该是插件化的

PostgreSQL 15+ 的 `archive_library` 方向是对的——shell fork/exec 的开销在高 TPS 下不可忽视。新设计的引擎应该从一开始就提供插件接口（pluggable API）：

```c
typedef struct ArchiveCallbacks {
    bool (*startup_cb)(void);
    bool (*check_configured_cb)(void);
    bool (*archive_file_cb)(const char *file, const char *path);
    void (*shutdown_cb)(void);
} ArchiveCallbacks;

/* 插件入口 */
void archive_module_init(ArchiveCallbacks *cb);
```

### 2. 归档必须是幂等的

这是 distributed systems 的铁律。由于网络重试、进程重启、并发归档，同一个 WAL 段可能被多次 archive_push：

```c
bool archive_file(const char *segment) {
    if (remote_exists(segment)) {
        /* 校验 content hash，相同则成功返回 */
        if (remote_hash(segment) == local_hash(segment))
            return true;
        /* hash 不同是严重错误，可能是数据损坏或 chain split */
        return false;
    }
    return remote_put_atomic(segment);
}
```

### 3. 用 streaming 而非 per-segment

传统的"每写满一个 16MB 段才归档"模型在云存储时代是反直觉的——对象存储的 API 延迟通常 50-200ms，16MB 段意味着 PITR 精度下限就是产生一个段的时间。流式归档（像 Barman 的 `streaming_archiver`、pgBackRest 的 async archive）可以把延迟降到秒级。

```
Streaming 模型：
  walsender → archive daemon → object storage
  每 N ms 或 M KB 上传一次 partial segment

Restart 友好性：
  partial segment 带 offset marker，可以从中间续传
```

### 4. 元数据和日志内容分离

归档的不仅是 WAL 字节流，还有**元数据**（LSN 范围、timeline、事务边界）。分开存储可以：

- 快速列出某时间段的所有段（不用下载内容）。
- 支持并行下载（先获取元数据，再并发拉 N 个段）。
- 便于 GC（按元数据决定过期）。

pgBackRest 的 backup.info 和 archive.info、TiDB BR 的 backupmeta 都是这个设计。

### 5. 加密在归档工具层做，不在存储层

理由：

- **云存储的服务端加密无法防止运营商（包括云厂商）访问**。端到端加密（客户端加密）才是真正的 E2EE。
- **加密+压缩的顺序不可逆**：先压缩后加密（正确），先加密后压缩（几乎无压缩收益，因为密文熵高）。
- **envelope encryption**：数据用对称密钥（DEK）加密，DEK 用 KEK 加密。轮换 KEK 不用重新加密所有历史数据。

### 6. PITR 的时间精度不能依赖系统时钟

生产系统时钟漂移是常态。PITR 目标应该支持：

- LSN / SCN / HLC（最精确）。
- 事务 ID（隔离某个特定事务的前后）。
- 时间戳（用户友好，但精度受时钟影响）。
- 命名标记（`CREATE RESTORE POINT`，DBA 主动打点）。

多种粒度并存，由用户根据场景选择。

### 7. 恢复时的并行性

大部分引擎的 WAL replay 仍然是**单线程**，这是恢复时间的最大瓶颈。1TB 数据库、1GB/s replay 也要 1000 秒。改进方向：

- **基于 resource group 的并行**：不同 relfilenode / tablet 的 replay 可以并发。
- **预取 dirty page**：replay 前并行预热 buffer pool。
- **Selective replay**：只回放必要的 page（结合 block change tracking）。

Oracle RMAN 的 RECOVER PARALLEL、MySQL 8.0 的 slave_parallel_type=LOGICAL_CLOCK、PG 16 的 recovery prefetch 都是这个方向。

## 总结对比矩阵

### 各引擎 WAL 归档核心能力总览

| 引擎 | 连续归档 | 云存储 | 压缩 | 加密 | PITR 粒度 | 并行恢复 | 工具生态 |
|------|---------|-------|------|------|----------|---------|---------|
| PostgreSQL | 是 | 工具 | 工具 | 工具 | 时间/LSN/XID | 有限 | pgBackRest/wal-g/barman |
| MySQL | 部分 | 工具 | 8.0+ | MEB | 时间/位置/GTID | 是 | xtrabackup/mariabackup |
| Oracle | 是 | RMAN | 是 | 是 | 时间/SCN/序号 | 是 | RMAN/OSB |
| SQL Server | 是 | URL | 是 | 是 | 时间/标记 | 是 | 原生 + Azure |
| DB2 | 是 | TSM/Vendor | 是 | 是 | 时间/LSN | 是 | Spectrum Protect |
| Snowflake | 托管 | 内建 | 自动 | 自动 | 时间/语句 | N/A | 无需 |
| BigQuery | 托管 | 内建 | 自动 | 自动 | 时间 | N/A | 无需 |
| CockroachDB | 是 | 原生 | 是 | 是 | HLC 时间 | 是 | 内建 |
| TiDB | 是 | 原生 | 是 | 是 | 时间/TS | 是 | BR |
| OceanBase | 是 | 原生 | 是 | 是 | 时间/SCN | 是 | OBBackup |
| YugabyteDB | 是 | 原生 | 是 | 是 | 时间/hybrid_time | 是 | yb-admin |

### 场景选型建议

| 场景 | 推荐方案 | 原因 |
|------|---------|------|
| PG 生产集群（自建） | pgBackRest + S3 | 社区事实标准，功能全 |
| PG + K8s / 云原生 | wal-g + object storage | Go 实现，无 Python 依赖 |
| MySQL 生产集群 | Percona XtraBackup + binlog 归档 | 开源成熟 |
| Oracle 企业 | RMAN + Data Guard | Oracle 官方全套 |
| SQL Server on Azure | BACKUP TO URL + Managed Instance | 原生集成 |
| 低运维诉求 | Snowflake/BigQuery/Spanner | 完全托管 |
| 分布式 NewSQL | CockroachDB BACKUP INTO / TiDB BR | 原生声明式 |
| 嵌入式 SQLite | Litestream / WAL 复制到 S3 | SQLite 生态 |
| 极低成本归档 | S3 Glacier Deep Archive | $0.00099/GB/月 |
| 零 RPO 金融 | 同步复制 + 归档双保险 | 两层冗余 |

## 参考资料

- PostgreSQL: [Continuous Archiving and Point-in-Time Recovery](https://www.postgresql.org/docs/current/continuous-archiving.html)
- PostgreSQL: [Archive Modules (15+)](https://www.postgresql.org/docs/current/archive-modules.html)
- PostgreSQL: [Recovery Configuration](https://www.postgresql.org/docs/current/recovery-config.html)
- pgBackRest: [User Guide](https://pgbackrest.org/user-guide.html)
- wal-g: [PostgreSQL Docs](https://github.com/wal-g/wal-g/blob/master/docs/PostgreSQL.md)
- Barman: [Documentation](https://docs.pgbarman.org/)
- MySQL: [Point-in-Time Recovery](https://dev.mysql.com/doc/refman/8.0/en/point-in-time-recovery.html)
- Oracle: [Database Backup and Recovery User's Guide](https://docs.oracle.com/en/database/oracle/oracle-database/19/bradv/index.html)
- Oracle: [RMAN Reference](https://docs.oracle.com/en/database/oracle/oracle-database/19/rcmrf/index.html)
- SQL Server: [Recovery Models](https://learn.microsoft.com/en-us/sql/relational-databases/backup-restore/recovery-models-sql-server)
- SQL Server: [Backup to URL](https://learn.microsoft.com/en-us/sql/relational-databases/backup-restore/sql-server-backup-to-url)
- DB2: [Database Logging](https://www.ibm.com/docs/en/db2/11.5?topic=logging-database-recovery)
- Snowflake: [Time Travel](https://docs.snowflake.com/en/user-guide/data-time-travel)
- BigQuery: [Point-in-time Recovery](https://cloud.google.com/bigquery/docs/time-travel)
- CockroachDB: [BACKUP Reference](https://www.cockroachlabs.com/docs/stable/backup.html)
- TiDB: [PITR Overview](https://docs.pingcap.com/tidb/stable/br-pitr-guide)
- YugabyteDB: [PITR](https://docs.yugabyte.com/preview/manage/backup-restore/point-in-time-recovery/)
- Mohan, C. et al. "ARIES: A Transaction Recovery Method Supporting Fine-Granularity Locking and Partial Rollbacks Using Write-Ahead Logging" (1992), ACM TODS
