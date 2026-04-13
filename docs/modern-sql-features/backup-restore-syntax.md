# 备份与恢复语法 (Backup and Recovery Syntax)

数据库可以丢任何东西，唯独不能丢数据。然而，备份与恢复却是 SQL 世界里最不"标准"的领域——SQL 标准从未规定过 `BACKUP DATABASE` 应该长什么样，每一家厂商都按照自己对存储引擎、文件格式、灾备模型的理解，独立演化出了一整套语法、命令行工具与运维范式。从 SQL Server 的 `BACKUP DATABASE ... TO DISK`、Oracle 的 RMAN，到 PostgreSQL 的 `pg_basebackup`、Snowflake "看不见"的 Time Travel，45+ 个数据库引擎在这一领域呈现出比任何其他主题都更剧烈的分化。

本文系统对比这些数据库在 SQL 级 BACKUP/RESTORE 语句、命令行工具、物理 vs 逻辑备份、热备份、增量/差异备份、PITR、WAL 归档、云存储备份、快照、跨版本恢复以及备份加密 11 个维度上的差异，并给出每个主流引擎的详细语法示例。如果说 SELECT 语句体现了 SQL 标准的胜利，那么 BACKUP 语句就是 SQL 标准的彻底缺席。

## SQL 标准对备份的态度：完全没有

ISO/IEC 9075（SQL:2023 及之前所有版本）从未定义任何 `BACKUP`、`RESTORE`、`DUMP`、`LOAD DATABASE` 语句。原因不难理解：

1. **备份本质上是物理操作**：涉及文件、块、页、WAL/redo log，与 SQL 这种声明式数据语言的抽象层次不匹配。
2. **每个引擎的存储格式完全不同**：Oracle 的 datafile、PostgreSQL 的 base directory、SQL Server 的 mdf/ldf、ClickHouse 的 parts，物理结构没有共性。
3. **灾备模型涉及部署架构**：主备复制、共享存储、对象存储、磁带库都不属于 SQL 语言本身的范畴。

唯一与 SQL 标准沾边的是 `IMPORT/EXPORT`、`COPY`、`LOAD`、`UNLOAD` 这类**逻辑数据导入导出**操作（参见 `bulk-import-export.md` 与 `copy-bulk-load.md`），但它们只能复制表数据与结构，不包括统计信息、用户、权限、序列状态、复制槽、WAL 流等运行时状态，因此严格来说不能称为"备份"。

结果就是：**所有真正的 BACKUP/RESTORE 语法都是厂商私有扩展**。掌握一种数据库的备份方式，几乎完全不能迁移到另一种数据库。

## 支持矩阵

### 矩阵一：SQL 级 BACKUP / RESTORE 语句

| 引擎 | SQL BACKUP 语句 | SQL RESTORE 语句 | 关键字 | 版本 |
|------|----------------|-----------------|--------|------|
| PostgreSQL | -- | -- | （仅命令行工具）| -- |
| MySQL | -- | -- | （仅 mysqldump/CLONE）| -- |
| MariaDB | `BACKUP STAGE` | -- | 备份阶段控制 | 10.4+ |
| SQLite | -- | -- | （`.backup` shell 命令） | -- |
| Oracle | -- | -- | （RMAN / Data Pump） | -- |
| SQL Server | `BACKUP DATABASE` | `RESTORE DATABASE` | T-SQL 内置 | 7.0+ |
| DB2 | `BACKUP DATABASE` | `RESTORE DATABASE` | CLP / SQL | 全版本 |
| Snowflake | -- | -- | Time Travel + Fail-safe | GA |
| BigQuery | `CREATE SNAPSHOT TABLE` | `CREATE TABLE CLONE` | 快照与克隆 | GA |
| Redshift | `CREATE SNAPSHOT` (CLI) | `RESTORE TABLE FROM SNAPSHOT` | API/CLI 为主 | GA |
| DuckDB | `EXPORT DATABASE` | `IMPORT DATABASE` | 文件目录形式 | 0.3+ |
| ClickHouse | `BACKUP` / `RESTORE` | 是 | 完整 SQL 语句 | 22.4+ (2022) |
| Trino | -- | -- | 计算引擎，无存储 | -- |
| Presto | -- | -- | 计算引擎，无存储 | -- |
| Spark SQL | -- | -- | （依赖底层存储） | -- |
| Hive | `EXPORT TABLE` | `IMPORT TABLE` | 表级 | 0.8+ |
| Flink SQL | -- | -- | （Savepoint 是状态而非数据） | -- |
| Databricks | `CLONE`（Delta 表） | `RESTORE TABLE TO VERSION` | Delta 时间旅行 | DBR 7.4+ |
| Teradata | -- | -- | （ARC / DSA / NetBackup） | -- |
| Greenplum | -- | -- | （gpbackup / gprestore） | -- |
| CockroachDB | `BACKUP` | `RESTORE` | 完整 SQL 语句 | 2.0+ |
| TiDB | -- | -- | （BR 工具 / br SQL 语句 6.5+） | -- |
| OceanBase | -- | -- | （OBProxy / OMS / obloader） | -- |
| YugabyteDB | -- | -- | （yb-admin / 分布式快照） | -- |
| SingleStore | `BACKUP DATABASE` | `RESTORE DATABASE` | 完整 SQL 语句 | 6.0+ |
| Vertica | -- | -- | （vbr.py） | -- |
| Impala | -- | -- | （依赖 HDFS/HMS） | -- |
| StarRocks | `BACKUP` / `RESTORE` | 是 | 完整 SQL 语句 | 1.18+ |
| Doris | `BACKUP` / `RESTORE` | 是 | 完整 SQL 语句 | 0.13+ |
| MonetDB | -- | -- | （`msqldump` 工具） | -- |
| CrateDB | `CREATE SNAPSHOT` | `RESTORE SNAPSHOT` | 完整 SQL 语句 | 0.55+ |
| TimescaleDB | -- | -- | （继承 PostgreSQL） | -- |
| QuestDB | `BACKUP TABLE` / `BACKUP DATABASE` | -- | 单边 SQL（无 RESTORE） | 6.0+ |
| Exasol | -- | -- | （EXAoperation / 远程归档） | -- |
| SAP HANA | `BACKUP DATA` | `RECOVER DATABASE` | 完整 SQL 语句 | 1.0+ |
| Informix | -- | -- | （ontape / onbar） | -- |
| Firebird | -- | -- | （gbak / nbackup） | -- |
| H2 | `BACKUP TO` | `RUNSCRIPT FROM` | 文件级备份 | 全版本 |
| HSQLDB | `BACKUP DATABASE TO` | （重启时自动）| 在线备份 | 1.9+ |
| Derby | -- | -- | （`SYSCS_BACKUP_DATABASE` 系统过程） | 10+ |
| Amazon Athena | -- | -- | （计算引擎，依赖 S3） | -- |
| Azure Synapse | -- | -- | （门户/REST API 自动备份） | -- |
| Google Spanner | -- | -- | （`gcloud spanner backups create`） | -- |
| Materialize | -- | -- | （持续物化，依赖上游） | -- |
| RisingWave | -- | -- | （Meta 节点 snapshot） | -- |
| InfluxDB | -- | -- | （`influxd backup`） | -- |
| Databend | -- | -- | （依赖对象存储版本控制） | -- |
| Yellowbrick | -- | -- | （`ybbackup`） | -- |
| Firebolt | -- | -- | （Engine 与 Database 解耦，自动持久化） | -- |

> 统计：约 13 个引擎提供 SQL 级 BACKUP/RESTORE 语句，其余 30+ 个完全依赖命令行工具、外部工具或云控制平面。

### 矩阵二：命令行 / 外部工具

| 引擎 | 主要工具 | 用途 |
|------|---------|------|
| PostgreSQL | `pg_dump` / `pg_dumpall` / `pg_basebackup` / `pg_restore` | 逻辑 + 物理 |
| MySQL | `mysqldump` / `mysqlpump` / `mysqlbackup` (Enterprise) / `xtrabackup` | 逻辑 + 物理 |
| MariaDB | `mariadb-dump` / `mariabackup` | 逻辑 + 物理 |
| SQLite | `.dump` / `.backup` (sqlite3 shell) / `sqlite3_backup` API | 逻辑 + 物理 |
| Oracle | RMAN / Data Pump (`expdp` / `impdp`) / `exp` / `imp` | 物理 + 逻辑 |
| SQL Server | `sqlcmd` / `bcp` / Azure Backup / SSMS | 命令行执行 T-SQL |
| DB2 | `db2 BACKUP DATABASE` (CLP) / `db2move` / `db2look` | 物理 + 逻辑 |
| Snowflake | -- | 内建，无外部工具 |
| BigQuery | `bq extract` / `bq load` | 仅数据导出导入 |
| Redshift | `aws redshift create-cluster-snapshot` | API 驱动 |
| DuckDB | `EXPORT DATABASE 'dir'` (SQL) | 文件目录 |
| ClickHouse | `clickhouse-backup` (开源工具) / `clickhouse-client` 执行 BACKUP SQL | 物理 + 逻辑 |
| Hive | `hive --service` / `distcp` + `EXPORT TABLE` | 表级 |
| Databricks | `dbutils.fs` / DBFS / Unity Catalog 表克隆 | 表级 |
| Teradata | `arcmain` (ARC) / DSA / `tdwallet` / NetBackup | 物理 + 逻辑 |
| Greenplum | `gpbackup` / `gprestore` / `pg_dump` | 并行物理/逻辑 |
| CockroachDB | `cockroach sql` 执行 BACKUP / `cockroach debug` | SQL 语句驱动 |
| TiDB | `br` (Backup & Restore CLI) / `dumpling` / `tidb-lightning` | 物理 + 逻辑 |
| OceanBase | `obloader` / `obdumper` / OMS | 逻辑 |
| YugabyteDB | `yb-admin create_snapshot` / `ysql_dump` / `yugabyted backup` | 物理 + 逻辑 |
| SingleStore | `singlestore-toolbox` / SQL BACKUP | SQL 为主 |
| Vertica | `vbr.py` | 物理 + 增量 |
| Impala | `impala-shell` 不含备份；依赖 `distcp` + HMS dump | 间接 |
| StarRocks | `BACKUP` SQL + Repository（指向 HDFS/S3） | SQL 驱动 |
| Doris | `BACKUP` SQL + Repository | SQL 驱动 |
| MonetDB | `msqldump` | 逻辑 |
| CrateDB | `CREATE/DROP REPOSITORY` + `SNAPSHOT` SQL | SQL 驱动 |
| TimescaleDB | `pg_dump` / `pg_basebackup` / `timescaledb-backup` | 同 PG |
| QuestDB | `BACKUP TABLE`/`BACKUP DATABASE` SQL，复制目录 | 半物理 |
| Exasol | EXAoperation Web UI / 远程归档卷 | 物理 |
| SAP HANA | HDBSQL / Cockpit / `hdbbackint` | 物理 + 日志 |
| Informix | `ontape` / `onbar` (集成 NetBackup/TSM) | 物理 + 日志 |
| Firebird | `gbak` (逻辑) / `nbackup` (物理增量) | 物理 + 逻辑 |
| H2 | `BACKUP TO 'file.zip'` SQL / `Script` 工具 | 文件级 |
| HSQLDB | `BACKUP DATABASE` SQL / `SqlTool` | 文件级 |
| Derby | `SYSCS_UTIL.SYSCS_BACKUP_DATABASE` 系统过程 | 文件级 |
| Amazon Athena | -- | 数据存于 S3，依赖 S3 版本/复制 |
| Azure Synapse | Azure Portal / REST API（自动每 8 小时） | 服务级 |
| Google Spanner | `gcloud spanner backups create` | 服务级 |
| Materialize | -- | 状态可重建 |
| RisingWave | `risectl meta backup-meta` | Meta 快照 |
| InfluxDB | `influxd backup` / `influx backup` | 物理 |
| Databend | 依赖对象存储版本控制 / `BACKUP/RESTORE` (Enterprise) | 物理 |
| Yellowbrick | `ybbackup` / `ybrestore` | 物理 |
| Firebolt | -- | Engine 自动持久化 Database |

### 矩阵三：物理 vs 逻辑备份

| 引擎 | 物理备份 | 逻辑备份 | 备注 |
|------|---------|---------|------|
| PostgreSQL | `pg_basebackup` / 文件系统快照 | `pg_dump` / `pg_dumpall` | 两者均成熟 |
| MySQL | XtraBackup / mysqlbackup / CLONE 插件 | mysqldump / mysqlpump | CLONE 8.0.17+ |
| MariaDB | mariabackup | mariadb-dump | 从 XtraBackup fork |
| SQLite | 文件复制 / `.backup` 命令 | `.dump` 生成 SQL | 单文件 |
| Oracle | RMAN | Data Pump expdp | RMAN 是物理备份核心 |
| SQL Server | `BACKUP DATABASE` 物理页 | bcp / `BACPAC` (Azure) | 内建即物理 |
| DB2 | `BACKUP DATABASE` | `db2move` | 内建即物理 |
| ClickHouse | `BACKUP` SQL（part 文件） | `INSERT INTO FUNCTION file()` | 22.4+ |
| Snowflake | （内部自动多版本存储） | `COPY INTO @stage` | 用户不感知物理层 |
| BigQuery | 表快照 | `EXPORT DATA` | 元数据级快照 |
| Redshift | 集群快照（增量块级） | `UNLOAD` to S3 | 块级增量 |
| DuckDB | 文件复制 | `EXPORT DATABASE` | 单文件 |
| Greenplum | gpbackup（并行） | `pg_dump` | 并行物理为主 |
| CockroachDB | `BACKUP` SQL（SST 文件） | -- | 分布式物理 |
| TiDB | BR（SST 文件） | `dumpling` | 物理推荐 |
| OceanBase | OB 自带物理备份 | `obdumper` | -- |
| YugabyteDB | yb-admin snapshot（物理） | `ysql_dump` | -- |
| Vertica | vbr.py 物理 | `vsql` 导出 | 物理为主 |
| Teradata | ARC（数据块级） | TPT export | 物理为主 |
| SAP HANA | `BACKUP DATA` | `EXPORT` SQL | 物理为主 |
| Firebird | nbackup（增量页） | gbak | 两者并存 |
| Informix | onbar / ontape | dbexport / dbschema | 物理为主 |

### 矩阵四：热备份（在线备份，无需停机）

| 引擎 | 支持热备份 | 实现方式 |
|------|-----------|---------|
| PostgreSQL | 是 | `pg_start_backup()` + WAL 归档 / `pg_basebackup` |
| MySQL InnoDB | 是 | XtraBackup 利用 redo log；CLONE 插件 |
| MariaDB | 是 | mariabackup |
| SQLite | 是（有限） | `.backup` 使用页面级 mutex |
| Oracle | 是 | RMAN（无需 BEGIN BACKUP 模式）/ ALTER TABLESPACE BEGIN BACKUP |
| SQL Server | 是 | 内建 BACKUP DATABASE 默认在线 |
| DB2 | 是 | `BACKUP DATABASE ... ONLINE` |
| Snowflake | 是 | 完全无感（持续多版本存储） |
| BigQuery | 是 | 快照基于元数据 |
| Redshift | 是 | 自动快照不影响查询 |
| ClickHouse | 是 | `BACKUP` 利用 part 不可变性 |
| DuckDB | 否（推荐离线） | 单文件 + WAL，建议 EXPORT 时只读 |
| CockroachDB | 是 | MVCC + 时间戳 |
| TiDB | 是 | TiKV snapshot |
| YugabyteDB | 是 | 分布式快照 |
| Greenplum | 是 | gpbackup 利用 PostgreSQL pg_start_backup |
| Vertica | 是 | vbr.py 利用 ROS 不可变性 |
| SAP HANA | 是 | 内建 |
| Teradata | 是 | ARC online dump |
| Firebird | 是 | nbackup 在线增量 |
| Informix | 是 | onbar online |
| H2 | 是 | `BACKUP TO` 在线 |

### 矩阵五：增量 / 差异备份

| 引擎 | 增量备份 | 差异备份 | 实现 |
|------|---------|---------|------|
| PostgreSQL | 17+ `pg_basebackup --incremental` | -- | 基于 WAL summary，17 之前需第三方 (pgBackRest, Barman) |
| MySQL | XtraBackup `--incremental` | -- | 基于 LSN |
| MariaDB | mariabackup `--incremental-basedir` | -- | 基于 LSN |
| Oracle | RMAN level 0/1 | RMAN cumulative | 块级 |
| SQL Server | 是 (`WITH DIFFERENTIAL`) + 日志备份 | 是 | 三层备份模型 |
| DB2 | `INCREMENTAL` / `INCREMENTAL DELTA` | 是 | 三层备份模型 |
| Snowflake | 自动（连续） | -- | 内部分片机制 |
| BigQuery | -- | -- | 快照即元数据指针 |
| Redshift | 自动增量快照 | -- | 块级 |
| ClickHouse | `BACKUP ... SETTINGS base_backup` | -- | 22.6+ |
| CockroachDB | `BACKUP ... INCREMENTAL FROM` | -- | 时间戳增量 |
| TiDB | BR `--lastbackupts` | -- | TS 增量 |
| Vertica | vbr.py 增量 | -- | epoch 级 |
| Greenplum | gpbackup `--incremental` | -- | 表级 |
| SAP HANA | `BACKUP DATA INCREMENTAL` | `BACKUP DATA DIFFERENTIAL` | 三层 |
| Teradata | ARC incremental | -- | -- |
| Firebird | nbackup level 0..N | -- | 多级增量 |
| Informix | onbar level 0/1/2 | -- | 三层 |
| YugabyteDB | yb-admin 增量快照 | -- | -- |

### 矩阵六：Point-in-Time Recovery (PITR)

| 引擎 | 支持 PITR | 粒度 | 实现 |
|------|----------|------|------|
| PostgreSQL | 是 | 任意时间戳 / LSN / xid | base + WAL replay |
| MySQL | 是 | binlog position / GTID / 时间 | full + binlog |
| MariaDB | 是 | binlog position / 时间 | full + binlog |
| SQLite | 否 | -- | -- |
| Oracle | 是 | SCN / 时间 / log sequence | RMAN + archived redo |
| SQL Server | 是 | LSN / 时间 (Full Recovery Model) | Full + log backup chain |
| DB2 | 是 | log sequence number / 时间 | Forward recovery |
| Snowflake | 是 | 任意时间戳（默认 1 天，最高 90 天） | Time Travel |
| BigQuery | 是 | 7 天内任意时间戳 | Time Travel（不可配置） |
| Redshift | 是 | 任意时间戳（保留期内） | 自动快照 + 回放 |
| DuckDB | 否 | -- | -- |
| ClickHouse | 部分 | 备份点 | BACKUP 之间无连续 PITR |
| CockroachDB | 是 | 任意时间（最长保留期内） | MVCC + revision history |
| TiDB | 是 | 任意时间 (5.4+) | Backup + 持续 CDC log |
| YugabyteDB | 是 | 时间戳 | 分布式快照 + WAL |
| Greenplum | 是 | 时间 / WAL | gpbackup + WAL |
| Vertica | 是 | epoch | epoch 级 |
| SingleStore | 是 | 时间 | 增量 + log |
| SAP HANA | 是 | 时间 / 日志位置 | log backup |
| Teradata | 是 | 时间 | DSA + journal |
| Firebird | 否（仅完整备份点） | -- | -- |
| Informix | 是 | 时间 / log | onbar log replay |
| Google Spanner | 是 | 1 小时（query staleness）/ 备份保留 7 天 | -- |
| Azure Synapse | 是 | 8 小时一次自动快照 | 服务级 |

### 矩阵七：WAL / Redo Log 归档

| 引擎 | 归档机制 | 归档目标 |
|------|---------|---------|
| PostgreSQL | `archive_command` / `archive_library` (15+) | 文件 / S3 (pgBackRest, wal-g) |
| MySQL | binlog (server_id) + `mysqlbinlog --read-from-remote-server` | 文件 / S3 |
| MariaDB | binlog | 文件 / S3 |
| Oracle | `LOG_ARCHIVE_DEST_n` | 文件 / RMAN catalog |
| SQL Server | Transaction log backup chain | 文件 / Azure Blob URL |
| DB2 | `LOGARCHMETH1` / `LOGARCHMETH2` | 文件 / TSM / 用户出口 |
| SAP HANA | log_mode = normal + log backup | 文件 / 第三方 backint |
| Informix | onbar logical log backup | TSM / NetBackup |
| Teradata | Permanent journal | 自动 |
| ClickHouse | -- | 不存在传统 WAL 归档 |
| Snowflake | -- | 内部，不暴露 |
| BigQuery | -- | -- |
| Redshift | -- | -- |
| CockroachDB | -- | 通过 MVCC + GC 配置实现 |

### 矩阵八：备份到云对象存储

| 引擎 | 直接 S3 / GCS / Azure Blob | 备注 |
|------|---------------------------|------|
| PostgreSQL | 通过 pgBackRest / wal-g / Barman Cloud | 主流方案 |
| MySQL | XtraBackup `--stream` 配合 aws cli | 间接 |
| Oracle | RMAN with `SBT_TAPE` + Oracle DB Backup Cloud Service | 是 |
| SQL Server | `BACKUP DATABASE ... TO URL = 'https://...blob.core.windows.net/...'` | 原生 |
| DB2 | `BACKUP DATABASE ... TO 'DB2REMOTE://...'` | Db2 11.5+ |
| ClickHouse | `BACKUP ... TO S3('https://bucket/path', 'AKID', 'secret')` | 原生 |
| Snowflake | 内部存储就是云对象存储 | -- |
| BigQuery | 快照即云存储 | -- |
| Redshift | 自动到 S3 | 服务级 |
| CockroachDB | `BACKUP INTO 's3://...'` / `gs://...` / `azure://...` | 原生 |
| TiDB | `br backup --storage 's3://...'` | 是 |
| YugabyteDB | yb-admin / yba 支持 S3 | 是 |
| Greenplum | gpbackup `--plugin-config` (S3 plugin) | 是 |
| StarRocks | `BACKUP ... TO repository_in_s3` | 是 |
| Doris | `BACKUP ... TO repository_in_s3` | 是 |
| Vertica | vbr.py 支持 S3/GCS/Azure | 是 |
| SAP HANA | `hdbbackint` 集成 | 第三方 backint |
| Databricks | DBFS 即对象存储 | 原生 |
| InfluxDB | `influxd backup` 不直接，但可流到对象存储 | 间接 |
| Spanner | gcloud backups 自动在 GCS | 是 |
| Yellowbrick | `ybbackup` 支持 S3/GCS/Azure | 是 |
| Databend | 数据本身存于对象存储 | -- |

### 矩阵九：快照（文件系统 / 卷快照）

| 引擎 | 支持文件系统快照备份 | 注意事项 |
|------|--------------------|---------|
| PostgreSQL | 是（需 pg_start_backup 或 LVM/ZFS 一致性） | 必须包含所有表空间 |
| MySQL InnoDB | 是（FLUSH TABLES WITH READ LOCK + LVM） | -- |
| Oracle | 是（ALTER DATABASE BEGIN BACKUP / Storage Snapshot Optimization） | 12c+ 优化 |
| SQL Server | 是（VSS 卷影副本）/ Snapshot Backup (`WITH SNAPSHOT`) | -- |
| DB2 | `BACKUP DATABASE ... USE SNAPSHOT` | 集成存储快照 |
| ClickHouse | 是（part 不可变） | 推荐 BACKUP SQL |
| SAP HANA | `BACKUP DATA CREATE SNAPSHOT` / `BACKUP DATA CLOSE SNAPSHOT` | 与存储集成 |
| Vertica | -- | epoch 取代 |
| 大多数云原生 | 不需要 | 服务级快照 |

### 矩阵十：跨版本恢复

| 引擎 | 跨主版本恢复 | 限制 |
|------|-------------|------|
| PostgreSQL | 物理（pg_basebackup）：仅同主版本 | 跨版本必须 pg_dump/pg_restore + pg_upgrade |
| MySQL | 物理：通常仅同主版本 | 逻辑 mysqldump 跨版本兼容 |
| Oracle | RMAN 跨版本：低版本 → 高版本可 (`RECOVER DATABASE`) | 高 → 低不可 |
| SQL Server | 高版本可恢复低版本 backup（不可逆） | -- |
| DB2 | 通过 `db2ckbkp` 检查兼容性 | 同 fix pack 范围 |
| Snowflake | -- | 用户不感知版本 |
| ClickHouse | BACKUP 通常向前兼容 | -- |
| DuckDB | 不同主版本格式可能不兼容 | EXPORT/IMPORT 跨版本可 |

### 矩阵十一：备份加密

| 引擎 | 备份加密 | 算法 / 机制 |
|------|---------|------------|
| SQL Server | `BACKUP DATABASE ... WITH ENCRYPTION (ALGORITHM = AES_256, SERVER CERTIFICATE = ...)` | 2014+ |
| Oracle | RMAN `CONFIGURE ENCRYPTION FOR DATABASE ON` (TDE / 密码 / 透明) | 三种模式 |
| DB2 | `BACKUP DATABASE ... ENCRYPT ENCRLIB ... ENCROPTS ...` | 是 |
| MySQL Enterprise Backup | `--encrypt-password` | AES |
| MariaDB | mariabackup `--encrypt=AES256 --encrypt-key-file` | AES |
| PostgreSQL | pg_dump 通过外部 GPG / pgBackRest `--repo-cipher-type` | 第三方 |
| ClickHouse | `BACKUP ... SETTINGS encryption_password='...'` | 是 |
| CockroachDB | `BACKUP ... WITH encryption_passphrase = '...'` | 是 |
| SAP HANA | `BACKUP DATA ... USING FILE ('...') CREDENTIAL ...` + 数据卷加密 | 是 |
| Snowflake | 默认全程加密（用户不可见） | -- |
| BigQuery | 默认 + CMEK | -- |
| Vertica | vbr.py + S3 SSE / 客户端加密 | 是 |
| TiDB | BR `--crypter` | AES128/192/256 |

## SQL Server：教科书级的 BACKUP/RESTORE T-SQL

SQL Server 是 SQL 级备份语句最完整、最成熟的代表。`BACKUP` 与 `RESTORE` 都是真正的 T-SQL 语句，可以在事务上下文之外执行，并与恢复模型（`SIMPLE` / `BULK_LOGGED` / `FULL`）紧密集成。

```sql
-- 完整数据库备份到本地磁盘
BACKUP DATABASE Sales
TO DISK = 'D:\Backups\Sales_Full.bak'
WITH FORMAT,                  -- 覆盖/初始化备份介质
     INIT,                    -- 重写已有备份集
     NAME = 'Sales-Full Database Backup',
     COMPRESSION,             -- 启用备份压缩 (2008+)
     CHECKSUM,                -- 校验和保护
     STATS = 10;              -- 每 10% 输出一次进度

-- 差异备份（自上次完整备份后的更改）
BACKUP DATABASE Sales
TO DISK = 'D:\Backups\Sales_Diff.bak'
WITH DIFFERENTIAL, COMPRESSION;

-- 事务日志备份
BACKUP LOG Sales
TO DISK = 'D:\Backups\Sales_Log_20260413_1200.trn';

-- 备份到 Azure Blob URL（2012+ Cumulative Update / 2014 GA）
BACKUP DATABASE Sales
TO URL = 'https://mystorage.blob.core.windows.net/backups/Sales.bak'
WITH CREDENTIAL = 'AzureBlobCredential',
     COMPRESSION,
     ENCRYPTION (
         ALGORITHM = AES_256,
         SERVER CERTIFICATE = BackupCert
     ),
     STATS = 5;

-- 多文件并行备份（跨多个磁盘条带化以提升吞吐）
BACKUP DATABASE LargeDB
TO DISK = 'D:\Bk\LargeDB_1.bak',
   DISK = 'E:\Bk\LargeDB_2.bak',
   DISK = 'F:\Bk\LargeDB_3.bak',
   DISK = 'G:\Bk\LargeDB_4.bak'
WITH FORMAT, COMPRESSION, MAXTRANSFERSIZE = 4194304, BUFFERCOUNT = 50;

-- 还原完整 + 差异 + 日志（PITR）
RESTORE DATABASE Sales
FROM DISK = 'D:\Backups\Sales_Full.bak'
WITH NORECOVERY, REPLACE;

RESTORE DATABASE Sales
FROM DISK = 'D:\Backups\Sales_Diff.bak'
WITH NORECOVERY;

RESTORE LOG Sales
FROM DISK = 'D:\Backups\Sales_Log_20260413_1200.trn'
WITH STOPAT = '2026-04-13T11:45:00', RECOVERY;

-- 仅复制备份（不打断备份链）
BACKUP DATABASE Sales
TO DISK = 'D:\Backups\Sales_CopyOnly.bak'
WITH COPY_ONLY, COMPRESSION;
```

要点：
- `WITH NORECOVERY` 让数据库保持"恢复中"状态以应用后续的差异/日志备份；最后一步用 `WITH RECOVERY` 完成恢复。
- 备份链一旦中断（例如 `BACKUP LOG ... WITH NO_LOG` 或恢复模型变更），后续日志备份将无效。
- `STOPAT` 实现 PITR；可以精确到秒。

## Oracle：RMAN + Data Pump 双轨制

Oracle 没有 SQL 级 `BACKUP` 语句，备份完全通过 RMAN（Recovery Manager）实现，逻辑导出导入则使用 Data Pump（`expdp`/`impdp`）。

```bash
# RMAN 配置示例
rman target /

CONFIGURE RETENTION POLICY TO RECOVERY WINDOW OF 14 DAYS;
CONFIGURE BACKUP OPTIMIZATION ON;
CONFIGURE DEFAULT DEVICE TYPE TO DISK;
CONFIGURE CHANNEL DEVICE TYPE DISK FORMAT '/u01/backup/%U';
CONFIGURE CONTROLFILE AUTOBACKUP ON;
CONFIGURE ENCRYPTION FOR DATABASE ON;
```

```sql
-- RMAN 命令（在 rman 会话中执行）

-- 完整数据库备份 + 归档日志
BACKUP DATABASE PLUS ARCHIVELOG;

-- 增量 0 级（基线）
BACKUP INCREMENTAL LEVEL 0 DATABASE TAG 'WEEKLY_FULL';

-- 增量 1 级（差异）
BACKUP INCREMENTAL LEVEL 1 DATABASE TAG 'DAILY_INC';

-- 增量 1 级累积（cumulative，自上次 0 级以来所有变化）
BACKUP INCREMENTAL LEVEL 1 CUMULATIVE DATABASE;

-- 表空间级备份
BACKUP TABLESPACE users, sales;

-- 恢复到时间点
RUN {
  SET UNTIL TIME "TO_DATE('2026-04-13 11:45:00','YYYY-MM-DD HH24:MI:SS')";
  RESTORE DATABASE;
  RECOVER DATABASE;
  ALTER DATABASE OPEN RESETLOGS;
}

-- 恢复到 SCN
RUN {
  SET UNTIL SCN 12345678;
  RESTORE DATABASE;
  RECOVER DATABASE;
  ALTER DATABASE OPEN RESETLOGS;
}

-- 块级别恢复（仅恢复损坏块，不影响其他数据）
RECOVER DATAFILE 4 BLOCK 1234;
RECOVER CORRUPTION LIST;
```

Data Pump 逻辑导出导入：

```bash
# 导出整个数据库
expdp system/oracle FULL=Y DIRECTORY=DATA_PUMP_DIR \
      DUMPFILE=full_%U.dmp PARALLEL=4 \
      ENCRYPTION=ALL ENCRYPTION_PASSWORD=secret \
      LOGFILE=full_export.log

# 按 schema 导出
expdp scott/tiger SCHEMAS=hr,sales DIRECTORY=DATA_PUMP_DIR \
      DUMPFILE=hr_sales.dmp COMPRESSION=ALL

# 按表导出 + 查询过滤
expdp scott/tiger TABLES=orders DIRECTORY=DATA_PUMP_DIR \
      DUMPFILE=orders_2026.dmp \
      QUERY='orders:"WHERE order_date >= DATE ''2026-01-01''"'

# 导入并重映射 schema
impdp system/oracle DIRECTORY=DATA_PUMP_DIR DUMPFILE=hr_sales.dmp \
      REMAP_SCHEMA=hr:hr_test REMAP_TABLESPACE=users:test_users
```

## PostgreSQL：pg_dump + pg_basebackup + WAL 归档

PostgreSQL 没有任何 SQL 级备份语句，全部通过命令行工具实现。

```bash
# 逻辑备份：pg_dump（单库）
pg_dump -h db.example.com -U postgres -d sales \
        -F custom -Z 9 -j 4 \
        -f /backup/sales.dump
# -F custom: 自定义二进制格式，支持 pg_restore 选择性恢复
# -Z 9: 最高压缩
# -j 4: 4 并行 worker（仅 directory 格式才更快，custom 格式串行写）

# 全集群逻辑备份（包括角色与表空间定义）
pg_dumpall -h db.example.com -U postgres \
           -f /backup/cluster_$(date +%F).sql

# 物理备份：pg_basebackup
pg_basebackup -h primary.example.com -U replicator \
              -D /backup/base \
              -F tar -z -P -X stream \
              -R                  # 自动创建 standby.signal
# -X stream: 备份过程中并行流式拉取 WAL，确保一致性
# -F tar -z: 输出 gzip 压缩 tar

# PostgreSQL 17+ 增量物理备份
pg_basebackup -D /backup/incr1 -i /backup/base/backup_manifest

# 恢复物理备份 + WAL 归档（PITR）
# 1. 解压基础备份到数据目录
# 2. 创建 recovery 配置（PostgreSQL 12+ 写在 postgresql.auto.conf）
cat >> $PGDATA/postgresql.auto.conf <<EOF
restore_command = 'cp /archive/%f %p'
recovery_target_time = '2026-04-13 11:45:00+08'
recovery_target_action = 'promote'
EOF
touch $PGDATA/recovery.signal
pg_ctl start
```

```sql
-- pg_restore（从 custom 格式恢复，支持选择性）
-- 仅恢复 schema
pg_restore -d new_db -s /backup/sales.dump
-- 仅恢复指定表
pg_restore -d new_db -t orders -t order_items /backup/sales.dump
-- 列出归档内容
pg_restore -l /backup/sales.dump

-- WAL 归档配置（postgresql.conf）
wal_level = replica
archive_mode = on
archive_command = 'test ! -f /archive/%f && cp %p /archive/%f'
```

第三方主流工具：**pgBackRest**（增量、并行、加密、S3）、**Barman**（远程备份与 PITR 管理）、**wal-g**（WAL/base 备份到对象存储）。

## MySQL / MariaDB：mysqldump、XtraBackup、CLONE 插件

```bash
# mysqldump（逻辑备份）
mysqldump -h db.example.com -u root -p \
          --single-transaction \         # 一致性快照（仅 InnoDB）
          --master-data=2 \              # 记录 binlog position
          --routines --triggers --events \
          --all-databases \
          | gzip > /backup/all_$(date +%F).sql.gz

# 单库 + 显式表
mysqldump --single-transaction sales orders order_items > sales.sql

# mysqlpump：多线程逻辑备份（5.7+）
mysqlpump --default-parallelism=4 --include-databases=sales > sales.sql

# Percona XtraBackup（开源物理热备份）
xtrabackup --backup --target-dir=/backup/full \
           --datadir=/var/lib/mysql --user=root --password=...
xtrabackup --prepare --target-dir=/backup/full

# 增量
xtrabackup --backup --target-dir=/backup/inc1 \
           --incremental-basedir=/backup/full

# mariabackup（MariaDB fork）
mariabackup --backup --target-dir=/backup/full --user=root
mariabackup --prepare --target-dir=/backup/full
mariabackup --copy-back --target-dir=/backup/full
```

MySQL 8.0.17+ 引入 **CLONE 插件**，可在 SQL 内触发物理克隆：

```sql
INSTALL PLUGIN clone SONAME 'mysql_clone.so';

-- 本地克隆（克隆到本机的另一个数据目录）
CLONE LOCAL DATA DIRECTORY = '/var/lib/mysql_clone';

-- 远程克隆（从源实例拉取整个数据）
SET GLOBAL clone_valid_donor_list = 'donor.example.com:3306';
CLONE INSTANCE FROM clone_user@'donor.example.com':3306
      IDENTIFIED BY 'password';
-- 克隆完成后接收方实例自动重启
```

PITR：

```bash
# 1. 还原 mysqldump 或 XtraBackup
# 2. 应用 binlog 到目标时间点
mysqlbinlog --start-position=4 \
            --stop-datetime='2026-04-13 11:45:00' \
            mysql-bin.000123 mysql-bin.000124 | mysql -u root -p
```

## DB2：内建 BACKUP DATABASE / RESTORE DATABASE

DB2 的 `BACKUP DATABASE` 和 `RESTORE DATABASE` 是 CLP（Command Line Processor）命令，但语法接近 SQL：

```sql
-- 完整在线备份到磁盘 + 包含日志
BACKUP DATABASE sales ONLINE TO '/backup/db2'
  WITH 4 BUFFERS BUFFER 1024
  PARALLELISM 4
  COMPRESS
  INCLUDE LOGS;

-- 增量备份
BACKUP DATABASE sales ONLINE INCREMENTAL TO '/backup/db2';

-- 增量 delta 备份（差异）
BACKUP DATABASE sales ONLINE INCREMENTAL DELTA TO '/backup/db2';

-- 加密备份
BACKUP DATABASE sales ONLINE TO '/backup/db2'
  ENCRYPT ENCRLIB 'libdb2encr.so'
  ENCROPTS 'Cipher=AES:Key Length=256';

-- 备份到 S3 (Db2 11.5+)
BACKUP DATABASE sales ONLINE TO 'DB2REMOTE://s3alias//bucket/path/';

-- 还原 + 前滚到时间点
RESTORE DATABASE sales FROM '/backup/db2' TAKEN AT 20260413120000;
ROLLFORWARD DATABASE sales TO 2026-04-13-11.45.00.000000 USING LOCAL TIME
  AND COMPLETE;
```

## Snowflake：没有 BACKUP，只有 Time Travel + Fail-safe

Snowflake 在备份这件事上做了一个根本性的产品决策：**用户永远不需要、也不能直接备份**。所有"备份"语义被两层机制取代：

1. **Time Travel**：在保留期内（Standard 1 天，Enterprise 最长 90 天）可以查询、克隆、恢复任意历史版本。
2. **Fail-safe**：Time Travel 期之后再保留 7 天，仅 Snowflake 支持人员可访问，用于灾难恢复。

```sql
-- 设置表级 Time Travel 保留期
ALTER TABLE orders SET DATA_RETENTION_TIME_IN_DAYS = 30;

-- 查询历史版本（按时间）
SELECT * FROM orders AT (TIMESTAMP => '2026-04-13 11:45:00'::timestamp_tz);

-- 按相对时间
SELECT * FROM orders AT (OFFSET => -60*60*2);  -- 2 小时前

-- 按 query_id（语句之前的状态）
SELECT * FROM orders BEFORE (STATEMENT => '019d8...');

-- 零拷贝克隆（产生独立的可写副本，仅元数据指向）
CREATE TABLE orders_clone CLONE orders
  AT (TIMESTAMP => '2026-04-13 11:45:00'::timestamp_tz);

CREATE DATABASE sales_clone CLONE sales
  AT (TIMESTAMP => '2026-04-13 11:45:00'::timestamp_tz);

-- UNDROP（在保留期内恢复被 DROP 的对象）
DROP TABLE orders;
UNDROP TABLE orders;
DROP DATABASE sales;
UNDROP DATABASE sales;

-- 数据真正离开 Snowflake：COPY INTO 外部 stage
COPY INTO @my_s3_stage/exports/orders
FROM orders
FILE_FORMAT = (TYPE = PARQUET)
HEADER = TRUE;
```

如果需要逻辑层"备份"以满足合规或迁移需求，唯一手段是 `COPY INTO @stage` 配合 Parquet/CSV 文件格式，把数据导到外部对象存储（S3/GCS/Azure Blob）。

## BigQuery：表快照与 Time Travel

BigQuery 同样没有 SQL `BACKUP` 语句，但提供了基于元数据的快照：

```sql
-- 创建表快照（轻量元数据指针，秒级完成）
CREATE SNAPSHOT TABLE mydataset.orders_snap_20260413
CLONE mydataset.orders
OPTIONS (
  expiration_timestamp = TIMESTAMP "2026-07-13 00:00:00 UTC",
  description = "April monthly snapshot"
);

-- 从快照恢复（创建新表）
CREATE TABLE mydataset.orders_restored
CLONE mydataset.orders_snap_20260413;

-- Time Travel：7 天内任意时间戳查询
SELECT * FROM mydataset.orders
FOR SYSTEM_TIME AS OF TIMESTAMP_SUB(CURRENT_TIMESTAMP(), INTERVAL 1 HOUR);

-- 表克隆（可写副本，按"差异"计费）
CREATE TABLE mydataset.orders_dev
CLONE mydataset.orders;

-- 跨地区备份：导出到 GCS
EXPORT DATA OPTIONS (
  uri = 'gs://mybucket/backup/orders/*.parquet',
  format = 'PARQUET',
  overwrite = true
) AS SELECT * FROM mydataset.orders;
```

注意：BigQuery 的 Time Travel 窗口固定 7 天（可在 dataset 层调整为 2-7 天，2023 年起可降低以节省成本，但不可超过 7 天）。

## Redshift：自动 + 手动快照

```sql
-- Redshift 没有 SQL BACKUP 语句，使用 AWS API/CLI
-- aws redshift create-cluster-snapshot \
--     --cluster-identifier prod-cluster \
--     --snapshot-identifier daily-20260413

-- 但有 RESTORE TABLE FROM CLUSTER SNAPSHOT
-- （从已存在的快照恢复单表到新表）
-- 通过 AWS CLI:
-- aws redshift restore-table-from-cluster-snapshot \
--     --cluster-identifier prod-cluster \
--     --snapshot-identifier daily-20260413 \
--     --source-database-name sales \
--     --source-table-name orders \
--     --new-table-name orders_restored

-- 数据导出到 S3
UNLOAD ('SELECT * FROM orders WHERE order_date >= ''2026-01-01''')
TO 's3://mybucket/backup/orders_'
IAM_ROLE 'arn:aws:iam::123456789012:role/RedshiftRole'
FORMAT AS PARQUET
PARTITION BY (order_date)
PARALLEL ON;
```

Redshift 自动每 8 小时（或每 5 GB 块变化）创建增量快照，保留 1 天（可调），跨区域复制可选。

## ClickHouse：22.4 起的 BACKUP / RESTORE SQL

ClickHouse 在 22.4（2022 年 4 月）首次引入了真正的 SQL 级 `BACKUP` 与 `RESTORE` 语句，此前用户只能依赖第三方 `clickhouse-backup` 工具或手动复制 part 目录。

```sql
-- 备份单表到本地磁盘
BACKUP TABLE default.orders TO Disk('backups', 'orders_20260413.zip');

-- 备份多个对象
BACKUP TABLE default.orders, TABLE default.customers, TABLE default.products
  TO Disk('backups', 'sales_20260413.zip');

-- 备份整个数据库
BACKUP DATABASE sales TO Disk('backups', 'sales_db.zip');

-- 备份所有数据库
BACKUP ALL TO Disk('backups', 'full_20260413.zip')
  EXCEPT DATABASE system;

-- 备份到 S3
BACKUP TABLE default.orders
TO S3('https://my-bucket.s3.amazonaws.com/backups/orders/', 'AKID', 'SECRET');

-- 增量备份（基于上次备份）
BACKUP TABLE default.orders
TO Disk('backups', 'orders_inc_20260413.zip')
SETTINGS base_backup = Disk('backups', 'orders_20260412.zip');

-- 加密备份
BACKUP TABLE default.orders
TO Disk('backups', 'orders_enc.zip')
SETTINGS encryption_password = 'mySecret';

-- 异步执行 + 后台监控
BACKUP TABLE default.orders TO Disk('backups', 'orders.zip') ASYNC;
SELECT * FROM system.backups WHERE status = 'BACKUP_CREATED';

-- 恢复
RESTORE TABLE default.orders
FROM Disk('backups', 'orders_20260413.zip');

-- 恢复并改名
RESTORE TABLE default.orders AS default.orders_restored
FROM Disk('backups', 'orders_20260413.zip');
```

注意 ClickHouse 备份的最大特点：由于 MergeTree 的 part 是不可变的，备份本质上就是把活跃 part 目录硬链接（或复制）到目标位置，开销极低。增量备份通过比对 part 名是否在 base backup 中存在实现。

## DuckDB：EXPORT DATABASE / IMPORT DATABASE

DuckDB 是单文件嵌入式数据库，最简单的"备份"就是复制 `.duckdb` 文件，但 DuckDB 还提供了一个跨版本可移植的逻辑备份机制：

```sql
-- 将整个数据库导出到目录（CSV/Parquet/JSON）
EXPORT DATABASE 'backup_dir' (FORMAT PARQUET);

-- 显式控制
EXPORT DATABASE 'backup_dir' (
  FORMAT CSV,
  DELIMITER '|'
);

-- 目录结构示例：
-- backup_dir/
--   schema.sql       -- 所有 CREATE 语句
--   load.sql         -- 所有 COPY FROM 语句
--   table_orders.parquet
--   table_customers.parquet

-- 恢复：在新数据库中执行
IMPORT DATABASE 'backup_dir';
-- 等价于：执行 schema.sql 然后执行 load.sql

-- 或者直接复制文件（需先关闭连接）
-- cp mydata.duckdb mydata.backup.duckdb
```

注意：`EXPORT DATABASE` 是文本/列存格式，跨主版本兼容；直接复制 `.duckdb` 二进制文件在不同主版本之间可能不兼容（DuckDB 1.0 GA 之后承诺了存储格式稳定性）。

## CockroachDB：分布式时代的 BACKUP/RESTORE

CockroachDB 把 BACKUP/RESTORE 设计成完整的 SQL 语句，并原生支持 S3/GCS/Azure Blob。

```sql
-- 完整集群备份到 S3
BACKUP INTO 's3://mybucket/backups?AUTH=specified&AWS_ACCESS_KEY_ID=...&AWS_SECRET_ACCESS_KEY=...';

-- 备份单个数据库
BACKUP DATABASE sales INTO 'gs://mybucket/backups/sales';

-- 备份单表
BACKUP TABLE sales.public.orders INTO 'azure://mycontainer/backup/orders?AZURE_ACCOUNT_KEY=...';

-- 增量备份（自动基于最近的完整备份）
BACKUP INTO LATEST IN 's3://mybucket/backups';

-- 加密备份
BACKUP DATABASE sales INTO 's3://mybucket/backups/sales'
  WITH encryption_passphrase = 'mySecret';

-- 计划备份（自动调度，21.2+）
CREATE SCHEDULE sales_backups
FOR BACKUP DATABASE sales INTO 's3://mybucket/backups/sales'
  RECURRING '@daily'
  FULL BACKUP '@weekly'
  WITH SCHEDULE OPTIONS first_run = 'now';

-- 恢复
RESTORE FROM LATEST IN 's3://mybucket/backups';
RESTORE DATABASE sales FROM LATEST IN 's3://mybucket/backups/sales'
  WITH new_db_name = 'sales_restored';

-- 时间点恢复（基于备份链 + revision history）
BACKUP DATABASE sales INTO 's3://mybucket/backups/sales'
  WITH revision_history;
RESTORE DATABASE sales FROM LATEST IN 's3://mybucket/backups/sales'
  AS OF SYSTEM TIME '2026-04-13 11:45:00';
```

## TiDB：BR 命令行工具是唯一推荐方式

TiDB 的 SQL 形式 `BACKUP` / `RESTORE` 语句最早在 4.0 作为**实验性**特性引入，在 5.4 已被**标记为废弃 (deprecated)**，6.x 起官方文档不再推荐使用。从 6.x 开始，**BR (Backup & Restore) 命令行工具**是 TiDB 备份恢复的唯一规范方法，PITR（基于日志备份的时间点恢复）也通过 `br log` 子命令完成。生产环境不应再使用 SQL 形式的 `BACKUP DATABASE` / `RESTORE DATABASE`。

```bash
# 全量备份（推荐）
br backup full \
   --pd "10.0.0.1:2379" \
   --storage "s3://mybucket/backup-2026-04-13?access-key=...&secret-access-key=..." \
   --ratelimit 128 \
   --log-file /var/log/br.log \
   --crypter.method aes256-ctr \
   --crypter.key-file /etc/br/key

# 库/表级备份
br backup db --db sales --pd "10.0.0.1:2379" --storage "s3://mybucket/sales"
br backup table --db sales --table orders --pd "10.0.0.1:2379" --storage "s3://..."

# 增量备份（指定上次备份的 TSO）
br backup full --lastbackupts 437502653940662272 ...

# 恢复
br restore full --pd "10.0.0.1:2379" --storage "s3://mybucket/backup-2026-04-13?..."

# PITR：启动持续日志备份任务
br log start --task-name=cluster_log --pd "10.0.0.1:2379" --storage='s3://mybucket/log/'

# PITR：恢复到指定时间点（先 restore full，再 restore point）
br restore point --pd "10.0.0.1:2379" \
   --full-backup-storage='s3://mybucket/backup-2026-04-13' \
   --storage='s3://mybucket/log/' \
   --restored-ts='2026-04-13 11:45:00 +08:00'
```

> 历史背景：TiDB 4.0 引入实验性 `BACKUP DATABASE` / `RESTORE DATABASE` SQL 语句，本质是在 SQL 层调用同样的 BR 逻辑；但因为缺少诸多 BR 工具的高级选项（限速、加密、PITR 衔接、并行调度等），从 5.4 起被标记为 deprecated，6.x 后 BR CLI 成为唯一规范路径。

## SAP HANA：事务一致的 BACKUP DATA

```sql
-- 完整数据备份到文件
BACKUP DATA USING FILE ('/backup/hana/COMPLETE_DATA_BACKUP');

-- 增量
BACKUP DATA INCREMENTAL USING FILE ('/backup/hana/INC_DATA');

-- 差异
BACKUP DATA DIFFERENTIAL USING FILE ('/backup/hana/DIFF_DATA');

-- 备份单个 tenant
BACKUP DATA FOR SALES USING FILE ('/backup/hana/SALES_BACKUP');

-- 通过 backint 接口备份到第三方介质（NetBackup/TSM/Veeam 等）
BACKUP DATA USING BACKINT ('COMPLETE_DATA_BACKUP');

-- 加密配置（数据库级加密 + 备份继承）
ALTER SYSTEM PERSISTENCE ENCRYPTION ON;
ALTER SYSTEM BACKUP ENCRYPTION ON;

-- 时间点恢复
RECOVER DATABASE FOR SALES UNTIL TIMESTAMP '2026-04-13 11:45:00'
  CLEAR LOG
  USING DATA PATH ('/backup/hana')
  USING LOG PATH ('/backup/hana/log');
```

## Firebird：gbak（逻辑）+ nbackup（物理增量）

```bash
# gbak 逻辑备份
gbak -B -USER SYSDBA -PASSWORD masterkey \
     localhost:/var/firebird/sales.fdb /backup/sales.fbk

# 逻辑恢复
gbak -C -USER SYSDBA -PASSWORD masterkey \
     /backup/sales.fbk localhost:/var/firebird/sales_restored.fdb

# nbackup 物理增量
nbackup -B 0 sales.fdb sales_L0.nbk     # level 0 完整
nbackup -B 1 sales.fdb sales_L1.nbk     # level 1 增量
nbackup -B 2 sales.fdb sales_L2.nbk     # level 2 增量

# 恢复多级
nbackup -R sales.fdb sales_L0.nbk sales_L1.nbk sales_L2.nbk
```

## Informix：ontape 与 onbar

```bash
# ontape 完整备份
ontape -s -L 0 -t /backup/sales_L0       # level 0
ontape -s -L 1 -t /backup/sales_L1       # level 1
ontape -s -L 2 -t /backup/sales_L2       # level 2

# 物理恢复
ontape -p -t /backup/sales_L0

# onbar（与 NetBackup/TSM/Veritas 集成，支持并行）
onbar -b -L 0                            # 完整
onbar -b -L 1                            # 增量
onbar -b -l                              # 逻辑日志备份

# 恢复到时间点
onbar -r -t '2026-04-13 11:45:00'
```

## 其他典型引擎

### Teradata（ARC / DSA）

```bash
# 经典 ARC 工具
arcmain <<EOF
LOGON tdpid/dba,password;
ARCHIVE DATA TABLES (sales.orders), RELEASE LOCK,
        FILE = ARCHIVE_FILE;
LOGOFF;
EOF

# DSA (Data Stream Architecture, 现代)
dsc -ip teradata-server -u dbc -p password \
    backup -t dsa-server -j daily_full -d sales
```

### Vertica（vbr.py）

```bash
vbr.py --task backup --config-file /etc/vertica/full_backup.ini
vbr.py --task restore --config-file /etc/vertica/full_backup.ini
# 配置文件支持 S3/GCS/Azure 目标、并行度、加密
```

### Greenplum（gpbackup / gprestore）

```bash
gpbackup --dbname sales --backup-dir /backup/gp \
         --jobs 8 --leaf-partition-data \
         --plugin-config /etc/gp/s3-config.yaml
gprestore --timestamp 20260413104500 --create-db
```

### StarRocks / Doris（基于 Repository）

```sql
-- 创建 Repository（一次性）
CREATE REPOSITORY `s3_repo`
WITH BROKER `broker_name`
ON LOCATION "s3a://mybucket/sr_backups"
PROPERTIES (
  "fs.s3a.access.key" = "...",
  "fs.s3a.secret.key" = "...",
  "fs.s3a.endpoint" = "https://s3.amazonaws.com"
);

-- 备份
BACKUP SNAPSHOT sales.snapshot_20260413
TO `s3_repo`
ON (orders, customers)
PROPERTIES ("type" = "full");

-- 恢复
RESTORE SNAPSHOT sales.snapshot_20260413
FROM `s3_repo`
ON (orders, customers)
PROPERTIES ("backup_timestamp" = "2026-04-13-10-45-00");
```

### CrateDB（基于 Repository 的快照）

```sql
CREATE REPOSITORY my_s3_repo TYPE s3
WITH (bucket='mybucket', base_path='backup/', protocol='https', ...);

CREATE SNAPSHOT my_s3_repo.snapshot_20260413
TABLE orders, customers
WITH (wait_for_completion = true);

RESTORE SNAPSHOT my_s3_repo.snapshot_20260413
TABLE orders WITH (wait_for_completion = true);
```

### H2 / HSQLDB / Derby（嵌入式）

```sql
-- H2
BACKUP TO 'backup_20260413.zip';
-- 恢复：解压后用 RUNSCRIPT
RUNSCRIPT FROM 'backup.sql';

-- HSQLDB
BACKUP DATABASE TO '/backup/hsql/' BLOCKING;
-- 或在线非阻塞
BACKUP DATABASE TO '/backup/hsql/' NOT BLOCKING;

-- Apache Derby（系统过程）
CALL SYSCS_UTIL.SYSCS_BACKUP_DATABASE('/backup/derby');
CALL SYSCS_UTIL.SYSCS_BACKUP_DATABASE_AND_ENABLE_LOG_ARCHIVE_MODE_NOWAIT(
  '/backup/derby', 1);
```

### Google Spanner / Azure Synapse / Materialize / RisingWave

这些"完全托管"或"流处理"系统几乎都把备份做成不可见的服务能力：

- **Spanner**：`gcloud spanner backups create --instance=...` 创建备份，最长保留 1 年；PITR 通过 `version_retention_period`（默认 1 小时，最长 7 天）。
- **Azure Synapse**：自动每 8 小时一次快照，保留 7 天，用户不可控制具体策略，仅可通过 Portal 触发恢复。
- **Materialize / RisingWave**：作为流物化系统，状态可由上游 Kafka/CDC 重建；备份的语义被替换为"重新订阅"。RisingWave 提供 `risectl meta backup-meta` 备份元数据快照，数据本身在对象存储上。
- **Firebolt**：Engine 与 Database 解耦，Database 的状态由服务自动持久化到 S3，用户不直接操作备份。
- **Athena**：本身是计算引擎，数据存于 S3，备份完全交给 S3 版本控制 / 跨区域复制。

## Point-in-time Recovery 详细对比

| 引擎 | 时间精度 | 关键依赖 | 配置开销 |
|------|---------|---------|---------|
| Oracle | SCN（事务级） | 归档日志 + RMAN | 高 |
| SQL Server | LSN（毫秒级） | Full Recovery Model + 日志备份链 | 中 |
| PostgreSQL | LSN / 时间戳 | WAL 归档 + base backup | 中 |
| MySQL/MariaDB | binlog 位点 / 时间 | binlog ON + GTID 推荐 | 低 |
| DB2 | LSN / 时间 | 归档日志 + Forward recovery | 中 |
| Snowflake | 任意时间戳 | 自动（Time Travel） | 零 |
| BigQuery | 7 天内任意时间 | 自动 | 零 |
| Redshift | 自动快照粒度 | 自动 | 零 |
| CockroachDB | 任意时间（GC TTL 内） | 修订历史备份 | 低 |
| TiDB | 任意时间 | BR + 持续日志备份 | 中 |
| YugabyteDB | 时间戳 | 分布式快照 + WAL | 中 |
| SAP HANA | 时间 / 日志位置 | log mode normal | 中 |
| Spanner | 1 小时～7 天 | version_retention_period | 零 |
| ClickHouse | 仅备份点 | （无连续 PITR） | -- |
| DuckDB / SQLite / Firebird | 仅备份点 | -- | -- |

PostgreSQL PITR 完整流程：

```bash
# 1. 启用 WAL 归档（之前已配置 archive_command）
# 2. 取一个 base backup
pg_basebackup -D /backup/base -F tar -z -X stream -P

# 3. 灾难发生后，准备恢复目录
mkdir -p /var/lib/pgsql/data
tar -xzf /backup/base/base.tar.gz -C /var/lib/pgsql/data

# 4. 写入 recovery 配置
cat >> /var/lib/pgsql/data/postgresql.auto.conf <<'EOF'
restore_command = 'cp /archive/%f %p'
recovery_target_time = '2026-04-13 11:45:00+00'
recovery_target_action = 'promote'
EOF
touch /var/lib/pgsql/data/recovery.signal

# 5. 启动数据库，PostgreSQL 会自动重放 WAL 到目标时间
pg_ctl -D /var/lib/pgsql/data start
```

SQL Server PITR 完整流程已在前文 `RESTORE LOG ... WITH STOPAT` 例子中展示。

Oracle PITR 通过 RMAN `SET UNTIL TIME` 或 `SET UNTIL SCN`，并在 `OPEN RESETLOGS` 之后产生新的 incarnation，旧 incarnation 的日志不能再用。

## 跨版本恢复对比

| 引擎 | 高 → 低 | 低 → 高 | 推荐路径 |
|------|--------|--------|---------|
| SQL Server | 不支持 | 支持（自动升级） | 备份/还原 |
| Oracle | 不支持 | 支持（RMAN cross-version restore） | RMAN |
| PostgreSQL（物理） | 否 | 仅同主版本 | 跨主版本必须 pg_dumpall + restore + pg_upgrade |
| MySQL（物理 XtraBackup） | 否 | 仅同主版本 | mysqldump 跨版本 |
| DB2 | 受限 | 支持 fix pack 范围 | -- |
| ClickHouse | 通常向前兼容 | 通常向前兼容 | -- |
| DuckDB | 二进制不保证 | 二进制不保证 | EXPORT DATABASE |
| Snowflake | -- | -- | 用户不感知 |

## 关键发现

经过对 45+ 个数据库引擎备份与恢复语法的横向梳理，可以提炼出以下关键观察：

1. **没有任何 SQL 标准**。BACKUP/RESTORE 是 SQL 世界中标准化程度最低的领域，每一个引擎都自成体系。
2. **SQL 级 BACKUP 语句是少数派**。只有约 13 个引擎在 SQL 中暴露了 `BACKUP`/`RESTORE` 关键字，其中以 SQL Server 和 DB2 最完整、ClickHouse 22.4+ 与 CockroachDB 最现代化。
3. **传统数据库依赖外部命令行工具**：PostgreSQL（pg_dump/pg_basebackup）、MySQL（mysqldump/xtrabackup）、Oracle（RMAN/expdp）、Greenplum（gpbackup）、Vertica（vbr.py）、TiDB（br）等，工具与数据库本体的版本演进是分开的。
4. **云原生数据仓库重新定义了"备份"**。Snowflake、BigQuery、Redshift、Spanner、Synapse 都把备份做成了用户不可见或近乎不可见的服务能力，用 Time Travel + 自动快照 + 零拷贝克隆替代了传统的 BACKUP DATABASE。Snowflake 甚至完全没有任何手动备份接口。
5. **物理 vs 逻辑备份的分工**。物理备份（XtraBackup、pg_basebackup、RMAN、ARC）速度快但格式锁定；逻辑备份（mysqldump、pg_dump、Data Pump、msqldump）跨版本兼容但慢。绝大多数严肃部署都会同时维护两种备份。
6. **CLONE/Snapshot 正在取代 backup**。MySQL 8.0.17 的 CLONE 插件、Snowflake 的零拷贝克隆、BigQuery 的 table clone、CockroachDB 的 incremental BACKUP，都把焦点从"导出文件"转向"快速创建一致的可写副本"。
7. **PITR 的实现差异巨大**。Oracle、SQL Server、PostgreSQL、MySQL 以归档日志为基础；Snowflake/BigQuery 以多版本存储为基础；CockroachDB/TiDB 以 MVCC + 持续 CDC 为基础。粒度从"事务级 SCN"到"7 天固定窗口"不等。
8. **增量备份算法差异**。Oracle RMAN 的 0/1 级是块级；SQL Server 是页级位图（DCM）；XtraBackup 基于 LSN 比较；ClickHouse 利用 part 不可变性比对名字；CockroachDB 用时间戳 revision history。结果是各家增量备份的体积、并行度、恢复速度差异极大。
9. **云对象存储成为事实上的备份介质**。S3/GCS/Azure Blob 正在取代磁带库。SQL Server 2014+、CockroachDB、TiDB、ClickHouse、StarRocks/Doris、Vertica 都原生支持直接备份到云存储；PostgreSQL/MySQL 通过 pgBackRest、wal-g、xtrabackup-stream 也走向同样的方向。
10. **备份加密尚未普及**。SQL Server、Oracle、DB2、ClickHouse、CockroachDB、TiDB、SAP HANA 内置了 SQL 层备份加密；PostgreSQL/MySQL 仍然依赖外部 GPG 或第三方工具完成加密，是合规场景下的痛点。
11. **跨版本恢复几乎只能向上**。除 Snowflake / BigQuery 等服务化系统之外，几乎所有引擎只允许从低版本备份恢复到高版本；高版本 → 低版本必须经由逻辑导出。
12. **嵌入式数据库走极简路线**。DuckDB（EXPORT/IMPORT DATABASE）、SQLite（`.backup`）、H2（`BACKUP TO`）、HSQLDB（`BACKUP DATABASE TO`）都把备份简化为一条 SQL 或 shell 命令，没有恢复模型、没有归档日志、没有备份链。
13. **流式系统的"备份"语义被瓦解**。Materialize、RisingWave、Flink SQL 把数据视为可由上游重建的物化结果；Flink 的 savepoint 是状态不是数据；备份的概念被订阅、重放、检查点取代。
14. **真正的备份策略是组合**：在生产环境中，DBA 通常组合多种机制——例如 PostgreSQL 用 pg_basebackup（物理热备） + WAL 归档（PITR） + pg_dumpall（逻辑跨版本） + 文件系统快照（快速回滚），并把所有产物推送到 S3 + 异地副本。任何一个数据库的"BACKUP 语法"只是这条防线中很小的一环。
15. **学会一种数据库的备份不能迁移到另一种**。这与 SELECT、JOIN、窗口函数等领域形成鲜明对比——对于切换数据库的团队来说，备份/恢复几乎需要从零开始重新学习运维。这也是 SQL 世界中最不"可移植"的能力。

如果说 SQL 标准的胜利体现在 SELECT 与窗口函数，那么备份与恢复就是 SQL 标准最大的空白——这恰恰提醒我们，数据库本质上仍然是工程系统，而不只是一种语言。
