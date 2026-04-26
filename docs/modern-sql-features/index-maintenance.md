# 索引维护 (Index Maintenance)

数据库工程师最常遇到的"索引明明命中却越查越慢"现象，背后藏着一个被持续低估的细节：索引在使用过程中会逐步降级——B 树叶子页因为分裂而稀疏、SSTable 因为更新而层叠、墓碑因为 GC 滞后而堆积。索引维护就是用空间换时间的反向操作，把"积累的熵"以可控的代价重新刷成有序的高密度状态。

## 为什么索引会"老化"

任何 B 树/B+ 树索引在持续 INSERT、UPDATE、DELETE 后都会出现以下问题：

1. **页分裂（Page Split）**：B+ 树叶子页满了之后插入新行会触发分裂，把原来 80%-90% 满的页分成两个 50% 满的新页，物理上往往不再相邻
2. **死索引项（Dead Index Entries）**：MVCC 数据库中 UPDATE 通常需要在索引中插入新版本但不能立即删除旧版本，导致索引项数量大于活元组数量
3. **碎片化（Fragmentation）**：叶子页的物理顺序与逻辑（键序）顺序背离，索引范围扫描需要更多随机 I/O
4. **填充率下降（Low Fill Factor）**：经过多轮 DELETE 后页面可能只剩 20%-30% 的有效项，浪费缓冲池
5. **统计信息漂移**：索引上的直方图、distinct values、相关系数过期，优化器选择劣化

PostgreSQL 社区流传的一个典型案例：一张 `sessions` 表只有 50 万活动行，但因为高频 UPDATE，主键 B+ 树膨胀到 12GB——索引扫描比顺序扫描还慢。SQL Server 的官方文档统计也指出：碎片率超过 30% 的索引范围扫描性能下降可达 10 倍以上。InnoDB 的 secondary index 在 OLTP 写密集场景下，叶子页平均填充率长期低于 60% 是常见现象。

## 没有 SQL 标准

ISO/IEC 9075（SQL:2023）至今没有任何关于索引维护的语句。原因和 VACUUM 一致——这些都是物理存储层的实现细节，标准只关心逻辑语义。每个引擎按自己的存储引擎特性发明了一套维护命令：

- **B+ 树系**（InnoDB、SQL Server、Oracle、PostgreSQL）：REBUILD、REORGANIZE、REINDEX
- **LSM 系**（CockroachDB、TiDB、YugabyteDB）：依赖后台 compaction，通常无显式索引维护命令
- **列存系**（ClickHouse、Vertica、Redshift）：通过 part merge / projection refresh 间接维护
- **存算分离系**（Snowflake、BigQuery）：完全黑盒，不暴露索引维护接口

唯一勉强算"准标准"的是 `ALTER INDEX ... REBUILD`——Oracle 引入后被 SQL Server、DB2、SAP HANA 部分继承，但具体语义和并发性差异巨大。

## 支持矩阵

### REBUILD INDEX（重建索引）

| 引擎 | 命令 | 默认行为 | 在线（ONLINE）选项 | 版本 |
|------|------|---------|-------------------|------|
| Oracle | `ALTER INDEX ... REBUILD` | 重建到新段 | `ONLINE` 9i+（2001） | 8i+ |
| SQL Server | `ALTER INDEX ... REBUILD` | 重建索引 | `WITH (ONLINE=ON)` 2005+ | 2005+ |
| PostgreSQL | `REINDEX INDEX` | 重建并替换 | `CONCURRENTLY` 12+（2019） | 7.0+ |
| MySQL InnoDB | `OPTIMIZE TABLE` / `ALTER TABLE ... ENGINE=InnoDB` | 重建表+索引 | 在线 DDL（5.6+） | 5.6+ |
| MySQL（5.7+） | `ALTER TABLE ... DROP/ADD INDEX` | 重新创建 | `ALGORITHM=INPLACE, LOCK=NONE` | 5.6+ |
| MariaDB | `ALTER TABLE ... ENGINE=InnoDB` | 重建表+索引 | 在线 DDL | 10.0+ |
| MyISAM | `REPAIR TABLE ... USE_FRM` | 重建索引 | 否（写锁） | 全部 |
| SQLite | `REINDEX` | 重建所有索引 | 否（写锁） | 3.0+ |
| DB2 | `REORG INDEXES` | 重组索引 | `ALLOW WRITE ACCESS` | 9.7+ |
| Snowflake | -- | 不暴露 | 自动维护（micro-partition） | -- |
| BigQuery | -- | 不暴露 | 自动维护 | -- |
| Redshift | `VACUUM REINDEX` | 重排序 + 重建 | 弱阻塞 | 2013+ |
| DuckDB | `DROP/CREATE INDEX` | 重新创建 | 否（写锁） | 全部 |
| ClickHouse | `OPTIMIZE TABLE ... FINAL` | 强制 part 合并 | 后台异步 | 全部 |
| Trino / Presto | -- | 不存数据 | -- | -- |
| Spark SQL | -- | 不直接管理索引 | -- | -- |
| Hive | -- | 已废弃索引功能（3.0+） | -- | -- |
| Flink SQL | -- | 状态后端管理 | -- | -- |
| Databricks | `OPTIMIZE` （Delta） | 文件合并 + Z-order | 后台 | 全部 |
| Teradata | `COLLECT STATISTICS` + 重建 | Primary Index 不可重建 | -- | 全部 |
| Greenplum | `REINDEX` | 继承 PG | 7+ 支持 CONCURRENTLY | 全部 |
| CockroachDB | -- | 后台自动 compaction | -- | 全部 |
| TiDB | `ADMIN RECOVER INDEX` | 修复一致性 | -- | 全部 |
| OceanBase | `ALTER INDEX ... REBUILD` | 重建索引 | 在线 | 全部 |
| YugabyteDB | `REINDEX` | 继承 PG 语法 | `CONCURRENTLY` 部分支持 | 2.6+ |
| SingleStore | `ALTER TABLE ... OPTIMIZE` | 行存合并 | 在线 | 全部 |
| Vertica | -- | Projection 自动重建 | -- | -- |
| Impala | -- | 不直接管理索引 | -- | -- |
| StarRocks | -- | BE 后台 compaction | -- | -- |
| Doris | `BUILD INDEX` | 重建倒排索引 | 异步 | 2.0+ |
| MonetDB | -- | 自动 imprints | -- | -- |
| CrateDB | `OPTIMIZE` | 段合并 | 后台 | 全部 |
| TimescaleDB | `REINDEX` | 继承 PG | `CONCURRENTLY` 12+ | 全部 |
| QuestDB | -- | 自动维护 | -- | -- |
| Exasol | -- | 自动维护 | -- | -- |
| SAP HANA | `ALTER INDEX ... REBUILD` | 列存索引重组 | 在线 | 2.0+ |
| Informix | `ALTER FRAGMENT` 重组 | 索引重建 | -- | 全部 |
| Firebird | `ALTER INDEX ... ACTIVE` | 切换状态触发重建 | -- | 全部 |
| H2 | `DROP/CREATE INDEX` | 重新创建 | 否 | 全部 |
| HSQLDB | `DROP/CREATE INDEX` | 重新创建 | 否 | 全部 |
| Derby | `DROP/CREATE INDEX` | 重新创建 | 否 | 全部 |
| Amazon Athena | -- | 不存数据 | -- | -- |
| Azure Synapse | `ALTER INDEX ... REBUILD` | 类似 SQL Server | `WITH (ONLINE=ON)` Gen3+ | GA |
| Google Spanner | -- | 自动维护 | -- | -- |
| Materialize | -- | 状态自动 | -- | -- |
| RisingWave | -- | 状态自动 | -- | -- |
| InfluxDB | -- | TSM compaction | -- | -- |
| Databend | `OPTIMIZE TABLE` | 段合并 | 后台 | 全部 |
| Yellowbrick | `REINDEX` | 重建 | -- | 全部 |
| Firebolt | -- | 自动维护 | -- | -- |

> 统计：约 22 个引擎暴露显式 REBUILD/REINDEX 命令，约 25 个引擎完全自动管理（多数是云原生/OLAP/LSM 系或不维护用户索引）。

### REORGANIZE（在线重组，不重建）

REORGANIZE 是一种比 REBUILD 更轻量的维护操作：只在叶子层做物理位置调整、合并稀疏页、压缩填充率，不重建整个 B 树结构。

| 引擎 | 命令 | 阻塞 | 说明 |
|------|------|------|------|
| SQL Server | `ALTER INDEX ... REORGANIZE` | 在线（短锁） | 仅叶子层，单线程，可中断 |
| Oracle | `ALTER INDEX ... COALESCE` | 在线 | 合并相邻稀疏块，不重建 |
| DB2 | `REORG INDEXES ... CLEANUP ONLY` | 在线 | 仅清理删除项 |
| PostgreSQL | -- | -- | 无对应概念，REINDEX 是唯一选项 |
| MySQL InnoDB | -- | -- | 无对应概念 |
| MariaDB | -- | -- | 无对应概念 |
| Sybase ASE | `REORG REBUILD` / `REORG COMPACT` | 在线 | SQL Server 的祖型 |
| SAP HANA | `ALTER INDEX ... REORGANIZE` | 在线 | 列存合并 |
| Informix | `ALTER INDEX ... TO CLUSTER` | 在线 | 物理重排 |
| 其他引擎 | -- | -- | 不区分 REBUILD 与 REORGANIZE |

> SQL Server 的 REORGANIZE 与 REBUILD 的区别是面试常考点：REORGANIZE 不需要 sort area、内存占用低、可随时中断、不重建统计信息；REBUILD 等价于全量重建、释放并重新分配空间、自动更新统计信息。

### 在线重建（Concurrent / Online Rebuild）

| 引擎 | 语法 | 阻塞 DML | 阻塞 DDL | 引入版本 |
|------|------|---------|---------|---------|
| Oracle | `REBUILD ONLINE` | 不阻塞 | 不阻塞 | 9i (2001) |
| SQL Server | `REBUILD WITH (ONLINE=ON)` | 不阻塞（除短暂的 schema 锁） | 不阻塞 | 2005 企业版 |
| PostgreSQL | `REINDEX CONCURRENTLY` | 不阻塞 | 不阻塞（除短暂的 ShareUpdateExclusiveLock） | 12 (2019) |
| MySQL InnoDB | `ALTER TABLE ... ALGORITHM=INPLACE, LOCK=NONE` | 不阻塞 | 不阻塞 | 5.6 (2013) |
| MariaDB | `ALTER TABLE ... ALGORITHM=INPLACE, LOCK=NONE` | 不阻塞 | 不阻塞 | 10.0 |
| DB2 | `REORG INDEXES ... ALLOW WRITE ACCESS` | 不阻塞 | 不阻塞 | 9.7 (2010) |
| OceanBase | `REBUILD ONLINE` | 不阻塞 | 不阻塞 | 全部 |
| YugabyteDB | `REINDEX CONCURRENTLY` | 部分支持 | 部分支持 | 2.6+ |
| TimescaleDB | `REINDEX CONCURRENTLY` | 不阻塞 | 不阻塞 | 12+ |
| Greenplum | `REINDEX CONCURRENTLY` | 部分阻塞（分布式协调） | 部分 | 7+ |
| CockroachDB | -- | -- | -- | 不需要（后台自动）|
| TiDB | -- | -- | -- | 不需要（后台自动）|
| SAP HANA | `REBUILD ONLINE` | 不阻塞 | 不阻塞 | 2.0+ |
| Azure Synapse | `REBUILD WITH (ONLINE=ON)` | 不阻塞 | 不阻塞 | Gen3+ |
| SQLite | -- | -- | -- | 不支持（写锁）|
| MyISAM | -- | -- | -- | 不支持（写锁）|

> 在线重建的本质：所有引擎都通过"双写日志 + 后台扫描复制 + 切换"的三阶段实现：
> 1. 创建新索引段，标记原索引为旧
> 2. 后台扫描数据，向新索引写入；同时所有 DML 双写到新旧两个索引
> 3. 验证一致性后短暂上锁，原子切换索引指针

### 碎片监控视图

| 引擎 | 系统视图 | 关键字段 | 备注 |
|------|---------|---------|------|
| SQL Server | `sys.dm_db_index_physical_stats` | `avg_fragmentation_in_percent`, `page_count` | 最完整 |
| Oracle | `INDEX_STATS`（需 `ANALYZE INDEX VALIDATE STRUCTURE`） | `HEIGHT`, `BLOCKS`, `DEL_LF_ROWS`, `PCT_USED` | 需手动触发 |
| PostgreSQL | `pgstattuple.pgstattuple_approx()` / `pgstatindex()` | `tuple_count`, `dead_tuple_percent`, `free_percent` | 扩展 |
| MySQL | `INFORMATION_SCHEMA.INNODB_INDEX_STATS` | `n_leaf_pages`, `size`, `n_diff_pfx*` | 通过 `mysql.innodb_table_stats` |
| MariaDB | 同 MySQL | -- | -- |
| DB2 | `SYSIBMADM.SNAPINDEX` | `INDEX_USAGE`, `EMPTY_PAGES_DELETED` | -- |
| SQLite | `dbstat` 虚表 | `pgsize`, `unused`, `mx_payload` | 编译时启用 |
| ClickHouse | `system.parts` | `marks`, `bytes_on_disk`, `rows` | 间接反映 |
| CockroachDB | `crdb_internal.gossip_alerts` | -- | 不直接暴露索引碎片 |
| TiDB | `INFORMATION_SCHEMA.TIKV_REGION_PEERS` | -- | LSM 风格 |
| Snowflake | -- | -- | 不暴露 |
| BigQuery | `INFORMATION_SCHEMA.TABLE_STORAGE` | -- | 仅表级 |
| Redshift | `SVV_TABLE_INFO` | `unsorted`, `tbl_rows` | 排序键碎片 |
| Vertica | `STORAGE_CONTAINERS` | -- | Projection 视图 |
| Greenplum | `gp_toolkit.gp_bloat_diag` | `bdirelpages`, `bdiexppages` | 表级 |
| TimescaleDB | `pgstatindex` | -- | 继承 PG |
| SAP HANA | `M_INDEX_STATISTICS` | `MEMORY_SIZE_IN_TOTAL`, `RECORD_COUNT` | -- |
| Azure Synapse | `sys.dm_db_index_physical_stats` | 同 SQL Server | -- |

### 自动重建 / 维护策略

| 引擎 | 自动重建 | 触发条件 | 配置位置 |
|------|---------|---------|---------|
| SQL Server | 否（需 SQL Agent / Azure Auto-Tune） | DBA 调度 | -- |
| Oracle | 否（需 DBMS_SCHEDULER） | DBA 调度 | -- |
| PostgreSQL | 否（仅 autovacuum 维护可见性） | -- | -- |
| MySQL | 否 | -- | -- |
| Azure SQL Database | 是（Auto-Tune） | 索引建议引擎 | 内置 |
| Azure Synapse | 是（Auto Statistics） | -- | 配置 |
| Aurora MySQL/PG | 部分（Performance Insights） | -- | -- |
| Snowflake | 是（micro-partition 自动） | 后台 | 完全托管 |
| BigQuery | 是（自动） | 后台 | 完全托管 |
| ClickHouse | 是（merge pool） | 大小阈值 | `merge_with_recompression_ttl_timeout` |
| CockroachDB | 是（Pebble compaction） | LSM 触发 | `kv.range_log.deletion_threshold` |
| TiDB | 是（GC worker） | `tidb_gc_run_interval` | -- |
| YugabyteDB | 是（DocDB compaction） | LSM 触发 | -- |
| StarRocks | 是（compaction manager） | 版本数 | -- |
| Doris | 是（compaction manager） | 版本数 | -- |
| Databricks | 是（predictive optimization） | ML 驱动 | 可选 |

> 行业现状：**传统 OLTP 数据库（PG/MySQL/Oracle/SQL Server）的索引维护仍依赖 DBA 主动调度**；云原生与 LSM 系数据库则普遍内置了自动维护。

### INDEX VALIDATE / 一致性检查

| 引擎 | 命令 | 检查内容 | 阻塞 |
|------|------|---------|------|
| Oracle | `ANALYZE INDEX ... VALIDATE STRUCTURE` | 物理结构 + 一致性 | 表锁 |
| Oracle | `VALIDATE STRUCTURE OFFLINE CASCADE` | 离线深度检查 | 离线 |
| SQL Server | `DBCC CHECKDB` / `DBCC CHECKTABLE` | 全库或单表 | 在线 |
| PostgreSQL | `pg_amcheck` (14+) | B-tree 一致性 | 在线 |
| MySQL InnoDB | `CHECK TABLE` | 索引与数据一致性 | 共享锁 |
| MyISAM | `myisamchk -ec` / `CHECK TABLE` | 离线/在线 | 共享锁 |
| SQLite | `PRAGMA integrity_check` | 全库一致性 | 共享锁 |
| DB2 | `INSPECT TABLE` | 索引检查 | 在线 |
| PostgreSQL | `pg_index.indisvalid` 字段 | 索引可用性标志 | 元数据 |
| TiDB | `ADMIN CHECK INDEX` | 索引一致性 | 在线 |
| TiDB | `ADMIN CHECK TABLE` | 表与索引一致性 | 在线 |
| OceanBase | `CHECK INDEX` | 索引一致性 | 在线 |
| CockroachDB | `EXPERIMENTAL_SCRUB DATABASE` | 全库检查 | 在线 |
| YugabyteDB | 继承 PG | -- | -- |
| Snowflake | -- | 不暴露 | -- |
| BigQuery | -- | 不暴露 | -- |
| Redshift | -- | 不暴露 | -- |
| ClickHouse | `CHECK TABLE` | part 校验和 | 在线 |
| Vertica | `ANALYZE_STATISTICS_PARTITION` | -- | -- |
| Greenplum | `pg_amcheck` | 继承 PG | -- |
| SAP HANA | `CHECK TABLE CONSISTENCY` | 索引一致性 | 在线 |
| Firebird | `gfix -validate` | 一致性 | 离线 |

## 各引擎实现详解

### SQL Server（最完整的索引维护工具集）

SQL Server 自 2005 起就提供了业界最完整的索引维护语法，区分 REBUILD 和 REORGANIZE 两种粒度：

```sql
-- 重建索引（重新创建整个 B+ 树，更新统计信息）
ALTER INDEX idx_orders_date ON dbo.Orders REBUILD;

-- 在线重建（不阻塞 DML）
ALTER INDEX idx_orders_date ON dbo.Orders REBUILD WITH (ONLINE = ON);

-- 重建并指定填充率（为后续插入预留空间）
ALTER INDEX idx_orders_date ON dbo.Orders
REBUILD WITH (ONLINE = ON, FILLFACTOR = 80, MAXDOP = 4);

-- REORGANIZE：仅整理叶子页，单线程，不重建
ALTER INDEX idx_orders_date ON dbo.Orders REORGANIZE;

-- 重建表上所有索引
ALTER INDEX ALL ON dbo.Orders REBUILD;

-- 重建分区索引的特定分区（2014+）
ALTER INDEX idx_orders_date ON dbo.Orders
REBUILD PARTITION = 5 WITH (ONLINE = ON);

-- 启用 RESUMABLE（2017+，可暂停/恢复的索引重建）
ALTER INDEX idx_orders_date ON dbo.Orders
REBUILD WITH (ONLINE = ON, RESUMABLE = ON, MAX_DURATION = 240 MINUTES);

-- 暂停一个 RESUMABLE 重建
ALTER INDEX idx_orders_date ON dbo.Orders PAUSE;

-- 恢复
ALTER INDEX idx_orders_date ON dbo.Orders RESUME;
```

碎片监控（`sys.dm_db_index_physical_stats` 是核心）:

```sql
-- 检查所有索引的碎片率
SELECT
    OBJECT_NAME(ips.object_id)              AS table_name,
    i.name                                   AS index_name,
    ips.index_type_desc,
    ips.avg_fragmentation_in_percent,
    ips.page_count,
    ips.avg_page_space_used_in_percent
FROM sys.dm_db_index_physical_stats(
    DB_ID(),
    NULL,         -- 所有表
    NULL,         -- 所有索引
    NULL,         -- 所有分区
    'LIMITED'     -- 模式：LIMITED / SAMPLED / DETAILED
) ips
JOIN sys.indexes i
    ON ips.object_id = i.object_id AND ips.index_id = i.index_id
WHERE ips.page_count > 1000  -- 仅大索引
ORDER BY ips.avg_fragmentation_in_percent DESC;
```

模式说明：
- `LIMITED`：只读父级页，最快但不计算 `avg_page_space_used_in_percent`
- `SAMPLED`：采样读取叶子页（约 1%）
- `DETAILED`：扫描所有叶子页，最慢但最准确

Paul Randal 提出的 SQL Server 索引维护"5%/30%"经验阈值已经成为业界事实标准：

```sql
-- Paul Randal 的标准索引维护脚本（简化版）
DECLARE @sql NVARCHAR(MAX);

SELECT @sql = STRING_AGG(
    CASE
        WHEN avg_fragmentation_in_percent BETWEEN 5 AND 30 THEN
            'ALTER INDEX [' + i.name + '] ON [' + s.name + '].[' + t.name + '] REORGANIZE;'
        WHEN avg_fragmentation_in_percent > 30 THEN
            'ALTER INDEX [' + i.name + '] ON [' + s.name + '].[' + t.name + '] REBUILD WITH (ONLINE = ON);'
    END, CHAR(10))
FROM sys.dm_db_index_physical_stats(DB_ID(), NULL, NULL, NULL, 'LIMITED') ips
JOIN sys.indexes i  ON ips.object_id = i.object_id AND ips.index_id = i.index_id
JOIN sys.tables  t  ON i.object_id = t.object_id
JOIN sys.schemas s  ON t.schema_id = s.schema_id
WHERE ips.page_count > 1000
  AND ips.avg_fragmentation_in_percent > 5;

EXEC sp_executesql @sql;
```

### Oracle（在线重建的鼻祖）

Oracle 9i（2001）首次引入 `ALTER INDEX ... REBUILD ONLINE`，是关系数据库历史上第一个支持真正在线重建的实现。

```sql
-- 基本重建（阻塞 DML）
ALTER INDEX idx_orders_date REBUILD;

-- 在线重建（9i 起，不阻塞 DML）
ALTER INDEX idx_orders_date REBUILD ONLINE;

-- 重建到不同的表空间
ALTER INDEX idx_orders_date REBUILD TABLESPACE indx_ts_2024;

-- 重建并指定 PCTFREE（填充率）
ALTER INDEX idx_orders_date REBUILD ONLINE PCTFREE 20;

-- 并行重建
ALTER INDEX idx_orders_date REBUILD ONLINE PARALLEL 8;

-- 压缩重建（适合 DSS 系统）
ALTER INDEX idx_orders_date REBUILD COMPRESS 2;

-- 合并稀疏块（轻量级，不需要完整重建）
ALTER INDEX idx_orders_date COALESCE;

-- 重建分区索引
ALTER INDEX idx_orders_date REBUILD PARTITION p_2024_q1 ONLINE;

-- 监控索引使用
ALTER INDEX idx_orders_date MONITORING USAGE;
-- 查询：SELECT * FROM v$object_usage WHERE index_name = 'IDX_ORDERS_DATE';
ALTER INDEX idx_orders_date NOMONITORING USAGE;
```

碎片监控（需要先 ANALYZE INDEX）:

```sql
-- 触发分析（会上短暂的 DDL 锁，谨慎使用）
ANALYZE INDEX idx_orders_date VALIDATE STRUCTURE;

-- 查询结果（仅当前会话可见）
SELECT name, height, blocks, br_rows, lf_rows,
       del_lf_rows, lf_rows_len, distinct_keys, used_space,
       pct_used, blks_gets_per_access
FROM index_stats;

-- 判断是否需要重建（经验阈值）
SELECT
    CASE
        WHEN del_lf_rows / NULLIF(lf_rows, 0) > 0.2 THEN 'REBUILD recommended (>20% deleted)'
        WHEN pct_used < 60 THEN 'REBUILD recommended (low fill)'
        WHEN height > 4 THEN 'REBUILD recommended (deep tree)'
        ELSE 'No action needed'
    END AS recommendation
FROM index_stats;

-- 离线深度检查（含交叉一致性，可选 CASCADE 检查所有相关索引）
ANALYZE INDEX idx_orders_date VALIDATE STRUCTURE OFFLINE CASCADE;
```

Oracle 在线重建的内部机制（与 SQL Server 类似但更早）：
1. 创建临时索引段 `SYS_JOURNAL_xxx` 记录所有变更
2. 扫描表数据，构建新索引段
3. 应用 journal 中累积的变更
4. 短暂上 DDL 锁（< 1 秒），切换 data dictionary 指针

### PostgreSQL（CONCURRENTLY 是分水岭）

PostgreSQL 的索引维护历史可分为两个时代：12 之前（仅离线 REINDEX）和 12 之后（CONCURRENTLY）。

```sql
-- 重建单个索引（阻塞 DML）
REINDEX INDEX idx_orders_date;

-- 重建表上所有索引
REINDEX TABLE orders;

-- 重建整个数据库（管理员操作）
REINDEX DATABASE mydb;

-- 重建系统目录
REINDEX SYSTEM mydb;

-- CONCURRENTLY（12+，不阻塞 DML）
REINDEX INDEX CONCURRENTLY idx_orders_date;
REINDEX TABLE CONCURRENTLY orders;

-- 监控 REINDEX 进度（12+，需要 pg_stat_progress_create_index 视图）
SELECT
    pid,
    datname,
    relid::regclass,
    index_relid::regclass,
    command,
    phase,
    blocks_done,
    blocks_total,
    tuples_done,
    tuples_total
FROM pg_stat_progress_create_index;
```

碎片监控需要 `pgstattuple` 扩展:

```sql
CREATE EXTENSION IF NOT EXISTS pgstattuple;

-- 索引膨胀检查
SELECT
    relname AS index_name,
    pg_size_pretty(pg_relation_size(oid)) AS size,
    pgstatindex(oid::regclass)
FROM pg_class
WHERE relkind = 'i'
  AND relname LIKE 'idx_%';

-- 详细索引统计
SELECT * FROM pgstatindex('idx_orders_date');
-- 返回: version, tree_level, index_size, root_block_no,
--       internal_pages, leaf_pages, empty_pages,
--       deleted_pages, avg_leaf_density, leaf_fragmentation

-- 高效近似检查（不锁全表）
SELECT
    relname,
    n_live_tup,
    n_dead_tup,
    round(n_dead_tup::numeric / NULLIF(n_live_tup, 0) * 100, 2) AS dead_pct
FROM pg_stat_user_tables
ORDER BY dead_pct DESC NULLS LAST;
```

`pg_index.indisvalid` 字段：

```sql
-- 失败的 CONCURRENTLY 操作会留下 INVALID 索引
SELECT
    schemaname,
    tablename,
    indexname,
    indexdef
FROM pg_indexes
JOIN pg_class c ON c.relname = pg_indexes.indexname
JOIN pg_index i ON i.indexrelid = c.oid
WHERE NOT i.indisvalid;

-- 清理失效索引：必须 DROP 后用 CREATE INDEX CONCURRENTLY 重建
DROP INDEX CONCURRENTLY idx_invalid;
CREATE INDEX CONCURRENTLY idx_recreated ON orders (created_at);
```

### MySQL InnoDB（隐式重建）

MySQL InnoDB 没有显式的 `REBUILD INDEX` 命令——所有索引重建都通过表级操作触发：

```sql
-- 重建表（同时重建所有索引）
OPTIMIZE TABLE orders;
-- 等价于
ALTER TABLE orders ENGINE=InnoDB;

-- 5.6+ 在线 DDL（默认就是在线）
ALTER TABLE orders ENGINE=InnoDB, ALGORITHM=INPLACE, LOCK=NONE;

-- 添加索引（在线，会触发新索引的初始构建）
ALTER TABLE orders ADD INDEX idx_status (status), ALGORITHM=INPLACE, LOCK=NONE;

-- 删除并重建索引（最常用的"重建"模式）
ALTER TABLE orders
    DROP INDEX idx_status,
    ADD INDEX idx_status (status),
    ALGORITHM=INPLACE, LOCK=NONE;

-- INSTANT 算法（8.0+，仅元数据变更，秒级完成）
ALTER TABLE orders ADD COLUMN region_id INT, ALGORITHM=INSTANT;
-- 注意：INSTANT 不能用于添加索引，仅添加列
```

碎片监控:

```sql
-- 表的总碎片
SELECT
    table_schema,
    table_name,
    data_length,
    index_length,
    data_free,
    round(data_free / (data_length + index_length + data_free) * 100, 2) AS free_pct
FROM information_schema.tables
WHERE table_schema = 'mydb'
ORDER BY free_pct DESC;

-- InnoDB 索引页填充率（间接指标）
SELECT
    database_name, table_name, index_name,
    stat_name, stat_value, stat_description
FROM mysql.innodb_index_stats
WHERE database_name = 'mydb' AND table_name = 'orders'
ORDER BY index_name, stat_name;

-- 关键字段：
-- n_leaf_pages    叶子页数
-- size            索引总大小（页数）
-- n_diff_pfx01..  各前缀的不同值数
```

InnoDB 自适应哈希索引（Adaptive Hash Index）的特殊维护：

```sql
-- 查看自适应哈希索引使用情况
SHOW ENGINE INNODB STATUS;
-- 在输出的 INSERT BUFFER AND ADAPTIVE HASH INDEX 段
-- "Hash table size" 和 "hash searches/s" 比值反映命中率

-- 关闭自适应哈希索引（高并发场景下可能成为瓶颈）
SET GLOBAL innodb_adaptive_hash_index = OFF;
```

### MyISAM（古老的 REPAIR）

虽然 MyISAM 已经基本被淘汰，但仍有大量遗留系统在使用，索引维护方式独特：

```sql
-- 修复表（包含索引重建）
REPAIR TABLE orders;

-- 强制重建索引（使用 .frm 文件而非 .MYI）
REPAIR TABLE orders USE_FRM;

-- 快速修复（仅修复索引头）
REPAIR TABLE orders QUICK;

-- 离线工具
-- $ myisamchk --recover --fast /var/lib/mysql/mydb/orders.MYI
-- $ myisamchk --safe-recover /var/lib/mysql/mydb/orders.MYI

-- 检查表
CHECK TABLE orders;
CHECK TABLE orders EXTENDED;  -- 完整一致性检查
```

MyISAM 索引文件（.MYI）独立于数据文件（.MYD），损坏几率高，因此 `REPAIR TABLE` 是 MyISAM DBA 的日常操作。

### DB2（REORG 系列）

DB2 的索引维护语义介于 SQL Server 与 Oracle 之间，提供细粒度的 CLEANUP 选项：

```sql
-- 完全重组索引
REORG INDEXES ALL FOR TABLE schema.orders;

-- 仅清理已删除项（最轻量）
REORG INDEXES ALL FOR TABLE schema.orders CLEANUP ONLY;

-- 在线重组（允许写入）
REORG INDEXES ALL FOR TABLE schema.orders ALLOW WRITE ACCESS;

-- 仅清理叶子层删除项（不重建中间节点）
REORG INDEXES ALL FOR TABLE schema.orders CLEANUP ONLY ALL;

-- 查询索引膨胀情况
SELECT
    INDSCHEMA, INDNAME, NLEAF, NLEVELS,
    NUM_EMPTY_LEAFS, NUMRIDS_DELETED, NUMRIDS,
    DECIMAL(NUMRIDS_DELETED * 100.0 / NULLIF(NUMRIDS, 0), 5, 2) AS DEL_PCT
FROM SYSCAT.INDEXES
WHERE TABNAME = 'ORDERS'
ORDER BY DEL_PCT DESC;

-- 调用 ADMIN_CMD 触发 REORG
CALL SYSPROC.ADMIN_CMD('REORG INDEXES ALL FOR TABLE schema.orders');
```

### TiDB / CockroachDB（LSM 不需要传统维护）

LSM 系数据库通过后台 compaction 持续维护索引，没有显式的 REBUILD 概念：

```sql
-- TiDB：仅在元数据不一致时使用
ADMIN CHECK INDEX orders idx_status;
ADMIN RECOVER INDEX orders idx_status;

-- 查看 region 信息（间接反映存储状态）
SHOW TABLE orders REGIONS;

-- 强制触发 region 分裂
SPLIT TABLE orders BY (1000), (2000), (3000);

-- CockroachDB：通过观察 store 健康状态
-- (无显式索引维护命令)
SELECT * FROM crdb_internal.kv_store_status;

-- 可以查看 LSM 层级
-- $ cockroach debug pebble metrics --store=...
```

### ClickHouse（OPTIMIZE 触发合并）

ClickHouse 的 MergeTree 索引（稀疏索引 + 跳数索引）通过 part 合并维护：

```sql
-- 触发指定表的合并（如果有多个 part）
OPTIMIZE TABLE events;

-- 强制全量合并到一个 part
OPTIMIZE TABLE events FINAL;

-- 仅合并指定分区
OPTIMIZE TABLE events PARTITION '2024-01' FINAL;

-- 去重合并（适用于 ReplacingMergeTree）
OPTIMIZE TABLE events DEDUPLICATE;

-- 监控合并状态
SELECT
    database, table, elapsed,
    progress, num_parts, source_part_names
FROM system.merges;

-- 监控 part 数量
SELECT
    database, table,
    count() AS parts,
    sum(rows) AS total_rows,
    sum(bytes_on_disk) AS total_bytes
FROM system.parts
WHERE active
GROUP BY database, table
ORDER BY parts DESC;

-- 跳数索引重建
ALTER TABLE events MATERIALIZE INDEX skipping_idx_user;
```

### Snowflake / BigQuery（完全自动）

云原生数据仓库不暴露任何索引维护接口：

```sql
-- Snowflake: 无 REBUILD 命令
-- micro-partition 由后台自动重组
-- 用户仅能影响 clustering key
ALTER TABLE events RECLUSTER;  -- 触发立即重新聚集

-- 查看 clustering 健康度
SELECT SYSTEM$CLUSTERING_INFORMATION('events', '(event_date)');

-- BigQuery: 无 REBUILD
-- 但可以重新创建分区表来触发数据重组
CREATE OR REPLACE TABLE dataset.events_new
PARTITION BY DATE(event_time)
CLUSTER BY user_id
AS SELECT * FROM dataset.events;
```

### Redshift（VACUUM REINDEX）

Redshift 的索引概念主要是 sort key + zone map：

```sql
-- 完整 VACUUM（重排序 + 删除）
VACUUM events;

-- 仅 REINDEX（重新生成 zone map）
VACUUM REINDEX events;

-- 仅排序（不删除已标记为删除的行）
VACUUM SORT ONLY events;

-- 监控未排序行的比例
SELECT
    "table" AS table_name,
    unsorted,
    tbl_rows,
    round(unsorted::numeric / NULLIF(tbl_rows, 0) * 100, 2) AS unsorted_pct
FROM svv_table_info
ORDER BY unsorted_pct DESC NULLS LAST;
```

## PostgreSQL REINDEX CONCURRENTLY 内部机制

PostgreSQL 12（2019 年）引入 `REINDEX CONCURRENTLY` 是社区多年讨论的成果，其内部实现是理解所有"在线索引重建"的最佳教材。

### 三阶段实现

```
阶段 1：创建并填充新索引（INVALID 状态）
  1. 申请 ShareUpdateExclusiveLock（不阻塞 DML，仅阻塞其他维护操作）
  2. 创建新索引（pg_index.indisvalid = false, indisready = false）
  3. 提交事务，释放锁

阶段 2：等待并行事务结束
  1. 等待所有持有可能修改源表的事务结束（通过 virtual XID wait）
  2. 标记新索引为 ready（indisready = true）
  3. 后续 DML 会同时维护新旧两个索引

阶段 3：等待所有事务能看到 ready 状态
  1. 再次等待并行事务
  2. 标记新索引为 valid（indisvalid = true）
  3. 标记旧索引为 INVALID
  4. 等待所有事务能看到 INVALID 状态
  5. DROP 旧索引，重命名新索引（短暂的 ShareUpdateExclusiveLock）
```

### 为什么会失败：INVALID 索引

如果 `REINDEX CONCURRENTLY` 在阶段 2 或 3 中途失败（例如违反唯一约束、连接断开），会留下一个 INVALID 索引：

```sql
-- 模拟失败场景：在 REINDEX 期间插入重复值
-- Session 1:
REINDEX INDEX CONCURRENTLY idx_users_email;
-- 假设此时 Session 2 插入了重复的 email
-- Session 1 报错: ERROR: could not create unique index

-- 检查：旧索引仍然 valid，新索引 INVALID
SELECT
    indexrelid::regclass, indisvalid, indisready
FROM pg_index
WHERE indrelid = 'users'::regclass;

-- 清理：必须 DROP INVALID 索引
DROP INDEX CONCURRENTLY idx_users_email_ccnew;
```

### 与 SQL Server / Oracle 在线重建的对比

| 维度 | PostgreSQL CONCURRENTLY | SQL Server ONLINE | Oracle REBUILD ONLINE |
|------|------------------------|-------------------|----------------------|
| 实现机制 | 三阶段（创建/ready/valid） | 双写 + 在线扫描 | 在线日志（journal） |
| 全表锁 | 短暂（< 100ms） | 短暂（< 100ms） | 短暂（< 1s） |
| 可中断/恢复 | 否（失败留 INVALID） | 是（2017+ RESUMABLE） | 否（失败需重做） |
| 内存需求 | 高（需双倍索引空间） | 高 | 高 |
| 失败处理 | 留 INVALID，需手动清理 | 自动回滚 | 自动回滚 |
| 影响 DML 性能 | 中（双写） | 中（双写） | 中（journal 写入） |
| 影响其他 DDL | 阻塞同表的其他 REINDEX/VACUUM | 阻塞同表的其他 ONLINE | 不阻塞 |
| 引入年份 | 2019 (12) | 2005 | 2001 (9i) |

### REINDEX CONCURRENTLY 的限制

```sql
-- 不能在事务块中执行
BEGIN;
REINDEX INDEX CONCURRENTLY idx_x;  -- ERROR: cannot run inside a transaction block
COMMIT;

-- 不能用于排他约束（exclusion constraint）
-- 不能用于系统目录（pg_catalog.* 索引）
REINDEX SYSTEM CONCURRENTLY mydb;  -- ERROR

-- 14+ 起支持 REINDEX TABLE CONCURRENTLY ... WITH (TABLESPACE = ...)
REINDEX TABLE CONCURRENTLY orders;
-- 等价于对 orders 表上每个索引依次执行 CONCURRENTLY

-- 17+ 起支持分区表整体的 CONCURRENTLY
REINDEX TABLE CONCURRENTLY orders_partitioned;
```

## 碎片化阈值：5%/30% 是怎么来的

Microsoft 文档和 Paul Randal（前 SQL Server 存储引擎架构师）提出的"5%/30%"经验阈值已经成为 SQL Server 索引维护的事实标准：

```
碎片率 < 5%      → 不做任何操作
5% ≤ 碎片率 < 30% → REORGANIZE（在线，轻量）
碎片率 ≥ 30%     → REBUILD（在线，重量）
```

### 阈值的物理意义

```
5% 阈值：
  对应约 5% 的页面分裂或物理乱序
  此时范围扫描的额外 I/O 通常 < 10%
  不值得花资源整理

30% 阈值：
  对应约 30% 的页面物理乱序
  范围扫描可能多 50%-100% 的随机 I/O
  REORGANIZE 一次只移动一个页，30% 以上需要的步骤过多
  REBUILD（一次性重排）反而更经济
```

### 阈值适用的前提条件

这个经验阈值有以下隐含假设：

1. **机械硬盘场景**（HDD 顺序 I/O 显著快于随机 I/O）
2. **范围扫描频繁**的工作负载
3. **页面大小 8KB**（SQL Server 默认）
4. **B+ 树结构**（不适用于 LSM、列存）

在 SSD/NVMe 时代，30% 阈值实际可以放宽到 50%-70%，因为随机 I/O 的代价远低于机械硬盘。许多公司已经将 REBUILD 阈值上调到 50%。

### 不同引擎的实际阈值建议

| 引擎 | REORGANIZE 阈值 | REBUILD 阈值 | 建议工具 |
|------|----------------|-------------|---------|
| SQL Server | 5%（avg_fragmentation_in_percent） | 30% | sys.dm_db_index_physical_stats |
| Oracle | 10%（DEL_LF_ROWS / LF_ROWS） | 25% | INDEX_STATS |
| PostgreSQL | -- | 30%（leaf_fragmentation） | pgstatindex |
| MySQL InnoDB | -- | 30%（data_free / total） | INFORMATION_SCHEMA.TABLES |
| DB2 | 5%（NUM_EMPTY_LEAFS） | 25% | SYSCAT.INDEXES |

## 索引膨胀（Bloat）的根因分析

### 不同存储引擎的膨胀机制

```
B+ 树（PostgreSQL/InnoDB/SQL Server/Oracle）:
  - 页分裂：插入引发页满，分裂后利用率降至 50%
  - 死索引项：MVCC 下的 UPDATE/DELETE 留下未清理项
  - HOT update（PG 优化）：避免索引重写但叶子页仍可能稀疏
  - 空闲空间不连续：DELETE 后的空间无法被有效利用

LSM（CockroachDB/TiDB/RocksDB）:
  - SSTable 重叠：同一 key 多版本散布在多层
  - 墓碑放大：DELETE 写入 tombstone，需要 compaction 才能消除
  - Write amplification：层级合并产生 10x-30x 的写入放大
  - 不存在传统的"页分裂"概念

列存（ClickHouse/Vertica/Parquet）:
  - 小 part 累积：流式写入产生大量小 part
  - 跳数索引粒度过细：mark 数膨胀拖慢查询
  - 分区文件碎片：按时间分区的旧数据维护成本

哈希索引（PG hash, MySQL MEMORY）:
  - bucket 倾斜：哈希冲突导致部分 bucket 过载
  - rehash 代价：扩容时全量重建
```

### PostgreSQL pgstattuple 实战

```sql
CREATE EXTENSION IF NOT EXISTS pgstattuple;

-- 表级膨胀分析
SELECT * FROM pgstattuple('orders');
-- 返回字段：
--   table_len            表总大小（字节）
--   tuple_count          活元组数
--   tuple_len            活元组总长度
--   tuple_percent        活元组占比
--   dead_tuple_count     死元组数
--   dead_tuple_len       死元组总长度
--   dead_tuple_percent   死元组占比 ← 关键指标
--   free_space           空闲空间（字节）
--   free_percent         空闲占比

-- 大表使用近似版本（采样，速度快）
SELECT * FROM pgstattuple_approx('orders');

-- 索引膨胀
SELECT * FROM pgstatindex('idx_orders_date');
-- 关键字段：
--   leaf_fragmentation   叶子页碎片率（百分比）
--   avg_leaf_density     平均叶子页密度
--   deleted_pages        已删除页数

-- 综合判断膨胀的脚本
SELECT
    schemaname, tablename, relname AS index_name,
    pg_size_pretty(pg_relation_size(schemaname || '.' || relname)) AS index_size,
    (pgstatindex(schemaname || '.' || relname)).leaf_fragmentation AS frag_pct,
    (pgstatindex(schemaname || '.' || relname)).avg_leaf_density AS density
FROM pg_stat_user_indexes
WHERE pg_relation_size(schemaname || '.' || relname) > 100 * 1024 * 1024  -- > 100MB
ORDER BY frag_pct DESC NULLS LAST;
```

## 索引维护与 VACUUM / GC 的关系

PostgreSQL 中索引维护与 VACUUM 是两个相关但独立的子系统：

```
VACUUM：
  - 标记表中死元组所在空间为可重用
  - 在索引中删除指向死元组的项（index cleanup）
  - 不重新组织索引结构
  - 不缩小索引大小

REINDEX：
  - 重新构建索引（从头扫描表）
  - 释放索引中的所有空闲空间
  - 自动获得最优的物理布局
  - 需要更多资源（时间、空间）
```

VACUUM 与索引维护的交互：

```sql
-- 完整 VACUUM 流程：
-- 1. 扫描表，找出死元组
-- 2. 扫描索引，找出指向死元组的项
-- 3. 删除索引项（不释放页面，仅标记删除）
-- 4. 标记表中死元组占用的空间为可重用

-- VACUUM 不会 REINDEX，索引可能仍然膨胀
VACUUM orders;

-- 显式索引维护
REINDEX TABLE CONCURRENTLY orders;

-- VACUUM FULL 等价于 REINDEX TABLE（重写整个表和所有索引）
VACUUM FULL orders;  -- 阻塞所有 DML
```

### 各引擎的"VACUUM == REINDEX"程度

| 引擎 | VACUUM 是否清理索引 | 是否释放索引空间 |
|------|-------------------|-----------------|
| PostgreSQL VACUUM | 是（删除死项） | 否（仅标记） |
| PostgreSQL VACUUM FULL | 是 | 是（重建） |
| MySQL InnoDB purge | 是（后台） | 否 |
| MySQL OPTIMIZE TABLE | 是 | 是（重建） |
| Oracle SMON / undo cleanup | 是 | 否 |
| Oracle ALTER INDEX REBUILD | -- | 是 |
| SQL Server ghost cleanup | 是 | 否 |
| SQL Server ALTER INDEX REBUILD | -- | 是 |
| Redshift VACUUM | 是（按 sort key） | 是 |
| Redshift VACUUM REINDEX | 是 | 是 |

详见 [vacuum-gc.md](vacuum-gc.md)。

## 关键发现

1. **没有 SQL 标准定义索引维护**。ISO/IEC 9075 完全不涉及，每个引擎按存储引擎特性发明自己的命令。

2. **在线重建已成标配**。Oracle 9i（2001）、SQL Server 2005、MySQL 5.6（2013）、DB2 9.7（2010）、PostgreSQL 12（2019）依次实现，目前主流 OLTP 数据库均支持不阻塞 DML 的索引重建。

3. **PostgreSQL 长期落后于商业数据库**。从 Oracle 引入 ONLINE REBUILD（2001）到 PG 引入 REINDEX CONCURRENTLY（2019），PG 落后了 18 年，主要因为 PG 的 MVCC 实现和 catalog 设计使得在线变更非常困难。

4. **REORGANIZE vs REBUILD 是 SQL Server 的独特概念**。仅 SQL Server、Oracle COALESCE、DB2 CLEANUP ONLY 区分轻量级与全量级维护；其他引擎只有 REBUILD 一种粒度。

5. **5%/30% 阈值的来源是 SQL Server 经验**。由 Microsoft 官方文档和 Paul Randal 推广，但严格来说仅适用于 HDD + B+ 树场景。SSD 时代该阈值过于保守，许多团队上调到 30%/50% 或更高。

6. **LSM 系数据库不需要传统索引维护**。CockroachDB、TiDB、YugabyteDB、ScyllaDB 通过持续后台 compaction 维护索引，没有用户可见的 REBUILD 命令。代价是写放大和不可预测的 compaction 风暴。

7. **云原生数据仓库完全黑盒**。Snowflake、BigQuery、Spanner、Materialize 不暴露索引维护接口，由内部自适应系统管理。优势是零运维，劣势是无法精细调优。

8. **MySQL InnoDB 没有显式 REBUILD INDEX**。所有索引维护都通过 `OPTIMIZE TABLE` 或 `ALTER TABLE ENGINE=InnoDB` 触发表级重写，因此无法仅维护单个索引。

9. **碎片监控工具差异巨大**。SQL Server 的 `sys.dm_db_index_physical_stats` 是事实标准；PostgreSQL 需要 `pgstattuple` 扩展；Oracle 需要先 `ANALYZE INDEX VALIDATE STRUCTURE` 才能查 `INDEX_STATS`；MySQL 仅有近似的 `INNODB_INDEX_STATS`。

10. **自动维护尚未在传统 OLTP 中普及**。Azure SQL Database 的 Auto-Tune、Aurora 的 Performance Insights 是少数走得最远的，但 PG/MySQL/Oracle/SQL Server 主线版本仍依赖 DBA 手动调度索引维护。

11. **REINDEX CONCURRENTLY 的失败处理是 PG 特有难题**。失败会留下 INVALID 索引，需要 DBA 手动 DROP 后重做；SQL Server RESUMABLE（2017+）和 Oracle REBUILD ONLINE 都有更优雅的失败恢复机制。

12. **填充率（FILLFACTOR / PCTFREE）是预防而非治疗**。所有 B+ 树引擎都支持设置叶子页填充率，但生产环境中默认 90%-100% 的设置最常见，真正按访问模式调整的极少。

13. **MyISAM REPAIR TABLE 仍在大量遗留系统中使用**。虽然 MyISAM 已基本淘汰，但 WordPress、phpMyAdmin 等场景仍有遗留 MyISAM 表，REPAIR TABLE 是这些 DBA 的日常操作。

14. **跨引擎迁移会遇到索引维护语义陷阱**。从 Oracle 迁移到 PG 的团队常被 `REINDEX CONCURRENTLY` 的失败语义困扰；从 SQL Server 迁移到 MySQL 的团队需要重新设计基于 `OPTIMIZE TABLE` 的维护策略。

15. **未来方向：自适应、可中断、可观测**。SQL Server 2017 的 RESUMABLE、Azure 的 Auto-Tune、Aurora 的 ML 驱动建议代表了下一代索引维护的方向：用户不再需要写"5%/30%"的阈值脚本，引擎根据实际工作负载和资源利用率自动调度。

## 相关文章

- [索引类型与创建语法](index-types-creation.md)：各引擎支持的索引类型与创建语法对比
- [VACUUM 与垃圾回收](vacuum-gc.md)：MVCC 引擎的死元组清理与空间回收

## 参考资料

- ISO/IEC 9075:2023 — 不涉及索引维护
- SQL Server: [Optimize index maintenance](https://learn.microsoft.com/en-us/sql/relational-databases/indexes/reorganize-and-rebuild-indexes)
- SQL Server: [sys.dm_db_index_physical_stats](https://learn.microsoft.com/en-us/sql/relational-databases/system-dynamic-management-views/sys-dm-db-index-physical-stats-transact-sql)
- Paul Randal: [Where do the Books Online index defragmentation thresholds come from?](https://www.sqlskills.com/blogs/paul/where-do-the-books-online-index-defragmentation-thresholds-come-from/)
- Oracle: [ALTER INDEX](https://docs.oracle.com/en/database/oracle/oracle-database/19/sqlrf/ALTER-INDEX.html)
- Oracle: [Monitoring Index Usage](https://docs.oracle.com/en/database/oracle/oracle-database/19/admin/managing-indexes.html)
- PostgreSQL: [REINDEX](https://www.postgresql.org/docs/current/sql-reindex.html)
- PostgreSQL: [pgstattuple](https://www.postgresql.org/docs/current/pgstattuple.html)
- PostgreSQL: [Building Indexes Concurrently](https://www.postgresql.org/docs/current/sql-createindex.html#SQL-CREATEINDEX-CONCURRENTLY)
- MySQL: [Online DDL Operations](https://dev.mysql.com/doc/refman/8.0/en/innodb-online-ddl-operations.html)
- MySQL: [OPTIMIZE TABLE](https://dev.mysql.com/doc/refman/8.0/en/optimize-table.html)
- DB2: [REORG INDEXES](https://www.ibm.com/docs/en/db2/11.5?topic=commands-reorg-indexes-table)
- ClickHouse: [OPTIMIZE](https://clickhouse.com/docs/en/sql-reference/statements/optimize)
- Redshift: [VACUUM](https://docs.aws.amazon.com/redshift/latest/dg/r_VACUUM_command.html)
- TiDB: [ADMIN CHECK INDEX](https://docs.pingcap.com/tidb/stable/sql-statement-admin-check-index)
- CockroachDB: [SCRUB](https://www.cockroachlabs.com/docs/stable/experimental-scrub.html)
- Snowflake: [Reclustering](https://docs.snowflake.com/en/user-guide/tables-clustering-keys)
- Brent Ozar: [Stop Worrying About SQL Server Index Fragmentation](https://www.brentozar.com/archive/2017/12/index-maintenance-madness/)
- Jonathan Lewis: "Cost-Based Oracle Fundamentals" (2006)
- Stéphane Faroult: "The Art of SQL" (2006)
