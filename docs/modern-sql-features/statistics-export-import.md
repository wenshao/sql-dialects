# 统计信息导出与导入 (Statistics Export and Import)

把生产库的统计信息原封不动拷到开发环境，让开发库瞬间复现生产的执行计划——这件事情看似平凡，却是高级 DBA 与普通 DBA 之间最显著的能力分水岭之一。统计信息的导出与导入能力，决定了你能否在不导入海量数据的情况下"重放"生产慢查询，决定了你能否把一张 TB 级表恢复后**跳过**几小时的 ANALYZE 重新收集，决定了你能否在升级数据库主版本时让查询性能保持稳定。本文系统对比 45+ 数据库引擎在统计信息导出/导入、冻结、锁定、跨版本兼容、`pg_dump --statistics` 等维度的能力差异。

## 为什么需要统计信息导出与导入

绝大多数引擎开发者和 DBA 第一次意识到"统计信息可以导出/导入"，往往是在以下三类场景中：

1. **开发环境复现生产执行计划**：开发库只有 1% 的数据量，跑同一条 SQL 时优化器选择的计划与生产截然不同（开发库走全表扫描，生产走索引）。原因不是数据量本身，而是优化器看到的统计信息差异——开发库的 NDV 估算偏小、直方图边界落在不同区间、MCV 列表完全不同。最优雅的解决办法不是把生产数据拷到开发库（合规、空间、隐私问题），而是**只把统计信息从生产导出再导入开发库**——开发库的优化器看到的"虚拟数据分布"与生产一致，自然产生与生产相同的执行计划。Oracle 的 `DBMS_STATS.EXPORT/IMPORT_TABLE_STATS` 设计初衷就是这一场景。

2. **大表恢复后跳过 ANALYZE**：1 TB 表通过物理备份恢复后，优化器看到的是"该表行数 0、所有列 NDV 0"——执行任何查询都会得到糟糕的计划。重新执行 `ANALYZE TABLE` 在 1 TB 上可能需要几小时。如果备份时**同时备份了统计信息**，恢复后就可以直接导入历史统计，让优化器立即恢复正确的代价估算，无需扫描全表。这是 PostgreSQL 18 (2025) `pg_dump --statistics` 历经多年终于落地的核心驱动力。

3. **跨版本升级稳定性**：从 PostgreSQL 14 升到 17、Oracle 19c 升到 23ai、MySQL 5.7 升到 8.0 时，最大的风险不是 SQL 兼容性问题，而是**统计信息丢失或重新收集后选择性发生变化**——这会让若干查询在升级当夜突然变慢 100 倍。如果升级前导出统计信息、升级后立即导入，能将此类回归概率降到接近零。Oracle 推荐的"在升级前用 `DBMS_STATS.EXPORT_DATABASE_STATS` 导出整个库统计"是这一最佳实践的标准实现。

除此之外，还有几个不那么常见但同样重要的场景：

- **A/B 实验执行计划**：导入两套不同的统计信息，观察优化器对同一 SQL 选择不同计划，用于分析"什么样的统计能让优化器走索引"。
- **支持工程师诊断**：客户报告某个 SQL 慢，导出客户库的统计信息后，支持工程师可以在内部环境用相同统计复现问题。
- **共享内部测试夹具**：QA 维护一组"代表性统计信息"，每次新建测试数据库后立即导入，让回归测试的执行计划稳定。
- **冻结统计避免计划抖动**：对核心 OLTP 表，**锁定**当前统计信息防止自动收集任务把选择性"算坏"，是生产稳定性运维的常规手段。

## 没有 SQL 标准

ISO/IEC 9075（SQL 标准的各个版本）**从未对统计信息收集做任何规定**，更不用说统计信息导出与导入。每家数据库厂商各自发明语法、各自定义存储格式、各自规定跨版本兼容性。

- Oracle 的 `DBMS_STATS.EXPORT_TABLE_STATS / IMPORT_TABLE_STATS / CREATE_STAT_TABLE` 自 8i Release 1 (1999) 起即存在，是这一领域最完整的实现。
- SQL Server 的 `DBCC SHOW_STATISTICS WITH STATS_HEADER` 用于读取，没有内置统一的导出/导入命令，需配合 `sp_create_stats` 或脚本化处理。
- PostgreSQL 在 18 之前不支持统计信息导出，只能从 `pg_statistic` 系统目录手工 COPY；PostgreSQL 18 (2025-09) 终于在 `pg_dump --statistics` 中加入对 planner 统计的完整支持，是这一领域近年最受期待的特性。
- MySQL 至今没有内置的统计信息导出/导入命令，业界依赖 Percona Toolkit 的 `pt-show-grants`、`pt-restore-table-stats` 或手工 `INSERT mysql.innodb_table_stats / mysql.innodb_index_stats`。
- 完全托管的云数仓（Snowflake、BigQuery、Spanner、Firebolt）几乎都不暴露统计信息的导出/导入能力——这是托管产品的设计哲学：用户不应关心统计，由系统全权管理。

因此，这一领域跨引擎的可移植性几乎为零。引擎选型时如果有"跨环境复现执行计划"的硬需求，Oracle 是事实上的金标准，PostgreSQL 18+ 是开源世界的新标杆，其他引擎都需要谨慎评估。

## 支持矩阵（综合）

### 统计信息导出/导入能力（45+ 引擎）

| 引擎 | 导出到表 | 导出到文件 | 导入 | 锁定/冻结 | 跨版本兼容 | 备份工具集成 | 版本/备注 |
|------|---------|----------|------|----------|-----------|-------------|----------|
| Oracle | `EXPORT_TABLE_STATS` | expdp 元数据 | `IMPORT_TABLE_STATS` | `LOCK_TABLE_STATS` | 高（向后） | Data Pump | 8i R1+ (1999) |
| SQL Server | -- | -- (DBCC 手工) | -- (sp_create_stats) | 间接（禁用 auto） | 中 | -- | 2005+ 间接 |
| PostgreSQL | `pg_statistic` (COPY) | `pg_dump --statistics` | restore | -- | 中（NDV 兼容，直方图慎重） | pg_dump 18+ | 18 (2025) 原生 |
| MySQL | -- (INSERT mysql.innodb_*_stats) | -- (mysqldump 否) | -- | `STATS_PERSISTENT` | 低 | Percona pt 工具 | 不支持原生 |
| MariaDB | -- (INSERT mysql.*_stats) | -- | -- | `use_stat_tables` | 低 | -- | 10.0+ 持久统计 |
| SQLite | -- (sqlite_stat1 表) | -- (含在数据库文件) | -- | -- | 高 | -- | 自然包含 |
| DB2 | `db2look -m` | -- | `RUNSTATS USE PROFILE` | `COLLECT_STATS_TYPE` 排除 | 中 | db2look | LUW 9.5+ |
| Snowflake | -- | -- | -- (自动) | -- | -- (托管) | -- | 不暴露 |
| BigQuery | -- | -- | -- (自动) | -- | -- (托管) | -- | 不暴露 |
| Redshift | -- | -- | -- | -- | -- | -- | 不支持 |
| DuckDB | -- | -- | -- | -- | -- | -- | 不支持 |
| ClickHouse | -- | -- | -- | -- | -- | -- | 无传统统计 |
| Trino | `ANALYZE` (元数据) | 连接器相关 | 连接器相关 | -- | 低 | -- | 不支持 |
| Presto | 同 Trino | -- | -- | -- | -- | -- | -- |
| Spark SQL | -- (Hive metastore) | -- | -- | -- | 中 | -- | 不支持原生 |
| Hive | metastore 表 | metastore 导出 | metastore 导入 | -- | 中 | metastore 备份 | 通过 metastore |
| Flink SQL | -- | -- | -- | -- | -- | -- | 不支持 |
| Databricks | Delta 元数据 | Delta clone | Delta clone | -- | 高 | Delta clone | Delta 表内 |
| Teradata | `HELP STATISTICS VALUES` | 文本输出 | `COLLECT STATISTICS USING SAMPLE` | 不支持 | 低 | -- | V2R6+ 间接 |
| Greenplum | 继承 PG | 继承 PG | 继承 PG | -- | 中 | gpbackup | 继承 PG |
| CockroachDB | `CREATE STATISTICS PERSISTED` | -- | -- | -- | 高 | -- | 19.1+ 持久化 |
| TiDB | `SHOW STATS_*` 后导出 SQL | mysqldump 否 | LOAD STATS | `LOCK STATS` | 中 | TiDB 工具 | 4.0+ |
| OceanBase | `DBMS_STATS.EXPORT_*` | 兼容 Oracle | `IMPORT_*` | `LOCK_*` | 高 | -- | 兼容 Oracle |
| YugabyteDB | 继承 PG | 部分继承 18 | 部分 | -- | -- | yb_dump | 继承 PG 计划 |
| SingleStore | -- | -- | -- | -- | -- | -- | 不支持 |
| Vertica | `EXPORT_STATISTICS` | XML 文件 | `IMPORT_STATISTICS` | -- | 高 | 内置 | 6.0+ (2012) |
| Impala | `COMPUTE STATS` (Hive metastore) | 同 Hive | 同 Hive | -- | -- | -- | 通过 metastore |
| StarRocks | -- | -- | -- | -- | -- | -- | 不支持 |
| Doris | -- | -- | -- | -- | -- | -- | 不支持 |
| MonetDB | -- | -- | -- | -- | -- | -- | 不支持 |
| CrateDB | -- | -- | -- | -- | -- | -- | 不支持 |
| TimescaleDB | 继承 PG | 18+ 继承 | 部分 | -- | -- | pg_dump | 继承 PG |
| QuestDB | -- | -- | -- | -- | -- | -- | 不支持 |
| Exasol | -- | -- | -- | -- | -- | -- | 不暴露 |
| SAP HANA | `EXPORT STATISTICS` | XML/CSV | `IMPORT STATISTICS` | -- | 高 | 内置 | 2.0+ |
| Informix | -- | -- (dbschema 部分) | -- | -- | -- | dbschema | 不支持 |
| Firebird | -- | -- | -- | -- | -- | -- | 不支持 |
| H2 | -- | -- | -- | -- | -- | -- | 不支持 |
| HSQLDB | -- | -- | -- | -- | -- | -- | 不支持 |
| Derby | -- | -- | -- | -- | -- | -- | 不支持 |
| Amazon Athena | -- | -- | -- | -- | -- | -- | 不支持 |
| Azure Synapse | -- | -- | -- | -- | -- | -- | 不直接 |
| Google Spanner | -- | -- | -- | -- | -- | -- | 完全托管 |
| Materialize | -- | -- | -- | -- | -- | -- | 流式系统 |
| RisingWave | -- | -- | -- | -- | -- | -- | 流式系统 |
| InfluxDB (SQL) | -- | -- | -- | -- | -- | -- | 时序无传统统计 |
| DatabendDB | -- | -- | -- | -- | -- | -- | 不支持 |
| Yellowbrick | 继承 PG 部分 | 继承 PG 部分 | 部分 | -- | 低 | -- | 有限 |
| Firebolt | -- | -- | -- | -- | -- | -- | 完全托管 |

> 统计：约 8 个引擎提供完整的统计信息导出/导入工作流（Oracle、PostgreSQL 18+、DB2、Vertica、SAP HANA、CockroachDB 持久化、OceanBase、TiDB），其余多数引擎要么完全托管（云数仓）、要么不支持、要么需要 OS 级文件备份/恢复变相实现。

### 统计信息锁定（防止自动收集覆盖）

| 引擎 | 锁定语法 | 粒度 | 解锁 | 默认 | 备注 |
|------|---------|------|------|------|------|
| Oracle | `DBMS_STATS.LOCK_TABLE_STATS` | 表/分区/schema/库 | `UNLOCK_*` | 否 | 8i R1+ |
| Oracle | `DBMS_STATS.LOCK_PARTITION_STATS` | 分区 | -- | -- | 11g+ |
| SQL Server | `STATISTICS_NORECOMPUTE = ON` | 表/索引 | OFF | 否 | 2005+ |
| SQL Server | `AUTO_UPDATE_STATISTICS = OFF` | 数据库级 | -- | -- | 全局禁用 |
| PostgreSQL | -- | -- | -- | -- | 不支持显式锁定 |
| PostgreSQL | `ALTER TABLE ... SET (autovacuum_analyze_threshold)` | 表 | RESET | 间接 | 调阈值变相延迟 |
| MySQL | `STATS_PERSISTENT=1` 后停止 ANALYZE | 表 | -- | -- | 间接 |
| MySQL | `STATS_AUTO_RECALC=0` | 表 | =1 | -- | 5.6.6+ |
| MariaDB | `use_stat_tables=NEVER` | 全局 | -- | -- | 间接 |
| DB2 | `EXCLUDING TABLE FROM PROFILE` | 表 | -- | -- | 通过 profile |
| TiDB | `LOCK STATS t` | 表 | `UNLOCK STATS t` | 否 | 6.5+ |
| CockroachDB | `sql.stats.automatic_collection.enabled=false` | 集群 | =true | -- | 全局 |
| Snowflake | -- | -- | -- | -- | 自动 |
| BigQuery | -- | -- | -- | -- | 自动 |
| OceanBase | `DBMS_STATS.LOCK_TABLE_STATS` | 表/分区 | `UNLOCK_*` | 否 | 兼容 Oracle |
| Vertica | -- | -- | -- | -- | 不支持 |
| SAP HANA | -- | -- | -- | -- | 不支持显式锁定 |
| 其他 | 多数不支持 | -- | -- | -- | 需禁用 auto job |

> 关键观察：**只有 Oracle、TiDB、OceanBase 提供原生的"表级统计锁定"语义**。其他引擎要么禁用整库自动收集（SQL Server `AUTO_UPDATE_STATISTICS = OFF`、CockroachDB 集群参数、MySQL `STATS_AUTO_RECALC=0`），要么完全不支持。这是 Oracle CBO 在生产稳定性维度上的核心优势之一。

### 跨数据库迁移与 dump 工具集成

| 工具 | 引擎 | 是否含统计 | 选项/语法 | 版本 |
|------|------|-----------|---------|------|
| `expdp` (Data Pump) | Oracle | 是 | 元数据中包含统计 | 10g+ |
| `pg_dump` | PostgreSQL | 18+ 是 | `--statistics` (默认开启) | 18 (2025-09) |
| `pg_dump` | PostgreSQL | 17 及以下 | -- | -- (手工导出 pg_statistic) |
| `mysqldump` | MySQL | 否 | -- | 始终不包含 |
| `db2look` | DB2 | 是 | `-m` 生成 RUNSTATS 脚本 | 9.5+ |
| `db2look` | DB2 | 是 | `-mod` 模拟统计（用于优化器测试） | 9.7+ |
| `expdp` Oracle | Oracle | 否 (默认) | `EXCLUDE=STATISTICS` 反义 | -- |
| Vertica `vbr` | Vertica | 是 | 自动包含 | -- |
| Snowflake clone | Snowflake | 是（隐式） | 物理共享 | -- |
| Delta clone | Databricks | 是 | `CLONE` 命令 | Delta 1.0+ |
| BigQuery `bq cp` | BigQuery | 是（隐式） | 自动 | -- |
| `gpbackup` | Greenplum | 是 | `--metadata-only` 含统计 | 7.0+ |
| TiDB `dumpling` | TiDB | 否 | -- | 7.x |
| Percona `pt-show-grants` | MySQL | 间接 | 不含统计 | -- |
| `xtrabackup` | MySQL | 是（物理） | 自动包含 | -- |
| `mongodump` | MongoDB（非 SQL） | 否 | -- | -- |

> `pg_dump --statistics`（PostgreSQL 18 默认开启）是这一领域 2025 年最重大的进展。在此之前，PostgreSQL DBA 想要保留 dump 中的统计，必须手工 `COPY pg_statistic`、用脚本生成 `INSERT` 序列、再在恢复后 `ANALYZE` 重建——一个有 5 万张表的大库恢复后的 ANALYZE 可能需要 24 小时以上。PG 18 让这一痛点彻底消失。

### Freeze 统计与 cardinality feedback

部分引擎提供更细粒度的"统计冻结"或"反馈式统计"机制：

| 引擎 | 冻结语法/能力 | 反馈能力 | 备注 |
|------|-------------|---------|------|
| Oracle | `DBMS_STATS.LOCK_*` + `DBMS_STATS.SET_*` 手工设置 | Cardinality Feedback (12c+) | 反馈基于运行时实际行数 |
| Oracle | `DBMS_STATS.SET_TABLE_STATS` (numrows, numblks) | -- | 直接设置假统计 |
| SQL Server | `UPDATE STATISTICS WITH NORECOMPUTE` | -- | 等同冻结 |
| PostgreSQL | `ALTER TABLE ... ALTER COLUMN ... SET STATISTICS 0` | -- | 列级关闭统计收集 |
| PostgreSQL | -- | -- | 17+ 计划稳定主要靠 plan freezing 扩展 |
| MySQL | -- | -- | 不支持 |
| TiDB | `LOCK STATS` | -- | 6.5+ |
| CockroachDB | -- | -- | 不支持冻结 |
| Vertica | -- | -- | 不支持 |
| SAP HANA | -- | -- | 不支持 |

## 各引擎深度详解

### Oracle DBMS_STATS：统计导出/导入的金标准

Oracle 在 8i Release 1 (1999) 推出 `DBMS_STATS` 包，逐步替代旧的 `ANALYZE TABLE COMPUTE STATISTICS`。`DBMS_STATS` 不仅功能更强，而且自带完整的导出/导入/锁定/还原工作流：

```sql
-- 步骤 1: 创建统计信息存储表
BEGIN
  DBMS_STATS.CREATE_STAT_TABLE(
    ownname => 'SYSTEM',
    stattab => 'STATS_BACKUP_2026Q1',
    tblspace => 'USERS'
  );
END;
/

-- STATS_BACKUP_2026Q1 表的结构由 Oracle 自动定义，包含 STATID, TYPE, VERSION,
-- FLAGS, C1..C5（标识列）, N1..N12（数值统计）, D1..D5（时间）, R1..R2（RAW）,
-- CHARGRP, CL1..CL2（CLOB 用于直方图） 等列。用户不需要关心其内部结构。

-- 步骤 2: 导出当前统计到该表
BEGIN
  DBMS_STATS.EXPORT_TABLE_STATS(
    ownname => 'SH',
    tabname => 'SALES',
    stattab => 'STATS_BACKUP_2026Q1',
    statown => 'SYSTEM',
    statid  => 'PROD_2026_03_01'  -- 业务标识，用于区分多次快照
  );
END;
/

-- 步骤 3: 导入统计到目标库（先用 expdp 把 STATS_BACKUP_2026Q1 拷过去）
BEGIN
  DBMS_STATS.IMPORT_TABLE_STATS(
    ownname => 'SH',
    tabname => 'SALES',
    stattab => 'STATS_BACKUP_2026Q1',
    statown => 'SYSTEM',
    statid  => 'PROD_2026_03_01',
    no_invalidate => FALSE  -- 立即让相关 SQL 重新硬解析
  );
END;
/
```

**整库导出/导入**：

```sql
BEGIN
  DBMS_STATS.EXPORT_DATABASE_STATS(
    stattab => 'STATS_BACKUP_DB',
    statid  => 'PRE_UPGRADE_19C_TO_23AI',
    statown => 'SYSTEM'
  );
END;
/

-- 升级到 23ai 后导回（前提：用 Data Pump 把 stattab 跟着系统一起升级了）
BEGIN
  DBMS_STATS.IMPORT_DATABASE_STATS(
    stattab => 'STATS_BACKUP_DB',
    statid  => 'PRE_UPGRADE_19C_TO_23AI',
    statown => 'SYSTEM'
  );
END;
/
```

**Schema 级别**：

```sql
-- 导出
EXEC DBMS_STATS.EXPORT_SCHEMA_STATS(
  ownname => 'SH',
  stattab => 'STATS_BACKUP',
  statid  => 'BEFORE_REORG'
);

-- 导入
EXEC DBMS_STATS.IMPORT_SCHEMA_STATS(
  ownname => 'SH',
  stattab => 'STATS_BACKUP',
  statid  => 'BEFORE_REORG',
  no_invalidate => FALSE
);
```

**单一索引的统计**：

```sql
EXEC DBMS_STATS.EXPORT_INDEX_STATS(
  ownname => 'SH',
  indname => 'SALES_PROD_BIX',
  stattab => 'STATS_BACKUP'
);

EXEC DBMS_STATS.IMPORT_INDEX_STATS(
  ownname => 'SH',
  indname => 'SALES_PROD_BIX',
  stattab => 'STATS_BACKUP'
);
```

### Oracle 的统计锁定与手工设置

Oracle 8i Release 1 起支持表级统计锁定，11g 起增加分区级锁定：

```sql
-- 锁定表级统计（防止 GATHER_STATS_JOB 自动覆盖）
EXEC DBMS_STATS.LOCK_TABLE_STATS('SH', 'SALES');

-- 锁定分区级
EXEC DBMS_STATS.LOCK_PARTITION_STATS('SH', 'SALES', 'SALES_Q1_2026');

-- 锁定 Schema
EXEC DBMS_STATS.LOCK_SCHEMA_STATS('SH');

-- 解锁
EXEC DBMS_STATS.UNLOCK_TABLE_STATS('SH', 'SALES');

-- 即使锁定，也可以用 FORCE 选项强制收集
EXEC DBMS_STATS.GATHER_TABLE_STATS('SH', 'SALES', force => TRUE);

-- 检查是否已锁定
SELECT stattype_locked
  FROM dba_tab_statistics
 WHERE owner = 'SH' AND table_name = 'SALES';
-- 'ALL' 表示完全锁定，'DATA' 表示只锁定数据统计，'CACHE' 锁定缓存统计，NULL 表示未锁定
```

`DBMS_STATS.SET_TABLE_STATS` 让 DBA 直接"伪造"统计信息（用于测试或修复异常）：

```sql
-- 直接设置假统计
EXEC DBMS_STATS.SET_TABLE_STATS(
  ownname  => 'SH',
  tabname  => 'SALES',
  numrows  => 1000000000,    -- 假装 10 亿行
  numblks  => 50000000,      -- 假装 5000 万块
  avgrlen  => 200            -- 假装平均行宽 200 字节
);

-- 设置列级统计
EXEC DBMS_STATS.SET_COLUMN_STATS(
  ownname  => 'SH',
  tabname  => 'SALES',
  colname  => 'PROD_ID',
  distcnt  => 100000,        -- 假装 NDV = 10 万
  density  => 0.00001,       -- 选择性 = 1/NDV
  nullcnt  => 0,
  srec     => NULL,          -- 不设置直方图
  avgclen  => 8
);

-- 设置索引统计
EXEC DBMS_STATS.SET_INDEX_STATS(
  ownname  => 'SH',
  indname  => 'SALES_PROD_BIX',
  numrows  => 1000000000,
  numlblks => 1000000,       -- 叶子块数
  numdist  => 100000,
  clstfct  => 5000000,       -- clustering factor
  indlevel => 3
);
```

### Oracle 统计还原（Statistics History）

Oracle 10g 起所有 GATHER_*_STATS 自动保存历史，默认保留 31 天：

```sql
-- 查看历史
SELECT table_name, stats_update_time
  FROM dba_tab_stats_history
 WHERE owner = 'SH' AND table_name = 'SALES'
 ORDER BY stats_update_time DESC;

-- 还原到某时刻
EXEC DBMS_STATS.RESTORE_TABLE_STATS(
  ownname        => 'SH',
  tabname        => 'SALES',
  as_of_timestamp => SYSTIMESTAMP - INTERVAL '7' DAY,
  no_invalidate  => FALSE
);

-- 调整保留天数
EXEC DBMS_STATS.ALTER_STATS_HISTORY_RETENTION(60);  -- 60 天

-- 查看当前保留期
SELECT DBMS_STATS.GET_STATS_HISTORY_RETENTION FROM DUAL;
```

这套"导出-导入-锁定-还原"的完整工作流，是 Oracle CBO 在生产环境运维上的核心竞争力之一。其他引擎做到这种程度的几乎为零。

### PostgreSQL 18 的 pg_dump --statistics（迟到的特性）

PostgreSQL 18 (2025-09) 在 `pg_dump` 中加入对 planner 统计的完整支持，是该版本最受期待的特性之一。在此之前，PostgreSQL DBA 面临的痛苦工作流：

```sql
-- PG 17 及之前的"手工"导出统计（社区脚本）
\COPY (SELECT * FROM pg_statistic WHERE starelid = 'orders'::regclass)
TO '/tmp/orders_stats.csv' CSV;

\COPY (SELECT * FROM pg_class WHERE relname = 'orders')
TO '/tmp/orders_relstats.csv' CSV;

-- 恢复时手工 INSERT，但 pg_statistic 列里有 anyarray 类型
-- 需要通过 SET 命令或专门的扩展才能跨实例迁移
-- 实际上几乎没人这样做，大多数 DBA 选择恢复后跑 ANALYZE
```

**PG 18 的新工作流**：

```bash
# 默认就包含统计（可用 --no-statistics 关闭）
pg_dump -d production_db -f prod.sql

# 或者只导统计（用于"刷新统计"场景）
pg_dump --statistics-only -d production_db -f stats_only.sql

# 恢复时同样默认带统计
psql -d staging_db -f prod.sql

# 不要统计（旧行为）
pg_dump --no-statistics -d production_db -f prod.sql
```

PG 18 引入新的 SQL 命令族 `pg_restore_relation_stats()`、`pg_restore_attribute_stats()`，pg_dump 在 dump 文件中生成对它们的调用：

```sql
-- pg_dump 生成的语句示例
SELECT pg_catalog.pg_restore_relation_stats(
  'relation'::text, 'public.orders'::regclass,
  'relpages'::text, 12345::integer,
  'reltuples'::text, 1234567.0::real,
  'relallvisible'::text, 12000::integer
);

SELECT pg_catalog.pg_restore_attribute_stats(
  'relation'::text, 'public.orders'::regclass,
  'attname'::text, 'status'::name,
  'inherited'::text, false::boolean,
  'null_frac'::text, 0.001::real,
  'avg_width'::text, 8::integer,
  'n_distinct'::text, 5::real,
  'most_common_vals'::text,
    '{PAID,PENDING,CANCELLED,REFUNDED,FAILED}'::text,
  'most_common_freqs'::text,
    '{0.7,0.15,0.10,0.04,0.01}'::real[]
);
```

**为什么 PostgreSQL 花了这么久**？PostgreSQL 社区从 2017 年起就有讨论（参见 hackers 邮件列表的 thread），核心难点：

1. **`pg_statistic` 中含有 `anyarray` 类型**：直方图边界、MCV 列表都是按列原始类型的数组存储的。文本化后还原时，需要保证目标库里有完全相同的类型定义、collation、编码。
2. **跨版本兼容性**：不同主版本之间，统计的存储格式可能微调（例如新增 stakind5）。简单 COPY 在跨版本时不安全。
3. **MCV 列表的精度**：将 `most_common_freqs` 文本化后再解析，会引入浮点误差，可能导致选择性估计与原库不完全一致。
4. **扩展统计**：`pg_statistic_ext` 的导出更复杂，涉及 `dependencies`、`ndistinct`、`mcv` 三种类型，每种序列化方式不同。

PG 18 的实现采用了"声明式还原 API"思路——`pg_restore_*_stats()` 函数对每个字段做类型校验和兼容性检查，跨版本失败时降级为部分还原而不是完全失败。这个设计让"PG 14 → PG 18 升级时直接迁移统计"成为可能。

### PostgreSQL 17 及之前的折中方案

在 PG 18 落地之前，业界有几种半官方方案：

```sql
-- 方案 1: pg_stats 视图（只读，高度衍生，无法直接 INSERT）
SELECT * FROM pg_stats WHERE tablename = 'orders';
-- 列：null_frac, n_distinct, most_common_vals, most_common_freqs, histogram_bounds

-- 方案 2: 直接 COPY pg_statistic（写入需要 superuser）
-- 注意：staattnum 是按列序号，跨实例迁移时需要重新映射
COPY pg_catalog.pg_statistic TO '/tmp/pg_stat.bin' BINARY;

-- 方案 3: pg_statistics 扩展（社区维护）
CREATE EXTENSION pg_stat_statements;  -- 注意这是查询统计，不是 planner 统计

-- 方案 4: 手工 fake 关键统计（仅用于测试）
UPDATE pg_class SET reltuples = 1000000000 WHERE relname = 'orders';
UPDATE pg_class SET relpages = 50000000   WHERE relname = 'orders';
-- 这种 hack 只影响行数估算，不影响直方图
```

### SQL Server 统计导出（受限的工作流）

SQL Server 没有内置统一的统计导出/导入命令。`DBCC SHOW_STATISTICS` 用于读取，`sp_create_stats` 用于一键创建所有列的统计：

```sql
-- 查看某个统计的详情
DBCC SHOW_STATISTICS ('Sales.SalesOrderDetail', 'IX_SalesOrderDetail_ProductID');
-- 输出三个结果集：
--   STATS_HEADER（行数、采样行数、最后更新时间）
--   DENSITY_VECTOR（前缀列的密度）
--   HISTOGRAM（最多 200 step 的等深直方图）

-- 只看 STATS_HEADER（用于检查是否需要重新收集）
DBCC SHOW_STATISTICS ('Sales.SalesOrderDetail', 'IX_SalesOrderDetail_ProductID')
  WITH STATS_HEADER, NO_INFOMSGS;

-- sp_create_stats: 一键给当前库的所有未统计列创建统计
EXEC sp_create_stats;

-- 也可以加选项
EXEC sp_create_stats @indexonly = 'INDEXONLY';   -- 只对已索引列
EXEC sp_create_stats @fullscan  = 'FULLSCAN';    -- 全扫描而非采样

-- 创建命名统计（手工而非 sp_create_stats）
CREATE STATISTICS stat_ProductId
  ON Sales.SalesOrderDetail (ProductID)
  WITH FULLSCAN;

-- WITH FULLSCAN: 强制全表扫描（默认会采样）
-- WITH SAMPLE 50 PERCENT: 指定采样率
-- WITH NORECOMPUTE: 禁用自动重算（等同于"冻结"）

-- 查看所有统计
SELECT s.name, s.auto_created, s.user_created, s.no_recompute,
       sp.last_updated, sp.rows, sp.rows_sampled,
       sp.steps, sp.unfiltered_rows, sp.modification_counter
  FROM sys.stats s
  CROSS APPLY sys.dm_db_stats_properties(s.object_id, s.stats_id) sp
 WHERE s.object_id = OBJECT_ID('Sales.SalesOrderDetail');
```

**SQL Server 的"导出导入"实际做法**：

```sql
-- 一种常见做法：脚本化所有统计的 CREATE STATISTICS 语句 + WITH STATS_STREAM
-- WITH STATS_STREAM 是未文档化但被 SSMS 使用的功能：把直方图二进制 dump
-- 这种方法仅限同版本同补丁级使用，跨版本有风险

UPDATE STATISTICS Sales.SalesOrderDetail
WITH STATS_STREAM = 0x0100000003000000...   -- 二进制 blob
   , ROWCOUNT = 121317
   , PAGECOUNT = 1234;

-- 注意：STATS_STREAM 是 internal 用法，不在官方文档中保证向后兼容
-- 微软支持工程师在排错时会用它"复制客户的统计"到内部环境复现问题
```

### MySQL 的统计工作流（基本不支持）

MySQL 至今没有原生的统计信息导出/导入命令，所有方案都是绕开它：

```sql
-- 持久化统计（5.6.6+）
-- 写入 mysql.innodb_table_stats 和 mysql.innodb_index_stats 系统表
ALTER TABLE orders STATS_PERSISTENT=1;

-- 查看
SELECT * FROM mysql.innodb_table_stats WHERE table_name = 'orders';
SELECT * FROM mysql.innodb_index_stats WHERE table_name = 'orders';

-- 直接 INSERT 这两张表（hack 方案）
INSERT INTO mysql.innodb_table_stats
  (database_name, table_name, last_update, n_rows, clustered_index_size, sum_of_other_index_sizes)
VALUES
  ('shop', 'orders', NOW(), 100000000, 5000000, 2000000)
ON DUPLICATE KEY UPDATE
  n_rows = VALUES(n_rows),
  clustered_index_size = VALUES(clustered_index_size),
  sum_of_other_index_sizes = VALUES(sum_of_other_index_sizes);

-- 然后 FLUSH（或重启）让 InnoDB 重新读取
FLUSH TABLE orders;

-- 或者用 ANALYZE TABLE 重新计算（但这违背了"导入"目的）
ANALYZE TABLE orders;
```

**Percona Toolkit 的辅助工具**：

```bash
# pt-show-grants: 实际是导出权限，不是统计；但同系列工具也提供了一些相关 hack
# 真正用于统计的辅助：手工脚本化 mysqldump 不包含的部分

# 通过 mysqldump 的元数据选项也无法包含 InnoDB 统计
mysqldump --no-data --routines --triggers shop > schema.sql
# 不会包含 innodb_table_stats / innodb_index_stats 数据

# 唯一可靠方案：物理备份（xtrabackup）
xtrabackup --backup --target-dir=/backup/full
xtrabackup --prepare --target-dir=/backup/full
# 物理备份自然包含 mysql.innodb_*_stats 系统表
```

### CockroachDB 的 PERSISTED 统计

CockroachDB 19.1 引入持久化统计（`CREATE STATISTICS PERSISTED`）：

```sql
-- 创建并持久化（默认行为，不需要 PERSISTED 关键字也是持久的）
CREATE STATISTICS my_stats ON (col1, col2) FROM orders;

-- 查看所有统计
SHOW STATISTICS FOR TABLE orders;
+----------------+----------------------+------------+---------+--------+
| statistics_name|        column_names  | created    | row_count| ...    |
+----------------+----------------------+------------+---------+--------+
| __auto__       | {customer_id}        | 2026-04-15 | 1234567 |        |
| __auto__       | {status}             | 2026-04-15 | 1234567 |        |
| my_stats       | {col1, col2}         | 2026-04-20 | 1234567 |        |
+----------------+----------------------+------------+---------+--------+

-- 备份/恢复时自动包含统计
BACKUP DATABASE shop TO 's3://bucket/backup' AS OF SYSTEM TIME '-10s';
RESTORE DATABASE shop FROM 's3://bucket/backup';
-- RESTORE 后统计自动可用，无需重新 ANALYZE

-- 关闭自动统计
SET CLUSTER SETTING sql.stats.automatic_collection.enabled = false;
```

CockroachDB 的关键设计：**统计存储在系统表（system.table_statistics）中，与表数据一起被备份**。这与 PostgreSQL 18 之前的方案根本不同——CRDB 把"统计是数据的一部分"作为基本设计假设。

### TiDB 的 LOAD STATS 与 LOCK STATS

TiDB 提供独立的统计文件导出/导入语法：

```sql
-- 导出统计为 JSON（实际由 mysqldump 或 dumpling 间接支持）
-- 标准做法：用 SHOW STATS_* 命令读取后由应用脚本化
SHOW STATS_META;
-- 输出: Db_name, Table_name, Update_time, Modify_count, Row_count

SHOW STATS_HISTOGRAMS WHERE table_name = 'orders';
SHOW STATS_BUCKETS WHERE table_name = 'orders';

-- TiDB 4.0+ 支持的语法
LOAD STATS '/tmp/tidb_stats.json';

-- 锁定统计（6.5+）
LOCK STATS orders;
LOCK STATS orders, customers;

-- 查看锁定状态
SHOW STATS_LOCKED;
-- 输出: Db_name, Table_name, Status

-- 解锁
UNLOCK STATS orders;

-- TiDB 自动统计参数
SET GLOBAL tidb_enable_auto_analyze = OFF;
```

### DB2 RUNSTATS USE PROFILE

DB2 LUW 9.5 引入 statistics profile 机制，允许"保存一组 RUNSTATS 选项"用于反复执行：

```sql
-- 创建一个 profile（在某次 RUNSTATS 时声明 SET PROFILE）
RUNSTATS ON TABLE shop.orders
  ON ALL COLUMNS
  WITH DISTRIBUTION ON ALL COLUMNS
  AND DETAILED INDEXES ALL
  SET PROFILE;

-- 之后用同样的选项重新收集
RUNSTATS ON TABLE shop.orders USE PROFILE;

-- 查看现有 profile
SELECT statistics_profile
  FROM syscat.tables
 WHERE tabschema = 'SHOP' AND tabname = 'ORDERS';

-- 删除 profile
RUNSTATS ON TABLE shop.orders UNSET PROFILE;

-- db2look 工具导出建表脚本 + RUNSTATS profile
db2look -d SAMPLE -e -m -t SHOP.ORDERS -o orders_metadata.sql
# -m 选项让 db2look 生成 RUNSTATS 命令以及 UPDATE 系统目录的命令

# -mod 选项更激进：直接生成"模拟统计"用于优化器调试
db2look -d SAMPLE -mod -t SHOP.ORDERS -o orders_simulated.sql
```

### Vertica EXPORT_STATISTICS / IMPORT_STATISTICS

Vertica 自 6.0 起提供完整的导出/导入工作流，使用 XML 格式：

```sql
-- 导出整个数据库的统计
SELECT EXPORT_STATISTICS('/tmp/full_stats.xml');

-- 导出某个 schema
SELECT EXPORT_STATISTICS('/tmp/sales_stats.xml', 'sales.*');

-- 导出某张表
SELECT EXPORT_STATISTICS('/tmp/orders_stats.xml', 'sales.orders');

-- 导入
SELECT IMPORT_STATISTICS('/tmp/orders_stats.xml');

-- 查看 XML 文件内容（人类可读）
-- <stats>
--   <projection name="sales.orders_super">
--     <column name="customer_id" rows="100000000" distinct="50000" min="1" max="999999"/>
--     ...
--   </projection>
-- </stats>
```

Vertica 的 XML 格式是该领域少有的"半人类可读"实现，对支持工程师诊断特别友好。

### SAP HANA EXPORT/IMPORT STATISTICS

```sql
-- 导出
EXPORT STATISTICS FOR TABLE shop.orders INTO '/tmp/orders_stats';

-- 导入
IMPORT STATISTICS FROM '/tmp/orders_stats';

-- 查看 data statistics 对象
SELECT * FROM STATISTICS WHERE SCHEMA_NAME = 'SHOP' AND TABLE_NAME = 'ORDERS';
```

### Hive / Spark via Metastore

Hive 和 Spark SQL 都将统计信息存储在 Hive Metastore 中（通常是 PostgreSQL 或 MySQL 后端）。"导出/导入"实际上是导出/导入 metastore：

```sql
-- Hive: 收集统计写入 metastore
ANALYZE TABLE orders COMPUTE STATISTICS;
ANALYZE TABLE orders COMPUTE STATISTICS FOR COLUMNS;
ANALYZE TABLE orders COMPUTE STATISTICS FOR COLUMNS customer_id, status;

-- 查看
DESCRIBE EXTENDED orders;
DESCRIBE FORMATTED orders customer_id;

-- Spark SQL（通过 Hive Metastore）
ANALYZE TABLE orders COMPUTE STATISTICS;
ANALYZE TABLE orders COMPUTE STATISTICS FOR COLUMNS customer_id;

-- 导出 metastore 的标准做法：
-- 1. 直接备份后端 PG/MySQL（pg_dump 或 mysqldump）
-- 2. 用 schematool 导出/导入 metastore schema（只含元数据，不含统计）
-- 3. 集群之间用 metastore 的 export/import 工具（Apache 有专门的 EximUtil）
```

### Snowflake / BigQuery / 完全托管系统

完全托管系统几乎都不暴露统计的导出/导入：

```sql
-- Snowflake
-- 没有 EXPORT STATISTICS 命令
-- 但是 zero-copy clone 隐式包含统计
CREATE TABLE orders_dev CLONE orders_prod;
-- orders_dev 立即拥有与 orders_prod 相同的统计（共享底层 micro-partitions）

-- BigQuery
-- 没有暴露统计
-- bq cp / table snapshot 隐式包含统计
bq cp prod.orders dev.orders_snapshot
```

托管产品的设计哲学：**用户不应关心统计的存储格式或迁移过程**。这一立场让统计的导出/导入变成了无关需求，但也意味着用户失去了对优化器行为的精细控制。

## 工作流深度详解

### Oracle 跨环境复现执行计划的完整工作流

业界最经典的"用 Oracle 统计跨环境复现执行计划"流程，在每家大型企业的 DBA 团队中几乎都有标准操作手册（runbook）：

```sql
-- 阶段 1: 在生产库导出统计
-- 1.1 创建 stat 表（仅首次）
CONN system/password@PROD
BEGIN
  DBMS_STATS.CREATE_STAT_TABLE(
    ownname  => 'SYSTEM',
    stattab  => 'PROD_STATS_EXPORT',
    tblspace => 'SYSAUX'
  );
END;
/

-- 1.2 导出特定 schema 的统计
BEGIN
  DBMS_STATS.EXPORT_SCHEMA_STATS(
    ownname => 'SH',
    stattab => 'PROD_STATS_EXPORT',
    statid  => 'SLOW_QUERY_2026_04_28'
  );
END;
/

-- 1.3 用 Data Pump 把 stat 表导出
-- (在 OS 层)
expdp system/password@PROD \
  DIRECTORY=DATA_PUMP_DIR \
  TABLES=SYSTEM.PROD_STATS_EXPORT \
  DUMPFILE=prod_stats.dmp \
  LOGFILE=prod_stats_export.log

-- 阶段 2: 把 dmp 文件传到开发环境
scp prod_stats.dmp dev_db_host:/tmp/

-- 阶段 3: 在开发库导入
CONN system/password@DEV
-- 3.1 用 Data Pump 把 stat 表导入
impdp system/password@DEV \
  DIRECTORY=DATA_PUMP_DIR \
  TABLES=SYSTEM.PROD_STATS_EXPORT \
  DUMPFILE=prod_stats.dmp \
  LOGFILE=prod_stats_import.log

-- 3.2 把统计导入到 SH schema
BEGIN
  DBMS_STATS.IMPORT_SCHEMA_STATS(
    ownname        => 'SH',
    stattab        => 'PROD_STATS_EXPORT',
    statid         => 'SLOW_QUERY_2026_04_28',
    no_invalidate  => FALSE,
    statown        => 'SYSTEM'
  );
END;
/

-- 阶段 4: 锁定开发库统计（防止开发库自动 ANALYZE 覆盖）
EXEC DBMS_STATS.LOCK_SCHEMA_STATS('SH');

-- 阶段 5: 在开发库执行慢 SQL，应该看到与生产相同的执行计划
SET AUTOTRACE ON EXPLAIN
SELECT * FROM sales WHERE prod_id = 14 AND time_id BETWEEN ... AND ...;
-- 此时开发库的优化器看到的统计与生产完全一致
-- 即使开发库只有 1% 的实际数据，执行计划也会与生产一样
```

**关键技巧**：

- 开发库的实际数据要么是生产的子集（例如最近 1 天的），要么是合成数据。**统计信息不需要与实际数据匹配**，CBO 只关心统计中的值。
- 锁定（`LOCK_SCHEMA_STATS`）是防止开发库的自动 ANALYZE 把"虚假"统计覆盖掉的关键步骤。如果不锁定，开发库下一次 GATHER_STATS_JOB 运行时统计就会被重置为开发库实际数据。
- `no_invalidate => FALSE` 让所有引用这些表的 SQL 立即重新硬解析，使用新统计。`TRUE` 则等到下次自然解析时才生效。
- 这套流程也用于"我升级数据库后想保留升级前的执行计划"——升级前 EXPORT，升级后 IMPORT。

### PG 18 完整工作流

PostgreSQL 18 让相同流程变得极其简洁：

```bash
# 阶段 1: 在生产库 dump（默认包含统计）
pg_dump -h prod-host -d shop --schema-only --include-statistics -f prod_schema.sql
# --include-statistics 是 PG 18 默认行为，可省略
# --schema-only 不包含数据，只包含表定义和统计

# 或者只导出统计部分
pg_dump --statistics-only -d shop -f prod_stats.sql

# 阶段 2: 传到开发环境
scp prod_schema.sql dev-host:/tmp/

# 阶段 3: 在开发环境恢复
psql -h dev-host -d shop -f /tmp/prod_schema.sql
# 此时开发库的 pg_statistic 与生产一致

# 阶段 4: 在开发库禁止 autovacuum analyze 覆盖
psql -h dev-host -d shop -c "
  ALTER TABLE orders SET (autovacuum_analyze_enabled = false);
  ALTER TABLE customers SET (autovacuum_analyze_enabled = false);
"
# PG 没有"锁定"的语义，只能禁用自动收集
# 注意：手工 ANALYZE 仍会覆盖，需要 DBA 配合不要执行

# 阶段 5: 复现慢 SQL
psql -h dev-host -d shop -c "EXPLAIN SELECT ..."
# 看到的计划应该与生产一致
```

### 统计锁定模式：保护核心 OLTP 表

某些场景下，DBA 希望"绝对禁止"自动统计收集修改某张核心表的统计，只允许手工管理：

```sql
-- Oracle: 锁定 + 手工设置
EXEC DBMS_STATS.LOCK_TABLE_STATS('PAYMENTS', 'TRANSACTIONS');

-- 一旦锁定，自动收集不会覆盖
-- 如果需要更新，必须用 FORCE
EXEC DBMS_STATS.GATHER_TABLE_STATS('PAYMENTS', 'TRANSACTIONS', force => TRUE);

-- 或者用 SET_TABLE_STATS 直接覆盖
EXEC DBMS_STATS.SET_TABLE_STATS('PAYMENTS', 'TRANSACTIONS', numrows => 5000000000, force => TRUE);

-- SQL Server: NORECOMPUTE
ALTER INDEX IX_TX_AccountId
  ON Payments.Transactions
  REBUILD WITH (STATISTICS_NORECOMPUTE = ON);

-- 或者所有统计禁止重算
EXEC sp_autostats 'Payments.Transactions', 'OFF';

-- TiDB: LOCK STATS
LOCK STATS payments.transactions;

-- 设置阈值（PG 间接做法）
ALTER TABLE payments.transactions
  SET (autovacuum_analyze_threshold = 999999999999,
       autovacuum_analyze_scale_factor = 1.0);
-- 实际上等同禁用 autovacuum analyze（除非行数变化超过现有行数 100%）
```

**为什么需要锁定**？典型场景：

1. **数据倾斜导致优化器被"误导"**：业务热点导致某个值（例如 `status='PAID'`）占 99% 行。某次自动 ANALYZE 之后 MCV 列表更新，优化器从此对该值估算偏低，慢 SQL 突现。**锁定一份"健康"的统计**可避免此问题。
2. **大批量写入触发 auto-analyze**：每月 1 号集中 INSERT 1000 万行后，autovacuum 立刻 analyze，但此时统计反映的是"刚导入的偏态分布"，对其后查询不利。**锁定昨天的统计**直到运维评估完后再手工更新。
3. **稳定性优先**：核心交易表的执行计划必须 100% 稳定，不允许任何统计抖动导致计划变化。**锁定 + 手工管理**是唯一方案。

### Cardinality Feedback：基于运行时反馈的统计修正

Oracle 12c 引入 cardinality feedback：优化器执行 SQL 后，对比估计行数与实际行数，如差异巨大则在下次执行时调整估计。这是一种"运行时反馈式统计"，与导出/导入正交：

```sql
-- 第一次执行：优化器估计 100 行，实际返回 100 万行
SELECT * FROM orders WHERE customer_segment = 'PREMIUM';
-- 实际行数 1,000,000

-- 第二次执行：优化器从执行历史中学习，估计调整为 ~1M 行
-- 计划可能从 Nested Loop 改为 Hash Join

-- 查看 feedback 历史
SELECT sql_id, child_number, plan_hash_value, executions,
       fetches, cardinality_feedback_used
  FROM v$sql
 WHERE sql_id = '...';
```

cardinality feedback 不是真正的"导出导入统计"，但它代表了"统计不再静态"的另一个方向——某种程度上，未来的引擎可能让"统计导入"变得不那么重要，因为运行时反馈会自动修正错误。

## 跨版本兼容性矩阵

不同主版本之间，统计信息的存储格式可能变化。以下是常见跨版本场景的兼容性：

| 场景 | 兼容性 | 备注 |
|------|--------|------|
| Oracle 11g → 12c → 19c → 23ai | 高 | DBMS_STATS API 向后兼容；stat 表跨版本可用 |
| Oracle 8i → 9i → 10g | 部分 | 早期直方图格式与 10g 不同，可能需要重新收集 |
| PostgreSQL 14 → 17（PG 17 之前） | 低 | pg_statistic 跨版本不安全，建议恢复后重新 ANALYZE |
| PostgreSQL 14 → 18 | 中 | PG 18 的 pg_restore_*_stats 做了向后兼容 |
| PostgreSQL 18 → 19+ | 高 (设计目标) | 新 API 在 18 中作为基线，未来版本应保持兼容 |
| SQL Server 2016 → 2019 → 2022 | 高 | 统计格式跨版本稳定 |
| SQL Server 2008 → 2016 | 中 | 不推荐直接 STATS_STREAM 跨版本，应重新收集 |
| MySQL 5.7 → 8.0 | 低 | innodb_*_stats 表结构有变化，建议升级后 ANALYZE |
| DB2 LUW 9.7 → 11.5 | 高 | RUNSTATS profile 跨版本兼容 |
| CockroachDB 19.x → 22.x → 24.x | 高 | system.table_statistics 跨版本兼容 |
| Vertica 跨版本 | 高 | XML 格式向后兼容 |
| TiDB 4.0 → 7.0 | 中 | LOAD STATS JSON 格式 6.0 之后稳定 |
| Snowflake / BigQuery | -- | 用户不可见 |

**关键原则**：

- 跨主版本升级前，先在测试环境模拟"导出 → 升级 → 导入"流程，验证统计是否完整迁移。
- 如果跨版本兼容性低，**升级后立即重新 ANALYZE 比依赖旧统计更安全**。
- Oracle 是少数能"统计随便跨主版本"的引擎，得益于 DBMS_STATS 在 8i Release 1 起就采用了稳定的存储格式。

## 物理备份 vs 逻辑备份对统计的影响

| 备份类型 | 是否含统计 | 备注 |
|---------|----------|------|
| 物理备份（文件级） | 是（隐式） | 数据文件中包含 pg_statistic / mysql.innodb_*_stats 等 |
| Oracle RMAN | 是 | 物理块级备份 |
| MySQL xtrabackup | 是 | 物理文件备份 |
| PostgreSQL pg_basebackup | 是 | 物理目录备份 |
| 逻辑备份（pg_dump 等） | 取决于版本 | PG 18 默认是；pg_dump < 18 否；mysqldump 否；expdp 是 |
| pg_dump (PG 18+) | 是 | 默认开启 |
| pg_dump (PG ≤ 17) | 否 | 需手工 |
| mysqldump | 否 | 始终不含 |
| Oracle expdp | 是 | 元数据自动包含 |
| DB2 db2look | 是 (-m) | 生成 RUNSTATS 脚本 |
| CockroachDB BACKUP | 是 | 系统表中含统计 |
| Snowflake clone | 是（隐式） | 物理共享 |
| Delta clone | 是 | Delta 元数据 |

**实践含义**：

1. **物理备份 + 恢复永远包含统计**——这是物理备份相对逻辑备份的天然优势之一。如果"恢复后必须立即可用，不能等 ANALYZE"，物理备份是唯一安全选择。
2. **逻辑备份的统计支持取决于工具**：mysqldump 永远不支持；pg_dump 在 PG 18 之前不支持；Oracle expdp 一直支持；DB2 db2look 通过 `-m` 间接支持。
3. **跨集群迁移时，物理备份的统计往往可用，但需注意版本兼容性**——MySQL 5.7 的 .ibd 文件还原到 8.0 集群时，统计可能因结构变化而失效。

## 关键发现 (Key Findings)

### 1. Oracle 是唯一拥有完整工作流的引擎

Oracle 自 8i Release 1 (1999) 起就提供了完整的"导出-导入-锁定-还原"工作流，覆盖表/分区/schema/database 各级粒度。其他引擎要么只支持其中一部分（PostgreSQL 18 仅支持导出/导入），要么完全不支持（MySQL）。这是 Oracle 在生产环境运维上 25 年积累下的核心竞争力之一。

### 2. PG 18 (2025) 是开源世界 2025 年最重要的统计特性

`pg_dump --statistics`（默认开启）历经 8 年讨论后终于在 PG 18 落地。这一特性让"PostgreSQL TB 级表恢复后跳过 ANALYZE"成为可能，是企业级 PostgreSQL 用户长期的核心痛点。但跨主版本兼容性仍需谨慎——PG 14 → 18 的迁移建议在测试环境先验证。

### 3. MySQL 至今没有原生支持

MySQL 9.0 仍然不支持统计的导出/导入。`STATS_PERSISTENT` 让统计能持久化到表中，但导出时 mysqldump 不包含。所有"MySQL 统计跨环境迁移"的方案都是基于 `INSERT mysql.innodb_*_stats` 的 hack，或者依赖 xtrabackup 物理备份。

### 4. 统计锁定语义只有少数引擎原生支持

Oracle 的 `LOCK_TABLE_STATS`、TiDB 的 `LOCK STATS`、OceanBase 的兼容 Oracle API 是少数提供"表级统计锁定"语义的引擎。其他引擎要么禁用整库自动收集（粒度太粗），要么完全不支持。这是 Oracle CBO 在生产稳定性上的关键能力。

### 5. 完全托管的云数仓不暴露统计

Snowflake、BigQuery、Spanner、Firebolt 等托管产品都不允许用户操作统计。设计哲学是"用户不应关心统计"——但代价是失去精细调优能力。Snowflake 的 zero-copy clone 隐式包含统计，是托管产品中"跨环境复现执行计划"的唯一可行方案。

### 6. 物理备份永远是统计迁移的最稳妥方案

xtrabackup、pg_basebackup、Oracle RMAN、CockroachDB BACKUP 等物理备份天然包含统计。当跨版本兼容性不确定时，物理备份是最不容易出错的方案。代价是物理备份不能跨平台/跨版本（小版本通常可以，主版本通常不行）。

### 7. CockroachDB / Delta 把统计视为"数据的一部分"

CockroachDB 把统计存在 system 表中，BACKUP/RESTORE 时自然带上；Delta Lake 的 clone 操作也隐式拷贝统计。这种"统计是数据的延伸"设计哲学，让用户不再需要单独的"导出/导入统计"概念。这与 Oracle 的"统计是元数据的一部分"哲学形成对比。

### 8. SQL Server 的 STATS_STREAM 是隐藏的强大功能

`UPDATE STATISTICS WITH STATS_STREAM = 0x...` 允许直接 dump 直方图二进制 blob 并跨实例还原。虽然未文档化，但 SSMS 内部使用，微软支持工程师诊断时也用它"复制客户统计"。这是 SQL Server 隐藏的"导出/导入"机制，但跨主版本风险高，不推荐生产使用。

### 9. 跨主版本统计兼容性参差不齐

Oracle 跨版本兼容性最好（DBMS_STATS API 25 年来稳定）；CockroachDB、SQL Server、DB2 中等；PostgreSQL（PG 18 之前）几乎不能跨版本；MySQL 跨版本基本要重新收集。这一差异直接影响"升级风险"——选择 Oracle 的企业升级时风险显著低于选择 MySQL 的企业。

### 10. 反馈式统计是未来方向

Oracle 12c 的 cardinality feedback、SQL Server 2022 的 cardinality feedback、CockroachDB 22.2+ 的 cardinality feedback 都代表了"统计不再静态，而是基于运行时学习"的新方向。这种机制可能在未来 5-10 年内逐步替代部分"导出/导入"需求——优化器自己会从历史执行中学习，无需 DBA 手工迁移统计。

## 对引擎开发者的建议

### 1. 设计阶段就把统计视为"可序列化的元数据"

如果新引擎从零设计，应该把统计存储在一个**有明确 schema 的系统表**中，而不是分散在各种 catalog 中。CockroachDB 的 `system.table_statistics`、PG 18 的 `pg_restore_*_stats` API 都验证了这一思路的有效性。避免 PG 14 之前的"统计与系统目录混在一起，无法独立 dump"困境。

### 2. 提供 RPC/API 而非纯 SQL 接口

`DBMS_STATS.EXPORT_TABLE_STATS` 是 Oracle 数十年的设计精髓——把统计的导出/导入做成"过程化 API"，比 SQL DML 更适合：

- 可以原子化处理"序列化为表行 → 持久化"
- 可以做版本兼容性检查
- 可以做权限控制（导出统计 ≠ 读取数据，是更高的权限）

PG 18 的 `pg_restore_*_stats()` 函数也走了这条路。新引擎应该跟随。

### 3. 锁定统计是高阶生产能力

如果只做"导出/导入"，能力是初级的；如果同时支持"锁定+手工设置"，能力是中级的；如果再支持"还原到任意时刻+保留历史"，能力才是高级的。Oracle 8i Release 1 起就实现了完整三层，新引擎不应该只做第一层就停下。

### 4. 备份工具必须考虑统计

`pg_dump --statistics`、`expdp` 默认包含、`db2look -m`、`gpbackup` 都把统计纳入备份元数据。如果新引擎的逻辑备份工具不支持统计，企业级用户会因"恢复后等待 ANALYZE 数小时"而拒绝采用。

### 5. 跨版本兼容性是长期承诺

Oracle DBMS_STATS API 从 8i Release 1 (1999) 到 23ai (2024) 的 25 年里保持兼容，是企业用户能放心做"导出 → 升级 → 导入"的根本原因。如果新引擎的统计存储格式每个主版本都变，那"统计导出/导入"就是空话——用户不会信任跨版本不兼容的能力。

### 6. 反馈式统计应作为补充而非替代

Cardinality feedback 不应该完全替代静态统计——静态统计是 CBO 第一次执行 SQL 时的唯一信息源。引擎应该同时支持：

- 静态统计（ANALYZE 收集 + 可导出/导入 + 可锁定）
- 反馈式统计（运行时学习并修正）
- 计划稳定性（plan baseline / plan freezing，让优化器在统计变化时仍优先用历史好计划）

三层防御是 Oracle 12c+ 的标准设计，新引擎应该参考。

### 7. 多租户场景的统计隔离

云原生数据库（Snowflake、CockroachDB Serverless）需要面对"多租户共享同一引擎"的场景。统计应该按租户隔离，不能让租户 A 的导出/导入影响租户 B。这要求 system 表中的统计带有 tenant_id，而且 API 必须做租户校验。完全托管的产品因此倾向于不暴露统计 API，但这并不是唯一选择——可以暴露但做好隔离。

### 8. 统计与 plan baseline 的协同

完整的"执行计划稳定性"工作流应该包括：

1. 导出统计 + 导出 plan baseline
2. 在新环境导入两者
3. 优化器优先使用 plan baseline；如果 baseline 失效，回退到统计驱动的计划

Oracle 11g+ 的 SQL Plan Management、SQL Server 2016+ 的 Query Store 都实现了这一协同。新引擎如果不支持 plan baseline，光有统计的导出/导入也只能解决一半问题。

## 参考资料

- Oracle: [DBMS_STATS Reference](https://docs.oracle.com/en/database/oracle/oracle-database/19/arpls/DBMS_STATS.html)
- Oracle: [Best Practices for Gathering Statistics](https://docs.oracle.com/en/database/oracle/oracle-database/19/tgsql/index.html)
- PostgreSQL 18: [pg_dump --statistics](https://www.postgresql.org/docs/18/app-pgdump.html)
- PostgreSQL 18: [pg_restore_relation_stats / pg_restore_attribute_stats](https://www.postgresql.org/docs/18/functions-admin.html)
- PostgreSQL: [pg_statistic system catalog](https://www.postgresql.org/docs/current/catalog-pg-statistic.html)
- SQL Server: [DBCC SHOW_STATISTICS](https://learn.microsoft.com/en-us/sql/t-sql/database-console-commands/dbcc-show-statistics-transact-sql)
- SQL Server: [CREATE STATISTICS](https://learn.microsoft.com/en-us/sql/t-sql/statements/create-statistics-transact-sql)
- SQL Server: [sp_create_stats](https://learn.microsoft.com/en-us/sql/relational-databases/system-stored-procedures/sp-create-stats-transact-sql)
- DB2 LUW: [RUNSTATS Command](https://www.ibm.com/docs/en/db2/11.5?topic=commands-runstats)
- DB2 LUW: [db2look Tool](https://www.ibm.com/docs/en/db2/11.5?topic=commands-db2look-mimic-database)
- MySQL: [InnoDB Persistent Statistics](https://dev.mysql.com/doc/refman/8.0/en/innodb-persistent-stats.html)
- CockroachDB: [CREATE STATISTICS](https://www.cockroachlabs.com/docs/stable/create-statistics.html)
- TiDB: [Introduction to Statistics](https://docs.pingcap.com/tidb/stable/statistics)
- TiDB: [LOCK STATS](https://docs.pingcap.com/tidb/stable/sql-statement-lock-stats)
- Vertica: [EXPORT_STATISTICS / IMPORT_STATISTICS](https://docs.vertica.com/24.1.x/en/sql-reference/functions/data-collector-functions/)
- SAP HANA: [Data Statistics](https://help.sap.com/docs/SAP_HANA_PLATFORM)
- Hive: [StatsDev](https://cwiki.apache.org/confluence/display/Hive/StatsDev)
- 相关文章: [`statistics-histograms.md`](./statistics-histograms.md) - 单列统计与直方图详解
- 相关文章: [`extended-statistics.md`](./extended-statistics.md) - 多列与扩展统计
