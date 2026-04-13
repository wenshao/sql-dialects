# 统计信息与直方图 (Statistics and Histograms)

如果优化器对 `WHERE status = 'PAID'` 估计为 100 行而实际是 1 亿行，再聪明的代价模型也只会输出灾难性的执行计划。统计信息与直方图正是连接"代价模型理论"和"真实数据分布"的唯一桥梁——它们决定了 90% 以上 SQL 性能问题的根因。

## 为什么基数估计如此重要

现代 SQL 优化器都是基于代价（Cost-Based Optimizer, CBO）。优化器在生成执行计划时需要回答几个核心问题：

1. **选择性估计**：`WHERE col = 'X'` 会过滤掉多少行？
2. **JOIN 基数估计**：两表 JOIN 后会输出多少行？
3. **聚合基数估计**：`GROUP BY col` 会产生多少个分组？
4. **数据倾斜识别**：某个值是否极端高频（MCV），需要特殊处理？
5. **JOIN 顺序选择**：先 JOIN 小表还是大表？
6. **JOIN 算法选择**：Hash Join、Merge Join、Nested Loop？
7. **索引选择**：走索引还是全表扫描？
8. **并行度决策**：是否启动并行扫描，使用多少线程？

所有这些决策的输入都是统计信息。统计信息错误一倍，执行计划就可能慢一千倍。Oracle 的 CBO、PostgreSQL 的 planner、SQL Server 的 query optimizer、MySQL 8.0 的优化器都遵循同样的逻辑。

统计信息通常包括：

- **表级统计**：行数（rowcount）、表大小（pages/blocks）、平均行宽
- **列级统计**：NULL 比例、distinct 值数量（n_distinct/NDV）、最小值、最大值、平均宽度
- **分布统计**：直方图（histogram）描述列值的整体分布
- **关联性**：列与物理存储顺序的相关性（correlation），影响索引扫描代价
- **多列统计**：列与列之间的依赖关系（如 city 和 zipcode 高度相关）
- **MCV 列表**：Most Common Values，处理数据倾斜的关键

直方图（histogram）是描述数据分布的核心数据结构，主要分为以下几种：

- **等宽直方图（Equi-width）**：将值域均匀切分为 N 段，统计每段行数。简单但不擅长倾斜数据
- **等深直方图（Equi-depth / Equi-height）**：每个桶包含大致相同的行数。倾斜友好
- **频率直方图（Frequency）**：列基数小时，每个 distinct 值一个桶。最精确
- **Top-Frequency**：保留 top-N 高频值，其余合并
- **混合直方图（Hybrid）**：等深直方图 + 端点频率，Oracle 12c 引入
- **MCV + Histogram 混合**：PostgreSQL 风格，先抽出 MCV 列表，剩余值再做等深直方图

本文不涉及 SQL 标准章节——统计信息与直方图完全是实现私有领域，ISO/IEC 9075 标准从未对其做任何规定。所有引擎的 ANALYZE / UPDATE STATISTICS 语法都是各自定义的。

## 支持矩阵

### ANALYZE / UPDATE STATISTICS 命令

| 引擎 | 命令语法 | 自动统计 | 默认开启 | 备注 |
|------|---------|---------|---------|------|
| PostgreSQL | `ANALYZE [VERBOSE] [table]` | autovacuum analyze | 是 | 触发阈值可配置 |
| MySQL | `ANALYZE TABLE t` | innodb_stats_auto_recalc | 是 | 默认开启 |
| MariaDB | `ANALYZE TABLE t [PERSISTENT FOR ALL]` | 是 | 是 | 持久化与即时统计 |
| SQLite | `ANALYZE [table]` | 否 | 否 | 手动执行，写入 sqlite_stat1 |
| Oracle | `DBMS_STATS.GATHER_TABLE_STATS` | AUTO_STATS_JOB | 是 | 11g 起内置维护窗口 |
| SQL Server | `UPDATE STATISTICS t` | auto_update_statistics | 是 | 阈值基于行数变化 |
| DB2 | `RUNSTATS ON TABLE t` | Auto Runstats | 是 | LUW 9.5+ 默认开启 |
| Snowflake | -- | 自动 | 是 | 完全托管，无用户控制 |
| BigQuery | -- | 自动 | 是 | 完全托管，无用户控制 |
| Redshift | `ANALYZE [table]` | Auto Analyze | 是 | 增量自动收集 |
| DuckDB | `ANALYZE` (有限支持) | -- | -- | 大多依赖运行时统计 |
| ClickHouse | -- | -- | -- | 没有传统统计，依赖索引粒度 |
| Trino | `ANALYZE table_name` | 否 | 否 | 写入 connector 元数据 |
| Presto | `ANALYZE table_name` | 否 | 否 | 同 Trino |
| Spark SQL | `ANALYZE TABLE t COMPUTE STATISTICS` | 否 | 否 | 需要手动触发 |
| Hive | `ANALYZE TABLE t COMPUTE STATISTICS` | 是（可配） | 否 | hive.stats.autogather |
| Flink SQL | `ANALYZE TABLE t COMPUTE STATISTICS` | 否 | 否 | 1.16+ 引入 |
| Databricks | `ANALYZE TABLE t COMPUTE STATISTICS` | Auto Optimize | 部分 | Delta Lake 自动维护 |
| Teradata | `COLLECT STATISTICS ON t` | 否 | 否 | 手动收集为主 |
| Greenplum | `ANALYZE [table]` | autovacuum analyze | 是 | 继承 PostgreSQL |
| CockroachDB | `CREATE STATISTICS name ON cols FROM t` | 自动 | 是 | 19.x+ |
| TiDB | `ANALYZE TABLE t` | 自动 | 是 | tidb_enable_auto_analyze |
| OceanBase | `ANALYZE TABLE t` / `DBMS_STATS` | 自动 | 是 | 兼容 Oracle 与 MySQL 双模式 |
| YugabyteDB | `ANALYZE [table]` | 否 | 否 | 继承 PostgreSQL 语法但默认关闭 |
| SingleStore | `ANALYZE TABLE t` | 自动 | 是 | columnstore 自动维护 |
| Vertica | `ANALYZE_STATISTICS('t')` | 否 | 否 | 显式调用 |
| Impala | `COMPUTE STATS t` | 否 | 否 | 也支持 COMPUTE INCREMENTAL STATS |
| StarRocks | `ANALYZE TABLE t` | 自动 | 是 | 2.5+ 引入 CBO |
| Doris | `ANALYZE TABLE t` | 自动 | 是 | 2.0+ 完整 CBO |
| MonetDB | `ANALYZE [schema.table]` | 否 | 否 | 显式触发 |
| CrateDB | `ANALYZE` | 自动 | 是 | 后台周期收集 |
| TimescaleDB | `ANALYZE [table]` | autovacuum analyze | 是 | 继承 PostgreSQL |
| QuestDB | -- | -- | -- | 没有传统统计 |
| Exasol | -- | 自动 | 是 | 内部维护，无用户接口 |
| SAP HANA | `CREATE STATISTICS` / `REFRESH STATISTICS` | 自动 | 是 | data statistics object |
| Informix | `UPDATE STATISTICS` | 否 | 否 | 经典语法 |
| Firebird | `SET STATISTICS INDEX` | 否 | 否 | 仅索引选择性 |
| H2 | `ANALYZE` | 否 | 否 | 简单实现 |
| HSQLDB | -- | -- | -- | 不支持显式 ANALYZE |
| Derby | `CALL SYSCS_UTIL.SYSCS_UPDATE_STATISTICS` | 否 | 否 | 系统过程调用 |
| Amazon Athena | `ANALYZE TABLE` | 否 | 否 | 继承 Trino |
| Azure Synapse | `UPDATE STATISTICS` / `CREATE STATISTICS` | 自动 | 部分 | Dedicated SQL Pool |
| Google Spanner | -- | 自动 | 是 | 完全托管 |
| Materialize | -- | -- | -- | 没有传统统计概念 |
| RisingWave | -- | -- | -- | 流式系统不依赖批量统计 |
| InfluxDB (SQL) | -- | -- | -- | 时序数据库无传统统计 |
| DatabendDB | `ANALYZE TABLE t` | 自动 | 是 | snapshot 级统计 |
| Yellowbrick | `ANALYZE [table]` | 自动 | 是 | 兼容 PostgreSQL |
| Firebolt | -- | 自动 | 是 | 完全托管 |

> 统计：约 38 个引擎提供某种 ANALYZE/UPDATE STATISTICS 命令，约 25 个具备自动统计收集能力。云原生托管服务（Snowflake、BigQuery、Spanner、Firebolt）通常完全屏蔽了用户控制。

### 直方图类型支持矩阵

| 引擎 | 等深 | 等宽 | 频率 | 混合 | MCV | 默认类型 |
|------|------|------|------|------|-----|---------|
| PostgreSQL | 是 | -- | -- | -- | 是 | 等深 + MCV |
| MySQL | 是 | 是 | -- | -- | -- | SINGLETON 或 EQUI-HEIGHT |
| MariaDB | 是 | -- | -- | -- | -- | 等高（DOUBLE_PREC_HB） |
| SQLite | -- | -- | -- | -- | -- | 仅 sqlite_stat1 行数 |
| Oracle | 是 (height-balanced) | -- | 是 | 是 (12c+) | top-frequency | 自动选择 |
| SQL Server | 是 | -- | -- | -- | -- | 等深（最多 200 step） |
| DB2 | 是 | -- | 是 | -- | 是 (quantiles) | 等深 |
| Snowflake | 内部 | -- | -- | -- | -- | 不暴露 |
| BigQuery | 内部 | -- | -- | -- | -- | 不暴露 |
| Redshift | 内部 | -- | -- | -- | -- | 不暴露 |
| DuckDB | -- | -- | -- | -- | -- | 仅基础统计 |
| ClickHouse | -- | -- | -- | -- | -- | 索引粒度替代 |
| Trino | -- | -- | -- | -- | -- | min/max/NDV |
| Presto | -- | -- | -- | -- | -- | min/max/NDV |
| Spark SQL | 是 | -- | -- | -- | -- | 等深（3.0+） |
| Hive | -- | -- | -- | -- | -- | 仅 NDV/min/max |
| Flink SQL | -- | -- | -- | -- | -- | 仅基础统计 |
| Databricks | 是 | -- | -- | -- | -- | 等深 |
| Teradata | 是 | -- | 是 | -- | 是 | 等深 + biased values |
| Greenplum | 是 | -- | -- | -- | 是 | 继承 PG |
| CockroachDB | 是 | -- | -- | -- | -- | 等深（20.1+） |
| TiDB | 是 | -- | -- | -- | 是 (CMSketch) | 等深 + Top-N |
| OceanBase | 是 | -- | 是 | 是 | 是 | 多种自动选择 |
| YugabyteDB | 是 | -- | -- | -- | 是 | 继承 PG |
| SingleStore | 是 | -- | -- | -- | -- | 等深 |
| Vertica | 是 | -- | -- | -- | -- | 等深 |
| Impala | -- | -- | -- | -- | -- | 仅 NDV/min/max |
| StarRocks | 是 | -- | -- | -- | 是 | 等深 + MCV |
| Doris | 是 | -- | -- | -- | 是 | 等深 + MCV |
| MonetDB | -- | -- | -- | -- | -- | min/max |
| CrateDB | 是 | -- | -- | -- | 是 | 继承 Lucene |
| TimescaleDB | 是 | -- | -- | -- | 是 | 继承 PG |
| QuestDB | -- | -- | -- | -- | -- | 时序索引替代 |
| Exasol | 是 | -- | -- | -- | -- | 内部 |
| SAP HANA | 是 | -- | -- | -- | -- | data statistics object 多种类型 |
| Informix | 是 | -- | -- | -- | -- | distribution |
| Firebird | -- | -- | -- | -- | -- | 仅索引选择性 |
| H2 | -- | -- | -- | -- | -- | 仅基础统计 |
| HSQLDB | -- | -- | -- | -- | -- | 不支持 |
| Derby | -- | -- | -- | -- | -- | 不支持 |
| Amazon Athena | -- | -- | -- | -- | -- | 继承 Trino |
| Azure Synapse | 是 | -- | -- | -- | -- | 继承 SQL Server |
| Google Spanner | -- | -- | -- | -- | -- | 内部 |
| Materialize | -- | -- | -- | -- | -- | -- |
| RisingWave | -- | -- | -- | -- | -- | -- |
| InfluxDB | -- | -- | -- | -- | -- | -- |
| DatabendDB | -- | -- | -- | -- | -- | NDV / min / max |
| Yellowbrick | 是 | -- | -- | -- | 是 | 继承 PG |
| Firebolt | -- | -- | -- | -- | -- | 不暴露 |

### 扩展统计 / 多列统计

| 引擎 | 多列依赖 | 多列 NDV | 多列 MCV | 表达式统计 | 命令/语法 |
|------|---------|---------|---------|----------|----------|
| PostgreSQL | 是 | 是 | 是 | 是 (14+) | `CREATE STATISTICS` (10+) |
| MySQL | -- | -- | -- | -- | -- |
| MariaDB | -- | -- | -- | -- | -- |
| SQLite | -- | -- | -- | -- | -- |
| Oracle | 是 | 是 | -- | 是 | `DBMS_STATS.CREATE_EXTENDED_STATS` |
| SQL Server | -- | -- | -- | 是 (computed col) | 计算列上的索引/统计 |
| DB2 | 是 | 是 | -- | 是 | `RUNSTATS ON COLUMN GROUP` |
| Snowflake | 内部 | -- | -- | -- | -- |
| BigQuery | -- | -- | -- | -- | -- |
| Redshift | -- | -- | -- | -- | -- |
| DuckDB | -- | -- | -- | -- | -- |
| Trino | -- | -- | -- | -- | -- |
| Spark SQL | -- | -- | -- | -- | -- |
| Hive | -- | -- | -- | -- | -- |
| Databricks | -- | -- | -- | -- | -- |
| Teradata | 是 | 是 | 是 | 是 | `COLLECT STATISTICS ON (col1, col2)` |
| Greenplum | 是 | -- | -- | -- | 继承 PG |
| CockroachDB | 是 | 是 | -- | -- | `CREATE STATISTICS ... ON (a, b)` |
| TiDB | -- | -- | -- | -- | -- |
| OceanBase | 是 | 是 | -- | 是 | DBMS_STATS 兼容 Oracle |
| YugabyteDB | 是 | -- | -- | -- | 继承 PG |
| SAP HANA | 是 | 是 | -- | 是 | data statistics object |
| StarRocks | -- | -- | -- | -- | -- |
| Doris | -- | -- | -- | -- | -- |
| Vertica | -- | -- | -- | -- | -- |
| SingleStore | -- | -- | -- | -- | -- |
| Azure Synapse | -- | -- | -- | -- | 继承 SQL Server |

> 统计：扩展（多列）统计的支持远不如单列统计普及，仅约 12 个引擎提供。PostgreSQL `CREATE STATISTICS`、Oracle `DBMS_STATS.CREATE_EXTENDED_STATS`、Teradata `COLLECT STATISTICS ON (a, b)` 是其中最成熟的实现。

### 分区表与采样配置

| 引擎 | 分区级统计 | 增量统计 | 采样比例配置 | bucket 数量配置 | 列级配置 |
|------|----------|---------|-------------|----------------|---------|
| PostgreSQL | 是 | -- | `default_statistics_target` | `default_statistics_target` (1-10000) | `ALTER TABLE ... ALTER COLUMN ... SET STATISTICS n` |
| MySQL | -- | -- | `innodb_stats_persistent_sample_pages` | `histogram_generation_max_mem_size` 间接 | `WITH N BUCKETS` (1-1024) |
| MariaDB | -- | -- | `analyze_sample_percentage` | `histogram_size` (1-255) | -- |
| Oracle | 是 (incremental) | 是 | `estimate_percent` | `method_opt 'FOR COLUMNS SIZE n'` (1-2048/254) | per column 设置 |
| SQL Server | 是 | 是 (incremental) | `WITH SAMPLE n PERCENT` | 固定 200 step | 通过 `CREATE STATISTICS` |
| DB2 | 是 | -- | `WITH SAMPLING` | `NUM_QUANTILES` | per column |
| Snowflake | 内部 | -- | -- | -- | -- |
| BigQuery | -- | -- | -- | -- | -- |
| Redshift | -- | 是 | `analyze_threshold_percent` | -- | -- |
| Trino | -- | -- | -- | -- | -- |
| Spark SQL | 是 | -- | -- | `spark.sql.statistics.histogram.numBins` (默认 254) | per column |
| Hive | 是 | -- | -- | -- | per column |
| Databricks | 是 | -- | -- | -- | -- |
| Teradata | 是 | 是 (USING) | `USING SAMPLE n PERCENT` | -- | per column |
| Greenplum | 是 | -- | `default_statistics_target` | -- | per column |
| CockroachDB | -- | -- | -- | `sql.stats.histogram_buckets.count` | -- |
| TiDB | 是 | -- | `tidb_analyze_version` | `tidb_analyze_distsql_scan_concurrency` | `STATS_BUCKETS` 视图 |
| OceanBase | 是 | 是 | `estimate_percent` | `method_opt` | per column |
| Vertica | 是 | -- | `PERCENT n` | -- | per column |
| Impala | 是 | 是 (INCREMENTAL) | `TABLESAMPLE SYSTEM` | -- | per column |
| StarRocks | 是 | -- | `statistic_sample_collect_rows` | -- | per column |
| Doris | 是 | 是 | `analyze.sample.rows` | -- | per column |
| Azure Synapse | 是 | -- | `WITH SAMPLE` | 固定 200 | per column |
| SAP HANA | 是 | -- | `WITH SAMPLE` | 可配 | per column |

## 关键引擎深度解析

### PostgreSQL：pg_statistic 与 default_statistics_target

PostgreSQL 的统计信息存储在系统目录 `pg_statistic` 中，可以通过视图 `pg_stats` 查看友好版本。

```sql
-- 收集统计信息
ANALYZE;                         -- 全库
ANALYZE orders;                  -- 单表
ANALYZE orders (customer_id);    -- 单列
ANALYZE VERBOSE orders;          -- 显示详细信息

-- 查看默认采样目标
SHOW default_statistics_target;  -- 默认 100

-- 修改全局采样目标
SET default_statistics_target = 500;

-- 修改单列采样目标（覆盖全局）
ALTER TABLE orders ALTER COLUMN customer_id SET STATISTICS 1000;

-- 查看统计
SELECT attname, n_distinct, null_frac, most_common_vals, most_common_freqs,
       histogram_bounds, correlation
FROM pg_stats
WHERE tablename = 'orders';
```

PostgreSQL 的核心设计：

- `default_statistics_target` 默认值 **100**，最大 **10000**
- 该值同时控制 MCV 列表的最大长度和直方图的桶数量
- 采样行数 = `300 * statistics_target`（所以默认采样 30000 行）
- 大表上若数据倾斜严重，建议将关键列的目标提高到 1000~5000

#### CREATE STATISTICS：多列扩展统计（10+）

PostgreSQL 10 引入 `CREATE STATISTICS`，解决多列相关性导致的基数估计误差。

```sql
-- 创建多列函数依赖统计
CREATE STATISTICS stats_city_zip (dependencies)
    ON city, zip FROM addresses;

-- 创建多列 NDV 统计
CREATE STATISTICS stats_city_zip_ndv (ndistinct)
    ON city, state, zip FROM addresses;

-- 创建多列 MCV 列表（PG 12+）
CREATE STATISTICS stats_city_zip_mcv (mcv)
    ON city, zip FROM addresses;

-- 表达式统计（PG 14+）
CREATE STATISTICS stats_lower_email (mcv)
    ON lower(email) FROM users;

ANALYZE addresses;  -- 必须 ANALYZE 后才生效
```

#### pg_statistic 字段深度解读

`pg_stats` 视图的关键字段：

| 字段 | 含义 |
|------|------|
| `n_distinct` | distinct 值数。正数表示绝对值，负数表示比例（-1 表示完全唯一） |
| `null_frac` | NULL 值占比（0~1） |
| `avg_width` | 该列平均字节宽度 |
| `most_common_vals` | MCV 列表（数组） |
| `most_common_freqs` | MCV 对应频率（数组） |
| `histogram_bounds` | 等深直方图的桶边界（数组）|
| `correlation` | 物理顺序与逻辑顺序的相关性（-1 到 1），影响索引扫描代价 |
| `most_common_elems` | 数组列的元素 MCV |
| `most_common_elem_freqs` | 数组元素 MCV 频率 |
| `elem_count_histogram` | 数组长度直方图 |

PostgreSQL 的直方图与 MCV 是**分开存储**的：先抽取出 MCV 列表，剩余值再做等深直方图。这种"MCV + 等深直方图"混合方案兼顾了倾斜数据和均匀数据的精度。

### Oracle：DBMS_STATS 与四种直方图

Oracle 的统计信息收集主要通过 `DBMS_STATS` 包（自 8i 引入），取代了早期的 `ANALYZE` 语句。

```sql
-- 收集表统计
EXEC DBMS_STATS.GATHER_TABLE_STATS(
    ownname    => 'SCOTT',
    tabname    => 'EMPLOYEES',
    estimate_percent => DBMS_STATS.AUTO_SAMPLE_SIZE,
    method_opt => 'FOR ALL COLUMNS SIZE AUTO',
    cascade    => TRUE
);

-- 收集 schema 统计
EXEC DBMS_STATS.GATHER_SCHEMA_STATS(ownname => 'SCOTT');

-- 收集数据库统计
EXEC DBMS_STATS.GATHER_DATABASE_STATS();

-- 创建扩展统计：多列
SELECT DBMS_STATS.CREATE_EXTENDED_STATS('SCOTT', 'EMPLOYEES', '(department_id, job_id)') FROM DUAL;

-- 创建扩展统计：表达式
SELECT DBMS_STATS.CREATE_EXTENDED_STATS('SCOTT', 'EMPLOYEES', '(LOWER(last_name))') FROM DUAL;

-- 自动统计任务
-- 11g 起内置 AUTO_STATS_JOB，每天维护窗口运行
SELECT job_name, enabled FROM dba_autotask_client WHERE client_name = 'auto optimizer stats collection';
```

#### Oracle 的四种直方图类型

Oracle 是直方图实现最复杂的商业数据库，根据数据特征自动选择四种类型之一：

| 类型 | 触发条件 | 适用场景 |
|------|---------|---------|
| **Frequency** | NDV ≤ bucket 数量（默认 254） | 列基数小、每个值都能记录 |
| **Top-Frequency** | NDV > buckets 但 top-N 值占比 > 99% | 长尾分布，少数高频值 |
| **Height-Balanced**（等深）| 11g 及更早默认 | 通用倾斜数据 |
| **Hybrid** | 12c 引入，取代 height-balanced | 兼顾等深 + 端点频率 |

Oracle 12c 的混合直方图（Hybrid Histogram）是一项重要改进：每个桶记录端点值的频率，避免了 height-balanced 直方图在桶边界处对高频值的低估。

```sql
-- 显式指定直方图
EXEC DBMS_STATS.GATHER_TABLE_STATS('SCOTT', 'EMPLOYEES',
    method_opt => 'FOR COLUMNS SIZE 254 SALARY');

-- method_opt SIZE 取值：
--   1            -- 不收集直方图
--   AUTO         -- 自动决定
--   REPEAT       -- 重新收集已存在直方图的列
--   SKEWONLY     -- 仅倾斜列收集
--   1-2048       -- 显式 bucket 数（10g+ 上限 254，12c+ 部分情况下 2048）

-- 查看直方图类型
SELECT column_name, histogram, num_buckets
FROM user_tab_col_statistics
WHERE table_name = 'EMPLOYEES';
```

### SQL Server：UPDATE STATISTICS 与 201 桶限制

SQL Server 的统计信息系统是其 CBO 的核心，由 `UPDATE STATISTICS`、`CREATE STATISTICS`、`sp_autostats` 等命令管理。

```sql
-- 创建命名统计对象
CREATE STATISTICS stats_orders_customer
    ON dbo.Orders(CustomerID) WITH FULLSCAN;

-- 更新统计
UPDATE STATISTICS dbo.Orders;
UPDATE STATISTICS dbo.Orders stats_orders_customer WITH FULLSCAN;
UPDATE STATISTICS dbo.Orders WITH SAMPLE 30 PERCENT;
UPDATE STATISTICS dbo.Orders WITH RESAMPLE;

-- 查看自动更新设置
EXEC sp_autostats 'dbo.Orders';

-- 启用自动更新
EXEC sp_autostats 'dbo.Orders', 'ON';

-- 数据库级开关
ALTER DATABASE MyDB SET AUTO_UPDATE_STATISTICS ON;
ALTER DATABASE MyDB SET AUTO_CREATE_STATISTICS ON;
ALTER DATABASE MyDB SET AUTO_UPDATE_STATISTICS_ASYNC ON;

-- 查看统计内容
DBCC SHOW_STATISTICS('dbo.Orders', stats_orders_customer);
```

#### 201 桶限制及其影响

SQL Server 的统计直方图**最多只有 200 个 step + 1 个边界**，总共 201 个值。这个限制自 SQL Server 7.0 起一直存在，无法配置。

**影响：**

1. 对 1 亿行的高基数列，每个直方图桶平均覆盖 50 万行，颗粒度极粗
2. 数据倾斜场景下容易导致严重低估
3. SQL Server 用 `RANGE_HI_KEY`、`RANGE_ROWS`、`EQ_ROWS`、`DISTINCT_RANGE_ROWS` 四个字段补偿桶内细节，但仍然有限
4. 对很高基数列，建议结合**过滤统计（filtered statistics）**使用，每个倾斜值或区段单独建一个统计对象

```sql
-- 过滤统计：针对热点值单独维护
CREATE STATISTICS stats_orders_high_priority
    ON dbo.Orders(CustomerID)
    WHERE Status = 'PENDING' AND Priority = 'HIGH';

-- 增量统计（分区表）：仅更新被修改的分区
CREATE STATISTICS stats_orders_inc
    ON dbo.Orders(OrderDate) WITH INCREMENTAL = ON;

UPDATE STATISTICS dbo.Orders stats_orders_inc
    WITH RESAMPLE ON PARTITIONS(3, 4);
```

SQL Server 2014 引入新基数估计器（New Cardinality Estimator, NewCE），改进了对多谓词独立性的假设。SQL Server 2016+ 起，自动统计的更新阈值改为按 `SQRT(1000 * rows)` 计算，比早期固定 20% 更敏感。

### MySQL：8.0.3 起的直方图支持

MySQL 在 8.0.3（2017 年末）才引入直方图支持，迟到了几十年但终于补上。

```sql
-- 收集表统计（基础）
ANALYZE TABLE orders;

-- 收集列直方图
ANALYZE TABLE orders UPDATE HISTOGRAM ON customer_id, status WITH 1024 BUCKETS;

-- 默认 100 桶
ANALYZE TABLE orders UPDATE HISTOGRAM ON status;

-- 删除直方图
ANALYZE TABLE orders DROP HISTOGRAM ON customer_id;

-- 查看
SELECT * FROM information_schema.column_statistics
WHERE table_name = 'orders';
```

MySQL 直方图的特点：

- **bucket 数量**：1 ~ 1024（默认 100）
- **两种实现**：当 distinct 值 ≤ bucket 数时用 `singleton`（频率直方图），否则用 `equi-height`（等高/等深）
- **不更新索引列**：MySQL 索引已有自己的统计，所以直方图主要面向**未建索引的列**
- **手动维护**：MySQL 直方图不会随 `ANALYZE TABLE` 自动重建，需要显式 `UPDATE HISTOGRAM`
- **innodb_stats_persistent_sample_pages**：控制 InnoDB 持久化统计的采样页数（默认 20）

### MariaDB：等高(height-balanced)直方图 (10.0+，早于 MySQL)

MariaDB 早在 10.0 就引入了直方图（`DOUBLE_PREC_HB` 为等高/height-balanced 实现），但实现完全不同于 MySQL：

```sql
-- 收集持久化统计（包括直方图）
ANALYZE TABLE orders PERSISTENT FOR ALL;

-- 收集指定列的统计
ANALYZE TABLE orders PERSISTENT FOR COLUMNS (customer_id, status) INDEXES ALL;

-- 设置直方图大小
SET GLOBAL histogram_size = 254;
SET GLOBAL histogram_type = DOUBLE_PREC_HB;  -- 默认；也可 SINGLE_PREC_HB

-- 查看
SELECT * FROM mysql.column_stats WHERE table_name = 'orders';
```

MariaDB 直方图的关键特点：

- **类型**：默认 `DOUBLE_PREC_HB`（双精度等高 (height-balanced/equi-depth)）或 `SINGLE_PREC_HB`
- **存储**：`mysql.column_stats` 系统表
- **histogram_size**：1 ~ 255 桶
- 与 MySQL 相比，MariaDB 直方图更早出现但接受度较低，许多查询模式下精度不如 MySQL 8.0 的等深方案

### TiDB：等深 + Top-N + CMSketch

TiDB 的统计信息系统经过多次重构，v5.3 起统称 `analyze_version=2`，是分布式数据库中最完善的实现之一。

```sql
-- 收集统计
ANALYZE TABLE orders;
ANALYZE TABLE orders WITH 1024 BUCKETS, 1024 TOPN, 8 SAMPLES;

-- 自动收集
SET GLOBAL tidb_enable_auto_analyze = ON;
SET GLOBAL tidb_auto_analyze_ratio = 0.5;
SET GLOBAL tidb_auto_analyze_start_time = '00:00 +0800';
SET GLOBAL tidb_auto_analyze_end_time = '06:00 +0800';

-- 并行度
SET GLOBAL tidb_build_stats_concurrency = 4;
SET GLOBAL tidb_distsql_scan_concurrency = 15;

-- 查看统计
SHOW STATS_META;
SHOW STATS_HISTOGRAMS;
SHOW STATS_BUCKETS;
SHOW STATS_TOPN;
```

TiDB 的关键设计：

- **等深直方图 + Top-N**：高频值进入 Top-N 列表，剩余值做等深直方图（类似 PostgreSQL 的 MCV + histogram）
- **CMSketch（Count-Min Sketch）**：v4.0 起取消默认（v5.1+ 移除），改为更精确的 Top-N
- **analyze_version=2**：v5.1+ 默认，改进了 NDV 估计与多列 JOIN 估计精度
- **样本量**：默认 10000 行，可通过 `tidb_analyze_distsql_scan_concurrency` 加速

### CockroachDB：CREATE STATISTICS（19.x+）

CockroachDB 较晚才引入 CBO，统计基础设施在 19.x 阶段建立，直方图支持在 20.1 引入。

```sql
-- 显式创建统计
CREATE STATISTICS my_stats ON name, age FROM users;

-- 多列统计
CREATE STATISTICS combined_stats ON city, state FROM users;

-- 查看统计
SHOW STATISTICS FOR TABLE users;
SHOW STATISTICS FOR TABLE users WITH HISTOGRAM;

-- 自动统计设置
SET CLUSTER SETTING sql.stats.automatic_collection.enabled = true;
SET CLUSTER SETTING sql.stats.histogram_collection.enabled = true;
SET CLUSTER SETTING sql.stats.histogram_buckets.count = 200;
```

CockroachDB 的特点：

- **自动统计**：默认开启，行数变化达到阈值时触发
- **直方图**：20.1+ 默认收集，每列最多 200 桶
- **多列统计**：用于多列选择性估计，但不支持依赖关系建模
- **JOIN cardinality**：使用直方图相交（histogram intersection）算法

### ClickHouse：没有传统统计

ClickHouse 的设计哲学与传统 OLTP/OLAP 不同：它**没有等深直方图、没有 MCV 列表**，而是依赖 MergeTree 的稀疏主键索引和数据跳过索引（skip index）。

```sql
-- 创建表时指定索引粒度
CREATE TABLE events (
    event_time DateTime,
    user_id UInt64,
    event_type String
) ENGINE = MergeTree()
ORDER BY (event_time, user_id)
SETTINGS index_granularity = 8192;

-- 数据跳过索引（min-max、set、bloom_filter）
ALTER TABLE events ADD INDEX idx_event_type event_type TYPE set(100) GRANULARITY 4;

-- 查询时优化器靠以下信息估算：
--   - 分区裁剪
--   - primary key prewhere
--   - skip index
--   - column compression metadata
```

ClickHouse 23.x 引入实验性的列统计（`ALTER TABLE ... MODIFY COLUMN ... STATISTIC`），可创建 `tdigest` 类型估算 percentile 和 cardinality，但仍然远未成为主流路径。

### Snowflake / BigQuery / Spanner：完全托管

云原生托管数据库的设计原则是"零运维"：

- **Snowflake**：micro-partition 元数据自动维护 min/max/null/distinct，用户不可见、不可调；底层基于 cardinality estimation algorithm（HLL）
- **BigQuery**：column statistics 完全由后端维护，没有 ANALYZE 命令；查询计划基于动态执行统计反馈
- **Google Spanner**：基于 ML 的 Adaptive Optimizer，2022 年引入，根据查询历史自动调整

这种设计的代价是用户**完全失去了对统计的控制**：无法强制更新、无法查看直方图、无法手工纠正基数估计错误。对绝大多数用户这是优点，但少数极端场景下可能成为问题。

### Spark SQL / Databricks：等深直方图（3.0+）

```sql
-- 表级统计
ANALYZE TABLE orders COMPUTE STATISTICS;

-- 列级统计（含直方图，3.0+ 需显式开启）
SET spark.sql.statistics.histogram.enabled = true;
SET spark.sql.statistics.histogram.numBins = 254;

ANALYZE TABLE orders COMPUTE STATISTICS FOR COLUMNS customer_id, status;

-- 查看
DESCRIBE EXTENDED orders;
DESCRIBE EXTENDED orders customer_id;
```

Spark SQL 的 CBO 默认是关闭的，需要 `spark.sql.cbo.enabled=true` 才会读取统计信息进行 JOIN 重排序与代价估计。Databricks Runtime 默认开启了 Auto Optimize，对 Delta Lake 表自动维护 file statistics。

### Trino / Presto：connector 元数据

Trino 自身不存储统计，而是从 connector（Hive、Iceberg、Delta、PostgreSQL 等）的元数据中读取：

```sql
-- 显式触发收集
ANALYZE hive.web.events;

-- 查看
SHOW STATS FOR hive.web.events;
SHOW STATS FOR (SELECT * FROM hive.web.events WHERE ds = '2024-01-01');
```

Trino 主要使用 NDV、min/max、null fraction 进行选择性估算，没有传统直方图。当 connector 支持时（如 Iceberg），Trino 会读取列级 lower/upper bound 进行分区裁剪。

### Vertica、Teradata、SAP HANA：MPP 商业方案

```sql
-- Vertica
SELECT ANALYZE_STATISTICS('public.orders');
SELECT ANALYZE_STATISTICS_PARTITION('public.orders', '2024-01-01', '2024-12-31');

-- Teradata
COLLECT STATISTICS COLUMN (customer_id) ON orders;
COLLECT STATISTICS COLUMN (customer_id, region) ON orders;
COLLECT STATISTICS USING SAMPLE 5 PERCENT ON orders;

-- SAP HANA
CREATE STATISTICS ON orders (customer_id) TYPE HISTOGRAM;
REFRESH STATISTICS ON orders;
```

这三家 MPP 厂商都支持多列统计、采样比例配置、分区级统计——这是商业 MPP 的标准能力。Teradata 的 `COLLECT STATISTICS USING SAMPLE` 和 `COLLECT STATISTICS USING NO SAMPLE` 是其标志性特性。

### StarRocks 与 Doris：新一代 MPP 的 CBO

```sql
-- StarRocks
ANALYZE TABLE orders;
ANALYZE FULL TABLE orders;
SET GLOBAL enable_auto_collect_statistics = true;

-- Doris
ANALYZE TABLE orders;
ANALYZE TABLE orders WITH SAMPLE PERCENT 10;
SET GLOBAL enable_auto_analyze = true;
```

StarRocks 2.5+ 与 Doris 2.0+ 都构建了完整的 CBO 与统计基础设施，包含等深直方图 + MCV 混合方案，性能与 PostgreSQL 接近。它们是开源 MPP 中统计实现最积极的两家。

### Redshift：增量自动收集

```sql
-- 显式收集
ANALYZE orders;
ANALYZE orders PREDICATE COLUMNS;  -- 仅 WHERE 中出现过的列

-- 配置自动 ANALYZE 阈值
SET analyze_threshold_percent TO 0.01;  -- 行数变化 1% 触发

-- 查看
SELECT * FROM stv_tbl_perm WHERE name = 'orders';
SELECT * FROM svv_table_info WHERE "table" = 'orders';
```

Redshift 的 `PREDICATE COLUMNS` 是聪明的优化：只收集查询中真正使用过的列的统计，节省了大量 ANALYZE 时间。

### DuckDB：嵌入式分析的取舍

DuckDB 的 `ANALYZE` 命令存在但功能有限。作为单进程嵌入式数据库，DuckDB 更倾向于在查询执行时动态收集统计（runtime statistics），并通过 vectorized execution 弥补静态统计不足。这与 ClickHouse 思路类似。

## 关键发现

经过对 45+ 数据库的横向对比，可以总结出以下规律：

1. **统计信息是 CBO 的命脉**：所有具备代价模型优化器的引擎都必须维护统计信息。SQLite、ClickHouse、QuestDB、Materialize 等没有传统 CBO 的引擎可以省略，但代价是查询计划质量受限。

2. **PostgreSQL 是直方图设计的事实标准**：MCV + 等深直方图的混合方案被 Greenplum、TimescaleDB、CockroachDB、TiDB、StarRocks、Doris、YugabyteDB 大量借鉴。这种"先抽倾斜、再做直方图"的设计兼顾了倾斜与均匀分布。

3. **Oracle 拥有最复杂的直方图体系**：四种类型自动选择（frequency / top-frequency / height-balanced / hybrid），加上扩展统计、AUTO_STATS_JOB、incremental statistics——是商业 RDBMS 中统计能力最深的代表。12c 引入的 hybrid histogram 修复了 height-balanced 在桶边界处的低估问题。

4. **SQL Server 的 201 桶限制是历史包袱**：自 1998 年以来未曾改变，导致高基数列上需要依赖过滤统计、incremental statistics、新 CE 来弥补。这是 SQL Server CBO 的最大短板。

5. **MySQL 直到 2017 年才有直方图**：8.0.3 引入 ANALYZE TABLE UPDATE HISTOGRAM，但仍需手动维护，不会自动重建。MariaDB 早 4 年支持但实现质量不及 MySQL 8.0 后期。

6. **多列扩展统计是高门槛特性**：仅 PostgreSQL（10+）、Oracle、DB2、Teradata、CockroachDB、SAP HANA、OceanBase 等约 12 个引擎完整支持。这是 OLTP 复杂查询场景下 CBO 准确度的关键。

7. **云托管 = 完全黑箱**：Snowflake、BigQuery、Spanner、Firebolt 完全不暴露统计控制接口。"零运维"换取"零控制"，对 99% 用户是好的折衷，对 1% 高级用户是限制。

8. **湖仓引擎的统计来自 connector**：Trino、Presto、Athena、Spark SQL、Hive、Flink 等本身不存储统计，依赖 Iceberg / Hudi / Delta / Hive Metastore 提供 file-level 元数据。Iceberg 与 Delta 已经成为开源湖仓的统计层事实标准。

9. **流式系统不需要批量统计**：Materialize、RisingWave、Flink SQL（流模式）通过增量物化视图与运行时反馈优化，传统 ANALYZE 模型不适用。

10. **ClickHouse 的"反统计"路线**：用 MergeTree 主键索引 + skip index 替代直方图，在分析场景下性能极好，但对未排序列的复杂谓词估算精度受限。

11. **采样比例与桶数量是核心调参点**：PostgreSQL `default_statistics_target` 默认 100、SQL Server 固定 200、MySQL 默认 100、CockroachDB 默认 200、Spark 默认 254。增大可提升精度但显著增加 ANALYZE 成本与 plan time。

12. **自动统计正在普及**：约 25 个引擎默认开启自动统计收集。手动 ANALYZE 时代正在过去，但理解何时自动统计会失效（如批量导入后立即查询）仍是 DBA 的必备技能。

13. **统计信息错误是性能问题第一根因**：在调优实践中，约 60-80% 的"慢查询"问题最终归因于统计过期、采样不足或缺少多列统计。理解每个引擎的统计模型，是 SQL 性能工程的入门门槛。

统计信息看似是优化器的"幕后角色"，但任何严肃的 SQL 工程师都应当对自己使用的引擎的统计模型了如指掌。一句话总结：**没有统计信息的 CBO 就像没有眼睛的弓箭手**。
