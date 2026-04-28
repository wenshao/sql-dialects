# 快照保留期与 Undo 配置 (Snapshot Retention and Undo Configuration)

凌晨两点,一个长时间运行的报表查询突然抛出 `ORA-01555: snapshot too old`。两小时前提交的事务覆写了同一行的旧版本,Oracle 的 UNDO 段已经被新事务覆盖,这条历史快照永远找不回来了。这就是 MVCC 数据库工程师永远在调和的天平:旧行版本保留多久?太短,长查询和长事务会失败;太长,死元组堆积、bloat 失控、磁盘炸裂。

每一个支持 MVCC 的数据库——Oracle、PostgreSQL、SQL Server、CockroachDB、TiDB、Snowflake 全都有一个或一组配置参数,用来回答"老的行版本保留多久"。参数的名字千差万别(`UNDO_RETENTION`、`vacuum_freeze_min_age`、`gc.ttlseconds`、`tidb_gc_life_time`、`DATA_RETENTION_TIME_IN_DAYS`),但要解决的问题都是同一个:在长查询/长事务的可见性需求,与 GC/VACUUM 的空间回收效率之间,找一个平衡点。

## SQL 标准的态度:完全不管

ISO/IEC 9075:2023 标准对快照保留、undo 配置、GC TTL 没有任何规定。原因和 VACUUM 章节相同——这些都是物理存储层和并发控制实现的内部细节,标准只关心隔离级别和事务可见性的逻辑语义,不关心引擎用什么手段实现。

但这就导致每个引擎按自己的存储模型发明了一套配置参数:

- 基于 undo 段的引擎(Oracle、SQL Server tempdb、MySQL InnoDB):配置 undo 容量上限和最小保留时间
- 基于行内多版本的引擎(PostgreSQL、Greenplum、CockroachDB):配置 GC TTL 和 vacuum/freeze 阈值
- 基于不可变文件的引擎(Snowflake、BigQuery、Delta Lake、Iceberg):配置历史版本保留天数(Time Travel window)
- LSM 系引擎(TiDB、YugabyteDB、TiKV、RocksDB):配置 GC safe point 和 compaction 阈值

理解每种存储模型对应的配置语义,是引擎开发者和 DBA 共同的功课。

## 支持矩阵

### Undo / 快照保留参数

| 引擎 | 关键参数 | 默认值 | 引入版本 | 自动调整 |
|------|---------|-------|---------|---------|
| Oracle | `UNDO_RETENTION` | 900 秒 | 9i (2001) | 10g 起 autotune |
| Oracle | `UNDO_TABLESPACE` | UNDOTBS1 | 9i | -- |
| Oracle | `RETENTION GUARANTEE` | OFF | 10g | -- |
| PostgreSQL | `vacuum_freeze_min_age` | 50,000,000 XID | 8.2 (2006) | -- |
| PostgreSQL | `autovacuum_freeze_max_age` | 200,000,000 XID | 8.3 (2008) | -- |
| PostgreSQL | `idle_in_transaction_session_timeout` | 0 (禁用) | 9.6 (2016) | -- |
| PostgreSQL | `old_snapshot_threshold` | -1 (禁用) | 9.6 (2016) | PG 17 移除 (2024) |
| PostgreSQL | `vacuum_cost_delay` | 2ms | 8.0 | -- |
| PostgreSQL | `hot_standby_feedback` | off | 9.1 | -- |
| MySQL InnoDB | `innodb_undo_log_truncate` | ON | 5.7 (2015) | 自动 |
| MySQL InnoDB | `innodb_purge_threads` | 4 | 5.7 | -- |
| MySQL InnoDB | `innodb_max_undo_log_size` | 1 GB | 5.7 | -- |
| MariaDB | 同 MySQL InnoDB | 同上 | 同上 | -- |
| SQL Server | `MAX_VERSION_STORE_SIZE_MB` | 间接,看 tempdb | 间接 | 自动扩展 |
| SQL Server | `ALLOW_SNAPSHOT_ISOLATION` | OFF | 2005 (2005) | -- |
| SQL Server | `READ_COMMITTED_SNAPSHOT` | OFF | 2005 | -- |
| Snowflake | `DATA_RETENTION_TIME_IN_DAYS` | 1 天 | GA | 0-90 (Enterprise) |
| BigQuery | `time_travel_window` | 7 天 | 2022 | 2-7 天可配 |
| Redshift | `vacuum_truncate_threshold` | 5% | -- | -- |
| CockroachDB | `gc.ttlseconds` | 14400 (4h, 24.1+) | 早期 | -- |
| TiDB | `tidb_gc_life_time` | 10 分钟 | 早期 | -- |
| TiDB | `tidb_gc_run_interval` | 10 分钟 | 早期 | -- |
| TiDB | `tidb_gc_enable` | ON | 早期 | -- |
| YugabyteDB | `idle_in_txn_timeout` (经 ysql_pg_conf_csv) | 0 | -- | -- |
| YugabyteDB | `timestamp_history_retention_interval_sec` | 900 秒 | -- | -- |
| OceanBase | `undo_retention` | 1800 秒 | 2.x | -- |
| OceanBase | `minor_freeze_times` | 5 | -- | -- |
| Greenplum | `vacuum_freeze_min_age` | 继承 PG | 继承 | -- |
| Vertica | `HistoryRetentionTime` | 0 (立即) | -- | -- |
| Spanner | 版本保留 (per-database) | 1 小时 | -- | 1h-7d |
| Delta Lake | `delta.deletedFileRetentionDuration` | 7 天 | -- | 与 VACUUM 配合 |
| Delta Lake | `delta.logRetentionDuration` | 30 天 | -- | -- |
| Iceberg | `history.expire.max-snapshot-age-ms` | 5 天 | -- | -- |
| ClickHouse | -- | 不适用 | -- | 无 MVCC |
| DuckDB | -- | 不适用 | -- | 单进程,无 GC TTL |
| SAP HANA | `history.cleanup_interval` | -- | -- | -- |
| Teradata | -- | 单版本,无快照 | -- | -- |
| StarRocks | `tablet_meta_checkpoint_min_interval_secs` | 600 | -- | -- |
| Doris | `streaming_load_max_mb` | -- | -- | -- |
| Materialize | `compaction_window` | 内部管理 | -- | -- |
| RisingWave | `state_table_compaction` | 内部管理 | -- | -- |
| InfluxDB | retention policy | 用户定义 | -- | -- |
| Firebolt | -- | 自动 | -- | -- |
| Databend | `data_retention_time_in_days` | 1 天 | -- | -- |
| TimescaleDB | 继承 PG + retention policy | 7 天默认 | -- | -- |
| QuestDB | -- | 列存追加,无 MVCC GC | -- | -- |
| SQLite | -- | 无 MVCC | -- | -- |
| H2 | -- | 无 MVCC | -- | -- |
| HSQLDB | -- | 无 MVCC | -- | -- |
| Derby | -- | 无 MVCC | -- | -- |
| Firebird | `MaxOATAdjustment` | 内部 | -- | -- |
| Informix | `LTAPEDEV` 等 logical-log 参数 | -- | -- | -- |
| MonetDB | -- | 单版本 | -- | -- |
| Exasol | -- | -- | -- | -- |
| CrateDB | `index.translog.retention.size` | -- | -- | -- |
| Yellowbrick | 自动 | -- | -- | -- |
| SingleStore | `versioned_lock_timeout` | -- | -- | -- |

> 统计:约 30 个引擎暴露某种快照/undo 保留配置;约 15 个引擎完全自动管理或不适用(单版本/无 MVCC/不可变追加)。

### 长事务 / 空闲事务超时

| 引擎 | 参数名 | 默认值 | 引入版本 | 单位 |
|------|--------|-------|---------|------|
| PostgreSQL | `idle_in_transaction_session_timeout` | 0 (禁用) | 9.6 (2016) | ms |
| PostgreSQL | `statement_timeout` | 0 (禁用) | -- | ms |
| PostgreSQL | `transaction_timeout` | 0 (禁用) | 17 (2024) | ms |
| PostgreSQL | `idle_session_timeout` | 0 (禁用) | 14 (2021) | ms |
| MySQL | `wait_timeout` | 28800 秒 | -- | 秒 |
| MySQL | `interactive_timeout` | 28800 秒 | -- | 秒 |
| MySQL | `lock_wait_timeout` | 31536000 秒 | -- | 秒 |
| MySQL | `innodb_rollback_on_timeout` | OFF | -- | -- |
| MariaDB | `idle_transaction_timeout` | 0 | 10.3 (2018) | 秒 |
| Oracle | `IDLE_TIME` (resource limit) | UNLIMITED | -- | 分钟 |
| Oracle | `MAX_IDLE_TIME` (init.ora) | 0 | 12c | 分钟 |
| Oracle | `MAX_IDLE_BLOCKER_TIME` | 0 | 19c | 分钟 |
| SQL Server | `LOCK_TIMEOUT` (会话级) | -1 | -- | ms |
| SQL Server | `SET DEADLOCK_PRIORITY` | NORMAL | -- | -- |
| CockroachDB | `idle_in_transaction_session_timeout` | 0 | 21.x | ms |
| CockroachDB | `idle_in_session_timeout` | 0 | -- | ms |
| TiDB | `tidb_idle_transaction_timeout` | 0 | -- | 秒 |
| TiDB | `wait_timeout` | 28800 | -- | 秒 |
| YugabyteDB | `idle_in_transaction_session_timeout` (PG 兼容) | 0 | -- | ms |
| Greenplum | 继承 PG `idle_in_transaction_session_timeout` | 0 | 6.0+ | ms |
| Snowflake | `STATEMENT_TIMEOUT_IN_SECONDS` | 172800 (48h) | -- | 秒 |
| Snowflake | `IDLE_SESSION_TIMEOUT_IN_MINUTES` | 30 | -- | 分钟 |
| BigQuery | 查询级超时 | 6 小时 | -- | -- |
| Redshift | `statement_timeout` | 0 (无) | -- | ms |
| Redshift | `idle_session_timeout` | 0 | -- | -- |
| DB2 | `IDLE_TIMEOUT` (workload mgmt) | -- | -- | -- |
| SAP HANA | `idle_connection_timeout` | 0 | -- | -- |
| Vertica | `statement_timeout` | 0 | -- | ms |

### 集群 / 数据库级 vs 表级粒度

| 引擎 | 集群级 | 数据库级 | 表级 / 对象级 |
|------|-------|---------|--------------|
| Oracle | UNDO_RETENTION (实例) | -- | RETENTION GUARANTEE 表空间 |
| PostgreSQL | postgresql.conf 全局 | ALTER DATABASE SET | ALTER TABLE 仅部分 (autovacuum_*) |
| MySQL InnoDB | innodb 全局 | -- | -- |
| SQL Server | tempdb 大小 | DATABASE 级隔离开关 | -- |
| CockroachDB | cluster setting | -- | ZONE CONFIG 表/索引/分区 |
| TiDB | 全局 system var | -- | placement rule 部分 |
| Snowflake | account 级 | DATABASE 级 | TABLE 级 (DATA_RETENTION_TIME_IN_DAYS) |
| BigQuery | -- | DATASET 级 (max_time_travel_hours) | -- |
| YugabyteDB | gflag 集群 | -- | -- |
| Spanner | -- | DATABASE 级 (version_retention_period) | -- |
| Delta Lake | spark conf | -- | TBLPROPERTIES 表级 |
| Iceberg | catalog | -- | TBLPROPERTIES 表级 |
| Vertica | 全局 + 节点 | -- | -- |
| Greenplum | 全局 + database | -- | autovacuum_* 表级部分 |

> 关键观察:Snowflake、Delta Lake、Iceberg 这类不可变存储引擎,把 Time Travel 窗口配置放在表级,粒度最细;Oracle、PostgreSQL、CockroachDB 默认是集群/实例级的全局配置,只有部分参数可在更细粒度覆盖。

## 各引擎深度详解

### Oracle:UNDO_RETENTION + UNDO_TABLESPACE 双参数模型

Oracle 9i (2001) 引入了 Automatic Undo Management (AUM),将以前需要 DBA 手工管理的 ROLLBACK 段统一收编到一个独立的 UNDO 表空间。从此 Oracle 的快照保留配置稳定为两个核心参数:

```sql
-- 查看当前配置
SHOW PARAMETER UNDO_RETENTION;
SHOW PARAMETER UNDO_TABLESPACE;
SHOW PARAMETER UNDO_MANAGEMENT;

-- 默认值:
-- UNDO_RETENTION = 900 (秒,即 15 分钟)
-- UNDO_TABLESPACE = UNDOTBS1
-- UNDO_MANAGEMENT = AUTO (10g 起强制)

-- 修改配置 (动态生效)
ALTER SYSTEM SET UNDO_RETENTION = 3600 SCOPE=BOTH;  -- 1 小时
ALTER SYSTEM SET UNDO_TABLESPACE = UNDOTBS2 SCOPE=BOTH;
```

**autotune 机制(10g 起)**:Oracle 不只看 `UNDO_RETENTION`,还会观察实际的查询/事务长度,自动延长保留时间。规则是:

1. 如果 UNDO 表空间是 AUTOEXTEND ON,优先扩展表空间,尽量保留更长的 undo
2. 如果是 AUTOEXTEND OFF (固定大小),Oracle 计算最大可保留时间 (MaxRetention = 表空间大小 / undo 生成速率),并以此为上限
3. `UNDO_RETENTION` 是**目标**而非硬性下限——只有 `RETENTION GUARANTEE` 才是硬性下限

```sql
-- 强制硬性保留(可能导致 DML 失败)
ALTER TABLESPACE UNDOTBS1 RETENTION GUARANTEE;
-- 后果:UNDO 满后,新 DML 会报 ORA-30036
ALTER TABLESPACE UNDOTBS1 RETENTION NOGUARANTEE;
```

**查看实际 autotune 后的保留期**:

```sql
-- V$UNDOSTAT 视图: 每 10 分钟一个采样点
SELECT BEGIN_TIME, END_TIME,
       UNDOTSN, UNDOBLKS,
       TXNCOUNT, MAXQUERYLEN,
       MAXQUERYID, TUNED_UNDORETENTION
FROM   V$UNDOSTAT
ORDER BY BEGIN_TIME DESC;

-- TUNED_UNDORETENTION 列就是 Oracle 当前使用的实际保留秒数
-- 与 UNDO_RETENTION 参数可能不同(autotune 后)
```

**与 Flashback Query 的交互**:

```sql
-- Flashback Query 依赖 UNDO 段
SELECT * FROM employees AS OF TIMESTAMP (SYSTIMESTAMP - INTERVAL '1' HOUR)
WHERE department_id = 10;

-- 如果 UNDO_RETENTION = 900 (15 分钟),上面查询会报 ORA-01555
-- 解决方案: 设置 UNDO_RETENTION >= 3600 + 设置 RETENTION GUARANTEE

-- Flashback Database / Flashback Table 依赖 Flashback Logs(独立于 UNDO)
-- 配置:
ALTER DATABASE FLASHBACK ON;
ALTER SYSTEM SET DB_FLASHBACK_RETENTION_TARGET = 1440;  -- 24 小时(分钟单位)
```

### Oracle ORA-01555:经典快照过期错误

`ORA-01555: snapshot too old: rollback segment number X with name "..." too small` 是 Oracle 工程师都遇到过的经典错误。它的两种触发场景:

**场景 1:经典 ORA-01555(UNDO 段被覆盖)**

```
时刻 T0: 长查询 Q 开始,SCN = 1000
时刻 T1: Q 读到第 N 行,该行的版本是 SCN 1500(在 Q 开始后被 UPDATE)
         Q 需要在 UNDO 中查找 SCN <= 1000 的旧版本
时刻 T2: 但旧的 UNDO 段已被新事务覆盖(因为 UNDO_RETENTION=900s 已过)
        → ORA-01555
```

**场景 2:延迟块清理(Delayed Block Cleanout)**

```
时刻 T0: 大事务 T1 提交(commit SCN = 100)
时刻 T1: 由于性能优化,T1 修改的某些数据块上的事务标记没有立即清理
时刻 T2: 长查询 Q (start SCN = 50) 读到这些块
        发现块上的 ITL(Interested Transaction List)还指向 T1 的 undo 槽
        Q 需要根据 undo 判断 T1 的提交时间
        但 T1 的 undo 已被覆盖 → ORA-01555
```

**诊断与修复**:

```sql
-- 步骤 1: 查看 V$UNDOSTAT 找出错误时段
SELECT BEGIN_TIME, MAXQUERYLEN, TUNED_UNDORETENTION
FROM V$UNDOSTAT
WHERE BEGIN_TIME BETWEEN TIMESTAMP '...' AND TIMESTAMP '...';

-- 步骤 2: 找出最长查询
SELECT MAX(MAXQUERYLEN) FROM V$UNDOSTAT;
-- 假设 MAX = 1800 秒

-- 步骤 3: 设置 UNDO_RETENTION >= 最长查询(留 buffer)
ALTER SYSTEM SET UNDO_RETENTION = 3600 SCOPE=BOTH;

-- 步骤 4: 确保 UNDO 表空间足够大
SELECT TABLESPACE_NAME, BYTES/1024/1024 MB
FROM DBA_DATA_FILES WHERE TABLESPACE_NAME LIKE 'UNDO%';

-- 步骤 5: (可选) RETENTION GUARANTEE
ALTER TABLESPACE UNDOTBS1 RETENTION GUARANTEE;

-- 步骤 6: 修复延迟块清理问题: 大事务后立即扫描全表
SELECT /*+ FULL(tab) */ COUNT(*) FROM big_updated_table tab;
```

**RETENTION GUARANTEE 的代价**:启用后,如果 UNDO 表空间不够大,新事务会报 `ORA-30036: unable to extend segment by N in undo tablespace`。也就是把 ORA-01555(读侧)换成了 ORA-30036(写侧)。

### PostgreSQL:多参数协作的 vacuum/freeze 系统

PostgreSQL 的快照保留模型与 Oracle 完全不同。PG 没有独立的 UNDO 段,旧版本就保存在数据文件本身(行内 `xmin`/`xmax` 字段)。"快照保留"是通过控制 VACUUM/autovacuum 的清理时机来实现的:

```ini
# postgresql.conf 关键参数
# === 冻结相关 ===
vacuum_freeze_min_age = 50000000           # 5000万 XID,默认
vacuum_freeze_table_age = 150000000        # 1.5亿 XID
autovacuum_freeze_max_age = 200000000      # 2亿 XID,触发 anti-wraparound

# === MultiXact 冻结(行锁场景) ===
vacuum_multixact_freeze_min_age = 5000000
vacuum_multixact_freeze_table_age = 150000000
autovacuum_multixact_freeze_max_age = 400000000

# === 长事务保护 ===
idle_in_transaction_session_timeout = 0    # 0 = 禁用 (默认)
transaction_timeout = 0                     # PG 17+
statement_timeout = 0                       # 0 = 禁用 (默认)

# === 副本/standby 反馈 ===
hot_standby_feedback = off                  # off = 主库不为副本延后 GC
max_standby_streaming_delay = 30s

# === 已弃用 (PG 17 移除) ===
old_snapshot_threshold = -1                 # PG 9.6 ~ 16,PG 17 删除
```

**`vacuum_freeze_min_age` (50M)**:VACUUM 处理某个页时,会冻结所有 `xmin` 早于 `OldestXmin - vacuum_freeze_min_age` 的元组。"冻结"等于把行的事务 ID 替换成特殊标记 `FrozenTransactionId`,意味着这一行对所有未来事务都可见,不再依赖 XID 比较。

**`autovacuum_freeze_max_age` (200M)**:这是硬性触发线。当某张表的 XID 落后超过 2 亿时,autovacuum 会强制对它进行 `VACUUM FREEZE`,即使该表没有死元组。这是 PG 防止 XID wraparound 的最后防线。

**`idle_in_transaction_session_timeout`(2016 引入)**:这是 PG 9.6 引入的关键参数,用于杀掉空闲在事务中的连接。如果一个连接 `BEGIN` 后什么都不做,它会一直持有 `OldestXmin`,阻塞所有 VACUUM 工作。这是 PG 工程师最常踩的坑:

```sql
-- 错误用法:连接保持事务 + 长时间空闲
BEGIN;
SELECT * FROM big_table;
-- ... 应用代码长时间不返回连接到池 ...
-- (此时所有 VACUUM 都被阻塞,bloat 持续累积)

-- 正确做法 1: 关闭事务
COMMIT;  -- 或 ROLLBACK

-- 正确做法 2: 配置超时
ALTER SYSTEM SET idle_in_transaction_session_timeout = '5min';
SELECT pg_reload_conf();
```

**`old_snapshot_threshold`(PG 9.6 引入,PG 17 移除)**:这是 PG 9.6 试图解决的"长事务阻塞 VACUUM"问题——允许 VACUUM 清理"理论上还可见但实际上被快照标记为太旧"的行。但 PG 团队在 PG 17 (2024) 决定**移除**这个参数,因为它的实现复杂且经常导致难以调试的"snapshot too old"错误。PG 17+ 的等价做法是用 `idle_in_transaction_session_timeout` 和应用层 timeout 直接杀掉超长事务。

```sql
-- 检查 PG 版本
SELECT current_setting('server_version_num')::int >= 170000 AS pg17_or_newer;

-- PG 16 及以下: 可以使用 old_snapshot_threshold
-- (注意: 启用后 SELECT 可能报 'snapshot too old' 错误)
ALTER SYSTEM SET old_snapshot_threshold = '60min';

-- PG 17+: 该参数已被移除,设置会报错
-- 改用以下方案:
ALTER SYSTEM SET idle_in_transaction_session_timeout = '10min';
ALTER SYSTEM SET transaction_timeout = '60min';  -- PG 17 新增
```

### PostgreSQL 长事务对 bloat 的灾难性影响

理解 PG 的 GC 模型,关键是知道一个事实:**最老的活跃事务决定了所有表的可清理边界**。具体地说,VACUUM 只能清理 `xmax < OldestXmin` 的死元组,而 `OldestXmin` 是所有活跃事务的最小 snapshot。

```sql
-- 查看当前最老活跃事务
SELECT now() - xact_start AS duration,
       state, query
FROM pg_stat_activity
WHERE state IN ('active', 'idle in transaction', 'idle in transaction (aborted)')
ORDER BY xact_start ASC NULLS LAST
LIMIT 5;

-- 查看 VACUUM 的可清理边界
SELECT datname,
       age(datfrozenxid) AS xid_age,
       2147483647 - age(datfrozenxid) AS xid_remaining
FROM pg_database
ORDER BY xid_age DESC;
```

**经典灾难场景**:

```
时刻 T0: 应用 A 开了一个事务,select 大表
时刻 T1: 应用 A 卡死(网络问题、锁等待、idle in tx 没设超时)
时刻 T2: 业务 B 持续高频 UPDATE 同一张表 (10万行/秒)
时刻 T3: 1 小时后,应用 A 还卡着,
        autovacuum 运行,但 OldestXmin 卡在 A 的 snapshot
        VACUUM 看到 3.6 亿死元组,但一行都不能删!
时刻 T4: 表大小从 1GB 增长到 50GB
时刻 T5: 全表扫描慢 50 倍,优化器 stats 失准,业务雪崩
```

**修复方案的优先级**:

1. 先杀掉长事务(确保问题根源解决):
```sql
SELECT pg_terminate_backend(pid)
FROM pg_stat_activity
WHERE state = 'idle in transaction'
  AND xact_start < now() - INTERVAL '1 hour';
```

2. 然后让 autovacuum 工作或手动 VACUUM:
```sql
VACUUM (VERBOSE, ANALYZE) bloated_table;
-- 注意: 普通 VACUUM 只回收空间标记可重用,不缩文件
-- 如需缩文件,需 VACUUM FULL(全表锁)或 pg_repack 在线重建
```

3. 长期防护:
```sql
ALTER SYSTEM SET idle_in_transaction_session_timeout = '5min';
ALTER SYSTEM SET log_min_duration_statement = '5min';
ALTER SYSTEM SET log_lock_waits = on;
SELECT pg_reload_conf();
```

### MySQL InnoDB:undo log 与 purge 系统

InnoDB 的 MVCC 实现介于 Oracle 和 PostgreSQL 之间——它把旧行版本放在 undo log(类似 Oracle 的 UNDO 段),但 undo log 又存储在系统表空间(或独立 undo tablespace,5.7+)中,而不是行内。配置参数:

```sql
-- 5.7+ 关键参数
SET GLOBAL innodb_undo_log_truncate = ON;          -- 自动截断 undo (默认 ON)
SET GLOBAL innodb_purge_threads = 4;                -- purge 线程数
SET GLOBAL innodb_purge_batch_size = 300;           -- 每次 purge 的 undo 页数
SET GLOBAL innodb_max_undo_log_size = 1073741824;   -- 1GB 阈值,超过触发 truncate
SET GLOBAL innodb_undo_tablespaces = 2;             -- 独立 undo 表空间数

-- 长事务保护
SET GLOBAL innodb_rollback_on_timeout = OFF;        -- 默认
SET GLOBAL lock_wait_timeout = 50;                   -- 锁等待超时
SET GLOBAL wait_timeout = 28800;                     -- 8 小时空闲断开
```

**MySQL 的"长事务 + undo 失控"故事**:

```sql
-- 用户开了一个长事务
BEGIN;
SELECT * FROM big_table WHERE id = 1;
-- 然后忘了提交,空闲 7 小时
-- 期间业务持续 UPDATE 该表

-- 检查 undo 大小
SELECT FILE_NAME,
       INITIAL_SIZE/1024/1024 AS init_mb,
       TOTAL_EXTENTS * EXTENT_SIZE/1024/1024 AS used_mb
FROM INFORMATION_SCHEMA.FILES
WHERE FILE_NAME LIKE '%undo%';

-- 检查长事务
SELECT trx_id, trx_started, trx_query
FROM INFORMATION_SCHEMA.INNODB_TRX
ORDER BY trx_started ASC;

-- 解决: kill 掉长事务
KILL <thread_id>;
```

**MariaDB 10.3+ 的 idle_transaction_timeout**:MariaDB 是少数引入了独立的 idle 事务超时参数的 MySQL 系引擎:

```sql
-- 仅 MariaDB 有
SET GLOBAL idle_transaction_timeout = 600;  -- 10 分钟
-- MySQL 至 8.x 没有等价参数,只能依赖 wait_timeout
```

### SQL Server:tempdb 间接配置

SQL Server 的快照实现机制独特——版本存储(version store)放在 tempdb 中,而不是数据库自身。所以"快照保留期"实际上由 tempdb 大小、`READ_COMMITTED_SNAPSHOT`/`SNAPSHOT_ISOLATION` 设置以及版本清理任务共同决定:

```sql
-- 启用快照隔离(数据库级,2005 引入)
ALTER DATABASE MyDB SET ALLOW_SNAPSHOT_ISOLATION ON;
ALTER DATABASE MyDB SET READ_COMMITTED_SNAPSHOT ON;

-- 查看 version store 大小
SELECT
    DB_NAME(database_id) AS db,
    reserved_space_kb / 1024.0 AS reserved_mb,
    used_space_kb / 1024.0 AS used_mb
FROM sys.dm_tran_version_store_space_usage;

-- 配置 tempdb(实例级别)
-- 通常规则: tempdb 大小 >= 最大期望版本量 + 排序缓冲 + 临时表使用
ALTER DATABASE tempdb MODIFY FILE
    (NAME = tempdev, SIZE = 10240MB, MAXSIZE = UNLIMITED);
```

**MAX_VERSION_STORE_SIZE_MB 实际不存在为独立参数**,SQL Server 通过 tempdb 大小间接限制。当 tempdb 的版本存储部分增长过快时,会触发 `Snapshot isolation transaction aborted due to update conflict`(冲突)或 `Snapshot isolation transaction failed in database 'X' because the object accessed by the statement has been modified by a DDL statement`。

**长查询保护**:

```sql
-- 会话级查询超时
SET LOCK_TIMEOUT 60000;  -- 60 秒

-- 资源调控器(Enterprise)
CREATE RESOURCE POOL ReportPool WITH (MAX_CPU_PERCENT = 30);
CREATE WORKLOAD GROUP ReportGroup
    WITH (MAX_DOP = 4, REQUEST_MAX_CPU_TIME_SEC = 300, REQUEST_MAX_MEMORY_GRANT_PERCENT = 25)
    USING ReportPool;
```

### CockroachDB:gc.ttlseconds 与 Zone Configuration

CockroachDB 是新一代分布式 SQL 中最早把 GC TTL 暴露为可配置参数的引擎之一。其 MVCC GC 模型基于全局时间戳(HLC),配置粒度可以精细到单个表/索引/分区:

```sql
-- 集群级默认 GC TTL
SHOW CLUSTER SETTING kv.gc.ttl.minimum;

-- 24.1 版本起,默认值从 90000 秒(25 小时)改为 14400 秒(4 小时)
-- 使新表的 default TTL 从 25h 缩短到 4h,以减少存储开销

-- 数据库 / 表级配置 (zone configuration)
ALTER DATABASE my_db CONFIGURE ZONE USING gc.ttlseconds = 86400;  -- 24h

ALTER TABLE orders CONFIGURE ZONE USING
    gc.ttlseconds = 7200,                  -- 2h(高频更新表)
    num_replicas = 3;

-- 备份/恢复表需要更长 TTL
ALTER TABLE archive_orders CONFIGURE ZONE USING
    gc.ttlseconds = 604800;                -- 7 天

-- 查看实际生效配置
SHOW ZONE CONFIGURATION FROM TABLE orders;
```

**为什么 24.1 把默认从 25h 改为 4h**:历史上 CRDB 默认 90000 秒(25h)是为了让 backup/restore 总能找到旧版本。但实际生产中 25h 导致的存储膨胀和 GC 滞后比预期严重。24.1 版本团队决定:

- 默认改为 4h(14400 秒),适合高频 OLTP 工作负载
- 备份/AS OF SYSTEM TIME 查询超过 4h 需显式 ALTER ZONE
- protected timestamp 机制可以临时延长某个对象的 GC TTL,不影响全局默认

**与 AS OF SYSTEM TIME 的交互**:

```sql
-- AS OF SYSTEM TIME 查询历史快照,要求 timestamp 仍在 GC TTL 内
SELECT * FROM orders AS OF SYSTEM TIME '-5m';

-- 如果 timestamp 早于 (now - gc.ttlseconds), 报错
SELECT * FROM orders AS OF SYSTEM TIME '-2d';  -- 默认 4h TTL → 报错
-- ERROR: relation "orders" does not exist (历史数据已 GC)

-- 解决方案 1: 调大 zone config
ALTER TABLE orders CONFIGURE ZONE USING gc.ttlseconds = 604800;  -- 7d

-- 解决方案 2: 使用 protected timestamp(保留特定时刻的快照)
-- (通过 backup job 或 changefeed job 自动管理)
```

### TiDB:tidb_gc_life_time 与 safe point

TiDB 的 GC 模型基于 Percolator 协议,所有节点共享一个全局 safe point,GC worker 定期推进:

```sql
-- 关键 system variables
SHOW VARIABLES LIKE 'tidb_gc%';

-- 默认值:
-- tidb_gc_enable = ON
-- tidb_gc_run_interval = 10m0s
-- tidb_gc_life_time = 10m0s
-- tidb_gc_concurrency = -1 (auto)
-- tidb_gc_scan_lock_mode = LEGACY

-- 修改 GC TTL
SET GLOBAL tidb_gc_life_time = '24h';

-- 查看当前 safe point
SELECT * FROM mysql.tidb WHERE variable_name = 'tikv_gc_safe_point';
-- 比当前时间晚 10 分钟(默认)的时间戳

-- 临时禁用 GC(用于备份/恢复)
SET GLOBAL tidb_gc_enable = OFF;
-- 结束后重新启用
SET GLOBAL tidb_gc_enable = ON;
```

**TiDB Stale Read 与 GC**:

```sql
-- TiDB 4.0+ Stale Read 读取历史快照(类似 CRDB 的 AS OF SYSTEM TIME)
SET TRANSACTION READ ONLY AS OF TIMESTAMP NOW() - INTERVAL 5 SECOND;
SELECT * FROM orders;
COMMIT;

-- 必须在 tidb_gc_life_time 范围内
-- 默认 10 分钟,即只能读 10 分钟前的数据
```

**长查询超时**:

```sql
-- TiDB 5.4+ 增加了独立的事务超时
SET tidb_idle_transaction_timeout = 600;  -- 10 分钟

-- 也可以用 TiDB 的资源管控限制查询时间
SET tidb_max_execution_time = 60000;  -- 60 秒
```

### YugabyteDB:DocDB compaction + PG 兼容超时

YugabyteDB 的存储引擎是基于 RocksDB 的 DocDB,它的 GC TTL 概念由 RocksDB compaction 触发,而 SQL 层借用 PG 的 idle_in_transaction_session_timeout:

```bash
# YB-TServer gflags
--timestamp_history_retention_interval_sec=900   # 默认 15 分钟
--retention_delete_with_delete_tombstone=true
--ysql_pg_conf_csv='idle_in_transaction_session_timeout=600000'
```

```sql
-- SQL 层:由 ysql_pg_conf_csv 透传到 PG 兼容层
SHOW idle_in_transaction_session_timeout;

-- 查询 timestamp_history_retention_interval_sec 影响 AS OF 查询能力
-- YB 的 AS OF SYSTEM TIME 类似 CRDB
SELECT * FROM orders AS OF SYSTEM TIME (NOW() - INTERVAL '5 minutes')::TIMESTAMPTZ;
```

### Snowflake:DATA_RETENTION_TIME_IN_DAYS 与 Time Travel

Snowflake 的快照保留是 Time Travel 功能的核心配置,粒度精细到单个表:

```sql
-- 账户级默认
ALTER ACCOUNT SET DATA_RETENTION_TIME_IN_DAYS = 7;

-- 数据库级
ALTER DATABASE my_db SET DATA_RETENTION_TIME_IN_DAYS = 30;

-- 表级(Enterprise 0-90 天,Standard 0-1 天)
ALTER TABLE orders SET DATA_RETENTION_TIME_IN_DAYS = 90;

-- Time Travel 查询
SELECT * FROM orders AT (OFFSET => -3600);            -- 1 小时前
SELECT * FROM orders AT (TIMESTAMP => '2024-01-01 12:00:00'::TIMESTAMP);
SELECT * FROM orders BEFORE (STATEMENT => '8e5d0ca9-...');

-- Fail-safe:Time Travel 之后,Snowflake 内部还有 7 天 fail-safe(不可查询)
-- 完全删除需 Time Travel + Fail-safe 都过期
```

**版本与定价模型**:Snowflake 的存储计费包含 Time Travel 范围的所有版本。`DATA_RETENTION_TIME_IN_DAYS = 90` 意味着所有删除/更新的行版本会保留 90 天,这会显著增加存储成本(典型估计 1.5-3x 原始大小)。

### BigQuery:time_travel_window (2022 引入)

BigQuery 在 2022 年正式发布 Time Travel 功能,允许查询过去 7 天内的快照。配置粒度是 dataset 级:

```sql
-- 创建 dataset 时配置
CREATE SCHEMA my_dataset
OPTIONS (
    location = 'US',
    max_time_travel_hours = 168    -- 7 天(默认),可设 48-168
);

-- 修改现有 dataset
ALTER SCHEMA my_dataset SET OPTIONS (max_time_travel_hours = 48);

-- Time Travel 查询
SELECT * FROM my_dataset.orders
FOR SYSTEM_TIME AS OF TIMESTAMP_SUB(CURRENT_TIMESTAMP(), INTERVAL 1 HOUR);

-- BigQuery 的 fail-safe 是固定 7 天(不可配)
-- 总数据保留 = max_time_travel_hours + 7 days fail-safe
```

**与计费的关系**:BigQuery 的 logical/physical 存储计费会包括 time travel 窗口内的版本。2023 年起 BigQuery 推出了 physical bytes billing 模型,使 time travel 存储成本透明化。

### ClickHouse:无 MVCC,但有 retention policy

ClickHouse 不是传统 MVCC 引擎(每个 INSERT 写到独立的 part,不修改已有数据),所以没有 UNDO_RETENTION 这种概念。但它有数据保留策略:

```sql
-- 表级 TTL
CREATE TABLE events (
    event_time DateTime,
    user_id UInt64,
    data String
) ENGINE = MergeTree()
ORDER BY (event_time, user_id)
TTL event_time + INTERVAL 90 DAY;

-- 修改 TTL
ALTER TABLE events MODIFY TTL event_time + INTERVAL 30 DAY;

-- 部分(part)级 TTL
ALTER TABLE events MODIFY SETTING merge_with_ttl_timeout = 86400;
```

ClickHouse 的"快照"概念类似 Iceberg/Delta:每次合并(merge)会创建新 parts,旧 parts 被标记为 outdated 但不立即删除,默认 8 分钟后清理(`old_parts_lifetime`)。

### DuckDB:单进程,无 GC TTL

DuckDB 是单进程嵌入式引擎,事务模型基于乐观并发控制 + 单写者。它通过版本链管理多版本,但版本链在事务结束时立即清理,不需要类似 PG 的 OldestXmin 跟踪。所以 DuckDB 没有 UNDO_RETENTION / vacuum_freeze_min_age 这类参数。

```sql
-- DuckDB 没有相关参数,但有显式 CHECKPOINT
CHECKPOINT;     -- 写盘 + 紧凑

-- 最长查询时间
SET statement_timeout = '60s';
```

### Delta Lake / Iceberg / Hudi:不可变文件 + retention policy

Delta Lake、Iceberg、Apache Hudi 都基于不可变文件(Parquet/ORC)+ metadata 文件的事务模型。它们的"快照"由 metadata 中的 snapshot 列表定义,旧 snapshot 通过文件的 retention policy 管理:

```sql
-- Delta Lake 表属性
ALTER TABLE my_table SET TBLPROPERTIES (
    'delta.deletedFileRetentionDuration' = 'interval 30 days',
    'delta.logRetentionDuration' = 'interval 30 days'
);

-- VACUUM 清理过期文件
VACUUM my_table RETAIN 168 HOURS;  -- 保留 7 天(默认)

-- Iceberg:expire_snapshots procedure
CALL spark_catalog.system.expire_snapshots(
    table => 'db.events',
    older_than => TIMESTAMP '2024-01-01 00:00:00',
    retain_last => 5
);
```

### Spanner:version_retention_period

Google Spanner 的 MVCC 实现基于 TrueTime,版本保留期是数据库级配置:

```sql
-- 创建/修改数据库时
ALTER DATABASE my_db SET OPTIONS (version_retention_period = '7d');

-- Stale Read
SELECT * FROM orders @{LOCK_HINT='SHARED_READ_TIMESTAMP'}
TIMESTAMP '2024-01-01T00:00:00Z';
```

默认 1 小时,可设范围 1h-7d。设得越长,Spanner 内部的 GC 滞后,存储膨胀。

## Oracle UNDO_RETENTION 与 Flashback Query 协同设计

Flashback Query 是 Oracle 9i 与 UNDO 一起引入的杀手特性。它依赖 UNDO 段中的旧版本来"回放"数据库的过去状态:

```sql
-- 1. Flashback Query (历史 SELECT)
SELECT * FROM employees
AS OF TIMESTAMP (SYSTIMESTAMP - INTERVAL '30' MINUTE);

SELECT * FROM employees
AS OF SCN 1234567;

-- 2. Flashback Versions Query (查看版本历史)
SELECT VERSIONS_STARTSCN, VERSIONS_ENDSCN, VERSIONS_OPERATION,
       employee_id, salary
FROM employees
VERSIONS BETWEEN SCN MINVALUE AND MAXVALUE
WHERE employee_id = 100;

-- 3. Flashback Table (回滚整张表)
FLASHBACK TABLE employees TO TIMESTAMP (SYSTIMESTAMP - INTERVAL '1' HOUR);

-- 4. Flashback Drop (回滚 DROP TABLE,从回收站)
DROP TABLE employees;
FLASHBACK TABLE employees TO BEFORE DROP;
-- (依赖 RECYCLEBIN,与 UNDO 无关)
```

**关键约束**:Flashback Query 只在 UNDO_RETENTION 范围内有效。如果你需要查询 1 小时前的数据,必须保证:

1. `UNDO_RETENTION >= 3600`
2. UNDO 表空间足够大(typically: 写吞吐 × UNDO_RETENTION × 1.5)
3. 推荐 `RETENTION GUARANTEE`(代价是新事务可能被阻塞)

**Flashback Database vs Flashback Query**:Flashback Database 不依赖 UNDO,而是用独立的 Flashback Logs(Flash Recovery Area):

```sql
ALTER DATABASE FLASHBACK ON;
ALTER SYSTEM SET DB_FLASHBACK_RETENTION_TARGET = 1440;  -- 24h(分钟)
ALTER SYSTEM SET DB_RECOVERY_FILE_DEST_SIZE = 100G;

-- 整库回滚到指定 SCN
SHUTDOWN IMMEDIATE;
STARTUP MOUNT;
FLASHBACK DATABASE TO TIMESTAMP (SYSDATE - 1);
ALTER DATABASE OPEN RESETLOGS;
```

## ORA-01555 深度剖析

ORA-01555 是 Oracle 工程师必读的经典错误。它的全称 `ORA-01555: snapshot too old` 暗示了根本原因——读一致性需要的旧版本已经不存在。

### 触发条件链

```
1. 长查询 Q 在 SCN = N 开始
2. 在 Q 执行期间,某个事务 T 修改了 Q 要读的某行
3. T 提交后,旧版本被写到 UNDO 段
4. UNDO_RETENTION 时间过去,UNDO 段被新事务覆盖
5. Q 继续读到该行,需要回到 SCN = N 的版本
6. UNDO 中找不到 → ORA-01555
```

### 五种典型场景

**场景 A:经典长查询失败**

```sql
-- 长查询(报表、ETL)
SELECT ... FROM big_table JOIN huge_table ON ...
-- 运行 30 分钟后报 ORA-01555
-- 原因:30 分钟 > UNDO_RETENTION (默认 15 分钟)
```

**场景 B:Cursor + Fetch 间隙**

```sql
-- 应用代码模式:
DECLARE
    CURSOR c IS SELECT id FROM big_table;
    v_id big_table.id%TYPE;
BEGIN
    OPEN c;
    LOOP
        FETCH c INTO v_id;
        EXIT WHEN c%NOTFOUND;
        -- 在每个 fetch 后做耗时操作 (调用外部服务、慢 UPDATE)
        UPDATE detail SET status = 'X' WHERE master_id = v_id;
        COMMIT;  -- 每行 commit
    END LOOP;
    CLOSE c;
END;
-- 风险:cursor c 持续的总时间可能超 UNDO_RETENTION
```

**场景 C:Read-only / Serializable 事务**

```sql
SET TRANSACTION READ ONLY;
-- 或 SET TRANSACTION ISOLATION LEVEL SERIALIZABLE;
SELECT ... FROM ... ;
-- 30 分钟后
SELECT ... FROM ... ;  -- 可能 ORA-01555
COMMIT;
```

**场景 D:Delayed Block Cleanout**

```sql
-- 大事务
UPDATE big_table SET ... WHERE ...;  -- 1 亿行
COMMIT;
-- 此时块上的 ITL 还指向 UNDO 槽,标记 commit SCN 为 NULL

-- 下一个长查询
SELECT ... FROM big_table;
-- 读到含 ITL 的块,需要查 UNDO 确认 commit SCN
-- 如果 UNDO 已被覆盖 → ORA-01555
```

**场景 E:Self-managed UNDO 过小**

```sql
-- 旧版本 Oracle (9i 前) 或手动 ROLLBACK 段管理
-- ROLLBACK 段配置过小,频繁切换覆盖
-- 现代 AUM 已基本不再发生
```

### 修复策略

```sql
-- 1. 立即:加大 UNDO_RETENTION
ALTER SYSTEM SET UNDO_RETENTION = 7200 SCOPE=BOTH;  -- 2 小时

-- 2. 短期:扩大 UNDO 表空间
ALTER DATABASE DATAFILE '/u01/oradata/undotbs01.dbf' RESIZE 50G;
ALTER TABLESPACE UNDOTBS1 ADD DATAFILE '/u02/undotbs02.dbf' SIZE 50G AUTOEXTEND ON;

-- 3. 中期:RETENTION GUARANTEE
ALTER TABLESPACE UNDOTBS1 RETENTION GUARANTEE;

-- 4. 长期:重构应用
-- - 消除超长 cursor + fetch 模式
-- - 大表更新分批 + 合理 commit 频率
-- - 报表查询走只读副本(Active Data Guard)

-- 5. 解决延迟块清理
-- 大事务后立即扫描表
SELECT /*+ FULL(t) */ COUNT(*) FROM big_updated_table t;
```

### V$UNDOSTAT 监控

```sql
-- 历史 UNDO 使用情况
SELECT BEGIN_TIME, END_TIME,
       UNDOTSN, UNDOBLKS,
       TXNCOUNT, MAXCONCURRENCY,
       UNXPSTEALCNT, UNXPBLKRELCNT,
       EXPSTEALCNT, EXPBLKRELCNT,
       SSOLDERRCNT, NOSPACEERRCNT,
       MAXQUERYLEN, MAXQUERYID,
       TUNED_UNDORETENTION
FROM V$UNDOSTAT
ORDER BY BEGIN_TIME DESC;

-- 列含义:
-- UNXPSTEALCNT: 偷取未过期 UNDO 的次数(预警!)
-- UNXPBLKRELCNT: 释放未过期 UNDO 块数
-- SSOLDERRCNT:  ORA-01555 发生次数
-- NOSPACEERRCNT: ORA-30036 发生次数
-- MAXQUERYLEN:  采样窗口内最长查询(秒)
-- TUNED_UNDORETENTION: 实际生效的保留期
```

## 长事务、idle in tx 与 bloat 的因果链

理解为什么 PostgreSQL/CockroachDB/TiDB 都把 idle in tx 超时作为关键参数,需要看完整的因果链:

```
应用代码 BEGIN; SELECT ...; ...
        ↓
应用代码 卡住或忘记 COMMIT
        ↓
连接持有 OldestXmin (PG) / oldest active timestamp (CRDB/TiDB)
        ↓
所有表的 VACUUM / GC 被阻塞,因为不能清理 xmax > OldestXmin 的行
        ↓
高频写入的表持续累积死元组
        ↓
表大小膨胀,索引膨胀
        ↓
查询性能下降 (扫描更多无效行,buffer pool miss 率上升)
        ↓
连锁反应: 慢查询占用更多连接,触发更多 idle in tx
        ↓
最终: bloat 不可控,被迫 VACUUM FULL (全表锁)或 pg_repack
```

### 识别"长事务杀手"模式

应用代码中的常见反模式:

```python
# 反模式 1: 事务内调用外部服务
with conn.transaction() as tx:
    rows = tx.execute("SELECT * FROM users WHERE ...")
    for row in rows:
        result = http.post("https://external-api.com/...", data=row)  # 慢
        tx.execute("UPDATE users SET ... WHERE id = %s", (row.id,))
# 问题: 事务时长 = N × HTTP 时延

# 反模式 2: ORM 长会话
session = SessionFactory()  # BEGIN 隐式
data = session.query(User).all()  # 触发 SELECT
# ...用户思考时间...
data2 = session.query(Order).all()
session.commit()  # 可能几分钟后

# 反模式 3: 连接池配置错误
pool.connection_max_idle_seconds = 3600  # 1 小时
# 连接保持事务上下文,占用 OldestXmin
```

### 防御性配置建议(PostgreSQL 推荐)

```ini
# postgresql.conf
idle_in_transaction_session_timeout = '5min'
idle_session_timeout = '1h'                  # PG 14+
statement_timeout = '10min'
transaction_timeout = '30min'                 # PG 17+
log_min_duration_statement = '1s'
log_lock_waits = on
deadlock_timeout = '1s'
```

### 防御性配置建议(其他引擎)

```sql
-- MySQL
SET GLOBAL wait_timeout = 1800;
SET GLOBAL interactive_timeout = 1800;

-- MariaDB(独有)
SET GLOBAL idle_transaction_timeout = 300;

-- Oracle(profile 级)
ALTER PROFILE app_profile LIMIT IDLE_TIME 30;  -- 分钟
ALTER USER app IDENTIFIED BY ... PROFILE app_profile;

-- CockroachDB
SET CLUSTER SETTING server.shutdown.query_wait = '60s';
SET idle_in_transaction_session_timeout = '5min';

-- TiDB
SET GLOBAL tidb_idle_transaction_timeout = 600;
SET GLOBAL max_execution_time = 60000;

-- Snowflake
ALTER SESSION SET STATEMENT_TIMEOUT_IN_SECONDS = 600;
ALTER ACCOUNT SET CLIENT_SESSION_KEEP_ALIVE = FALSE;
```

## 时间轴:快照保留参数的演化

```
2001  Oracle 9i 引入 UNDO_TABLESPACE + UNDO_RETENTION + AUM
2003  Oracle 10g UNDO autotune
2005  SQL Server 2005 引入 ALLOW_SNAPSHOT_ISOLATION (tempdb 版本存储)
2006  PostgreSQL 8.2 vacuum_freeze_min_age
2008  PostgreSQL 8.3 autovacuum 默认开启,autovacuum_freeze_max_age
2010  Oracle 11g R2 Total Recall (Flashback Data Archive)
2013  CockroachDB 项目启动(2014 KV 层 GC TTL 设计)
2015  MySQL 5.7 innodb_undo_log_truncate, 独立 undo 表空间
2016  PostgreSQL 9.6 idle_in_transaction_session_timeout, old_snapshot_threshold
2018  MariaDB 10.3 idle_transaction_timeout
2018  Snowflake Time Travel GA, DATA_RETENTION_TIME_IN_DAYS
2018  Apache Iceberg 1.0 (snapshot-based metadata)
2019  Delta Lake 开源,带 retention 配置
2020  TiDB GC 模型基于 Percolator,tidb_gc_life_time 默认 10min
2021  PostgreSQL 14 idle_session_timeout
2022  BigQuery time_travel_window 通用化
2023  PostgreSQL 16 持续优化 freeze 性能
2024  PostgreSQL 17 移除 old_snapshot_threshold, 新增 transaction_timeout
2024  CockroachDB 24.1 默认 gc.ttlseconds 从 90000 改为 14400
2025  PostgreSQL 17 频繁讨论 freeze map 的设计改进
```

## 核心发现

### 1. 默认值差异巨大,反映存储模型选择

| 引擎 | 默认快照保留 |
|------|------------|
| Oracle | 900 秒 (15 分钟) |
| TiDB | 10 分钟 |
| OceanBase | 30 分钟 |
| YugabyteDB | 15 分钟 |
| CockroachDB | 4 小时 (24.1 起,之前 25h) |
| Snowflake | 1 天 |
| BigQuery | 7 天 |
| Iceberg | 5 天 |
| Delta Lake | 7 天 |

**规律**:OLTP 引擎倾向于较短保留(分钟级),减少存储开销;数据湖/分析引擎倾向于较长保留(天级),支持时间回溯查询和审计。

### 2. PostgreSQL 与 Oracle 的根本差异

| 维度 | Oracle | PostgreSQL |
|------|--------|-----------|
| 旧版本存储 | 独立 UNDO 段 | 行内(同一数据文件) |
| 主要参数 | UNDO_RETENTION (秒) | autovacuum 阈值(行/比例) |
| 长事务影响 | UNDO 不够 → ORA-01555 | OldestXmin 卡住 → bloat |
| 防护手段 | RETENTION GUARANTEE | idle_in_tx_timeout |
| 失败方向 | 读侧失败 (ORA-01555) | 写侧 bloat + 性能退化 |

Oracle 的设计更"立即一致":要么读到旧版本要么报错;PostgreSQL 的设计更"惰性":永远不报错但代价是 bloat。

### 3. idle_in_transaction_session_timeout 是关键防护

PG 9.6 (2016) 引入这一参数,标志着工程界承认"长事务是 MVCC 的最大敌人"。其他引擎陆续跟进:

- PostgreSQL 9.6 (2016): idle_in_transaction_session_timeout
- MariaDB 10.3 (2018): idle_transaction_timeout
- CockroachDB 21.x: idle_in_transaction_session_timeout
- TiDB 5.4: tidb_idle_transaction_timeout
- YugabyteDB: 透传 PG 兼容参数
- PostgreSQL 17 (2024): transaction_timeout(整个事务级别,不区分 idle/active)

**MySQL InnoDB 至今没有等价的独立参数**,只能依赖 wait_timeout(影响整个连接)。

### 4. CockroachDB 24.1 默认值大幅缩短

CockroachDB 24.1 把 `gc.ttlseconds` 默认从 90000 (25h) 改为 14400 (4h),这是一次大胆的设计决策:

- 减少 6 倍的存储膨胀风险
- 备份/AS OF SYSTEM TIME 用户必须显式 ALTER ZONE
- 推动 protected timestamp 机制成为主流方案

类似的趋势:CockroachDB 的设计哲学从"宽容默认"转向"安全默认 + 显式覆盖"。

### 5. PostgreSQL 17 移除 old_snapshot_threshold

PG 9.6 (2016) 引入 `old_snapshot_threshold`,允许 VACUUM 清理"理论可见但实际超过阈值"的旧行。PG 17 (2024) 移除此参数,理由:

- 实现复杂,代码维护负担大
- 经常导致难以调试的 "snapshot too old" 错误(Oracle ORA-01555 风格)
- 实际生产场景中很少正确启用

替代方案:`idle_in_transaction_session_timeout` + `transaction_timeout` + 应用层超时。这是"硬阻塞 vs 软清理"两种哲学的较量,最终硬阻塞胜出。

### 6. 不可变文件引擎的 retention 是计费驱动

Snowflake、BigQuery、Delta Lake、Iceberg 都把"快照保留"暴露为表/dataset 级配置,粒度细且与计费深度绑定:

- Snowflake: 存储费用 = 当前数据 + Time Travel + Fail-safe
- BigQuery: physical bytes billing 包括 time travel 范围
- Delta Lake: deleted/log retention 影响 cloud storage 成本
- Iceberg: snapshot retention 影响存储和元数据膨胀

**用户场景驱动配置**:审计/合规要求长保留(7-90 天);流式 OLAP 倾向短保留(几小时);数据科学家需要可重复查询(中等保留)。

### 7. 监控参数比配置参数更重要

仅设置 UNDO_RETENTION = 3600 不够,必须配套监控:

```sql
-- Oracle
SELECT * FROM V$UNDOSTAT;        -- 实际 retention,长查询长度
SELECT * FROM DBA_HIST_UNDOSTAT; -- 历史趋势

-- PostgreSQL
SELECT * FROM pg_stat_database;     -- 全局 XID age
SELECT * FROM pg_stat_user_tables;  -- 死元组比例
SELECT * FROM pg_stat_progress_vacuum; -- VACUUM 进度

-- CockroachDB
SHOW ZONE CONFIGURATION FROM TABLE foo;
SELECT crdb_internal.gc_stats(...);

-- TiDB
SELECT * FROM information_schema.tikv_region_status;
```

每个引擎都有专门的视图揭示 GC 健康度。配置不监控等于没配置。

### 8. 长查询/长事务的"隐形成本"

不只是配置 UNDO_RETENTION,还要思考:

- **存储成本**:更长保留 = 更多旧版本占空间。Snowflake 90 天 retention 可能让存储费翻 3 倍。
- **VACUUM/GC 成本**:更长保留 = GC 范围更大,扫描时间更长,IOPS 占用更多。
- **可见性判断成本**:更多旧版本 = SELECT 跳过更多无效行。极端情况下索引扫描比全表扫描慢。
- **副本同步成本**:streaming replication 的 hot_standby_feedback 让主库为副本延迟 GC,放大了 retention 影响。

### 9. 应用与数据库的边界协议

最佳实践逐步形成共识,涵盖应用层与数据库层的双向责任:

**应用层职责**:

- 不在事务中调用外部服务
- 连接归还到池前必须 COMMIT/ROLLBACK
- ORM 配置中限制会话生命周期
- 监控并杀掉超长查询(应用框架级)

**数据库层职责**:

- 设置合理的 idle_in_tx_timeout / statement_timeout
- 监控 UNDO/version store 大小
- 告警 ORA-01555 / bloat / GC lag
- 提供 zone-level / table-level 配置覆盖能力

**协议化趋势**:Snowflake/BigQuery 把这些"协议"内化为产品自动行为,用户基本不需要关心(代价是计费透明度)。CRDB/TiDB 暴露完整配置,DBA 需主动管理。Oracle 和 PostgreSQL 处于中间——auto-tune + 显式覆盖。

### 10. 没有"正确"答案,只有权衡

最终,快照保留期配置是一个多维权衡:

```
保留越长:
  + 时间旅行查询能力
  + 长事务/长查询安全
  + 备份/审计/调试能力
  - 存储成本上升
  - GC 工作量上升
  - 副本同步延迟容忍度变窄

保留越短:
  + 存储成本下降
  + GC 高效
  - 长查询风险高
  - 时间旅行不可用
  - 大事务(如 ETL)容易失败
```

**经验法则**:把保留时间设为 P95 长查询时长的 2-3 倍。例如 P95 报表查询 20 分钟,UNDO_RETENTION 设 60-90 分钟较安全。OLTP 系统通常 30 分钟到 2 小时;OLAP 4-24 小时;审计 7-90 天。

## 引擎实现建议(给数据库内核工程师)

### 1. 暴露分层配置

```
集群级默认 (cluster setting / system parameter)
  ↓
数据库级 (DATABASE option) — 部分引擎
  ↓
表级 (TBLPROPERTIES / ZONE CONFIG / DATA_RETENTION_TIME_IN_DAYS)
  ↓
分区/索引级 — 最细粒度
```

不要只暴露集群级。Snowflake / CRDB / Iceberg 的细粒度配置极受用户欢迎。

### 2. 自动调整,但不隐藏配置

Oracle 10g 的 UNDO 自动调整模式是一个好的范式:**有显式参数(目标),但实际生效值由系统自动调整**。系统视图(V$UNDOSTAT.TUNED_UNDORETENTION)暴露真实生效值。

避免"完全黑盒"或"完全手动"两个极端。

### 3. 长事务防护必须默认开启

新引擎应该:

- `idle_in_transaction_session_timeout` 默认 5-10 分钟,而非 0
- `statement_timeout` 默认 30 分钟,而非 0
- 提供 `protected timestamp` 机制,允许特定 job 临时延长保留

PG 长期默认 0 是一个"历史包袱"——很多用户从来不主动配置,导致生产事故。

### 4. 监控视图必须易用

```sql
-- 标准化的监控视图建议
SELECT * FROM information_schema.snapshot_age_stats;
-- 列: object_name, current_retention_seconds, oldest_active_snapshot_age,
--     bytes_held_by_versions, last_gc_time, gc_lag_seconds, ...
```

目前没有跨引擎的 information_schema 标准。各引擎自定义视图(V$UNDOSTAT, pg_stat_database, crdb_internal.*),用户需为每个引擎学习不同的查询。

### 5. ORA-01555 风格错误的现代替代

现代引擎应该:

- 优先用阻塞写入(RETENTION GUARANTEE 风格),而非随机失败读
- 提供 `protected timestamp` 让长查询主动声明保护点
- 错误消息包含 actionable 建议(具体参数名 + 当前值 + 建议值)

CockroachDB 的 `protected timestamp` 是一个优秀实践:backup 任务主动声明"保护到 SCN X",GC 跳过这个范围,不需要全局延长 TTL。

### 6. 测试要点

```
压力测试场景:
1. 长查询(30 分钟)+ 高频写入(10万 ops/s)
   验证: 不报 snapshot too old; UNDO 大小可控
2. idle_in_tx 连接 + 高频写入
   验证: 超时正确触发; OldestXmin 解锁; bloat 控制
3. 大事务 commit + 立即长查询
   验证: 延迟块清理不导致错误
4. 时间旅行 + GC 边界
   验证: 在 TTL 内 OK,超过 TTL 优雅失败
5. 副本反馈 + 主库 GC
   验证: hot_standby_feedback 不导致主库 OldestXmin 卡死
```

### 7. 对 CDC / changefeed 的特殊处理

CDC 工具(Debezium、Maxwell、CRDB CHANGEFEED、TiCDC)需要历史快照来 bootstrap。引擎应该:

- 提供机制让 CDC 任务声明 protected timestamp
- 任务结束后自动释放
- 监控视图暴露当前 protected timestamps 列表

PG 的 `pg_replication_slot` 是一个例子(replication slot 持有 OldestXmin)。CRDB 的 CHANGEFEED 自动管理 protected timestamp。

### 8. 与备份/恢复的协同

完整备份/PITR(point-in-time recovery)需要的快照保留可能比常规事务长得多。建议:

- 提供独立的 `backup_retention` 参数,与事务 retention 分离
- 备份任务自动声明 protected timestamp
- 监控视图区分"事务持有的 OldestXmin"与"备份持有的"

## 对应用工程师的建议

### 1. 永远不要在事务中调用外部服务

```python
# 反模式
with db.transaction() as tx:
    user = tx.query("SELECT * FROM users WHERE id = ?", uid)
    response = http.post("https://payment.com/charge", ...)  # 慢!
    tx.execute("UPDATE users SET balance = ? WHERE id = ?", ...)

# 正确
with db.transaction() as tx:
    user = tx.query("SELECT * FROM users WHERE id = ? FOR UPDATE", uid)

response = http.post("https://payment.com/charge", ...)

with db.transaction() as tx:
    tx.execute("UPDATE users SET balance = ? WHERE id = ?", ...)
```

### 2. ORM 会话配置要严

```python
# SQLAlchemy 推荐配置
engine = create_engine(
    "postgresql://...",
    pool_size=20,
    max_overflow=10,
    pool_recycle=300,         # 5 分钟回收连接
    pool_pre_ping=True,
    connect_args={
        "options": "-c idle_in_transaction_session_timeout=300000"
    }
)
```

### 3. 长查询用专用副本

```sql
-- 主库: OLTP 短事务
-- 副本(read replica): 报表 / ETL 长查询
-- 配置 hot_standby_feedback 只在副本端生效,主库不受影响

-- 副本端 PG conf:
hot_standby_feedback = on
max_standby_streaming_delay = -1   # 不限制延迟
```

### 4. 分批处理大数据集

```sql
-- 反模式: 单事务全表更新
UPDATE huge_table SET status = 'X' WHERE created_at < '2020-01-01';
-- 1 亿行,30 分钟,UNDO 爆炸

-- 正确: 分批
DECLARE @batch_size INT = 10000;
WHILE 1 = 1 BEGIN
    UPDATE TOP (@batch_size) huge_table
    SET status = 'X'
    WHERE created_at < '2020-01-01' AND status <> 'X';
    IF @@ROWCOUNT < @batch_size BREAK;
END
```

### 5. 监控并报警

```sql
-- PG: 报警长事务
SELECT pid, now() - xact_start AS dur, state, query
FROM pg_stat_activity
WHERE xact_start < now() - INTERVAL '10 min'
  AND state IN ('active', 'idle in transaction');

-- Oracle: 报警 ORA-01555
SELECT * FROM V$UNDOSTAT WHERE SSOLDERRCNT > 0;

-- CRDB: 报警 GC TTL 接近
SELECT range_id, gc_threshold, now() - gc_threshold AS gc_age
FROM crdb_internal.kv_store_status_with_gc;
```

## 参考资料

- ISO/IEC 9075:2023, Information technology — Database languages — SQL (无 GC/retention 规定)
- Oracle Database Reference: [UNDO_RETENTION](https://docs.oracle.com/en/database/oracle/oracle-database/19/refrn/UNDO_RETENTION.html)
- Oracle Database Administrator's Guide: Managing Undo
- PostgreSQL Documentation: [Routine Vacuuming](https://www.postgresql.org/docs/current/routine-vacuuming.html)
- PostgreSQL Documentation: [Server Configuration: Client Connection Defaults](https://www.postgresql.org/docs/current/runtime-config-client.html)
- PostgreSQL 17 Release Notes: removal of `old_snapshot_threshold`, addition of `transaction_timeout`
- MySQL Reference Manual: [InnoDB Purge Configuration](https://dev.mysql.com/doc/refman/8.0/en/innodb-purge-configuration.html)
- MariaDB Knowledge Base: [Server System Variables: idle_transaction_timeout](https://mariadb.com/kb/en/server-system-variables/#idle_transaction_timeout)
- SQL Server Documentation: [Snapshot Isolation in SQL Server](https://learn.microsoft.com/en-us/sql/relational-databases/snapshot-isolation-in-sql-server)
- CockroachDB Documentation: [Configure Replication Zones](https://www.cockroachlabs.com/docs/stable/configure-replication-zones.html), [Garbage Collection](https://www.cockroachlabs.com/docs/stable/architecture/storage-layer.html#garbage-collection)
- CockroachDB 24.1 Release Notes: default `gc.ttlseconds` change
- TiDB Documentation: [GC Overview](https://docs.pingcap.com/tidb/stable/garbage-collection-overview), [System Variables: tidb_gc_life_time](https://docs.pingcap.com/tidb/stable/system-variables#tidb_gc_life_time)
- YugabyteDB Documentation: [Read replica reads](https://docs.yugabyte.com/preview/architecture/transactions/read-committed/)
- Snowflake Documentation: [DATA_RETENTION_TIME_IN_DAYS](https://docs.snowflake.com/en/sql-reference/parameters#data-retention-time-in-days), [Time Travel](https://docs.snowflake.com/en/user-guide/data-time-travel)
- Google BigQuery Documentation: [Time travel](https://cloud.google.com/bigquery/docs/time-travel)
- Google Spanner Documentation: [Versioning](https://cloud.google.com/spanner/docs/data-retention)
- Delta Lake Documentation: [Table Properties](https://docs.delta.io/latest/table-properties.html)
- Apache Iceberg Documentation: [Snapshot Expiration](https://iceberg.apache.org/docs/latest/maintenance/#expire-snapshots)
- Tom Kyte. "Expert Oracle Database Architecture". Apress (经典 ORA-01555 章节)
- Bruce Momjian. "PostgreSQL: Vacuum Strategy". 多次 PGCon presentation
- Andy Pavlo. "Database I/O Patterns under MVCC GC pressure". CMU 15-721 lectures
