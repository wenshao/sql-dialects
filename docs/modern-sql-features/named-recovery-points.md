# 命名恢复点 (Named Recovery Points)

"把数据库恢复到 2025-04-29 14:53:17.842" 是一种说法，"把数据库恢复到 `before_release_v2.4` 这个标签" 是另一种说法。前者是时间戳 PITR，看似精确实则脆弱：UTC 与本地时间转换错误、NTP 漂移、备库重放延迟造成 GTID 与时间戳之间的非线性映射，都能让一次本应"恰好回到误操作之前"的恢复变成"早了 0.5 秒还有半个失败事务"或"晚了 0.3 秒已经回滚不了"。**命名恢复点（Named Recovery Point）**——也叫 Restore Point、Recovery Point、Named LSN、Named Marker——是引擎提供的另一种坐标系：DBA 在做危险操作之前，显式调用 `CREATE RESTORE POINT before_purge` 把当前 WAL 位置（LSN/GTID/SCN）打上一个人类可读的标签；事后无论是 1 分钟还是 30 天后做恢复，都可以直接 `RECOVER UNTIL RESTORE POINT before_purge`，引擎从归档日志中精确定位那一条记录，不再依赖时间戳的对齐。

姊妹文章：[WAL 归档与 PITR](./wal-archiving.md) 关注"持久化日志流如何让任意时间点恢复成为可能"；[系统版本控制查询](./system-versioned-queries.md) 关注"已经写入的历史版本如何通过 `FOR SYSTEM_TIME AS OF` 查询"；[数据库克隆](./database-cloning.md) 关注"如何瞬间创建一个独立可写的副本"；本文专注于"如何在 WAL/redo 流中打标签，并把这些标签作为恢复目标"。

## 为什么需要命名恢复点

设想一个常见场景：周五晚上凌晨两点，DBA 准备执行一次涉及十张关键业务表的批量数据迁移脚本，预计 40 分钟完成。万一脚本中某条 UPDATE 把 WHERE 写错把整张表刷成同一个值，DBA 需要回到脚本开始执行的那一刻。可选方案：

1. **基于时间戳的 PITR**：记下 `02:00:00 UTC`，回滚到这个时间点。问题：批处理执行过程中产生了若干其他业务事务（账单、推送、库存调整），如果时间戳不精确，可能回滚得太多或太少；操作系统时钟、NTP 漂移、归档延迟都可能让时间戳与日志位置之间产生几百毫秒的偏差。
2. **手动记录 LSN/GTID**：执行 `SELECT pg_current_wal_lsn()` 或 `SHOW MASTER STATUS`，记录到运行手册。问题：要求 DBA 在压力下手抄 16 进制偏移量，跨人移交时易遗失，多套环境（主备、跨机房）的 LSN 不一致。
3. **命名恢复点**：执行 `SELECT pg_create_restore_point('before_migration_2025_04_29')`，把当前 WAL 位置和这个标签持久化到 WAL 流中。事后无论是当晚还是几个月后做演练，都可以 `recovery_target_name = 'before_migration_2025_04_29'`。

命名恢复点解决的不只是"记一个 LSN 太麻烦"，更核心的是把恢复目标从**物理坐标（时间/LSN/GTID）**抽象为**逻辑事件名**。这种抽象带来三个好处：

- **人类可读**：运行手册、变更工单、灾难演练剧本里写的是 `pre_release_2_4_0` 这样的名字，而不是 `0/3A8F2B40`。
- **跨节点稳定**：物理 LSN 在主备/跨机房之间可能不同（特别是异步复制场景），但同一个 restore point 在每个节点的 WAL 流里都能找到对应的标记记录。
- **审计追踪**：所有 restore point 都被持久化到 WAL/redo 中，`v$restore_point`（Oracle）或 `pg_waldump`（PostgreSQL）可以列出所有命名标签，方便回溯"上一次完整测试是哪个时间点的状态"。

进一步的高级用途：

1. **危险变更前**：DDL、批量 UPDATE/DELETE、Schema 迁移之前打标签，事后可精确回滚。
2. **发布回滚锚点**：每次软件发布前打 `pre_release_X.Y` 标签；新版本如果在生产暴露问题，可以快速恢复到发布前。
3. **季度/年度审计快照**：会计季度结束打 `quarter_end_2025_Q1`，作为不可变的审计时点。
4. **测试复现**：定期打标签作为回归测试的"已知好状态"，让 QA 可以反复回滚到该时点跑测试。
5. **跨数据中心同步基线**：在主中心打标签，备中心确认 replay 到该标签后，两个站点对齐基线。
6. **Guaranteed Restore Point**：Oracle 独有，引擎承诺保留足够 redo + flashback log 让你**保证**能闪回到该点，与普通 restore point 仅作为标签不同。
7. **Savepoint 兼容**：事务内的 `SAVEPOINT` 是另一个层次的"命名点"，但它仅在事务内有效，事务一旦提交就消失，与持久化的 restore point 不是一个量级。

## 没有 SQL 标准

ISO/IEC 9075（包括 SQL:2003、SQL:2011、SQL:2016、SQL:2023）只在事务子句中定义了 `SAVEPOINT name` / `ROLLBACK TO SAVEPOINT name`，这是**事务局部**（transaction-local）的命名点：savepoint 仅在它所属事务的生命周期内有效，事务提交或回滚后立即消失，无法用于事务结束后的 PITR。

对于持久化、跨事务、与 WAL/redo 流绑定的命名恢复点，SQL 标准完全不涉及，各引擎术语和实现差异极大：

- **Oracle** 用 `CREATE RESTORE POINT name`，并区分 normal restore point（仅元数据标签）和 guaranteed restore point（额外保证 flashback log 保留）。
- **PostgreSQL** 用 `pg_create_restore_point('name')` 函数，将一条特殊 WAL 记录写入日志流；恢复时通过 `recovery_target_name = 'name'` 指定。
- **SQL Server** 用 `BACKUP LOG ... WITH MARK 'name'`，把命名标记同时写入 transaction log 和 backup metadata。
- **MySQL** 没有原生命名恢复点；社区方案是把 binlog 文件名 + 位置偏移量人工记录，或用 GTID 区间作为恢复目标。
- **CockroachDB** 用 `BACKUP ... AS OF SYSTEM TIME ...` + `BACKUP CHECKPOINTS`，通过 backup 标签作为恢复锚点。
- **TiDB** 通过 BR (backup-restore) 工具的 `--backupts` 和 `--restore-name` 维护命名快照。
- **DB2** 通过 `db2relocatedb` + `RECOVER ... TO MARK` 实现类似命名点。
- **Snowflake / BigQuery / Spanner** 把这一切隐藏在 Time Travel 之后，用户不感知具体的标签机制。

虽然没有标准，"在 WAL 流中打标签 + 通过名字而非时间戳恢复" 已是各主流引擎认可的事实模式。

## 支持矩阵

### 1. SAVEPOINT（事务局部命名点，SQL 标准）

事务内的 savepoint 是 SQL 标准（自 SQL:1999 起）的一部分，几乎所有支持事务的引擎都支持。注意：**savepoint 在事务结束后即失效**，不是持久化恢复点，但很多用户混淆这两个概念，所以这里也列出。

| 引擎 | SAVEPOINT | RELEASE SAVEPOINT | ROLLBACK TO SAVEPOINT | 嵌套 | 自动命名 | 版本 |
|------|-----------|-------------------|----------------------|------|---------|------|
| PostgreSQL | 是 | 是 | 是 | 是 | -- | 8.0+ |
| MySQL | 是 | 是 | 是 | 是 | -- | 4.0+ |
| MariaDB | 是 | 是 | 是 | 是 | -- | 5.0+ |
| SQLite | 是 | 是 | 是 | 是 | -- | 3.6+ |
| Oracle | 是 | -- | 是 | 是 | -- | 早期 |
| SQL Server | 是 | -- | 是 | 否 | -- | 2000+ |
| DB2 | 是 | 是 | 是 | 是 | -- | 早期 |
| Snowflake | -- | -- | -- | -- | -- | 不支持 |
| BigQuery | -- | -- | -- | -- | -- | 不支持 |
| Redshift | 是 | 是 | 是 | 是 | -- | GA |
| DuckDB | 是 | 是 | 是 | 是 | -- | GA |
| ClickHouse | -- | -- | -- | -- | -- | 不支持 |
| Trino/Presto | -- | -- | -- | -- | -- | 不支持 |
| Spark SQL | -- | -- | -- | -- | -- | 不支持 |
| Hive | -- | -- | -- | -- | -- | 不支持 |
| Flink SQL | -- | -- | -- | -- | -- | 不支持 |
| Databricks | -- | -- | -- | -- | -- | 不支持 |
| Teradata | -- | -- | -- | -- | -- | 不支持 |
| Greenplum | 是 | 是 | 是 | 是 | -- | 继承 PG |
| CockroachDB | 是 | 是 | 是 | 是 | -- | 19.1+ |
| TiDB | 是 | 是 | 是 | 是 | -- | 6.2+ |
| OceanBase | 是 | 是 | 是 | 是 | -- | 兼容 MySQL/Oracle |
| YugabyteDB | 是 | 是 | 是 | 是 | -- | 继承 PG |
| SingleStore | -- | -- | -- | -- | -- | 不支持 |
| Vertica | -- | -- | -- | -- | -- | 不支持 |
| Impala | -- | -- | -- | -- | -- | 不支持 |
| StarRocks | -- | -- | -- | -- | -- | 不支持 |
| Doris | -- | -- | -- | -- | -- | 不支持 |
| MonetDB | -- | -- | -- | -- | -- | 不支持 |
| CrateDB | -- | -- | -- | -- | -- | 不支持 |
| TimescaleDB | 是 | 是 | 是 | 是 | -- | 继承 PG |
| QuestDB | -- | -- | -- | -- | -- | 不支持 |
| Exasol | -- | -- | -- | -- | -- | 不支持 |
| SAP HANA | 是 | 是 | 是 | 是 | -- | 1.0+ |
| Informix | 是 | 是 | 是 | 是 | -- | 早期 |
| Firebird | 是 | 是 | 是 | 是 | -- | 1.5+ |
| H2 | 是 | -- | 是 | 是 | -- | 1.x+ |
| HSQLDB | 是 | 是 | 是 | 是 | -- | 1.8+ |
| Derby | 是 | 是 | 是 | 是 | -- | 早期 |
| Amazon Athena | -- | -- | -- | -- | -- | 不支持 |
| Azure Synapse | 是 | -- | 是 | 否 | -- | 继承 SQL Server |
| Google Spanner | -- | -- | -- | -- | -- | 不支持 |
| Materialize | -- | -- | -- | -- | -- | 不支持 |
| RisingWave | -- | -- | -- | -- | -- | 不支持 |
| InfluxDB | -- | -- | -- | -- | -- | 不支持 |
| DatabendDB | -- | -- | -- | -- | -- | 不支持 |
| Yellowbrick | 是 | 是 | 是 | 是 | -- | 继承 PG |
| Firebolt | -- | -- | -- | -- | -- | 不支持 |

> 统计：约 22 个引擎支持事务内的 SAVEPOINT，分析型/MPP 引擎普遍不支持（无事务模型或单语句模型）。

### 2. 持久化命名恢复点（CREATE RESTORE POINT 类语法）

这是本文的核心：跨事务持久化的、与 WAL/redo 流绑定的命名标签。

| 引擎 | 创建语法 | Guaranteed 变种 | 持久化位置 | 列举语法 | 删除语法 | 版本 |
|------|---------|----------------|----------|---------|---------|------|
| Oracle | `CREATE RESTORE POINT name` | `CREATE RESTORE POINT name GUARANTEE FLASHBACK DATABASE` | redo log + control file | `SELECT * FROM v$restore_point` | `DROP RESTORE POINT name` | 10g R2 (2005) |
| SQL Server | `BACKUP LOG db TO ... WITH MARK 'name'` | -- | transaction log + msdb | `SELECT * FROM msdb.dbo.logmarkhistory` | -- | 2000 |
| PostgreSQL | `SELECT pg_create_restore_point('name')` | -- | WAL 中的特殊记录 | `pg_waldump` 解析 | -- | 9.1 (2011) |
| MySQL | -- | -- | -- | -- | -- | 无原生 |
| MariaDB | -- | -- | -- | -- | -- | 无原生 |
| SQLite | -- | -- | -- | -- | -- | 无 |
| DB2 | `db2 archive log + label` (RECOVER TO MARK) | -- | log archive 元数据 | `LIST HISTORY` | -- | v9+ |
| Snowflake | -- | -- | -- (隐藏) | -- | -- | 隐藏在 Time Travel 后 |
| BigQuery | -- | -- | -- (隐藏) | -- | -- | 隐藏在自动 PITR 后 |
| Redshift | snapshot 命名 | -- | 快照元数据 | `SELECT * FROM stv_xen_xact_history` | `DROP SNAPSHOT` | GA |
| DuckDB | -- | -- | -- | -- | -- | 不支持 |
| ClickHouse | `BACKUP TABLE ... NAMED ...` | -- | backup 元数据 | `system.backups` | `BACKUP DROP` | 22.x+ |
| Trino/Presto | -- | -- | -- | -- | -- | 计算引擎 |
| Spark SQL | -- | -- | -- | -- | -- | 计算引擎 |
| Hive | -- | -- | -- | -- | -- | -- |
| Flink SQL | savepoint name | -- | savepoint 文件 | `SHOW SAVEPOINTS` | `DROP SAVEPOINT` | 1.x+ |
| Databricks | Delta Lake `RESTORE TO VERSION` | -- | Delta log | `DESCRIBE HISTORY` | -- | GA |
| Teradata | Permanent Journal checkpoint | -- | PJ 元数据 | `HELP JOURNAL` | -- | 早期 |
| Greenplum | 继承 PG | -- | WAL 记录 | `pg_waldump` | -- | 继承 PG |
| CockroachDB | `BACKUP ... INTO 'subdir' WITH revision_history` | -- | backup 目录 | `SHOW BACKUPS IN '...'` | -- | 21.1+ |
| TiDB | `BACKUP DATABASE TO 'name'` (BR tool) | -- | backup metadata | `br backup list` | `br backup delete` | 4.0+, 命名 6.2+ |
| OceanBase | `ALTER SYSTEM ... ADD RESTORE POINT` | -- | OceanBase 元数据 | `oceanbase.gv$ob_backup_set` | `REMOVE RESTORE POINT` | 3.x+ |
| YugabyteDB | snapshot schedule + label | -- | yb-master 元数据 | `yb-admin list_snapshots` | `yb-admin delete_snapshot` | 2.14+ |
| SingleStore | named milestone | -- | log mark | `SHOW MILESTONES` | -- | 7.x+ |
| Vertica | `vbr.py snapshot --label` | -- | snapshot metadata | `vbr.py listbackup` | `vbr.py remove --label` | 9.0+ |
| Impala | -- | -- | -- | -- | -- | -- |
| StarRocks | `BACKUP SNAPSHOT name TO ...` | -- | backup 元数据 | `SHOW BACKUP` | -- | 2.5+ |
| Doris | `BACKUP SNAPSHOT name TO ...` | -- | backup 元数据 | `SHOW BACKUP` | -- | 1.2+ |
| MonetDB | -- | -- | -- | -- | -- | 不支持 |
| CrateDB | snapshot 命名 | -- | repository | `SHOW SNAPSHOTS` | `DROP SNAPSHOT` | 4.0+ |
| TimescaleDB | 继承 PG | -- | WAL | `pg_waldump` | -- | 继承 PG |
| QuestDB | -- | -- | -- | -- | -- | 不支持 |
| Exasol | EXAoperation backup label | -- | backup metadata | EXAoperation UI | -- | 6.x+ |
| SAP HANA | `BACKUP DATA ... USING FILE ('name')` + log mark | -- | backup catalog | `M_BACKUP_CATALOG` | `BACKUP CATALOG DELETE` | 1.0+ |
| Informix | `onbar -b -L name` | -- | bar metadata | `onstat -g bar` | `onbar -P -L name` | 早期 |
| Firebird | nbackup level + label | -- | nbackup 元数据 | -- | -- | 2.5+ |
| H2 | -- | -- | -- | -- | -- | 不支持 |
| HSQLDB | -- | -- | -- | -- | -- | 不支持 |
| Derby | -- | -- | -- | -- | -- | 不支持 |
| Amazon Athena | -- | -- | -- | -- | -- | 计算引擎 |
| Azure Synapse | LOG MARK (继承 SQL Server) | -- | 同 SQL Server | 同 SQL Server | -- | GA |
| Google Spanner | -- | -- | -- (隐藏) | -- | -- | 隐藏在 PITR 后 |
| Materialize | -- | -- | -- | -- | -- | 不支持 |
| RisingWave | -- | -- | -- | -- | -- | 不支持 |
| InfluxDB | -- | -- | -- | -- | -- | 不支持 |
| DatabendDB | -- | -- | -- | -- | -- | 不支持 |
| Yellowbrick | 继承 PG | -- | WAL | `pg_waldump` | -- | 继承 PG |
| Firebolt | -- | -- | -- | -- | -- | 隐藏 |

> 统计：约 16 个引擎提供原生持久化命名恢复点；Oracle 和 PostgreSQL 是最经典的两套实现；分析型引擎多数依赖 backup 元数据中的 label，与传统 RDBMS 的"WAL 内嵌标签"机制不同。

### 3. 通过名字恢复（Recovery Target by Name）

| 引擎 | 恢复语法 | 在主库上重启动 | 在备库上 promote | 在 standalone restore 中 | 版本 |
|------|---------|---------------|-----------------|-----------------------|------|
| Oracle | `RECOVER DATABASE UNTIL RESTORE POINT name` | 是 | 是 | 是 | 10g R2 |
| Oracle (Flashback) | `FLASHBACK DATABASE TO RESTORE POINT name` | 是（DB 在 mount 状态） | -- | -- | 10g R2 |
| PostgreSQL | `recovery_target_name = 'name'`（recovery.signal/postgresql.auto.conf） | -- | 是 | 是 | 9.1 |
| SQL Server | `RESTORE LOG db FROM ... WITH STOPATMARK = 'name'` | 是 | 是 | 是 | 2000 |
| SQL Server | `RESTORE LOG db FROM ... WITH STOPBEFOREMARK = 'name'` | 是 | 是 | 是 | 2000 |
| DB2 | `RECOVER DATABASE TO MARK 'name'` | 是 | -- | 是 | v9+ |
| MySQL | -- (binlog GTID/position 替代) | -- | -- | -- | -- |
| MariaDB | -- (同 MySQL) | -- | -- | -- | -- |
| SAP HANA | `RECOVER DATABASE TO LOG POSITION 'mark'` | 是 | 是 | 是 | 1.0+ |
| Informix | `onbar -r -t 'mark_name'` | 是 | -- | 是 | 早期 |
| OceanBase | `ALTER SYSTEM RESTORE database UNTIL RESTORE POINT 'name'` | 是 | -- | 是 | 3.x+ |
| TiDB BR | `br restore full --backup-name=...` | -- | -- | 是 | 4.0+ |
| CockroachDB | `RESTORE FROM 'subdir' AS OF SYSTEM TIME ...` | -- | -- | 是 | 21.1+ |
| Vertica | `vbr.py restore --label name` | -- | -- | 是 | 9.0+ |
| ClickHouse | `RESTORE TABLE ... FROM ... NAMED ...` | -- | -- | 是 | 22.x+ |
| Snowflake | `CREATE TABLE ... CLONE src AT (TIMESTAMP => ...)` | -- | -- | 是 | GA |
| Databricks | `RESTORE TABLE name TO VERSION AS OF n` 或 `TO TIMESTAMP AS OF '...'` | -- | -- | 是 | GA |
| Greenplum | 继承 PG | -- | 是 | 是 | 继承 PG |
| YugabyteDB | `yb-admin restore_snapshot_schedule snapshot_id` | -- | -- | 是 | 2.14+ |

> 统计：约 13 个引擎支持"按名字"作为恢复目标；其中 Oracle、SQL Server、PostgreSQL、DB2、SAP HANA 是经典的"WAL 内嵌标签 + 通过名字恢复"四件套实现。

### 4. Guaranteed Flashback Database（Oracle 独有）

| 引擎 | 关键字 | 保留机制 | 影响 | 配置 | 版本 |
|------|-------|--------|------|------|------|
| Oracle | `GUARANTEE FLASHBACK DATABASE` | Flash Recovery Area 不会因为空间压力删除该 RP 之后的 flashback log | 强制保留磁盘 | `DB_FLASHBACK_RETENTION_TARGET` | 10g R2 |
| 其他引擎 | -- | -- | -- | -- | 无对应能力 |

> Guaranteed Restore Point 是 Oracle 独有的能力，本质是把"我必须能闪回到这个点"作为一个**资源约束**，引擎会在 Flash Recovery Area 中无条件保留所需 flashback log，即使空间紧张也不删除。这与"普通 restore point 仅作为标签，不保证可恢复"形成对比。

### 5. 名字解析与冲突处理

| 引擎 | 唯一性范围 | 重名行为 | 大小写敏感 | 最大长度 | 命名空间 |
|------|----------|---------|----------|--------|---------|
| Oracle | 全数据库 | 报错 ORA-38778 | 是（默认大写） | 128 字节 | 与表/索引共享 |
| PostgreSQL | WAL 流 | 后写覆盖（恢复时取首个匹配） | 是 | NAMEDATALEN = 64 | 独立 |
| SQL Server | 同一 transaction log 内可重复 | 后写不覆盖，列表中按 LSN 区分 | 是 | 128 字符 | 独立 |
| DB2 | recovery history | 报错 SQL2402N | 是 | 128 字节 | 独立 |
| SAP HANA | 系统级 | 后写覆盖 | 是 | 256 字符 | 独立 |
| OceanBase | 租户级 | 报错 OB_ERR_RESTORE_POINT_EXIST | 是 | 64 字节 | 独立 |
| TiDB BR | 备份目录全局 | 报错 BR:Backup:ErrSavedNameExist | 是 | 取决于 OS 文件系统 | 独立 |

## Oracle Restore Points + Flashback Database 深入

Oracle 在 10g R2（2005）首次引入 `CREATE RESTORE POINT`，并在同一版本扩展为 Guaranteed Restore Point + Flashback Database 联动机制。这是当今最完整的命名恢复点实现，本节做完整剖析。

### 基础语法

```sql
-- 普通 restore point（仅元数据标签）
CREATE RESTORE POINT before_release_v2_4;

-- 显式指定基于的 SCN
CREATE RESTORE POINT q1_2025_close
    AS OF SCN 1234567890;

-- Guaranteed restore point（要求保留足够 flashback log）
CREATE RESTORE POINT pre_migration_2025_04_29
    GUARANTEE FLASHBACK DATABASE;

-- 列出所有 restore point
SELECT name, scn, time, guarantee_flashback_database, storage_size
FROM v$restore_point;

-- 删除
DROP RESTORE POINT before_release_v2_4;
```

### 普通 vs Guaranteed Restore Point

```
普通 Restore Point:
  仅在 control file 和 v$restore_point 中保留 SCN + 名字
  不影响 redo / flashback log 的保留策略
  Flash Recovery Area 仍按照 DB_FLASHBACK_RETENTION_TARGET 自动清理
  风险：如果保留窗口（默认 1440 分钟 = 24 小时）已过，restore point 仍存在，
       但你已经无法 FLASHBACK 到那个点（redo / flashback log 已删除）

Guaranteed Restore Point:
  额外承诺：FRA 中所有从该 restore point 之后的 flashback log 必须保留
  即使 FRA 接近满，也不会删除（可能阻塞新 redo 写入 → 数据库 hang）
  必须显式 DROP 才会释放
  storage_size 列显示已占用的空间
  风险：忘记 DROP 导致 FRA 撑爆，主库可能直接停机
```

### 配置 Flashback Database

```sql
-- 1. 配置 Flash Recovery Area
ALTER SYSTEM SET DB_RECOVERY_FILE_DEST = '/u02/fra' SCOPE=SPFILE;
ALTER SYSTEM SET DB_RECOVERY_FILE_DEST_SIZE = 100G SCOPE=SPFILE;

-- 2. 设置 flashback 保留窗口（分钟）
ALTER SYSTEM SET DB_FLASHBACK_RETENTION_TARGET = 1440;  -- 24 小时

-- 3. 启用 flashback database（数据库需要 mount 状态）
SHUTDOWN IMMEDIATE;
STARTUP MOUNT;
ALTER DATABASE FLASHBACK ON;
ALTER DATABASE OPEN;

-- 4. 验证
SELECT flashback_on FROM v$database;  -- YES
```

### 使用 Restore Point 做 Flashback

```sql
-- 准备：创建 guaranteed restore point
CREATE RESTORE POINT pre_dml_2025_04_29 GUARANTEE FLASHBACK DATABASE;

-- 执行危险操作
UPDATE orders SET status = 'X' WHERE 1=1;  -- 错误：忘记 WHERE
COMMIT;

-- 发现错误，回滚整个数据库到 restore point
SHUTDOWN IMMEDIATE;
STARTUP MOUNT;
FLASHBACK DATABASE TO RESTORE POINT pre_dml_2025_04_29;
ALTER DATABASE OPEN RESETLOGS;

-- 完成后清理
DROP RESTORE POINT pre_dml_2025_04_29;
```

### 使用 Restore Point 做 Media Recovery

```sql
-- 在备份恢复场景，restore point 作为 RMAN recovery target
RUN {
    SET UNTIL RESTORE POINT pre_dml_2025_04_29;
    RESTORE DATABASE;
    RECOVER DATABASE;
}
ALTER DATABASE OPEN RESETLOGS;
```

### v$restore_point 视图详解

```sql
SELECT
    name,                            -- restore point 名字
    scn,                             -- 对应的 SCN（System Change Number）
    storage_size,                    -- 占用 FRA 空间（字节，仅 guaranteed 有值）
    time,                            -- 创建时间
    database_incarnation#,           -- 所属数据库化身
    guarantee_flashback_database,    -- YES / NO
    preserved,                       -- YES = 持续保留, NO = 可被自动清理
    clean_pdb_restore_point,         -- 12c+ 多租户支持
    pdb_restore_point,               -- 12c+ 多租户支持
    pdb_incarnation#,                -- 12c+
    replicated                       -- 12c+ 是否在 Data Guard 下复制
FROM v$restore_point
ORDER BY scn;
```

### Multi-tenant（PDB）下的 Restore Point

```sql
-- 12c+ 在 PDB 内创建 restore point
ALTER SESSION SET CONTAINER = pdb_app1;
CREATE RESTORE POINT pdb_pre_release GUARANTEE FLASHBACK DATABASE;

-- 仅闪回 PDB 而不影响整个 CDB
ALTER PLUGGABLE DATABASE pdb_app1 CLOSE;
FLASHBACK PLUGGABLE DATABASE pdb_app1 TO RESTORE POINT pdb_pre_release;
ALTER PLUGGABLE DATABASE pdb_app1 OPEN RESETLOGS;
```

### Data Guard 集成

```sql
-- 在主库创建 guaranteed restore point
-- Data Guard 物理备库会自动同步该 restore point
-- 备库可以 FAILOVER 后用同一个 restore point 名字闪回

-- 主库
CREATE RESTORE POINT pre_critical_op GUARANTEE FLASHBACK DATABASE;

-- 备库（自动收到 restore point）
SELECT name, scn, replicated
FROM v$restore_point
WHERE name = 'PRE_CRITICAL_OP';
-- replicated = YES

-- 备库 FAILOVER 后
ALTER DATABASE FLASHBACK TO RESTORE POINT pre_critical_op;
```

### 性能与容量管理

```sql
-- 检查 FRA 使用情况
SELECT * FROM v$flash_recovery_area_usage;
-- BACKUP_PIECE / FLASHBACK_LOG / ARCHIVELOG / ... 各占多少

-- 当 FRA 容量紧张时，guaranteed restore point 可能阻塞 redo 写入
-- 此时需要：
-- 1. 删除不再需要的 guaranteed restore point
-- 2. 增大 DB_RECOVERY_FILE_DEST_SIZE
-- 3. 减小 DB_FLASHBACK_RETENTION_TARGET（仅影响普通 flashback，不影响 guaranteed）

-- 估算 guaranteed restore point 的 flashback log 增长
SELECT
    estimated_flashback_size / 1024 / 1024 / 1024 AS estimated_gb,
    flashback_size / 1024 / 1024 / 1024 AS current_gb,
    retention_target
FROM v$flashback_database_log;
```

### 限制与注意事项

```
1. NOLOGGING 操作：DIRECT PATH INSERT、SQL*Loader DIRECT、CTAS 在 NOLOGGING 模式下
   不会写 redo，FLASHBACK 这些块的结果是无法恢复的（Oracle 报 ORA-38754）
   缓解：FORCE LOGGING 或 ALTER TABLESPACE ... LOGGING

2. SHRINK 操作：不可闪回过 SHRINK SPACE 操作
3. DROP TABLE PURGE：bypassing recycle bin，不可恢复
4. 跨 RESETLOGS：FLASHBACK 不能跨越 OPEN RESETLOGS 操作（数据库化身改变）
5. 表空间离线：包含 OFFLINE 表空间时 FLASHBACK 失败
```

## PostgreSQL pg_create_restore_point() 深入

PostgreSQL 9.1（2011）引入的 `pg_create_restore_point()` 函数是另一个经典实现，与 Oracle 的核心区别是：PG 没有"保证可恢复"的承诺，restore point 仅是一条特殊的 WAL 记录。

### 基础语法

```sql
-- 必须由超级用户调用，不能在备库上调用
SELECT pg_create_restore_point('before_release_2_4');
-- 返回：lsn (text，如 '0/3A8F2B40')

-- 这个函数实际上做了什么：
-- 1. 在当前 WAL 流写入一条 XLOG_RESTORE_POINT 记录，payload 是 restore point 名字
-- 2. 返回这条记录的起始 LSN
-- 3. 名字会被持久化到归档 WAL 中，可以在恢复时通过 recovery_target_name 引用
```

### archive_mode 与 archive_command 配置

restore point 名字必须出现在归档的 WAL 中才能被恢复使用。配置示例：

```ini
# postgresql.conf
wal_level = replica  # 或更高
archive_mode = on
archive_command = 'cp %p /mnt/wal_archive/%f'
# 或者用 pgBackRest / wal-g
```

### 在 recovery.signal / postgresql.auto.conf 中指定恢复目标

PostgreSQL 12+ 把恢复参数从 recovery.conf 移到了 postgresql.conf，并通过空文件 recovery.signal 触发恢复模式。

```bash
# 1. 停止数据库
pg_ctl stop -m fast

# 2. 用 base backup 恢复 PGDATA
rm -rf $PGDATA
pg_basebackup -D $PGDATA -h backup_source

# 3. 配置恢复目标
cat >> $PGDATA/postgresql.auto.conf <<EOF
restore_command = 'cp /mnt/wal_archive/%f %p'
recovery_target_name = 'before_release_2_4'
recovery_target_action = 'promote'
EOF

# 4. 触发恢复
touch $PGDATA/recovery.signal

# 5. 启动数据库
pg_ctl start
# PostgreSQL 会重放 WAL 直到遇到名为 'before_release_2_4' 的 restore point，然后停止
# recovery_target_action = 'promote' 让它自动从恢复模式切换到正常模式
```

### recovery_target_* 参数家族

PostgreSQL 提供 5 种 recovery target，互斥（只能选一个）：

| 参数 | 含义 | 何时用 |
|------|------|------|
| `recovery_target_name` | 命名 restore point | 推荐：发布前/危险操作前显式打标签 |
| `recovery_target_time` | 时间戳 | 临时 PITR，没有命名标签时用 |
| `recovery_target_lsn` | LSN | 极端精确控制（如已知错误事务的 LSN） |
| `recovery_target_xid` | 事务 ID | 极端精确控制（如知道误操作的 XID） |
| `recovery_target` | `'immediate'` | 一致性恢复后立即停止（用于 base backup 验证） |

```ini
# 示例 1：恢复到命名点
recovery_target_name = 'pre_release_2_4'

# 示例 2：恢复到时间戳
recovery_target_time = '2025-04-29 14:53:00 UTC'

# 示例 3：恢复到 LSN
recovery_target_lsn = '0/3A8F2B40'

# 示例 4：恢复到事务
recovery_target_xid = '12345678'

# 控制是 inclusive 还是 exclusive（仅对 time/lsn/xid 有效，name 总是 inclusive）
recovery_target_inclusive = on  # 默认 on，恢复到该点之后即停止；off 则在该点之前停止
```

### recovery_target_action 三态

```ini
# pause（默认）：到达目标后暂停，等待管理员决策
#   pg_wal_replay_resume() 继续，pg_promote() 升为主库
recovery_target_action = 'pause'

# promote：到达目标后立即升为读写主库
recovery_target_action = 'promote'

# shutdown：到达目标后停止数据库（用于离线验证）
recovery_target_action = 'shutdown'
```

### 名字冲突的解析规则

如果同一个名字在 WAL 中出现多次（例如先后两次 `pg_create_restore_point('test')`），PostgreSQL 在恢复时只匹配 **第一次** 出现的位置：

```sql
-- 时刻 T1: 创建第一个
SELECT pg_create_restore_point('test');  -- LSN=0/100

-- 时刻 T2: 创建第二个同名
SELECT pg_create_restore_point('test');  -- LSN=0/200

-- 恢复时 recovery_target_name = 'test'
-- 恢复到 LSN=0/100 即停止（first match），LSN=0/200 永远不会被读到
```

为了避免歧义，建议在名字中加入时间戳或唯一计数器。

### 在备库上调用？

`pg_create_restore_point()` 只能在主库上调用。备库（standby）无法写 WAL，因此无法创建 restore point。如果在 standby 上调用会报错：

```
ERROR:  recovery is in progress
HINT:   pg_create_restore_point() cannot be executed during recovery.
```

但是主库创建的 restore point 会自动出现在 standby 的 WAL replay 流中，standby 可以用 `recovery_target_name` 停在该点（典型场景：把 standby 提升为独立的"时点克隆"）。

### pg_waldump 检查

```bash
# 列出 WAL 段中的所有 restore point 记录
pg_waldump /pg_wal/000000010000000000000003 | grep RESTORE_POINT

# 输出示例：
# rmgr: XLOG  len (rec/tot):     43/    43, tx:     0, lsn: 0/3A8F2B40, prev 0/3A8F2B08,
#   desc: RESTORE_POINT before_release_2_4
```

### 限制与注意事项

```
1. 必须主库执行；备库无法创建
2. 必须超级用户或拥有 pg_create_restore_point 函数的 EXECUTE 权限
3. 名字最长 NAMEDATALEN-1 = 63 字节（UTF-8 多字节字符占多个字节）
4. 恢复时 recovery_target_inclusive 对 name 无效（始终 inclusive）
5. 调用本身写一条 WAL，会被归档；archive_mode=off 时 restore point 失去意义
6. 没有 "guaranteed" 概念：如果对应的 WAL 段已被 wal_keep_size / replication slot
   清理，restore point 名字仍存在但恢复时会找不到该 LSN
```

### 通过 SQL 函数管理（PostgreSQL 没有 DROP）

PostgreSQL 没有"删除 restore point"的概念，因为它仅是 WAL 中的一条记录。"删除"等同于"让该 WAL 段过期被 archive_cleanup_command 删除"。

```sql
-- 列出当前可见的 restore point 比较麻烦，因为它存在 WAL 中而非 catalog
-- 唯一可靠方式是 pg_waldump

-- 系统视图 pg_replication_slots 展示哪些 LSN 还被 slot 引用
SELECT slot_name, restart_lsn FROM pg_replication_slots;

-- 系统函数检查归档状态
SELECT pg_walfile_name_offset(pg_current_wal_lsn());
```

### 与 pgBackRest / wal-g 的集成

```bash
# pgBackRest：直接支持 --target=name
pgbackrest --stanza=main --type=name --target='before_release_2_4' restore

# wal-g：通过 recovery_target_name 配合 wal-g wal-fetch 实现
wal-g backup-fetch $PGDATA LATEST
echo "restore_command = 'wal-g wal-fetch %f %p'" >> $PGDATA/postgresql.auto.conf
echo "recovery_target_name = 'before_release_2_4'" >> $PGDATA/postgresql.auto.conf
echo "recovery_target_action = 'promote'" >> $PGDATA/postgresql.auto.conf
touch $PGDATA/recovery.signal
pg_ctl start
```

## SQL Server BACKUP LOG WITH MARK

SQL Server 自 2000 起支持事务日志标记（log mark）。它与 Oracle / PG 的实现略有不同：mark 是事务的副产品，必须在 BEGIN TRAN 中显式声明，并通过 BACKUP LOG 持久化。

### 创建 marked transaction

```sql
-- 标记事务：在事务开始时声明 WITH MARK
USE OrdersDB;
GO

BEGIN TRANSACTION pre_release_2_4 WITH MARK 'Before release 2.4 deployment';
GO

-- 必须有写操作才能 commit 一个 mark（否则 mark 不被持久化）
UPDATE marker_table SET marked_at = GETUTCDATE() WHERE id = 1;
GO

COMMIT TRANSACTION pre_release_2_4;
GO

-- 备份事务日志，确保 mark 持久化到备份链
BACKUP LOG OrdersDB TO DISK = 'C:\Backup\OrdersDB_log.bak';
GO
```

### 列出所有 marked transaction

```sql
-- 系统表 logmarkhistory 在 msdb 中
SELECT
    database_name,
    mark_name,
    description,
    user_name,
    lsn,
    mark_time
FROM msdb.dbo.logmarkhistory
WHERE database_name = 'OrdersDB'
ORDER BY mark_time DESC;
```

### 通过名字恢复

```sql
-- 1. 全量备份恢复（不上线）
RESTORE DATABASE OrdersDB
FROM DISK = 'C:\Backup\OrdersDB_full.bak'
WITH NORECOVERY, REPLACE;

-- 2. 恢复差异备份（如果有）
RESTORE DATABASE OrdersDB
FROM DISK = 'C:\Backup\OrdersDB_diff.bak'
WITH NORECOVERY;

-- 3. 恢复事务日志到指定 mark
RESTORE LOG OrdersDB
FROM DISK = 'C:\Backup\OrdersDB_log.bak'
WITH STOPATMARK = 'pre_release_2_4', RECOVERY;

-- 或者：恢复到 mark 之前（不包含 mark 事务本身）
RESTORE LOG OrdersDB
FROM DISK = 'C:\Backup\OrdersDB_log.bak'
WITH STOPBEFOREMARK = 'pre_release_2_4', RECOVERY;
```

### STOPATMARK vs STOPBEFOREMARK

```
STOPATMARK = 'name':
  恢复到包含 mark 的事务（mark 事务本身被 commit）
  常用于"恢复到这次操作之后立即停止"

STOPBEFOREMARK = 'name':
  恢复到 mark 之前（mark 事务被 rollback）
  常用于"恢复到这次操作之前的状态"

如果同一名字出现多次，可以加 AFTER datetime 限定：
WITH STOPATMARK = 'pre_release', AFTER '2025-04-28 12:00:00'
```

### LSN 标签：fn_dblog 解析

```sql
-- SQL Server 提供 undocumented fn_dblog() 查询活跃事务日志
-- （仅当前 active log，不含已截断的）
SELECT
    [Current LSN],
    Operation,
    [Transaction Name],
    [Description],
    [Begin Time]
FROM fn_dblog(NULL, NULL)
WHERE Operation = 'LOP_BEGIN_XACT'
  AND [Transaction Name] LIKE 'pre_%'
ORDER BY [Current LSN];

-- fn_dump_dblog() 解析备份文件中的事务日志
SELECT [Current LSN], Operation, [Transaction Name]
FROM fn_dump_dblog(
    NULL, NULL, 'DISK', 1, 'C:\Backup\OrdersDB_log.bak',
    DEFAULT, DEFAULT, DEFAULT, DEFAULT, DEFAULT, DEFAULT,
    DEFAULT, DEFAULT, DEFAULT, DEFAULT, DEFAULT, DEFAULT,
    DEFAULT, DEFAULT, DEFAULT, DEFAULT, DEFAULT, DEFAULT,
    DEFAULT, DEFAULT, DEFAULT, DEFAULT, DEFAULT, DEFAULT,
    DEFAULT, DEFAULT, DEFAULT, DEFAULT, DEFAULT, DEFAULT,
    DEFAULT, DEFAULT, DEFAULT, DEFAULT, DEFAULT, DEFAULT,
    DEFAULT, DEFAULT, DEFAULT, DEFAULT, DEFAULT, DEFAULT,
    DEFAULT, DEFAULT, DEFAULT, DEFAULT, DEFAULT, DEFAULT,
    DEFAULT, DEFAULT, DEFAULT, DEFAULT, DEFAULT, DEFAULT,
    DEFAULT, DEFAULT, DEFAULT, DEFAULT, DEFAULT, DEFAULT,
    DEFAULT, DEFAULT
)
WHERE [Transaction Name] LIKE 'pre_%';
```

### 跨数据库 marked transaction

SQL Server 的 `WITH MARK` 还支持跨多个数据库的协调恢复：如果同一事务跨越多个 DB（DTC 场景），mark 会同时写入所有相关 DB 的日志，恢复时可以让多个 DB 同步停在同一个逻辑点。

```sql
BEGIN DISTRIBUTED TRANSACTION CrossDB_Mark WITH MARK 'cross_db_consistent_point';

UPDATE OrdersDB..orders SET ...;
UPDATE InventoryDB..stock SET ...;

COMMIT;

-- 恢复时
RESTORE LOG OrdersDB FROM ... WITH STOPATMARK = 'cross_db_consistent_point', RECOVERY;
RESTORE LOG InventoryDB FROM ... WITH STOPATMARK = 'cross_db_consistent_point', RECOVERY;
-- 两个 DB 在同一个逻辑时点对齐
```

### 与 Oracle / PG 的核心差异

```
SQL Server 的 mark 必须依附于一个事务：
  - 没有"非事务的 restore point"
  - mark 必须在 BEGIN TRANSACTION ... WITH MARK 时声明
  - 如果事务回滚，mark 不被持久化
  - 必须在事务内有写操作（否则 commit 时 mark 不被记录）

Oracle 的 restore point 是独立对象：
  - CREATE RESTORE POINT 自身不在用户事务中
  - 创建即生效，记录到 control file
  - 可以指定 AS OF SCN 引用过去的某个 SCN

PostgreSQL 的 restore point 是函数调用：
  - SELECT pg_create_restore_point() 是独立的 SQL 调用
  - 立即写一条 XLOG_RESTORE_POINT 到 WAL
  - 没有"基于过去 SCN"的能力（必须当前时刻）
```

## MySQL：没有原生命名恢复点

MySQL（包括 MariaDB、Percona 分支）至今（截至 8.4）没有"通过名字恢复"的能力。常用替代方案：

### binlog 文件名 + 位置偏移量

```sql
-- 1. 在做危险操作之前，记录当前 binlog 位置
SHOW MASTER STATUS;
-- File: mysql-bin.000123, Position: 4567890

-- 2. 也可以记录当前 GTID
SELECT @@GLOBAL.GTID_EXECUTED;
-- 0e9123ab-4567-89cd-ef01-234567890123:1-100000

-- 3. 在运行手册或 ChatOps 中保留这个值
```

### 用临时表存储"标签"

```sql
-- 业内常用的 work-around：建一张 marker 表，记录命名时点
CREATE TABLE IF NOT EXISTS __recovery_marks (
    name VARCHAR(64) PRIMARY KEY,
    binlog_file VARCHAR(256),
    binlog_pos BIGINT,
    gtid_executed TEXT,
    created_at DATETIME(6) DEFAULT CURRENT_TIMESTAMP(6),
    description TEXT
);

-- 使用：危险操作前
INSERT INTO __recovery_marks (name, binlog_file, binlog_pos, gtid_executed, description)
SELECT
    'pre_release_2_4',
    File,
    Position,
    @@GLOBAL.GTID_EXECUTED,
    'Before v2.4 deploy'
FROM
    (SHOW MASTER STATUS) AS m;
-- 注意：MySQL 不允许 SELECT 直接消费 SHOW MASTER STATUS，实际要用应用层
```

### 通过 mysqlbinlog 工具恢复

```bash
# 用 binlog 位置恢复
mysqlbinlog \
    --start-position=4567890 \
    --stop-position=5000000 \
    /var/log/mysql/mysql-bin.000123 \
  | mysql -u root -p

# 或用时间戳
mysqlbinlog \
    --start-datetime='2025-04-29 14:53:00' \
    --stop-datetime='2025-04-29 15:00:00' \
    /var/log/mysql/mysql-bin.000123 \
  | mysql -u root -p
```

### Percona XtraBackup + 命名约定

```bash
# 用文件夹命名作为 "label"
xtrabackup --backup --target-dir=/backup/pre_release_2_4

# 恢复时按文件夹名定位
xtrabackup --copy-back --target-dir=/backup/pre_release_2_4
```

### 社区呼声

MySQL 社区多次请求添加类似 `pg_create_restore_point()` 的功能（参见 MySQL Bugs #80788, #91234），但官方一直没有原生支持。InnoDB Cluster + MySQL Router 在 8.0+ 提供了 GTID-based recovery，部分缓解了"位置定位"的痛点。

## CockroachDB：BACKUP CHECKPOINTS

CockroachDB 21.1+ 在 `BACKUP` 中引入 `WITH revision_history`，实现"快照 + 增量"的命名恢复链。

```sql
-- 创建带 revision history 的 backup（包含从备份起所有 WAL）
BACKUP DATABASE my_db INTO 's3://backups/my_db'
    WITH revision_history;

-- 列出某个 backup 集合中的所有可用恢复点
SHOW BACKUPS IN 's3://backups/my_db';
SHOW BACKUP FROM '2025-04-29-14-53-00.00' IN 's3://backups/my_db';

-- 通过 AS OF SYSTEM TIME 在 backup 范围内恢复任意时点
RESTORE DATABASE my_db FROM '2025-04-29-14-53-00.00' IN 's3://backups/my_db'
    AS OF SYSTEM TIME '2025-04-29 14:55:00.00';
```

CockroachDB 没有"用户命名"的 restore point，但 backup 子目录名（默认时间戳）可以视为系统命名。用户可以指定 subdir：

```sql
BACKUP DATABASE my_db INTO 's3://backups/my_db/pre_release_2_4'
    WITH revision_history;
RESTORE DATABASE my_db FROM 'pre_release_2_4' IN 's3://backups/my_db';
```

## TiDB BR：Named Snapshots since 6.2

TiDB 的 BR (Backup-Restore) 工具是 4.0 引入的，6.2（2022）增加了 `--backup-name` 命名能力。

```bash
# 创建命名快照
br backup full \
    --pd "pd-host:2379" \
    --storage "s3://backups/tidb/pre_release_2_4" \
    --backup-name "pre_release_2_4" \
    --gcttl 86400

# 列出所有命名 backup
br backup list --storage "s3://backups/tidb"
# 输出：
# NAME                START_TS       END_TS         BACKUP_SIZE
# pre_release_2_4     438xxxxxx      438xxxxxx      120 GB
# quarter_end_q1      438xxxxxx      438xxxxxx      105 GB

# 通过名字恢复
br restore full \
    --pd "pd-host:2379" \
    --storage "s3://backups/tidb/pre_release_2_4"

# Point-in-Time Recovery（6.2+ 支持 log backup）
# 1. 持续 log backup
br log start --pd "pd-host:2379" --storage "s3://backups/tidb/log"

# 2. 在某时点恢复到该时点 + 名字
br restore point \
    --pd "pd-host:2379" \
    --full-backup-storage "s3://backups/tidb/pre_release_2_4" \
    --storage "s3://backups/tidb/log" \
    --restored-ts "2025-04-29 15:00:00 +0800"
```

## DB2 RECOVER TO MARK

DB2 通过 `RECOVER ... TO MARK 'name'` 实现命名恢复点，但需要先在 backup 命令中标记。

```bash
# 在 db2 命令行
db2 "BACKUP DATABASE sample TO /backup WITH 4 BUFFERS BUFFER 1024 PARALLELISM 2 \
     INCLUDE LOGS WITHOUT PROMPTING"

# 通过 RECOVER 引用名字（其中 mark 通常是 timestamp）
db2 "RECOVER DATABASE sample TO 2025-04-29.14.53.00.000000 USING HISTORY FILE \
     (/db2/sample/db2dump/db2rhist.asc)"

# 9.5+ 支持 LIST HISTORY 列出所有可用 mark
db2 "LIST HISTORY ALL FOR sample"
```

DB2 的 mark 主要基于时间戳和 log sequence，命名能力较弱，但 `LIST HISTORY` 提供完整的事件流追溯。

## SAP HANA Log Backup Marks

```sql
-- 创建命名备份 mark
BACKUP DATA USING FILE ('/backup/hana_pre_release_2_4');

-- 创建 log backup（持续）
ALTER SYSTEM SET ('persistence', 'log_backup_using_backint') = 'true';

-- 通过 log position 名字恢复
RECOVER DATABASE FOR sample
    UNTIL TIMESTAMP '2025-04-29 14:53:00'
    USING LOG PATH ('/backup')
    USING DATA PATH ('/backup/hana_pre_release_2_4');
```

## Snowflake / BigQuery / Spanner：Time Travel 隐藏命名

云数仓把命名恢复点的复杂性完全隐藏在 Time Travel API 之后，用户无需感知 WAL/redo：

```sql
-- Snowflake：Time Travel 1-90 天，通过 TIMESTAMP / OFFSET / STATEMENT 引用过去状态
SELECT * FROM orders AT (TIMESTAMP => '2025-04-29 14:53:00 UTC');
SELECT * FROM orders AT (OFFSET => -3600);   -- 一小时前
SELECT * FROM orders AT (STATEMENT => '01b91234-...');  -- 某条语句之前

-- 没有用户可命名的 restore point，但可以用 CLONE + 命名表来达到效果
CREATE TABLE orders_pre_release_2_4 CLONE orders AT (TIMESTAMP => '2025-04-29 14:53:00');

-- BigQuery：自动 PITR 7 天
SELECT * FROM dataset.orders FOR SYSTEM_TIME AS OF TIMESTAMP_SUB(CURRENT_TIMESTAMP(), INTERVAL 1 HOUR);

-- Spanner：PITR 1 小时-7 天，通过 STALE READ 或 BACKUP
SELECT * FROM orders AS OF SYSTEM_TIME '2025-04-29T14:53:00Z';
```

## 迁移模式

### Oracle → PostgreSQL

```sql
-- Oracle
CREATE RESTORE POINT pre_release_2_4 GUARANTEE FLASHBACK DATABASE;
-- 危险操作 ...
FLASHBACK DATABASE TO RESTORE POINT pre_release_2_4;
DROP RESTORE POINT pre_release_2_4;

-- PostgreSQL（无 guaranteed 等价物，必须依赖 wal_keep_size 或 replication slot）
SELECT pg_create_restore_point('pre_release_2_4');
-- 确保 WAL 不被清理：
ALTER SYSTEM SET wal_keep_size = '16GB';   -- PG 13+
SELECT pg_create_physical_replication_slot('pre_release_2_4_slot');
-- 危险操作 ...
-- 恢复（必须重启进入恢复模式）
-- 在 postgresql.auto.conf:
-- recovery_target_name = 'pre_release_2_4'
-- recovery_target_action = 'promote'
-- 然后 touch recovery.signal 重启
```

### Oracle → SQL Server

```sql
-- Oracle
CREATE RESTORE POINT pre_release_2_4;

-- SQL Server（必须在事务里）
BEGIN TRANSACTION pre_release_2_4 WITH MARK 'before release 2.4';
UPDATE __marks SET marked_at = GETUTCDATE() WHERE id = 1;  -- 必须有写操作
COMMIT;
BACKUP LOG OrdersDB TO DISK = 'C:\Backup\Log.bak';  -- 持久化 mark
```

### MySQL → PostgreSQL

```sql
-- MySQL（无原生）
SHOW MASTER STATUS;  -- 手动记录 file + position
-- 或用 GTID
SELECT @@GLOBAL.GTID_EXECUTED;

-- PostgreSQL
SELECT pg_create_restore_point('pre_release_2_4');
```

### SQL Server → Oracle

```sql
-- SQL Server
BEGIN TRANSACTION pre_release_2_4 WITH MARK;
UPDATE __marks SET marked_at = GETUTCDATE();
COMMIT;
BACKUP LOG db TO DISK = '...';

-- Oracle（更简单）
CREATE RESTORE POINT pre_release_2_4 GUARANTEE FLASHBACK DATABASE;
```

### 通用迁移规则

| 源 | 目标 | 迁移建议 |
|----|------|---------|
| Oracle Guaranteed RP | PostgreSQL | 用 pg_create_restore_point + wal_keep_size + replication slot 模拟 |
| Oracle Normal RP | PostgreSQL | 直接用 pg_create_restore_point |
| Oracle RP | SQL Server | 用 marked transaction，必须配合 BACKUP LOG 持久化 |
| Oracle RP | MySQL | 无对应能力，记录 GTID 替代 |
| SQL Server marked transaction | Oracle | 用 CREATE RESTORE POINT，无需事务 |
| SQL Server marked transaction | PostgreSQL | 用 pg_create_restore_point，无需事务 |
| PostgreSQL RP | Oracle | 用 CREATE RESTORE POINT |
| PostgreSQL RP | MySQL | 无对应能力，记录 GTID 替代 |

## 设计争议

### Restore Point vs Savepoint：根本不同

新手最常混淆的两个概念：

```
SAVEPOINT (事务局部):
  - 仅在 BEGIN ... COMMIT/ROLLBACK 之间有效
  - 事务结束后自动消失，无法用于事务外的恢复
  - 用于"长事务内的部分回滚"
  - SQL 标准（SQL:1999+）定义

CREATE RESTORE POINT (持久化):
  - 跨事务、跨数据库重启都有效
  - 必须显式删除（或随 WAL 段过期清理）
  - 用于"全数据库的 PITR"
  - SQL 标准未定义，各引擎自定义
```

引擎实现者必须在文档中清晰区分这两个概念，避免用户误认为"savepoint 一直有效"。

### 时间戳 vs 命名：可读性 vs 精度

```
时间戳恢复 (recovery_target_time = '2025-04-29 14:53:00'):
  优点：不需要事先打标签，事后任意时点恢复
  缺点：
    - 时区/NTP/时钟漂移导致 ±数百毫秒误差
    - 时间戳到 LSN 的映射不是单调（同一秒可能有数千事务）
    - inclusive vs exclusive 的语义模糊（包不包含 14:53:00.000 那一瞬间？）

命名恢复点 (recovery_target_name = 'pre_release_2_4'):
  优点：
    - 人类可读，运行手册友好
    - 精确定位到特定 LSN，无时钟模糊
    - 跨节点稳定（同一名字在每个 standby 上都对应相同 WAL 记录）
  缺点：
    - 必须事先创建（无法事后追溯）
    - 名字管理负担（重名、过期、文档同步）
    - 仅对"已知"事件有用，无法应对"未知错误后的回滚"
```

最佳实践：发布、迁移、批量操作之前**总是打 restore point**；事后追溯型恢复才用时间戳。

### Guaranteed 的代价：FRA 风险

Oracle 的 Guaranteed Restore Point 有一个致命陷阱：忘记删除。如果 DBA 在测试环境创建了 GRP，然后忘记 `DROP`，几天后 FRA 撑爆，主库 redo 写入被阻塞，最终导致**数据库 hang**。

防御措施：
- 命名约定中加入到期日期：`pre_release_2025_04_29__expire_2025_05_06`
- 监控 `v$flash_recovery_area_usage`，flashback log > 80% 报警
- 自动化脚本定期清理过期 GRP

### 名字解析：first match vs last match

不同引擎对重名 restore point 的处理不同：

| 引擎 | 重名处理 | 备注 |
|------|---------|------|
| PostgreSQL | first match（恢复时取首个匹配的 LSN） | 不报错，但语义可能反直觉 |
| Oracle | 报错 ORA-38778 | 强制唯一 |
| SQL Server | 列表中保留所有，恢复时取首个或用 AFTER 限定 | 半灵活 |
| DB2 | 报错 SQL2402N | 强制唯一 |
| OceanBase | 报错 OB_ERR_RESTORE_POINT_EXIST | 强制唯一 |

引擎实现者建议：**强制唯一性**优于"first match"，因为后者在 DBA 失误下会产生隐蔽的恢复错误。

### 数据库化身（incarnation）边界

`OPEN RESETLOGS`（Oracle）或 `pg_resetwal`（PostgreSQL）会创建新的数据库化身，旧的 restore point 在新化身中可能找不到对应 WAL：

```sql
-- Oracle 通过 v$database_incarnation 查询
SELECT incarnation#, prior_incarnation#, status, resetlogs_change#, resetlogs_time
FROM v$database_incarnation;

-- 跨化身的 FLASHBACK 通常不可用
-- 必须先 RESET DATABASE TO INCARNATION 切换化身
RESET DATABASE TO INCARNATION 2;
FLASHBACK DATABASE TO RESTORE POINT pre_release_2_4;
```

PostgreSQL 通过 timeline 隔离化身：

```bash
# 列出所有 timeline
ls -la $PGDATA/pg_wal/*.history

# 跨 timeline 的 restore point 默认不可用
# 必须通过 recovery_target_timeline 显式指定
echo "recovery_target_timeline = '2'" >> $PGDATA/postgresql.auto.conf
```

## 关键发现

经过对 45+ 引擎的横向对比，命名恢复点的支持谱系可以归纳为：

### 1. 完整实现派（Oracle + PostgreSQL + SQL Server + DB2 + SAP HANA）

这五家是命名恢复点的"四件套完整实现"：
- 创建语法（CREATE RESTORE POINT / pg_create_restore_point / WITH MARK / RECOVER TO MARK）
- 持久化到 WAL/redo（不是仅仅元数据）
- 列举与删除接口（v$restore_point / pg_waldump / msdb.logmarkhistory / LIST HISTORY）
- 通过名字恢复（RECOVER UNTIL RESTORE POINT / recovery_target_name / STOPATMARK / RECOVER TO MARK）

### 2. 增强派（Oracle Guaranteed Restore Point）

只有 Oracle 提供"保证可恢复"的承诺，通过 Flash Recovery Area 强制保留 flashback log。这是命名恢复点的"金标准"，但代价是 FRA 容量风险。

### 3. 备份元数据派（CockroachDB / TiDB / Vertica / ClickHouse / Doris / StarRocks）

分布式 / 分析型引擎多数没有 WAL 内嵌标签的能力，转而用 backup 子目录名 + revision history 实现近似的"命名快照"。优点：与对象存储天然集成；缺点：只能恢复到 backup 时点，不是任意 LSN。

### 4. Time Travel 隐藏派（Snowflake / BigQuery / Spanner / Databricks）

云数仓把所有命名复杂性藏在 `AS OF TIMESTAMP` 之后。用户无法直接命名恢复点，但可以通过 `CREATE TABLE ... CLONE source AT (TIMESTAMP => ...)` 把任意时点物化为命名表。

### 5. 无原生支持派（MySQL / SQLite / 多数轻量级引擎）

MySQL 至今（8.4）无原生命名恢复点，依赖 binlog 文件名 + position + GTID 的人工记录。对许多生产场景（金融、医疗）是显著缺陷。

### 6. 事务局部 Savepoint：不能等同于 Restore Point

绝大多数引擎都支持 SAVEPOINT，但它仅在事务内有效。把 savepoint 当作 restore point 使用是常见错误，必须在引擎文档和 DBA 培训中强调区别。

### 7. 命名解析的隐藏陷阱

不同引擎对重名、大小写、跨化身、跨时间线的处理策略截然不同：
- Oracle / DB2 / OceanBase：强制唯一
- PostgreSQL：first match（不报错但语义反直觉）
- SQL Server：列表保留，需要 AFTER 限定

这是迁移和工具开发时最容易踩的坑。

### 8. Guaranteed 的双刃剑

Oracle 的 Guaranteed Restore Point 是最强大也最危险的特性：
- 优点：真正的"保证可恢复"，对金融/医疗合规至关重要
- 缺点：忘记删除会撑爆 FRA，导致数据库 hang
- 必须配合监控、命名约定（含到期日）、自动清理脚本

### 9. 与 Time Travel 的本质区别

`FOR SYSTEM_TIME AS OF`（系统版本控制查询）与命名恢复点是两种正交能力：
- Time Travel 是**点查**能力，针对单表的历史版本，不需要全库恢复
- Restore Point 是**全库恢复**能力，必须重启或 promote 备库

理想的引擎应该同时提供两者，让用户在不同场景下选用。

### 10. 引擎选型建议

| 场景 | 推荐引擎/方案 | 原因 |
|------|-------------|------|
| 严格金融/合规，要求"保证可恢复" | Oracle GUARANTEE FLASHBACK | 唯一提供真正承诺的引擎 |
| 开源 PITR + 命名标签 | PostgreSQL + pgBackRest | 标准 + 工具链成熟 |
| 微软栈，事务级精度 | SQL Server WITH MARK | 跨 DB 协调恢复 |
| MySQL 生态，无奈选择 | binlog + GTID 人工记录 | 缺失原生支持 |
| 云数仓，不想感知 | Snowflake / BigQuery Time Travel | 完全托管 |
| 分布式 NewSQL | TiDB BR 6.2+ / CockroachDB BACKUP CHECKPOINTS | 备份级命名 |
| 轻量级嵌入式 | DuckDB / SQLite | 无支持，只能用 dump |

## 对引擎开发者的实现建议

### 1. WAL 内嵌标签的格式

```
建议在 WAL 中定义独立的 RESTORE_POINT 记录类型：

struct RestorePointRecord {
    uint8_t  rmgr_id;        // resource manager id (XLOG)
    uint8_t  info;           // RESTORE_POINT info bit
    uint64_t lsn;            // 当前 LSN
    uint64_t prev_lsn;       // 上一条记录的 LSN
    uint32_t name_length;    // 名字字节长度
    char     name[];         // 名字（UTF-8，最长 NAMEDATALEN-1）
}

恢复时扫描 WAL：
  for each record in wal_stream:
    if record.rmgr_id == XLOG && record.info & XLOG_RESTORE_POINT:
        if record.name == target_name:
            stop_at = record.lsn
            break
```

### 2. 名字唯一性策略

```
强制唯一（推荐）:
  - 创建时检查 name 是否已存在（扫描现有 WAL + 元数据表）
  - 存在则报错，提示用户改名或删除旧的
  - 优点：避免 first-match 陷阱

不唯一 + first match（PostgreSQL 风格）:
  - 创建时不检查
  - 恢复时取首个匹配
  - 优点：实现简单，无需扫描
  - 缺点：用户失误时无错误提示

建议：默认强制唯一，提供 ALLOW_DUPLICATE 标志位让高级用户绕过
```

### 3. Guaranteed 模式的实现

```
关键挑战：如何在不影响 redo 写入的前提下保证 flashback log 不被清理

思路 1（Oracle）：
  - 维护 "minimum_recovery_lsn" 全局变量
  - WAL 段清理任务读取该值，跳过 < minimum 的段
  - 创建 guaranteed restore point 时更新该值
  - 删除时重新计算（取所有 guaranteed RP 中最小的 LSN）

思路 2（基于引用计数）：
  - 每个 guaranteed RP 持有一个引用 slot（类似 PG 的 replication slot）
  - WAL 段被任一 slot 引用 → 不可清理
  - 删除 RP 释放 slot

思路 3（基于硬链接）：
  - 创建 guaranteed RP 时，把当前 WAL 段硬链接到独立目录
  - WAL 清理任务删除原文件，硬链接保留物理空间
  - 仅适用于本地 FS，不适用于对象存储

性能影响：
  - guaranteed RP 越多，可清理的 WAL 段越少 → FRA 占用上升
  - 必须监控 FRA 容量并预警
```

### 4. 名字到 LSN 的索引

```
全 WAL 扫描在数据量大时极慢。建议维护一个 catalog：

CREATE TABLE pg_restore_points (
    name varchar(64) PRIMARY KEY,
    lsn pg_lsn NOT NULL,
    created_at timestamptz NOT NULL,
    is_guaranteed bool DEFAULT false,
    description text
);

创建 RP 时同时插入这张表 + 写 WAL 记录
查询时直接走 catalog（O(1)）
恢复时仍需扫描 WAL（catalog 可能不在 base backup 中）

注意：catalog 必须自身被 WAL 保护（否则灾难恢复时丢失）
PostgreSQL 选择不维护 catalog，纯靠 WAL 扫描；Oracle 选择维护 v$restore_point
```

### 5. 跨节点同步

```
主备复制场景下：
  - 主库创建 RP → WAL 流传播到备库
  - 备库 replay 到该 WAL 记录时，自动注册到本地 catalog
  - 备库本身不应允许创建新 RP（standby 只读）

多写复制（如 Galera Cluster）：
  - 必须有全局协调（Paxos/Raft）决定 RP 创建顺序
  - 名字冲突需要全局检测
  - PostgreSQL BDR / CockroachDB / TiDB 等需要特殊处理

跨数据中心：
  - 异步复制下，备 DC 的 RP LSN 可能滞后主 DC
  - 通过名字而非 LSN 可以容忍这种滞后
```

### 6. 与 promotion 的交互

```
PostgreSQL 风格：
  recovery_target_action = 'promote'
  recovery_target_name = 'pre_release_2_4'
  → 恢复到该 RP 后立即升为读写主库

需要处理：
  1. 提升时创建新 timeline，旧 timeline 的 WAL 不再被消费
  2. 旧 timeline 上 RP 之后的 WAL 段进入 pg_wal/00000002.history 历史
  3. 后续 base backup 必须能选择 timeline，否则恢复路径模糊

Oracle 风格：
  ALTER DATABASE OPEN RESETLOGS;
  → 创建新 incarnation
  → v$database_incarnation 记录祖先关系
  → 旧 RP 在新 incarnation 不可见，必须 RESET DATABASE TO INCARNATION 切回
```

### 7. 监控与可观测性

```
必须暴露的指标：
  - 当前 RP 数量（normal / guaranteed 分别）
  - 最旧 RP 的 LSN / 创建时间
  - guaranteed RP 占用的 WAL/flashback log 空间
  - 因 RP 阻塞的 WAL 段清理数量

报警阈值（建议）：
  - guaranteed RP 占用 > FRA 80%
  - 单个 RP 存活 > 30 天（可能是忘记删除）
  - 同名 RP 创建尝试（可能是脚本 bug）
```

### 8. API 设计

```
推荐的 SQL 接口：

CREATE RESTORE POINT name [WITH (
    guaranteed = true,
    description = '...',
    expires_at = '2025-05-06 00:00 UTC'
)];

DROP RESTORE POINT name [IF EXISTS];

ALTER RESTORE POINT name RENAME TO new_name;
ALTER RESTORE POINT name SET expires_at = '...';

SELECT * FROM pg_restore_points
WHERE name LIKE 'pre_%'
  AND created_at > now() - interval '7 days';

# 函数式接口（PostgreSQL 风格）
SELECT create_restore_point('name', guaranteed := true);
SELECT drop_restore_point('name');
SELECT list_restore_points();

# expires_at 的实现：
#   后台 worker 定期扫描，到期自动 DROP
#   防御性命名：如果 DBA 忘记删除，至少不会无限累积
```

### 9. 测试用例

```
基础测试：
  1. 创建 RP → 写 WAL → 重启 → 用名字恢复 → 验证状态正确
  2. 创建多个 RP → 列举 → 顺序正确
  3. 删除 RP → 列举 → 不存在
  4. 重名创建 → 报错或 first-match（按设计）

边界测试：
  5. 名字最长边界（NAMEDATALEN-1）→ 成功
  6. 名字 NAMEDATALEN → 报错
  7. 空名字 → 报错
  8. UTF-8 多字节字符 → 字节长度 vs 字符长度

恢复测试：
  9. 恢复到 RP 名字 → LSN 精确停在该点
  10. 恢复到不存在的 RP 名字 → 报错或 hang（按设计）
  11. 恢复到 RP 后再开新事务 → 创建新 timeline / incarnation
  12. 跨 timeline / incarnation 的 RP 不可见

并发测试：
  13. 多客户端同时创建 RP → 顺序串行化
  14. 创建 RP 时主库崩溃 → 重启后部分写入应被清理或完整保留

容量测试：
  15. guaranteed RP 持续累积 → FRA 空间增长
  16. FRA 超限 → 报警 + 拒绝新 redo

复制测试：
  17. 主库创建 RP → 备库自动可见
  18. 备库尝试创建 RP → 报错（standby read-only）
  19. 备库 promote → RP 在新 timeline 仍可用
```

## 总结对比矩阵

### 命名恢复点能力总览

| 能力 | Oracle | SQL Server | PostgreSQL | DB2 | SAP HANA | MySQL | Snowflake | TiDB | CockroachDB |
|------|--------|------------|------------|-----|----------|-------|-----------|------|-------------|
| 创建语法 | CREATE RESTORE POINT | WITH MARK | pg_create_restore_point | RECOVER TO MARK | log mark | -- | CLONE AT | BR --backup-name | BACKUP INTO subdir |
| Guaranteed | 是 | -- | -- | -- | -- | -- | -- | -- | -- |
| 通过名字恢复 | UNTIL RESTORE POINT | STOPATMARK | recovery_target_name | TO MARK | TO LOG POSITION | -- | AT TIMESTAMP | --backup-name | FROM subdir |
| 唯一性 | 强制 | 不强制 | first-match | 强制 | 后写覆盖 | -- | -- | 强制 | 子目录唯一 |
| 列举接口 | v$restore_point | logmarkhistory | pg_waldump | LIST HISTORY | M_BACKUP_CATALOG | -- | INFORMATION_SCHEMA | br backup list | SHOW BACKUPS |
| Multi-tenant | PDB 级 | DB 级 | -- | -- | tenant 级 | -- | -- | -- | -- |
| 主备同步 | Data Guard | AlwaysOn | streaming | HADR | system replication | -- | -- | -- | -- |
| 引入版本 | 10g R2 (2005) | 2000 | 9.1 (2011) | v9+ | 1.0+ | -- | GA | 6.2 (2022) | 21.1 (2021) |

### 与时间戳 PITR 的对比

| 维度 | 时间戳 PITR | 命名恢复点 |
|------|-----------|----------|
| 精度 | 取决于时钟同步 | LSN 精确 |
| 可读性 | 数字串 | 人类可读 |
| 事先准备 | 不需要 | 必须事先创建 |
| 跨节点稳定性 | 弱（时钟漂移） | 强（WAL 内嵌） |
| 适用场景 | 事后追溯型恢复 | 计划性危险操作 |
| 名字管理 | 无 | 需要命名约定 |
| 工具链支持 | 普遍 | 需要引擎原生支持 |

### 与 Savepoint 的本质区别

| 维度 | SAVEPOINT | 命名恢复点 |
|------|-----------|----------|
| 作用域 | 单个事务 | 全数据库 |
| 持久化 | 内存（事务结束即消失） | WAL/redo（持久） |
| SQL 标准 | SQL:1999+ | 实现定义 |
| 创建权限 | 任意用户 | 通常需要超级用户 |
| 用途 | 部分回滚 | PITR 恢复 |
| 引擎广泛性 | 大部分支持 | 只有 RDBMS 完整支持 |

## 参考资料

- Oracle: [CREATE RESTORE POINT](https://docs.oracle.com/en/database/oracle/oracle-database/19/sqlrf/CREATE-RESTORE-POINT.html)
- Oracle: [Flashback Database](https://docs.oracle.com/en/database/oracle/oracle-database/19/bradv/rman-flashback.html)
- Oracle: [Guaranteed Restore Points](https://docs.oracle.com/en/database/oracle/oracle-database/19/bradv/rman-flashback-restore-points.html)
- PostgreSQL: [pg_create_restore_point()](https://www.postgresql.org/docs/current/functions-admin.html#FUNCTIONS-ADMIN-BACKUP)
- PostgreSQL: [Recovery Target Settings](https://www.postgresql.org/docs/current/runtime-config-wal.html#RUNTIME-CONFIG-WAL-RECOVERY-TARGET)
- SQL Server: [BACKUP LOG ... WITH MARK](https://learn.microsoft.com/en-us/sql/t-sql/statements/backup-transact-sql)
- SQL Server: [RESTORE LOG ... WITH STOPATMARK](https://learn.microsoft.com/en-us/sql/t-sql/statements/restore-statements-arguments-transact-sql)
- DB2: [Recovery to a point in time](https://www.ibm.com/docs/en/db2/11.5)
- SAP HANA: [Recovery with Log Mark](https://help.sap.com/docs/SAP_HANA_PLATFORM)
- TiDB: [BR Backup and Restore](https://docs.pingcap.com/tidb/stable/backup-and-restore-overview)
- CockroachDB: [BACKUP with revision_history](https://www.cockroachlabs.com/docs/stable/backup.html)
- OceanBase: [ALTER SYSTEM ADD RESTORE POINT](https://www.oceanbase.com/docs)
- ANSI/ISO SQL:1999, Section 7.x — SAVEPOINT
- Gray, J. & Reuter, A. "Transaction Processing: Concepts and Techniques" (1993), Chapter on Recovery
- Mohan, C. et al. "ARIES: A Transaction Recovery Method" (1992), ACM Transactions on Database Systems
