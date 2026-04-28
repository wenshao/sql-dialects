# 并行备份与恢复 (Parallel Backup and Restore)

凌晨 3 点，一个 4TB 的 PostgreSQL 主库刚刚硬件故障，DBA 只有不到 6 小时的恢复窗口。如果选择 `pg_dump | pg_restore` 单线程方案，光是恢复就要 18 小时；改用 `pg_restore --jobs=16` 并行恢复后，时间被压缩到 4 小时——这中间的差距,就是"并行备份与恢复"这一主题的全部价值。

当数据规模从 GB 进入 TB 甚至 PB 时代，串行备份/恢复的时间开销往往直接超出业务可接受的 RTO（Recovery Time Objective）。从 2009 年 PostgreSQL 8.4 引入 `pg_restore --jobs`、2010 年 `mydumper/myloader` 项目启动、2013 年 PostgreSQL 9.3 让 `pg_dump` 也支持 `--jobs`，再到 2020 年 `pg_basebackup -j` 让基础备份也能多线程化、2022 年 ClickHouse 在 22.8 引入原生 `BACKUP/RESTORE`——并行化的边界一直在被推开。本文系统对比 45+ 个数据库引擎在并行备份与恢复方面的能力差异，覆盖五个关键维度：并行备份、并行恢复、表级并行（per-table jobs）、表空间级并行（per-tablespace parallelism）、流水线优化（pipeline: 压缩 + 上传），并深入剖析 PostgreSQL `pg_dump --jobs` 的目录格式、Oracle RMAN 的并行通道，以及"备份时并行 vs 恢复时并行"这一经典权衡。

## 没有 SQL 标准

与 `BACKUP/RESTORE` 语句一样，`PARALLEL`、`JOBS`、`THREADS`、`CHANNELS` 等并行控制选项**完全不在 SQL 标准的范围之内**。ISO/IEC 9075（SQL:2023 及之前）从未定义任何并行备份/恢复语义,因为：

1. **并行度本质上是物理执行参数**：与存储布局、磁盘 IOPS、网络带宽、CPU 核数密切相关，不属于声明式数据语言的抽象层次。
2. **每个引擎的并行单位完全不同**：PostgreSQL 按表、Oracle RMAN 按数据文件、SQL Server 按 stripe 文件、MySQL 按表（mydumper）或表空间页（XtraBackup）、ClickHouse 按 part，没有共性。
3. **失败语义也不同**：单个 worker 失败应该重试还是中止整个备份？是否回滚已完成部分？标准化困难。

结果就是：所有并行备份/恢复语法都是厂商私有扩展,关键字五花八门——`--jobs`、`--parallel`、`--threads`、`PARALLEL N`、`MAXTRANSFERSIZE`、`STRIPE`、`CHANNEL`、`KICKING_THREAD`、`MIRROR TO`、`PARALLELISM`，且语义微妙。

## 支持矩阵

### 矩阵一：并行备份能力

| 引擎 | 并行备份语法 | 并行单位 | 默认并行度 | 关键参数 | 引入版本 |
|------|------------|---------|-----------|---------|---------|
| PostgreSQL | `pg_dump --jobs=N` | 表（directory format） | 1 | `-Fd -j N` | 9.3 (2013) |
| PostgreSQL | `pg_basebackup -j N` | 表空间 | 1 | `--jobs=N` | 13 (2020) |
| MySQL | mysqldump（无原生并行） | -- | 1 | -- | -- |
| MySQL | mydumper `--threads` | 表/chunk | 4 | `-t N` | 2010+ |
| MySQL | XtraBackup `--parallel` | 表空间文件 | 1 | `--parallel=N` | 1.6.x (2010) |
| MariaDB | mariadb-dump（无并行） | -- | 1 | -- | -- |
| MariaDB | mariabackup `--parallel` | 表空间文件 | 1 | `--parallel=N` | 10.1+ |
| SQLite | `.backup`（单线程） | -- | 1 | -- | -- |
| Oracle | RMAN `PARALLELISM N` | 数据文件 | 1 | `PARALLELISM N` 或 `CHANNELS N` | 9i (2001) |
| Oracle | Data Pump `PARALLEL=N` | 表/分区 | 1 | `PARALLEL=N` | 10g (2003) |
| SQL Server | `BACKUP DATABASE TO 多个 DISK/URL` | stripe 文件 | 1 | `MIRROR TO` 或多 URL | 2005+ (stripe), 2014+ (URL) |
| DB2 | `BACKUP DATABASE PARALLELISM N` | 表空间 | 自动 | `PARALLELISM N` | 全版本 |
| DB2 | `BACKUP ... WITH N BUFFERS` | 缓冲区 | 自动 | `WITH N BUFFERS` | 全版本 |
| Snowflake | 自动并行（用户不可见） | micro-partition | 自动 | -- | GA |
| BigQuery | 自动并行（load/extract job） | 文件 | 自动 | `--max_workers`（部分场景） | GA |
| Redshift | `UNLOAD PARALLEL ON`（数据导出） | slice | 自动 | `PARALLEL ON/OFF` | GA |
| DuckDB | `EXPORT DATABASE`（单线程导出，多文件可并行读回） | -- | 1 | -- | 0.3+ |
| ClickHouse | `BACKUP ... ON CLUSTER` 分片并行 | part/分片 | 自动 | `s3 / local` 后端 | 22.8 (2022) |
| Trino | -- | -- | -- | -- | -- |
| Presto | -- | -- | -- | -- | -- |
| Spark SQL | 依赖底层（Delta/Iceberg），文件并行 | 文件 | 自动 | -- | -- |
| Hive | `EXPORT TABLE`（单作业） | -- | 受 MR/Tez 控制 | mapreduce 参数 | 0.8+ |
| Flink SQL | savepoint 并行 | task | 自动 | `state.backend` 配置 | -- |
| Databricks | Delta CLONE 并行 | 文件 | 自动 | -- | DBR 7.4+ |
| Teradata | ARC/DSA 多 stream | session | 多 | `SESSIONS=N` | V2R5+ |
| Greenplum | `gpbackup --jobs` | segment + 表 | 1 | `--jobs=N` | 5.0+ |
| CockroachDB | `BACKUP`（分布式） | range | 自动 | `kv.bulk_io_write.concurrent_export_requests` | 2.0+ |
| TiDB | `br backup --concurrency` | region | 4 | `--concurrency=N` | 4.0+ (2020) |
| OceanBase | `obdumper` 多线程 | 表 | 1 | `--threads=N` | GA |
| YugabyteDB | `ysql_dump --jobs` / 分布式 snapshot | 表/tablet | 1 | `--jobs=N` | 2.0+ |
| SingleStore | `BACKUP DATABASE WITH SPLIT_FILES` | partition | 自动 | `WITH SPLIT_FILES` | 6.0+ |
| Vertica | `vbr.py --task backup`（多 stream） | projection/节点 | 自动 | `concurrency_backup` | GA |
| Impala | -- | -- | -- | -- | -- |
| StarRocks | `BACKUP` 多 tablet 并行 | tablet | 自动 | -- | 1.18+ |
| Doris | `BACKUP` 多 tablet 并行 | tablet | 自动 | -- | 0.13+ |
| MonetDB | `msqldump`（单线程） | -- | 1 | -- | -- |
| CrateDB | `CREATE SNAPSHOT`（基于 ES，节点并行） | shard | 自动 | -- | 0.55+ |
| TimescaleDB | 继承 PG `pg_dump --jobs` | hypertable chunk | 1 | `-j N` | 继承 PG |
| QuestDB | `BACKUP` 单线程 | -- | 1 | -- | 6.0+ |
| Exasol | EXAoperation 远程归档 | volume/节点 | 自动 | -- | -- |
| SAP HANA | `BACKUP DATA USING FILE` 多 channel | service/volume | 多 | `WITH N CHANNELS`（备份目录形态） | 1.0+ |
| Informix | `onbar` 多 stream | dbspace | 自动 | `BAR_MAX_BACKUP` | 全版本 |
| Firebird | `gbak` 单线程 / `nbackup` 单线程 | -- | 1 | -- | -- |
| H2 | `BACKUP TO` 单线程 | -- | 1 | -- | 全版本 |
| HSQLDB | `BACKUP DATABASE TO` 单线程 | -- | 1 | -- | 1.9+ |
| Derby | `SYSCS_BACKUP_DATABASE` 单线程 | -- | 1 | -- | 10+ |
| Amazon Athena | -- | -- | -- | -- | -- |
| Azure Synapse | 自动并行 | 分布 | 自动 | -- | GA |
| Google Spanner | `gcloud spanner backups` 自动并行 | split | 自动 | -- | GA |
| Materialize | -- | -- | -- | -- | -- |
| RisingWave | meta snapshot 单线程 | -- | 1 | -- | -- |
| InfluxDB | `influxd backup` 单线程 | -- | 1 | -- | -- |
| Databend | 依赖对象存储 | -- | -- | -- | -- |
| Yellowbrick | `ybbackup` 多 stream | shard/节点 | 自动 | `--parallelism=N` | GA |
| Firebolt | 自动持久化 | -- | -- | -- | GA |

> 统计：在 45+ 个引擎中，约 30+ 提供某种形式的并行备份能力（命令行参数、自动并行或分布式分片并行），其余 10+ 个为单线程或不支持显式备份。

### 矩阵二：并行恢复能力

| 引擎 | 并行恢复语法 | 并行单位 | 默认并行度 | 关键参数 | 引入版本 |
|------|------------|---------|-----------|---------|---------|
| PostgreSQL | `pg_restore --jobs=N` | 表/索引 | 1 | `-j N` | 8.4 (2009) |
| PostgreSQL | `pg_basebackup` 恢复 | 单线程拷贝 | -- | -- | -- |
| MySQL | `mysql < dump.sql`（单线程） | -- | 1 | -- | -- |
| MySQL | myloader `--threads` | 表/chunk | 4 | `-t N` | 2010+ |
| MySQL | XtraBackup `--prepare`（少量并行） | -- | 自动 | `--use-memory` | 1.6.x |
| MariaDB | mariabackup `--copy-back` 单线程 | -- | 1 | -- | -- |
| Oracle | RMAN `RESTORE` PARALLELISM | 数据文件 | 1 | `PARALLELISM N` | 9i (2001) |
| Oracle | Data Pump `IMPORT PARALLEL=N` | 表/分区 | 1 | `PARALLEL=N` | 10g (2003) |
| SQL Server | `RESTORE DATABASE FROM 多个 DISK` | stripe | 1 | 多 DISK/URL | 2005+ |
| DB2 | `RESTORE DATABASE PARALLELISM N` | 表空间 | 自动 | `PARALLELISM N` | 全版本 |
| Snowflake | Time Travel 自动恢复 | -- | 自动 | -- | GA |
| BigQuery | `LOAD DATA` 自动并行 | 文件 | 自动 | -- | GA |
| Redshift | `COPY` 自动并行 | slice | 自动 | -- | GA |
| DuckDB | `IMPORT DATABASE`（单线程） | -- | 1 | -- | 0.3+ |
| ClickHouse | `RESTORE ... ON CLUSTER` 分片并行 | part/分片 | 自动 | -- | 22.8 (2022) |
| Hive | `IMPORT TABLE` 受底层并行控制 | -- | 受 MR/Tez 控制 | -- | -- |
| Databricks | Delta CLONE/RESTORE | 文件 | 自动 | -- | DBR 7.4+ |
| Teradata | ARC/DSA 多 stream | session | 多 | `SESSIONS=N` | V2R5+ |
| Greenplum | `gprestore --jobs` | segment + 表 | 1 | `--jobs=N` | 5.0+ |
| CockroachDB | `RESTORE`（分布式） | range | 自动 | -- | 2.0+ |
| TiDB | `br restore --concurrency` | region | 128 | `--concurrency=N` | 4.0+ |
| TiDB | tidb-lightning 多线程 | 表/chunk | 自动 | `region-concurrency` | 3.0+ |
| OceanBase | `obloader` 多线程 | 表 | 1 | `--threads=N` | GA |
| YugabyteDB | `ysqlsh -f`（单线程）/ snapshot 恢复（分布式） | -- | -- | -- | -- |
| SingleStore | `RESTORE DATABASE` 多文件并行 | partition | 自动 | -- | 6.0+ |
| Vertica | `vbr.py --task restore` 并行 | projection/节点 | 自动 | -- | GA |
| StarRocks | `RESTORE` 多 tablet 并行 | tablet | 自动 | -- | 1.18+ |
| Doris | `RESTORE` 多 tablet 并行 | tablet | 自动 | -- | 0.13+ |
| CrateDB | `RESTORE SNAPSHOT` shard 并行 | shard | 自动 | -- | 0.55+ |
| TimescaleDB | 继承 PG `pg_restore --jobs` | -- | 1 | `-j N` | 继承 PG |
| SAP HANA | `RECOVER DATABASE` 多 channel | service | 多 | -- | 1.0+ |
| Yellowbrick | `ybrestore --parallelism` | shard/节点 | 自动 | `--parallelism=N` | GA |
| MonetDB / SQLite / H2 / HSQLDB / Derby / Firebird / QuestDB | 单线程 | -- | 1 | -- | -- |

> 统计：约 25+ 引擎提供并行恢复能力。注意"备份并行"与"恢复并行"经常不对称——例如 PostgreSQL 在 8.4 (2009) 就支持 `pg_restore --jobs`，但 `pg_dump --jobs` 直到 9.3 (2013) 才出现，相隔 4 年。

### 矩阵三：表级并行 vs 表空间级并行

| 引擎 | 表级并行（per-table） | 表空间级并行（per-tablespace） | 段/分片级并行 | 备注 |
|------|---------------------|----------------------------|------------|------|
| PostgreSQL | `pg_dump -Fd -j N`（按 TOC item） | `pg_basebackup -j N` 13+ | -- | 两个层次的并行 |
| MySQL（XtraBackup） | -- | `--parallel=N`（每个 .ibd） | -- | 表空间文件级 |
| MySQL（mydumper） | `--threads=N` 按表/chunk | -- | -- | 表/chunk 级 |
| Oracle RMAN | -- | -- | datafile 级 PARALLELISM | datafile 是物理单位 |
| Oracle Data Pump | `PARALLEL=N` 按表/分区 | -- | -- | 逻辑层 |
| SQL Server | -- | filegroup（部分） | stripe | 多 DISK 写入 |
| DB2 | -- | tablespace 级 PARALLELISM | -- | 表空间是天然并行单位 |
| Greenplum | gpbackup `--jobs` 按表 | -- | segment 级（天然） | 双层并行 |
| TiDB | tidb-lightning 表级 | -- | region 级 | 双层 |
| CockroachDB | -- | -- | range 级 | 分布式天然分片 |
| ClickHouse | per-table BACKUP | -- | part 级 / shard 级 | 集群拓扑相关 |
| Vertica | -- | projection 级 | 节点级 | MPP 天然 |
| Snowflake | -- | -- | micro-partition 级 | 完全自动 |
| Yellowbrick | -- | -- | shard 级 | MPP 天然 |
| Teradata | -- | -- | AMP 级 | MPP 天然 |

### 矩阵四：流水线优化（压缩 + 加密 + 上传）

并行备份的另一个维度是**流水线化**：边备份、边压缩、边加密、边上传到对象存储,各阶段并行执行。

| 引擎 | 流水线压缩 | 流水线加密 | 直接上传对象存储 | 备注 |
|------|----------|----------|----------------|------|
| PostgreSQL | `pg_dump -Z 9` 同步压缩 | `pgbackrest`（社区工具）/SSL 流式加密 | `pgbackrest --repo-type=s3` | 标准工具链 |
| MySQL XtraBackup | `--compress=lz4` | `--encrypt=AES256` | 配合 xbcloud `--storage=s3` | 内置流水线 |
| MySQL mydumper | `--compress` (gzip/zstd) | -- | 配合 mc / aws cli 后处理 | 较弱 |
| Oracle RMAN | `COMPRESSED BACKUPSET` | `ENCRYPTION ON` + transparent encryption | `BACKUP TO 'sbt:...'` 经 OSB/MML | 完整 |
| SQL Server | `WITH COMPRESSION` | `WITH ENCRYPTION = ...` | `BACKUP TO URL='https://...'` | 内置 |
| DB2 | `COMPRESS` | `ENCRYPT` 或 keystore | 经 TSM/cloud SDK | 完整 |
| Snowflake | 完全自动 | 完全自动 | 内置（基于云） | 透明 |
| BigQuery | -- | 服务端加密 | 内置（GCS） | 透明 |
| ClickHouse | `BACKUP ... TO S3('...')` 内置压缩 | s3 SSE | 是 | 内置 |
| CockroachDB | `BACKUP ... TO 's3://...' WITH compression='gzip'` | encryption_passphrase | 是 | 内置 |
| TiDB BR | `--compression-type=zstd` | KMS 加密 | `--storage=s3://...` | 内置 |
| Greenplum gpbackup | `--compression-type=zstd` | -- | gpbackup-s3-plugin | 完整 |
| Vertica | `vbr` 任务级 | -- | s3 plugin | 完整 |

> 一般来说，**云原生分布式数据库**（CockroachDB、TiDB、ClickHouse、Snowflake、BigQuery）在流水线方面体验最好,因为它们一开始就把对象存储作为一等公民。

## 各引擎并行备份/恢复深入对比

### PostgreSQL 系列

PostgreSQL 提供 4 种主要的备份工具,每种都有不同的并行能力:

| 工具 | 用途 | 并行能力 | 引入版本 |
|------|------|---------|---------|
| `pg_dump` | 逻辑备份单库 | `-j N`（仅 directory format） | 9.3 (2013) |
| `pg_dumpall` | 逻辑备份全集群 | 无 | -- |
| `pg_restore` | 恢复 `pg_dump` 产出 | `-j N` | 8.4 (2009) |
| `pg_basebackup` | 物理备份（基础备份） | `-j N`（每表空间一线程） | 13 (2020) |

#### pg_dump --jobs 深入剖析

`pg_dump` 的 `--jobs` 选项**仅在 directory format（`-Fd`）下可用**,因为 directory format 是唯一允许多个进程并发写入的备份格式:

```bash
# 单线程逻辑备份（custom format,不能并行）
pg_dump -Fc -f db.dump mydb

# 并行逻辑备份（directory format,可并行）
pg_dump -Fd -j 8 -f /backup/db.dir mydb

# 并行恢复（不限于 directory format,custom format 也支持）
pg_restore -j 8 -d newdb /backup/db.dir
pg_restore -j 8 -d newdb db.dump   # custom format 也行
```

##### directory format 的物理结构

```
/backup/db.dir/
├── toc.dat                    # Table of Contents（元数据）
├── 16384.dat.gz               # 表 oid=16384 的数据（压缩）
├── 16385.dat.gz               # 表 oid=16385 的数据
├── 16386.dat.gz               # 表 oid=16386 的数据
├── ...
└── blob_xxx.toc               # 大对象 TOC
```

**关键设计**：每个表的数据被独立写入 `<oid>.dat.gz`,8 个 worker 进程可以同时写入 8 个不同的文件,无锁竞争。toc.dat 由主进程统一生成,worker 只负责数据复制。

##### worker 调度算法

```
pg_dump 的 worker 调度（简化）：
1. master 解析所有表的 schema,生成 dump 计划
2. master 为每个表创建一个 SnapshotID（保证一致性）
3. 多个 worker 各自连接数据库,SET TRANSACTION SNAPSHOT 到同一快照
4. master 将表的 oid 列表分发给 worker（默认按表大小降序）
5. 每个 worker 处理一张表 → 写入 <oid>.dat.gz → 报告完成 → 领下一张表
6. 直到所有表处理完毕

关键点：
- 一致性：所有 worker 使用同一个 MVCC 快照 → 备份语义等同于一次大事务
- 大表优先：避免最后单个 worker 处理超大表导致拖尾
- 锁：每个 worker 在导出表时持有 ACCESS SHARE,与 DML 不冲突,与 DDL 冲突
```

##### 一致性快照协议

PostgreSQL 9.2+ 引入 `pg_export_snapshot()` 函数,允许多个会话共享同一快照:

```sql
-- master 进程
BEGIN ISOLATION LEVEL REPEATABLE READ;
SELECT pg_export_snapshot();  -- 返回 'xxxxxxxx-xx'

-- worker 进程
BEGIN ISOLATION LEVEL REPEATABLE READ;
SET TRANSACTION SNAPSHOT 'xxxxxxxx-xx';
-- 此后所有 worker 看到的数据完全一致
```

这正是 `pg_dump -j N` 实现一致性的核心机制——9.3 之前由于没有这个 API,无法实现并行 dump。

##### pg_dump --jobs 的局限

```
不适用场景：
- 大量小表（< 1MB）：worker 协调开销大于收益
- 单一巨大表（> 80% 数据）：拖尾严重,只有一个 worker 在工作
- 大对象（large object）：BLOB 不能并行
- 跨网络备份到慢速磁盘：网络/IO 瓶颈在前

最佳场景：
- 中等数量（10-1000）的中等大小（100MB - 100GB）表
- 本地 SSD 备份
- 多核 CPU（8-32 核）
```

#### pg_restore --jobs 深入剖析

`pg_restore --jobs` 比 `pg_dump --jobs` 早了 4 年（2009 vs 2013）,因为恢复时**TOC 信息已经在备份文件中**,worker 可以直接读取 TOC 然后并行执行 `COPY` 和 `CREATE INDEX`,无需一致性快照协议:

```bash
# 经典恢复
pg_restore -j 8 -d newdb /backup/db.dir

# 仅恢复 schema（DDL）
pg_restore -j 8 -d newdb --schema-only /backup/db.dir

# 仅恢复数据（COPY）
pg_restore -j 8 -d newdb --data-only /backup/db.dir
```

##### 恢复任务的依赖图

`pg_restore` 内部维护一个 DAG (Directed Acyclic Graph),描述恢复任务的依赖关系:

```
TYPE       (无依赖)
  ↓
TABLE      (依赖 TYPE)
  ↓
DATA       (依赖 TABLE)
  ↓
INDEX      (依赖 DATA)
  ↓
CONSTRAINT (依赖 INDEX)
  ↓
TRIGGER    (依赖 CONSTRAINT)
  ↓
RULE       (依赖 TRIGGER)
```

worker 严格按依赖顺序执行,但**同一层级的任务可以完全并行**。例如恢复 1000 张表时,1000 个 COPY 操作可以在 8 个 worker 上并行执行,完成后 1000 个 CREATE INDEX 又可以并行——这是 `pg_restore --jobs` 提速最显著的阶段。

##### CREATE INDEX 并行的双重收益

恢复巨型表的常见瓶颈是索引重建。`pg_restore --jobs=8` 不仅让多个 INDEX 并发构建,**每个 INDEX 还可以利用 PG 11+ 的并行索引构建**（`max_parallel_maintenance_workers`）:

```bash
# 设置最大维护并行
ALTER SYSTEM SET max_parallel_maintenance_workers = 4;

# 8 个 worker × 4 个并行 = 32 路并行索引构建
pg_restore -j 8 -d newdb db.dump
```

实际效果：4TB 数据库 + 200 个表 + 1000 个索引,从 18 小时压缩到 4 小时是常见的优化倍数。

#### pg_basebackup -j 的设计

PostgreSQL 13 (2020) 引入 `pg_basebackup -j N`,但**并行单位是表空间**而非表:

```bash
# 单表空间集群：-j 没有任何效果
pg_basebackup -D /backup/base -j 4   # 仍然单线程

# 多表空间集群：每个表空间一个 worker
# tablespace1 → worker1
# tablespace2 → worker2
# tablespace3 → worker3
# tablespace4 → worker4
pg_basebackup -D /backup/base -j 4
```

为何设计如此？因为 `pg_basebackup` 是**物理备份**,直接 streaming 数据目录的文件——而 PostgreSQL 的数据文件按表空间组织,跨表空间的文件可以并行流式拷贝,但**同一表空间内的文件之间存在物理依赖**（pg_class、pg_index 等系统表),不易并行。

### Oracle RMAN：经典的 channel 模型

Oracle RMAN（Recovery Manager）从 9i (2001) 起就支持并行通道（channels）,是工业界并行备份的早期典范:

```sql
-- 配置默认 4 个通道
RMAN> CONFIGURE DEVICE TYPE DISK PARALLELISM 4 BACKUP TYPE TO BACKUPSET;

-- 显式分配 4 个通道（每通道一个进程）
RMAN> RUN {
  ALLOCATE CHANNEL c1 DEVICE TYPE DISK FORMAT '/backup/%U_c1';
  ALLOCATE CHANNEL c2 DEVICE TYPE DISK FORMAT '/backup/%U_c2';
  ALLOCATE CHANNEL c3 DEVICE TYPE DISK FORMAT '/backup/%U_c3';
  ALLOCATE CHANNEL c4 DEVICE TYPE DISK FORMAT '/backup/%U_c4';
  BACKUP DATABASE PLUS ARCHIVELOG;
}

-- 大数据文件分段并行（section size）
RMAN> RUN {
  ALLOCATE CHANNEL c1 DEVICE TYPE DISK;
  ALLOCATE CHANNEL c2 DEVICE TYPE DISK;
  BACKUP SECTION SIZE 1G DATABASE;
}
```

#### channel 调度策略

```
RMAN 的并行调度（简化）：
1. 优化器为每个数据文件估算大小 + IO 代价
2. 按"最长作业优先"（LPT 启发式）排序
3. 4 个 channel 各自从队列头部领取数据文件
4. 大文件可拆分（SECTION SIZE）→ 多 channel 共同处理一个文件
5. 失败的 channel 不影响其他 channel
6. 完成后所有 channel 共同生成 control file 备份

关键设计：
- 通道是与服务器进程的 TCP 连接,可以分布到不同主机的 sbt 设备（如 RMAN 库）
- 每个通道独立读取数据文件 → 独立写入 BACKUPSET
- 备份集（backupset）是 RMAN 的逻辑单元,可包含多个数据文件
```

#### MAX_FILE_PER_BACKUPSET vs PARALLELISM

```sql
-- 4 个通道但每个备份集仅 1 个文件 → 备份集数量 = 数据文件数（细粒度）
RMAN> RUN {
  CONFIGURE DEVICE TYPE DISK PARALLELISM 4;
  BACKUP DATABASE FILESPERSET 1;
}

-- 4 个通道,每个备份集允许 8 个文件 → 备份集少（粗粒度）
RMAN> RUN {
  CONFIGURE DEVICE TYPE DISK PARALLELISM 4;
  BACKUP DATABASE FILESPERSET 8;
}
```

权衡：粒度越细,**恢复时**越容易并行（仅恢复一两个数据文件不必读整个备份集）;但备份本身的元数据开销越大。

#### RESTORE 时的并行

```sql
RMAN> RUN {
  ALLOCATE CHANNEL c1 DEVICE TYPE DISK;
  ALLOCATE CHANNEL c2 DEVICE TYPE DISK;
  ALLOCATE CHANNEL c3 DEVICE TYPE DISK;
  ALLOCATE CHANNEL c4 DEVICE TYPE DISK;
  RESTORE DATABASE;
  RECOVER DATABASE;
}
```

RECOVER 阶段（应用 redo log）的并行由 `RECOVERY_PARALLELISM` 初始化参数控制,默认是 CPU 核数 - 1。在 RAC 环境下,recovery 还可以分布到多个实例上。

### Oracle Data Pump：逻辑层并行

Data Pump (`expdp`/`impdp`) 是 Oracle 10g (2003) 引入的逻辑备份工具,与 RMAN 并行,但层次不同:

```bash
# 8 路并行导出
expdp scott/tiger DIRECTORY=dpdir DUMPFILE=full_%U.dmp PARALLEL=8 FULL=Y

# 8 路并行导入
impdp scott/tiger DIRECTORY=dpdir DUMPFILE=full_%U.dmp PARALLEL=8 FULL=Y

# 表级粒度
expdp scott/tiger TABLES=emp,dept PARALLEL=4 DUMPFILE=tabs_%U.dmp
```

`%U` 是 Data Pump 自动生成的递增编号（01, 02, ..., 99）,允许并行写入多个 dump file。

#### 并行单位

- **表级**：每个表分配给一个 worker
- **分区级**：分区表的每个分区可分给不同 worker
- **METADATA_ONLY 模式**：DDL 串行,但可与 DATA_ONLY 并行重叠

### SQL Server：stripe 备份

SQL Server 通过将备份**条带化（stripe）**到多个目标实现并行:

```sql
-- 备份到 4 个 stripe 文件（每个文件一个 worker thread）
BACKUP DATABASE AdventureWorks
TO DISK = 'D:\backup\aw_1.bak',
   DISK = 'D:\backup\aw_2.bak',
   DISK = 'E:\backup\aw_3.bak',
   DISK = 'E:\backup\aw_4.bak'
WITH FORMAT, COMPRESSION, MAXTRANSFERSIZE = 4194304;

-- 备份到云（Azure Blob URL）多 stripe
BACKUP DATABASE AdventureWorks
TO URL = 'https://acc.blob.core.windows.net/backup/aw_1.bak',
   URL = 'https://acc.blob.core.windows.net/backup/aw_2.bak',
   URL = 'https://acc.blob.core.windows.net/backup/aw_3.bak',
   URL = 'https://acc.blob.core.windows.net/backup/aw_4.bak'
WITH COMPRESSION, BLOCKSIZE = 65536;

-- 恢复时也必须指定所有 stripe
RESTORE DATABASE AdventureWorks
FROM DISK = 'D:\backup\aw_1.bak',
     DISK = 'D:\backup\aw_2.bak',
     DISK = 'E:\backup\aw_3.bak',
     DISK = 'E:\backup\aw_4.bak';
```

#### MAXTRANSFERSIZE 和 BUFFERCOUNT

```sql
-- 调优参数
BACKUP DATABASE AdventureWorks
TO DISK = '...'
WITH MAXTRANSFERSIZE = 4194304,    -- 4MB,默认 1MB
     BUFFERCOUNT = 50,             -- 缓冲数,默认计算
     BLOCKSIZE = 65536;             -- 块大小（云存储常用 65536）
```

`MAXTRANSFERSIZE` 控制每次 IO 大小,`BUFFERCOUNT` 控制并行缓冲区数量,二者共同决定了备份的并行 IO 深度。

#### MIRROR TO（多目标镜像）

```sql
-- 同时备份到 4 个目标（每个都是完整备份的副本）
BACKUP DATABASE AdventureWorks
TO DISK = 'D:\primary\aw.bak'
MIRROR TO DISK = 'E:\mirror1\aw.bak'
MIRROR TO URL = 'https://acc.blob/mirror2/aw.bak';
```

这与 stripe 不同：MIRROR 是冗余,4 个目标各自是完整备份;stripe 是分散,4 个目标合起来是完整备份。

### MySQL 生态：mydumper/myloader 与 XtraBackup

MySQL 自带的 `mysqldump` **没有任何并行能力**。社区项目 mydumper（2010 年由 Domas Mituzas 等人启动）填补了这个空白:

```bash
# mydumper 8 线程导出（按表）
mydumper -h localhost -u root -p secret \
  --threads=8 \
  --output=/backup/mydump \
  --compress \
  --regex='^(?!mysql\.)'

# myloader 8 线程恢复
myloader -h localhost -u root -p secret \
  --threads=8 \
  --directory=/backup/mydump \
  --overwrite-tables
```

#### mydumper 的工作模型

```
mydumper 设计：
1. 主线程获取一致性快照（FLUSH TABLES WITH READ LOCK + START TRANSACTION）
2. 释放表锁（事务级一致性已建立）
3. 8 个 worker 各自 START TRANSACTION + SET ISOLATION LEVEL REPEATABLE READ
4. worker 在 InnoDB 事务的快照中读取表数据
5. 大表拆分（chunk）：按主键范围切分,每个 chunk 一个 worker
6. 输出格式：每表 → schema.table.sql（DDL）+ schema.table.NNNNN.sql（数据）

关键创新：
- 一致性 + 并行：MySQL 长期没有 PG 的 pg_export_snapshot() 等价物,直到 5.7+
- chunk 拆分：超大表（如 1TB 单表）也能并行
- --rows / --chunk-filesize：控制 chunk 粒度
```

#### XtraBackup 的物理并行

XtraBackup（Percona）从 1.6.x（约 2010）开始支持 `--parallel`,这是物理层面的并行:

```bash
# 8 路并行物理备份
xtrabackup --backup --parallel=8 --target-dir=/backup/xb

# 物理拷贝阶段也并行
xtrabackup --copy-back --parallel=8 --target-dir=/backup/xb

# 流水线（压缩 + 加密 + 上传）
xtrabackup --backup --stream=xbstream --compress --compress-threads=8 --encrypt=AES256 \
  | xbcloud put --storage=s3 --s3-bucket=mybackups xb-2026-04
```

`--parallel=N` 在 XtraBackup 中**仅作用于 .ibd 文件的拷贝**——InnoDB 的每个表空间是独立文件,可以多线程同时拷贝。redo log 拷贝由专门的 `redo_copy_thread` 单线程持续运行（保证不丢日志）。

### IBM DB2：表空间级并行

DB2 长期是企业级并行备份的代表:

```sql
-- 表空间级并行（PARALLELISM N）
BACKUP DATABASE mydb TO /backup
  PARALLELISM 8
  WITH 16 BUFFERS BUFFER 4096
  COMPRESS;

-- 在线备份 + 表空间并行
BACKUP DATABASE mydb ONLINE TO /backup
  PARALLELISM 8
  INCLUDE LOGS;

-- 恢复时并行
RESTORE DATABASE mydb FROM /backup
  TAKEN AT 20260428120000
  PARALLELISM 8;
```

DB2 的并行**单位是表空间（tablespace）**:每个 tablespace 是一组 container（文件或裸设备）,可以由独立的 buffer 池服务,因此天然适合并行 IO。`WITH N BUFFERS` 控制并发缓冲数量。

### CockroachDB / TiDB / YugabyteDB：分布式天然并行

分布式数据库的并行备份是"原生的",因为数据本来就分布在多节点:

```sql
-- CockroachDB
BACKUP DATABASE mydb TO 's3://my-bucket/2026-04-28' AS OF SYSTEM TIME '-10s';
-- 自动按 range 并行,所有节点参与导出

-- 限速以避免抢占在线流量
SET CLUSTER SETTING kv.bulk_io_write.concurrent_export_requests = 4;
```

```bash
# TiDB BR（Backup & Restore）
br backup full --pd "pd-host:2379" \
  --storage "s3://bucket/path?region=us-east-1" \
  --concurrency 16 \
  --compression-type zstd

br restore full --pd "pd-host:2379" \
  --storage "s3://bucket/path?region=us-east-1" \
  --concurrency 128
```

#### 并行单位差异

| 引擎 | 备份并行单位 | 恢复并行单位 | 默认并行度 |
|------|------------|------------|----------|
| CockroachDB | range（默认 64MB） | range | `kv.bulk_io_write.concurrent_export_requests` |
| TiDB | region（默认 96MB） | region | backup 4 / restore 128 |
| YugabyteDB | tablet（默认 1GB） | tablet | 取决于 tablet 数量 |

注意 TiDB 的 restore 默认 concurrency=128,远高于 backup 的 4——这是因为**恢复主要是 IO + 索引重建**,而备份主要受**集群在线流量**限制（不能压垮线上集群）。

### ClickHouse：22.8 引入的原生 BACKUP

ClickHouse 从 22.8 (2022 年 8 月) 才引入原生 `BACKUP/RESTORE` 语法。在此之前,只能用社区工具 `clickhouse-backup`:

```sql
-- 单实例本地备份
BACKUP DATABASE my_db TO Disk('backups', 'my_db.zip');

-- 备份到 S3
BACKUP DATABASE my_db TO S3('https://bucket.s3.amazonaws.com/path/', 'access_key', 'secret_key');

-- 集群备份（自动按 shard 并行）
BACKUP DATABASE my_db ON CLUSTER my_cluster TO S3('...');

-- 恢复
RESTORE DATABASE my_db FROM Disk('backups', 'my_db.zip');
RESTORE DATABASE my_db ON CLUSTER my_cluster FROM S3('...');

-- 部分恢复
RESTORE TABLE my_db.events FROM Disk('backups', 'my_db.zip');
```

#### 并行模型

```
ClickHouse BACKUP 并行：
- 单实例：每个 part（默认按时间分区,GB 量级）一个线程
- 集群：每个 shard 在自己的副本上并行执行 BACKUP,通过 ZooKeeper 协调
- 后端为 S3：使用 multipart upload,part 内部也并行
- 不需要锁：基于 part 的不可变性,直接复制 part 文件夹
```

### Greenplum gpbackup：双层并行

Greenplum 的 `gpbackup`（替代旧的 `gp_dump`）实现了**集群并行 + 表并行**双层:

```bash
# 4 路并行 → 每个 segment 上启动 4 个进程
gpbackup --dbname mydb \
  --backup-dir /backup \
  --jobs 4 \
  --compression-type zstd

# 恢复
gprestore --backup-dir /backup \
  --timestamp 20260428120000 \
  --jobs 4 \
  --create-db
```

```
Greenplum 并行模型：
- 集群层：每个 segment（数据节点）独立执行 COPY → 自然并行
- 表层：每个 segment 上的进程,可以多线程处理多张表
- 总并行度 = segments × jobs

例如 32 个 segments + jobs=4 → 总并行度 128 个进程同时备份
```

### SAP HANA：channel-based 多进程

SAP HANA 提供 channel 风格的并行:

```sql
-- 备份到 4 个 channel（4 个文件）
BACKUP DATA USING FILE ('/backup/full')
  ASYNCHRONOUS
  CHANNELS 4;

-- 多 channel 增量
BACKUP DATA INCREMENTAL USING FILE ('/backup/incr')
  CHANNELS 4;

-- 恢复
RECOVER DATABASE
  UNTIL TIMESTAMP '2026-04-28 12:00:00'
  USING FILE ('/backup/full')
  USING CATALOG PATH ('/backup/log');
```

HANA 是内存数据库,`CHANNELS N` 让每个 service（index server, name server, statistics server 等）使用独立的 channel,实现服务级并行。

### MariaDB mariabackup：fork 自 XtraBackup

MariaDB 从 10.1 起 fork 了 XtraBackup 为 `mariabackup`,保留了 `--parallel` 参数:

```bash
mariabackup --backup --parallel=8 --target-dir=/backup
mariabackup --prepare --target-dir=/backup
mariabackup --copy-back --parallel=8 --target-dir=/backup
```

与 XtraBackup 区别：mariabackup 支持 MariaDB 特有的存储引擎（如 Aria）的备份,但不支持 MySQL 8.0 的某些新格式。

### 较小或特殊引擎的简要对比

| 引擎 | 命令 | 并行能力概要 |
|------|------|------------|
| SingleStore | `BACKUP DATABASE mydb WITH SPLIT_FILES TO 's3://...'` | partition 级并行 |
| Vertica | `vbr.py --task backup -c full.ini` | projection + 节点级并行 |
| StarRocks | `BACKUP SNAPSHOT mydb.snap TO repo ON (table1, table2)` | tablet 级并行 |
| Doris | `BACKUP SNAPSHOT mydb.snap TO repo ON (table1, table2)` | tablet 级并行 |
| CrateDB | `CREATE SNAPSHOT my_repo.snap1 ALL` | shard 级并行（基于 ES） |
| Yellowbrick | `ybbackup --parallelism=16` | shard 级并行 |
| Informix | `onbar -b -L 0 -p 4` | dbspace 级,p 控制并行度 |
| Snowflake / BigQuery | 无显式备份命令（Time Travel / 自动持久化） | 完全自动 |

## PostgreSQL pg_dump --jobs 深入剖析

考虑到 `pg_dump --jobs` 是开源世界最广泛使用的并行备份方案之一,本节展开详细分析。

### 历史演进

| 版本 | 年份 | 关键特性 |
|------|------|---------|
| 8.4 | 2009 | `pg_restore --jobs` 引入（恢复时并行) |
| 9.0 | 2010 | custom format（`-Fc`）支持流式压缩 |
| 9.2 | 2012 | `pg_export_snapshot()` 函数（支持快照共享) |
| 9.3 | 2013 | `pg_dump --jobs` 引入（备份时并行,需 directory format) |
| 9.5 | 2016 | 部分 schema 加锁优化 |
| 13 | 2020 | `pg_basebackup -j` 引入（物理备份并行) |
| 14 | 2021 | `--no-toast-compression` 提升备份吞吐 |
| 16 | 2023 | `pg_dump --filter` 精确选择 dump 对象 |
| 17 | 2024 | `pg_dump --filter` 支持更细粒度过滤 |

### 调优参数

```bash
# 完整的并行备份命令
pg_dump \
  --host=primary.db.example.com \
  --username=postgres \
  --dbname=production \
  --format=directory \
  --jobs=8 \
  --compress=9 \
  --no-acl \
  --no-owner \
  --quote-all-identifiers \
  --file=/backup/prod-2026-04-28.dir
```

#### 推荐 `--jobs` 数量

```
推荐公式（经验值）：
  jobs = min(CPU_cores, IOPS_capacity / 1000, 表数 / 10)

具体例子：
  16 核服务器 + NVMe SSD（10K IOPS） + 200 张表 →  min(16, 10, 20) = 10
  8 核 VM + 普通 SSD（3K IOPS） + 50 张表 → min(8, 3, 5) = 3
  32 核 + 高性能阵列 + 5000 张表 → min(32, 50, 500) = 32

推论：
  - 表数 < 10：--jobs 没有意义
  - 表数 << CPU 数：CPU 浪费
  - IOPS 低：增加 jobs 反而拖慢（IO 队列拥塞）
```

#### 与压缩的交互

```bash
# 不压缩,纯 IO 极快
pg_dump -Fd -j 8 -Z 0 -f /backup/db mydb

# zstd 压缩（PG 16+）,平衡 CPU + IO
pg_dump -Fd -j 8 --compress=zstd:3 -f /backup/db mydb

# zlib 最高压缩,CPU 密集（pg_dump 经典选项）
pg_dump -Fd -j 8 -Z 9 -f /backup/db mydb
```

每个 worker 独立压缩,因此 `-j 8 -Z 9` 不会成为压缩瓶颈（除非 CPU 已饱和)。zstd（16+）在大多数场景下提供更好的速度/比率折中。

### 容易被忽略的限制

```
1. 一致性快照需要 9.2+,但 9.3 之前的版本没有 pg_dump --jobs

2. directory format 不能流式输出（不能 pipe 到 ssh / aws s3 cp -)
   解决：先 dump 到本地,再 rsync/aws s3 sync

3. 大对象（large object）不能并行
   - blob 数据由主进程串行处理
   - 含大量 BLOB 的库,--jobs 收益有限

4. 索引不会被 dump（DDL 形式输出 CREATE INDEX）
   恢复时由 pg_restore 触发并行 CREATE INDEX

5. 不能在 standby 上运行（虽然 read-only 但需要写临时文件）

6. 版本兼容：pg_dump 14 输出可被 pg_restore 13 读取（向后兼容),反之不行
```

## Oracle RMAN 并行通道深入

### CHANNEL 与 PARALLELISM 的关系

```sql
-- 方式一：自动分配 4 个 channel
CONFIGURE DEVICE TYPE DISK PARALLELISM 4;
BACKUP DATABASE;
-- RMAN 自动 ALLOCATE 4 个 channel

-- 方式二：显式 ALLOCATE（覆盖 PARALLELISM 设置）
RUN {
  ALLOCATE CHANNEL c1 DEVICE TYPE DISK FORMAT '/backup/%U_c1';
  ALLOCATE CHANNEL c2 DEVICE TYPE DISK FORMAT '/backup/%U_c2';
  ALLOCATE CHANNEL c3 DEVICE TYPE DISK FORMAT '/backup/%U_c3';
  ALLOCATE CHANNEL c4 DEVICE TYPE DISK FORMAT '/backup/%U_c4';
  BACKUP DATABASE;
}
```

显式 `ALLOCATE` 的优势:可为每个 channel 指定不同的 FORMAT、不同的 DEVICE TYPE（混合磁盘 + 磁带）、不同的 RATE 限速。

### 数据文件级 vs section 级并行

#### 数据文件级（默认）

每个数据文件被分配给一个 channel,channel 内部串行处理该文件:

```
8 个数据文件 + 4 个 channel：
  channel c1 ← 处理 file1 + file5
  channel c2 ← 处理 file2 + file6
  channel c3 ← 处理 file3 + file7
  channel c4 ← 处理 file4 + file8
```

#### section 级（11g+）

超大数据文件（如 1TB 单文件）可被切分为多个 section,**多个 channel 协作处理同一个文件**:

```sql
RUN {
  ALLOCATE CHANNEL c1 DEVICE TYPE DISK;
  ALLOCATE CHANNEL c2 DEVICE TYPE DISK;
  ALLOCATE CHANNEL c3 DEVICE TYPE DISK;
  ALLOCATE CHANNEL c4 DEVICE TYPE DISK;
  BACKUP SECTION SIZE 1G DATABASE;
  -- 每个 1G section 独立分配给某个 channel
}
```

适用场景:数据文件数量少（如 ASM 大文件部署）但单个文件极大。

### 内存与缓冲区调优

```sql
-- 大文件备份的缓冲调优
BACKUP DATABASE
  CHANNELS 4
  MAXOPENFILES 8         -- 每个 channel 最多同时打开 8 个文件
  MAXSETSIZE 50G         -- 单个 backupset 最大 50G
  FILESPERSET 1;         -- 每个 backupset 仅 1 个文件（细粒度）
```

`LARGE_POOL_SIZE` 初始化参数控制 RMAN 的缓冲池大小,默认很小,大量并行 channel 时建议提升:

```sql
ALTER SYSTEM SET large_pool_size = 256M;
-- 或更精细的 RMAN 缓冲计算：
-- 每个 channel × 每个 input file × 1MB buffer = ~ 4 × 8 × 1MB = 32MB
```

### RAC 环境下的并行

Oracle RAC（Real Application Clusters）可以将 channel 分布到多个实例:

```sql
RUN {
  ALLOCATE CHANNEL c1 DEVICE TYPE DISK CONNECT 'sys/pwd@instance1';
  ALLOCATE CHANNEL c2 DEVICE TYPE DISK CONNECT 'sys/pwd@instance2';
  ALLOCATE CHANNEL c3 DEVICE TYPE DISK CONNECT 'sys/pwd@instance3';
  ALLOCATE CHANNEL c4 DEVICE TYPE DISK CONNECT 'sys/pwd@instance4';
  BACKUP DATABASE;
}
```

每个实例的 channel 处理本地的数据文件（由 ASM 决定分布),减少跨节点 IO。

### 恢复时的并行限制

```sql
-- 恢复 channel 数应等于或少于备份时
RUN {
  ALLOCATE CHANNEL c1 DEVICE TYPE DISK;
  ALLOCATE CHANNEL c2 DEVICE TYPE DISK;
  ALLOCATE CHANNEL c3 DEVICE TYPE DISK;
  ALLOCATE CHANNEL c4 DEVICE TYPE DISK;
  RESTORE DATABASE;
  RECOVER DATABASE;     -- RECOVER 阶段使用 RECOVERY_PARALLELISM
}
```

注意:**RESTORE 与 RECOVER 是两个阶段**,前者用 RMAN channel,后者用 redo apply 的并行（`RECOVERY_PARALLELISM` 参数,默认 CPU-1）。

## 备份时并行 vs 恢复时并行：核心权衡

这是并行备份/恢复设计中最重要的决策维度。

### 不对称的现象

| 引擎 | 备份并行引入年份 | 恢复并行引入年份 | 差距 |
|------|----------------|----------------|------|
| PostgreSQL | 9.3 (2013) | 8.4 (2009) | 4 年（恢复先行） |
| MySQL/mydumper | 2010 | 2010 | 同时 |
| Oracle RMAN | 9i (2001) | 9i (2001) | 同时 |
| SQL Server | 2005 (stripe) | 2005 | 同时 |
| ClickHouse | 22.8 (2022) | 22.8 (2022) | 同时 |
| TiDB | 4.0 (2020) | 4.0 (2020) | 同时 |

PostgreSQL 是有趣的例外——`pg_restore --jobs` 早 4 年。原因:

```
恢复时并行容易：
  - TOC（元数据）已存储在备份文件中
  - worker 直接读 TOC 后并行 COPY + CREATE INDEX
  - 不需要数据库提供并发快照机制

备份时并行难：
  - 需要 N 个会话看到同一时刻的数据快照
  - PG 8.x 没有 pg_export_snapshot() API
  - 直到 9.2 引入快照共享,9.3 才能实现 pg_dump --jobs
```

### 设计权衡

```
场景 A：备份频繁 + 偶尔恢复
  优化方向：提升备份并行度
  典型：每天凌晨备份,故障时才恢复
  推荐：PostgreSQL pg_dump -j 16,Oracle RMAN PARALLELISM 16

场景 B：备份偶尔 + 频繁恢复（如 dev 环境刷新）
  优化方向：提升恢复并行度
  典型：周末 dump 生产,工作日多次恢复到 dev
  推荐：pg_restore -j 32,设置 max_parallel_maintenance_workers

场景 C：紧急 RTO（数小时内必须上线）
  优化方向：最大化恢复并行 + 跳过非必需步骤
  推荐：
    - pg_restore --no-owner --no-acl --jobs=N（跳过 ACL 重建）
    - --section=data 先恢复数据,后台慢慢重建索引
    - 或用物理备份（pg_basebackup,无需逻辑重建）
```

### 备份/恢复时间不对称

```
经验观察（PostgreSQL）：
  pg_dump 速度：~50 MB/s/线程（受 CPU/IO 限制）
  pg_restore 速度：~150 MB/s/线程（更快,因为没有快照协议开销）
  CREATE INDEX 速度：~30 MB/s/线程（CPU + 排序密集）

500GB 数据库 + 8 路并行：
  pg_dump：500GB / (50MB/s × 8) = 1250s ≈ 21 分钟
  pg_restore COPY 阶段：500GB / (150MB/s × 8) = 416s ≈ 7 分钟
  pg_restore CREATE INDEX 阶段：取决于索引数量,通常 30-120 分钟
  
关键观察：
  - 索引重建是恢复的瓶颈,不是 COPY
  - 如果可以接受"先恢复数据,后台慢慢建索引",RTO 大幅缩短
  - 物理备份（pg_basebackup）跳过这一阶段,因此恢复极快
```

### 物理 vs 逻辑备份的并行差异

| 维度 | 物理备份（如 pg_basebackup, RMAN） | 逻辑备份（如 pg_dump, mydumper） |
|------|-------------------------------|-----------------------------|
| 备份并行单位 | 表空间 / 数据文件 | 表 |
| 恢复并行单位 | 表空间 / 数据文件 | 表 + 索引 |
| 恢复时间 | 等于解压 + 拷贝时间 | 解压 + COPY + 建索引 |
| 跨版本 | 不行（同版本/同架构） | 可（升级常用） |
| 索引重建 | 不需要（直接拷贝） | 必需（DDL 语句执行） |
| 一致性协议 | 检查点 + WAL/redo | 快照共享 |

物理备份的恢复速度通常是逻辑备份的 5-10 倍,因为跳过了索引重建——这是 RPO/RTO 严苛场景下选物理的根本原因。

## 并行恢复的瓶颈分析

### 恢复阶段拆解

```
典型并行恢复（pg_restore -j 8）的时间分布：
  1. 元数据加载（TOC 解析）         < 1%
  2. CREATE TABLE / 类型定义        ~ 5%
  3. COPY 数据（并行）              ~ 30%
  4. CREATE INDEX（并行）           ~ 50%
  5. ADD CONSTRAINT / FK             ~ 10%
  6. ANALYZE / 统计信息              ~ 5%

观察：CREATE INDEX 占了一半时间,即便 8 路并行
```

### 索引重建的优化策略

```sql
-- 临时调整为 fast index build 友好
ALTER SYSTEM SET maintenance_work_mem = '4GB';
ALTER SYSTEM SET max_parallel_maintenance_workers = 4;
ALTER SYSTEM SET wal_level = 'minimal';   -- 危险,仅在初始恢复
ALTER SYSTEM SET archive_mode = 'off';
ALTER SYSTEM SET fsync = 'off';            -- 极危险,仅在恢复期间

-- pg_restore 后再恢复
ALTER SYSTEM RESET wal_level;
ALTER SYSTEM RESET fsync;
```

### 不可并行化的部分

```
即使 --jobs=N,以下步骤仍然串行：
1. 单个超大表的 COPY（一表 = 一 worker）
2. 大对象（BLOB/CLOB）恢复
3. 物化视图刷新（如果备份包含数据）
4. 序列重置（CREATE SEQUENCE 串行）
5. 用户/权限 DDL
6. 扩展（CREATE EXTENSION）

应对：
  - 超大表预先分区（utilizes pg_dump 表级并行 + 分区级并行）
  - 物化视图改为视图,事后 REFRESH
  - 逻辑备份避开 BLOB,改用文件系统直接拷贝 BLOB 目录
```

## 关键发现

1. **没有 SQL 标准**：所有并行备份/恢复语法都是厂商私有扩展。`--jobs`、`--parallel`、`PARALLELISM N`、`CHANNELS N`、`THREADS N` 五花八门,语义微妙差异。

2. **PostgreSQL 的并行简史**：`pg_restore --jobs`（8.4, 2009）→ `pg_dump --jobs`（9.3, 2013）→ `pg_basebackup -j`（13, 2020）。恢复并行比备份并行早 4 年,因为后者需要 9.2 才有的快照共享 API。

3. **mydumper 填补 MySQL 空白**：MySQL 自带的 `mysqldump` 至今（9.0+）仍是单线程,Domas Mituzas 等人在 2010 年启动的 mydumper/myloader 项目成为事实标准,典型场景下 4-32 jobs。

4. **Oracle RMAN 的 channel 模型**：从 9i (2001) 起就支持 PARALLELISM,通过 channel 抽象将并行度与设备类型解耦,可混合磁盘 + 磁带 + 云存储,是工业并行备份的早期典范。

5. **SQL Server 的 stripe 模型**：通过将备份**条带化到多个 DISK/URL**实现并行,每个 stripe 一个 worker thread。MAXTRANSFERSIZE 和 BUFFERCOUNT 是核心调优参数。

6. **XtraBackup --parallel 仅作用于 .ibd**：MySQL InnoDB 的并行备份按表空间文件并行（每个 .ibd 一个线程),redo log 由专门的单线程拷贝。

7. **DB2 的表空间天然并行**：tablespace 是 DB2 的天然并行单位,`PARALLELISM N` + `WITH N BUFFERS` 双参数控制。

8. **分布式数据库自带并行**：CockroachDB、TiDB、ClickHouse、YugabyteDB 的备份天然按 range/region/part/tablet 并行,无需额外配置。云端通常默认 PB 级备份。

9. **TiDB 备份/恢复并行度差距大**：默认 backup concurrency=4（保护在线流量),restore concurrency=128（最大化 IO 利用)——这是设计明确的不对称性。

10. **ClickHouse 22.8 (2022) 才有 BACKUP**：在此之前依赖社区工具 `clickhouse-backup`,基于 part 复制 + S3 multipart upload。

11. **Snowflake/BigQuery 完全自动**：用户不可见的并行度,基于 micro-partition 或 file-level 自动分发。

12. **物理备份恢复 5-10 倍快于逻辑备份**：物理备份直接拷贝数据文件,跳过 COPY + CREATE INDEX 阶段;逻辑备份需要重建索引,即便 8 路并行也是恢复瓶颈。

13. **流水线（pipeline）能力**：现代云原生数据库（CockroachDB、TiDB、ClickHouse、Snowflake、BigQuery）将"压缩 + 加密 + 上传"流水线化,直接备份到 S3/GCS/Azure Blob,延迟和带宽都优于"先本地备份 + 后期上传"。

14. **CREATE INDEX 是恢复瓶颈**：即使 `pg_restore -j 32`,索引重建通常占恢复时间 50% 以上。优化方向:`max_parallel_maintenance_workers`、临时调高 `maintenance_work_mem`、考虑物理备份。

15. **小型嵌入式引擎几乎都单线程**：SQLite、H2、HSQLDB、Derby、Firebird、QuestDB、MonetDB 的备份均无并行能力,因为目标场景就是单机单库。

16. **RTO/RPO 决定方案选择**：
    - RPO < 1 分钟:WAL 流复制 + 物理备份 + 短间隔 incremental
    - RTO < 1 小时:物理备份 + 高并行恢复（PG `pg_basebackup` + `pg_promote`)
    - RTO < 1 天:逻辑备份 + 并行恢复（`pg_restore -j 16`)
    - 跨版本/跨架构:必须逻辑备份（`pg_dump` / `mysqldump`)

17. **企业 DBA 的"经验值"**：jobs/threads 参数经验范围:
    - 单机:CPU 核数 / 2 ~ CPU 核数
    - 网络瓶颈场景:1-4
    - 高 IOPS NVMe + 32+ 核:8-32
    - 极小数据库（< 1GB）:1（并行无意义）

18. **RTO 验证至关重要**：备份再快,如果不验证恢复时间,生产事故时仍可能超 RTO。建议:
    - 每月演练一次完整恢复（time it!)
    - 每季度演练一次跨数据中心恢复
    - 在测试集群定期 "shoot the postman"（随机踢节点,触发恢复)

## 参考资料

### 官方文档

- PostgreSQL: [pg_dump](https://www.postgresql.org/docs/current/app-pgdump.html) / [pg_restore](https://www.postgresql.org/docs/current/app-pgrestore.html) / [pg_basebackup](https://www.postgresql.org/docs/current/app-pgbasebackup.html)
- Oracle: [RMAN Performance Tuning](https://docs.oracle.com/en/database/oracle/oracle-database/19/bradv/tuning-rman-performance.html) / [Data Pump Export/Import](https://docs.oracle.com/en/database/oracle/oracle-database/19/sutil/oracle-data-pump.html)
- SQL Server: [BACKUP (Transact-SQL)](https://learn.microsoft.com/en-us/sql/t-sql/statements/backup-transact-sql) / [Backup Stripe sets](https://learn.microsoft.com/en-us/sql/relational-databases/backup-restore/media-sets-media-families-and-backup-sets-sql-server)
- MySQL: [mysqldump](https://dev.mysql.com/doc/refman/8.0/en/mysqldump.html) / [Percona XtraBackup](https://docs.percona.com/percona-xtrabackup/8.0/) / [mydumper](https://github.com/mydumper/mydumper)
- DB2: [BACKUP DATABASE](https://www.ibm.com/docs/en/db2/11.5?topic=commands-backup-database) / [PARALLELISM clause](https://www.ibm.com/docs/en/db2/11.5?topic=parameters-parallelism)
- ClickHouse: [BACKUP and RESTORE](https://clickhouse.com/docs/en/operations/backup)
- CockroachDB: [BACKUP](https://www.cockroachlabs.com/docs/stable/backup) / [RESTORE](https://www.cockroachlabs.com/docs/stable/restore)
- TiDB: [BR Backup & Restore Tool](https://docs.pingcap.com/tidb/stable/backup-and-restore-overview)
- Greenplum: [gpbackup utility](https://docs.vmware.com/en/VMware-Greenplum-Backup-and-Restore/index.html)
- SAP HANA: [BACKUP DATA Statement](https://help.sap.com/docs/SAP_HANA_PLATFORM/4fe29514fd584807ac9f2a04f6754767/c4761e75bb571014a8d5ed3a755866b5.html)

### 历史演进资料

- PostgreSQL 8.4 (2009): pg_restore --jobs 引入 commit
- PostgreSQL 9.3 (2013): pg_dump --jobs 引入 commit (Joachim Wieland)
- PostgreSQL 13 (2020): pg_basebackup --jobs 引入 commit (Asif Rehman)
- mydumper Project: [GitHub mydumper/mydumper](https://github.com/mydumper/mydumper) (started ~2010)
- Percona XtraBackup: 1.6.x 引入 --parallel (around 2010)
- ClickHouse 22.8 (2022 年 8 月): 原生 BACKUP/RESTORE 引入
- Oracle RMAN: 9i Release 1 (2001) 引入 PARALLELISM

### 性能与调优

- PostgreSQL Wiki: [Parallel Pg_dump](https://wiki.postgresql.org/wiki/Parallel_pg_dump) （社区性能数据)
- Percona Blog: 多篇 XtraBackup 性能调优指南
- IBM Redbook: DB2 BACKUP/RESTORE Performance
- Oracle 白皮书: RMAN Performance Tuning Best Practices
- TiDB 文档: BR Performance Tuning

### 相关文章

- 备份与恢复语法 → `backup-restore-syntax.md`
- 批量导入导出 → `bulk-import-export.md`
- 快照导出 → `snapshot-export.md`
- COPY/Bulk Load → `copy-bulk-load.md`
- WAL 归档与 PITR → `wal-archiving.md`
