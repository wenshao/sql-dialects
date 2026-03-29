# 物化视图跨方言全面对比

预计算并持久化查询结果——从 Oracle 的 MV Log 到 Materialize 的流式增量维护，45+ 引擎在查询加速、数据新鲜度与维护成本之间的不同抉择。

## 支持矩阵

### 传统关系型与云数据库

| 引擎 | 关键字 | 刷新策略 | 查询改写 | 增量刷新 | 版本 |
|------|--------|---------|---------|---------|------|
| Oracle | `MATERIALIZED VIEW` | COMPLETE / FAST / FORCE | 自动 | MV Log | 8i+ |
| PostgreSQL | `MATERIALIZED VIEW` | REFRESH / CONCURRENTLY | 不支持 | 不支持 | 9.3+ |
| SQL Server | Indexed View | 同步自动维护 | 自动 (Enterprise) | 同步 | 2000+ |
| MySQL | 不支持 | - | - | - | 需手动模拟 |
| MariaDB | 不支持 | - | - | - | 需手动模拟 |
| Db2 | `MATERIALIZED QUERY TABLE` | REFRESH IMMEDIATE / DEFERRED | 自动 | 暂存表 | 8.1+ |
| Db2 (z/OS) | `MATERIALIZED QUERY TABLE` | REFRESH / ENABLE QUERY OPTIMIZATION | 自动 | 支持 | V8+ |
| Informix | `MATERIALIZED VIEW` | REFRESH COMPLETE / FAST | 部分 | 支持 | 14+ |
| SAP HANA | `MATERIALIZED VIEW` | 自动 / 手动 | 不支持 | 支持 | 2.0+ |
| Teradata | `JOIN INDEX / HASH INDEX` | 自动同步 | 自动 | 同步 | V2R5+ |
| SQLite | 不支持 | - | - | - | - |

### 云数据仓库

| 引擎 | 关键字 | 刷新策略 | 查询改写 | 增量刷新 | 版本 |
|------|--------|---------|---------|---------|------|
| BigQuery | `MATERIALIZED VIEW` | 自动增量 | 智能改写 | 自动 | GA |
| Snowflake | `MATERIALIZED VIEW` | 自动增量 | 自动 | 自动 | Enterprise+ |
| Redshift | `MATERIALIZED VIEW` | REFRESH / AUTO REFRESH | 自动 | 增量 (部分) | 2019+ |
| Azure Synapse | `MATERIALIZED VIEW` | 自动 / 手动 | 自动 | 增量 | GA |
| Databricks | `MATERIALIZED VIEW` | 自动 / 手动 | 自动 | 增量 | Runtime 12.2+ |
| Google AlloyDB | `MATERIALIZED VIEW` | REFRESH / pg_cron | 不支持 | 不支持 | GA |
| Amazon Aurora | `MATERIALIZED VIEW` | REFRESH (同 PostgreSQL) | 不支持 | 不支持 | GA |
| Firebolt | `MATERIALIZED VIEW` | JOIN INDEX (聚合索引) | 自动 | 增量 | GA |

### OLAP / 分析引擎

| 引擎 | 关键字 | 刷新策略 | 查询改写 | 增量刷新 | 同步/异步 |
|------|--------|---------|---------|---------|----------|
| ClickHouse | `MATERIALIZED VIEW` | INSERT 触发 | 不支持 | INSERT 级 | 同步 |
| StarRocks | `MATERIALIZED VIEW` | 异步 / 同步 | 自动 | 支持 | 均支持 |
| Doris | `MATERIALIZED VIEW` | 异步 / 同步 | 自动 | 支持 | 均支持 |
| Vertica | `PROJECTION` | 自动同步 | 自动 (Projection) | 同步 | 同步 |
| Greenplum | `MATERIALIZED VIEW` | REFRESH (同 PostgreSQL) | 不支持 | 不支持 | - |
| MonetDB | `MATERIALIZED VIEW` | 手动 REFRESH | 不支持 | 不支持 | - |
| DuckDB | 不支持 | - | - | - | - |
| Pinot | `MATERIALIZED VIEW` (预聚合) | 实时摄入 | 自动路由 | 实时 | 同步 |
| Druid | Rollup / Pre-aggregation | 摄入时聚合 | 自动 | 摄入级 | 同步 |
| Kylin | `CUBE` | BUILD SEGMENT | 自动路由 | 增量构建 | 异步 |

### NewSQL / 分布式数据库

| 引擎 | 关键字 | 刷新策略 | 查询改写 | 版本 |
|------|--------|---------|---------|------|
| CockroachDB | `MATERIALIZED VIEW` | REFRESH | 不支持 | 20.2+ |
| TiDB | 不支持 (计划中) | - | - | - |
| YugabyteDB | `MATERIALIZED VIEW` | REFRESH (同 PostgreSQL) | 不支持 | 2.6+ |
| OceanBase | `MATERIALIZED VIEW` | COMPLETE / FAST | 自动 | 4.0+ |
| PolarDB | `MATERIALIZED VIEW` | REFRESH (兼容 PG/Oracle) | 取决于兼容模式 | GA |
| GaussDB | `MATERIALIZED VIEW` | COMPLETE / FAST | 自动 | 支持 |
| SingleStore (MemSQL) | `MATERIALIZED VIEW` | 自动维护 | 不支持 | 7.0+ |
| Vitess | 不支持 | - | - | - |

### 流处理 / 实时引擎

| 引擎 | 关键字 | 模型 | 延迟 |
|------|--------|------|------|
| Materialize | `MATERIALIZED VIEW` | 流式增量 (Differential Dataflow) | 毫秒级 |
| RisingWave | `MATERIALIZED VIEW` | 流式增量 | 毫秒~秒级 |
| ksqlDB | `CREATE TABLE AS SELECT` | 流式聚合 | 毫秒~秒级 |
| Flink SQL | `CREATE TABLE AS SELECT` (持续查询) | 流式增量 | 毫秒级 |
| Apache Calcite | MV 框架 (Lattice) | 查询改写框架 | 不适用 |

### 其他引擎

| 引擎 | 关键字 | 备注 |
|------|--------|------|
| Hive | `MATERIALIZED VIEW` | 3.0+，Calcite 改写，增量重建 |
| Spark SQL | 不支持 | `CACHE TABLE` 替代 |
| Presto/Trino | 不支持 | 联邦引擎，无持久化层 |
| TimescaleDB | `CONTINUOUS AGGREGATE` | 时序专用 MV 变体 |
| QuestDB | `MATERIALIZED VIEW` | 2025 新增 |
| InfluxDB | `TASK` | 定时聚合写入目标表 |
| Exasol | `MATERIALIZED VIEW` | 支持自动刷新 |
| Yellowbrick | `MATERIALIZED VIEW` | 支持自动刷新 |
| HeavyDB | 不支持 | GPU 引擎 |
| CrateDB | 不支持 | 需手动模拟 |

## CREATE MATERIALIZED VIEW 语法对比

### Oracle

```sql
CREATE MATERIALIZED VIEW mv_name
BUILD { IMMEDIATE | DEFERRED }
REFRESH { COMPLETE | FAST | FORCE | NEVER }
ON { COMMIT | DEMAND }
{ START WITH date NEXT date }        -- 定时调度
{ ENABLE | DISABLE } QUERY REWRITE
AS SELECT ...;
```

`BUILD IMMEDIATE` 创建时立即填充数据；`BUILD DEFERRED` 延迟到首次刷新。`REFRESH FORCE` 优先尝试 FAST，失败回退 COMPLETE。`REFRESH NEVER` 表示创建后不再刷新（只读快照）。

### PostgreSQL

```sql
CREATE MATERIALIZED VIEW mv_name
[ TABLESPACE ts_name ]
AS SELECT ...
[ WITH [ NO ] DATA ];
```

语法极简。`WITH NO DATA` 创建空壳，需后续 `REFRESH` 填充。无刷新策略、无查询改写、无增量刷新——全部需外部机制。

### SQL Server (Indexed View)

```sql
CREATE VIEW dbo.v_name
WITH SCHEMABINDING
AS SELECT ...;

CREATE UNIQUE CLUSTERED INDEX ix ON dbo.v_name (col);
```

不是独立的 DDL，而是"视图 + 聚集索引"的组合。创建聚集索引的瞬间数据被物化。此后每次基表 DML 同步维护。

### BigQuery

```sql
CREATE MATERIALIZED VIEW mv_name
[ OPTIONS (
    enable_refresh = true,
    refresh_interval_minutes = 30,
    max_staleness = INTERVAL '4' HOUR,
    allow_non_incremental_definition = true
) ]
AS SELECT ...;
```

`max_staleness` 是 BigQuery 独有的新鲜度容忍参数——允许查询在 MV 数据不超过指定陈旧度时直接使用 MV 结果。

### Snowflake

```sql
CREATE [ OR REPLACE ] [ SECURE ] MATERIALIZED VIEW mv_name
[ CLUSTER BY (expr, ...) ]
AS SELECT ...;
```

限制较多：不支持 JOIN、子查询、窗口函数、UNION、HAVING。仅支持单表聚合或单表筛选。自动维护，无需手动刷新。

### Redshift

```sql
CREATE MATERIALIZED VIEW mv_name
[ BACKUP { YES | NO } ]
[ DISTSTYLE { EVEN | KEY | ALL } ]
[ DISTKEY (col) ]
[ SORTKEY (col, ...) ]
[ AUTO REFRESH { YES | NO } ]
AS SELECT ...;
```

`AUTO REFRESH YES` 启用后台自动刷新。支持分布键和排序键设定，与普通表一致。

### ClickHouse

```sql
CREATE MATERIALIZED VIEW mv_name
[ TO target_table ]
ENGINE = SummingMergeTree()
ORDER BY (col)
[ POPULATE ]
AS SELECT ...;
```

`TO target_table` 指定目标表（如已存在）。`POPULATE` 回填历史数据（危险：执行期间新 INSERT 的数据可能丢失）。ClickHouse 的 MV 本质是 INSERT 触发器——只对新写入数据执行 SELECT 并将结果写入目标表。

### StarRocks

```sql
-- 同步物化视图 (Rollup)
CREATE MATERIALIZED VIEW mv_name
AS SELECT col1, SUM(col2) FROM t GROUP BY col1;

-- 异步物化视图 (2.4+)
CREATE MATERIALIZED VIEW mv_name
REFRESH { ASYNC | MANUAL }
[ PARTITION BY col ]
[ DISTRIBUTED BY HASH(col) BUCKETS n ]
[ PROPERTIES ("mv_rewrite_staleness_second" = "60") ]
AS SELECT ...;
```

StarRocks 区分同步和异步两种物化视图。同步 MV 类似 Rollup 索引，写入时自动维护；异步 MV 自 2.4 版本引入，功能更强大，支持多表 JOIN、定时刷新、查询改写。

### Doris

```sql
-- 同步物化视图
CREATE MATERIALIZED VIEW mv_name
AS SELECT col1, SUM(col2) FROM t GROUP BY col1;

-- 异步物化视图 (2.1+)
CREATE MATERIALIZED VIEW mv_name
BUILD { IMMEDIATE | DEFERRED }
REFRESH { COMPLETE | AUTO }
ON { MANUAL | SCHEDULE EVERY n { SECOND | MINUTE | HOUR | DAY } }
[ PARTITION BY col ]
[ DISTRIBUTED BY HASH(col) BUCKETS n ]
AS SELECT ...;
```

与 StarRocks 类似，Doris 也同时支持同步和异步物化视图。异步 MV 支持 `SCHEDULE EVERY` 定时刷新语法。

### Db2 (Materialized Query Table)

```sql
CREATE TABLE mqt_name AS (
    SELECT ... FROM ...
) DATA INITIALLY DEFERRED
REFRESH { IMMEDIATE | DEFERRED }
{ ENABLE | DISABLE } QUERY OPTIMIZATION
MAINTAINED BY { SYSTEM | USER };
```

Db2 使用 `MATERIALIZED QUERY TABLE` (MQT) 这一术语。`REFRESH IMMEDIATE` 实现同步维护；`MAINTAINED BY USER` 允许用户自行管理数据。

### Hive

```sql
CREATE MATERIALIZED VIEW mv_name
[ DISABLE REWRITE ]
[ PARTITIONED ON (col) ]
[ TBLPROPERTIES ("key" = "value") ]
[ ROW FORMAT ... ]
[ STORED AS fileformat ]
AS SELECT ...;
```

Hive 3.0+ 支持物化视图，集成 Calcite 查询改写框架。支持增量重建（基于 ACID 表的事务信息）。

### Materialize

```sql
CREATE MATERIALIZED VIEW mv_name AS
SELECT ... FROM source_or_view;
```

语法极简，但底层是完整的流式增量维护引擎。每一行变更都通过 Differential Dataflow 传播。无需手动刷新——数据始终是最新的。

### RisingWave

```sql
CREATE MATERIALIZED VIEW mv_name AS
SELECT ... FROM source_or_table;
```

与 Materialize 类似，RisingWave 的物化视图是流式增量维护的。语法与 PostgreSQL 兼容，但语义完全不同——创建后自动持续更新。

### TimescaleDB (Continuous Aggregate)

```sql
CREATE MATERIALIZED VIEW mv_name
WITH (timescaledb.continuous) AS
SELECT time_bucket('1 hour', time) AS bucket,
       device_id,
       AVG(value) AS avg_value
FROM metrics
GROUP BY bucket, device_id
WITH NO DATA;

-- 添加刷新策略
SELECT add_continuous_aggregate_policy('mv_name',
    start_offset => INTERVAL '3 days',
    end_offset   => INTERVAL '1 hour',
    schedule_interval => INTERVAL '1 hour');
```

时序数据库场景下的 MV 变体。`time_bucket` 是必须的分组函数。支持实时/历史分离的增量刷新窗口。

### OceanBase

```sql
-- Oracle 模式
CREATE MATERIALIZED VIEW mv_name
REFRESH { COMPLETE | FAST | FORCE }
ON { DEMAND | COMMIT }
{ ENABLE | DISABLE } QUERY REWRITE
AS SELECT ...;

-- MySQL 模式（兼容层）
CREATE MATERIALIZED VIEW mv_name
REFRESH COMPLETE ON DEMAND
AS SELECT ...;
```

OceanBase 在 Oracle 兼容模式下提供接近 Oracle 完整度的 MV 支持。

### Vertica (Projection)

```sql
CREATE PROJECTION proj_name AS
SELECT col1, col2, SUM(col3) AS total
FROM t
GROUP BY col1, col2
ORDER BY col1
SEGMENTED BY HASH(col1) ALL NODES;
```

Vertica 的 Projection 不是传统意义上的物化视图，而是表数据的物理排列方式。每个表至少有一个 super projection。额外 projection 相当于额外的物化排列，自动同步维护。

## 刷新策略深度对比

### 全量刷新 (COMPLETE / FULL)

最简单的策略：清空目标 → 重新执行查询 → 写入结果。

| 引擎 | 语法 | 阻塞查询 | 原子性 |
|------|------|---------|--------|
| Oracle | `DBMS_MVIEW.REFRESH('mv','C')` | 默认阻塞 | 事务性 |
| PostgreSQL | `REFRESH MATERIALIZED VIEW mv` | 阻塞读 | 事务性 |
| PostgreSQL | `REFRESH ... CONCURRENTLY` | 不阻塞读 | 原子交换 |
| Redshift | `REFRESH MATERIALIZED VIEW mv` | 不阻塞读 | 原子 |
| CockroachDB | `REFRESH MATERIALIZED VIEW mv` | 不阻塞读 | 事务性 |
| Doris (异步) | `REFRESH MATERIALIZED VIEW mv COMPLETE` | 不阻塞 | 分区级 |
| Hive | `ALTER MATERIALIZED VIEW mv REBUILD` | 提交 MR/Tez 作业 | 作业级 |

PostgreSQL 的 `CONCURRENTLY` 模式值得关注：它在后台构建新结果集，与旧数据做 diff（需要 UNIQUE INDEX），然后原子应用差异。代价是执行时间约为普通刷新的 2 倍。

### 增量刷新 (FAST / INCREMENTAL)

只处理自上次刷新以来的变更数据。

**Oracle FAST REFRESH：业界标杆**

```sql
-- 步骤 1：创建物化视图日志
CREATE MATERIALIZED VIEW LOG ON orders
WITH ROWID, SEQUENCE (customer_id, amount)
INCLUDING NEW VALUES;

-- 步骤 2：创建支持 FAST 刷新的 MV
CREATE MATERIALIZED VIEW mv_order_summary
REFRESH FAST ON DEMAND
AS
SELECT o.customer_id, SUM(o.amount) AS total,
       COUNT(*) AS cnt, COUNT(o.amount) AS cnt_amount
FROM orders o GROUP BY o.customer_id;
```

Oracle 增量刷新要求严格：聚合 MV 必须包含 `COUNT(*)` 和 `COUNT(col)`；JOIN MV 的每个基表都需要 MV Log；`INCLUDING NEW VALUES` 确保日志同时记录变更前后的值。

**StarRocks / Doris 分区级增量刷新**

```sql
-- StarRocks: 基表分区变更时只刷新对应的 MV 分区
CREATE MATERIALIZED VIEW mv_daily_sales
PARTITION BY date_trunc('day', dt)
REFRESH ASYNC
AS SELECT dt, store_id, SUM(amount) FROM sales GROUP BY dt, store_id;

-- 手动刷新指定分区
REFRESH MATERIALIZED VIEW mv_daily_sales
PARTITION START ('2024-01-01') END ('2024-01-02');
```

**Db2 REFRESH IMMEDIATE**

```sql
CREATE TABLE mqt_summary AS (
    SELECT dept_id, SUM(salary) AS total_salary, COUNT(*) AS cnt
    FROM employees GROUP BY dept_id
) DATA INITIALLY DEFERRED REFRESH IMMEDIATE;
-- 首次: REFRESH TABLE mqt_summary; 之后 DML 自动同步维护
```

### ON COMMIT 刷新

基表事务提交时自动刷新物化视图。

| 引擎 | 支持 | 备注 |
|------|------|------|
| Oracle | 支持 | `REFRESH FAST ON COMMIT`，需 MV Log |
| Db2 | 支持 | `REFRESH IMMEDIATE` (语义等价) |
| SQL Server | 支持 (Indexed View) | 聚集索引自动同步 |
| Teradata | 支持 (JOIN INDEX) | 自动同步 |
| OceanBase | 支持 | Oracle 兼容模式 |
| PostgreSQL | 不支持 | 需触发器模拟 |
| BigQuery | 不适用 | 自动异步，非事务级 |

ON COMMIT 提供最强一致性（MV 与基表事务级一致），但每次写入都有额外维护开销。

### ON DEMAND / 手动刷新

用户或调度器显式触发。Oracle 提供 `DBMS_MVIEW.REFRESH('mv','C'|'F'|'?')`、`REFRESH_ALL_MVIEWS`、`REFRESH_DEPENDENT('table')`。PostgreSQL / Redshift / CockroachDB / StarRocks / Doris 均使用 `REFRESH MATERIALIZED VIEW mv_name` 语法。PostgreSQL 额外支持 `CONCURRENTLY` 关键字。

### 定时刷新 (SCHEDULED)

| 引擎 | 机制 | 示例 |
|------|------|------|
| Oracle | `START WITH ... NEXT ...` | `NEXT SYSDATE + 1/24` (每小时) |
| Doris | `SCHEDULE EVERY` | `ON SCHEDULE EVERY 1 HOUR` |
| StarRocks | `ASYNC START(...)` | `REFRESH ASYNC START('2024-01-01') EVERY(INTERVAL 1 HOUR)` |
| BigQuery | `refresh_interval_minutes` | `OPTIONS(refresh_interval_minutes=30)` |
| Redshift | `AUTO REFRESH YES` | 系统自动决定刷新频率 |
| TimescaleDB | `add_continuous_aggregate_policy` | `schedule_interval => INTERVAL '1 hour'` |
| PostgreSQL | pg_cron (外部) | `cron.schedule('*/5 * * * *', 'REFRESH ...')` |
| InfluxDB | TASK | `EVERY 1h` |

## 查询改写 / 自动路由

查询改写（Query Rewrite）是物化视图最有价值的能力：用户查询基表，优化器透明地使用 MV 回答。

### 各引擎查询改写能力对比

| 引擎 | 查询改写 | 条件 | 控制方式 |
|------|---------|------|---------|
| Oracle | 自动 | `ENABLE QUERY REWRITE` + `query_rewrite_enabled=TRUE` | 参数/Hint |
| SQL Server | 自动 (Enterprise) | Indexed View + 聚集索引 | `NOEXPAND` Hint |
| BigQuery | 自动 | MV 数据在 `max_staleness` 范围内 | 自动 |
| Snowflake | 自动 | MV 有效且数据新鲜 | 自动 |
| Redshift | 自动 | `AUTO REFRESH` 启用 | 自动 |
| Azure Synapse | 自动 | `result_set_caching=ON` | 自动 |
| Databricks | 自动 | Delta Live Tables / Unity Catalog | 自动 |
| StarRocks | 自动 | 异步 MV + 候选 MV 新鲜度在容忍范围内 | `enable_materialized_view_rewrite` |
| Doris | 自动 | 异步 MV + 候选 MV 新鲜度在容忍范围内 | `enable_materialized_view_rewrite` |
| Hive | 自动 | Calcite 框架 | `hive.materializedview.rewriting=true` |
| OceanBase | 自动 | Oracle 模式下 `ENABLE QUERY REWRITE` | 参数 |
| PostgreSQL | **不支持** | 必须显式查询 MV | - |
| ClickHouse | **不支持** | 必须显式查询目标表 | - |
| CockroachDB | **不支持** | 必须显式查询 MV | - |

**Subsumption 判定条件**：(1) FROM 表覆盖；(2) WHERE 条件不强于查询；(3) GROUP BY 粒度不粗于查询；(4) SELECT 列覆盖；(5) 聚合可组合（`SUM` 可组合，`AVG` 需拆为 `SUM/COUNT`，`MEDIAN` 不可组合）。

## 增量刷新的前提条件

### 物化视图日志 / 变更追踪

| 引擎 | 变更捕获机制 | 创建语法 |
|------|-------------|---------|
| Oracle | Materialized View Log | `CREATE MATERIALIZED VIEW LOG ON table WITH ...` |
| Db2 | Staging Table | 系统自动管理 |
| SQL Server | Change Tracking | Indexed View 内部机制 |
| StarRocks | FE 元数据 + 分区版本 | 自动跟踪基表分区变更 |
| Doris | 分区版本跟踪 | 自动跟踪基表分区变更 |
| ClickHouse | 无（INSERT 触发） | INSERT 时直接处理新数据块 |
| Materialize | WAL / Differential Dataflow | 内置流式变更传播 |
| RisingWave | 内置变更流 | 基于 barrier 的一致性快照 |
| TimescaleDB | Hypertable chunk 元数据 | 基于时间分区的增量追踪 |

**Oracle MV Log 详解**：

```sql
CREATE MATERIALIZED VIEW LOG ON sales
WITH ROWID, SEQUENCE (col1, col2, col3)
INCLUDING NEW VALUES    -- 记录变更前后值（聚合 MV 增量维护所需）
PURGE IMMEDIATE;        -- 刷新后立即清理（DEFERRED 用于多 MV 共享日志）
-- WITH ROWID: 行标识跟踪; SEQUENCE: DML 操作排序（同事务多次变更）
```

## ALTER / DROP MATERIALIZED VIEW

### ALTER 操作

```sql
-- Oracle: 修改刷新方式
ALTER MATERIALIZED VIEW mv_name REFRESH FAST;
ALTER MATERIALIZED VIEW mv_name ENABLE QUERY REWRITE;
ALTER MATERIALIZED VIEW mv_name COMPILE;  -- 重新验证有效性

-- PostgreSQL: 修改所有者/表空间（不能修改查询定义）
ALTER MATERIALIZED VIEW mv_name OWNER TO new_owner;
ALTER MATERIALIZED VIEW mv_name SET TABLESPACE new_ts;
ALTER MATERIALIZED VIEW mv_name RENAME TO new_name;

-- Redshift: 修改自动刷新
ALTER MATERIALIZED VIEW mv_name AUTO REFRESH YES;

-- StarRocks: 修改刷新策略
ALTER MATERIALIZED VIEW mv_name
REFRESH ASYNC EVERY(INTERVAL 2 HOUR);

-- Doris: 修改刷新策略
ALTER MATERIALIZED VIEW mv_name
REFRESH COMPLETE ON SCHEDULE EVERY 1 HOUR;

-- Hive: 启用/禁用查询改写
ALTER MATERIALIZED VIEW mv_name ENABLE REWRITE;
ALTER MATERIALIZED VIEW mv_name DISABLE REWRITE;
```

### DROP 操作

```sql
-- 标准语法（大多数引擎通用）
DROP MATERIALIZED VIEW [ IF EXISTS ] mv_name;

-- SQL Server (Indexed View)
DROP INDEX ix ON dbo.v_name;    -- 删除索引取消物化
DROP VIEW dbo.v_name;           -- 删除视图本身

-- Oracle: 级联删除 MV Log
DROP MATERIALIZED VIEW mv_name PRESERVE TABLE;  -- 保留底层表
DROP MATERIALIZED VIEW LOG ON base_table;        -- 删除 MV 日志

-- ClickHouse
DROP TABLE mv_name;             -- MV 本质是表
DROP TABLE mv_target_table;     -- 目标表需单独删除

-- Vertica
DROP PROJECTION proj_name;
```

## 同步 vs 异步物化视图

StarRocks 和 Doris 是同时提供两种模式的典型代表。

同步 MV 在写入路径内同步维护（强一致、增加写入延迟、功能受限于单表聚合）。异步 MV 由后台任务定时/触发刷新（最终一致、不影响写入、支持 JOIN/子查询/窗口函数）。

### StarRocks 同步/异步对比

| 维度 | 同步 MV | 异步 MV (2.4+) |
|------|---------|---------------|
| 创建语法 | `CREATE MATERIALIZED VIEW` (无 REFRESH) | `CREATE MATERIALIZED VIEW ... REFRESH ASYNC` |
| 数据模型 | Rollup（列子集+预聚合） | 独立表 |
| 多表 JOIN | 不支持 | 支持 |
| 窗口函数 | 不支持 | 支持 |
| 查询改写 | 自动（单表维度聚合） | 自动（多表复杂查询） |
| 刷新粒度 | 行级同步 | 分区级增量 |
| 新鲜度容忍 | 实时 | `mv_rewrite_staleness_second` 可配置 |

## 分区物化视图

分区物化视图将 MV 数据按分区组织，实现分区级增量刷新——仅刷新变更分区，避免全量重算。

### 支持情况

| 引擎 | 分区 MV | 分区对齐 | 分区级刷新 |
|------|--------|---------|-----------|
| Oracle | 支持 | 支持 (PCT) | Partition Change Tracking |
| StarRocks | 支持 | 自动对齐基表分区 | 支持 |
| Doris | 支持 | 自动对齐基表分区 | 支持 |
| Hive | 支持 | 手动 | 支持 |
| BigQuery | 支持 | 与基表对齐 | 自动 |
| Databricks | 支持 | Delta 表自动 | 自动 |
| PostgreSQL | 不支持 | - | - |
| ClickHouse | 支持 (目标表分区) | 手动 | 手动 |

**Oracle Partition Change Tracking (PCT)**：

```sql
-- 基表按日期范围分区
CREATE TABLE sales (
    sale_id NUMBER, sale_date DATE, amount NUMBER
) PARTITION BY RANGE (sale_date) (...);

-- 基于分区表的物化视图
CREATE MATERIALIZED VIEW mv_sales
REFRESH FAST ON DEMAND
ENABLE QUERY REWRITE
AS SELECT sale_date, SUM(amount) total
FROM sales GROUP BY sale_date;

-- 当 sales 的某个分区被 TRUNCATE 或交换时
-- Oracle 只刷新 MV 中对应的部分（PCT 刷新）
EXEC DBMS_MVIEW.REFRESH('mv_sales', 'F');
```

**StarRocks 分区 MV**：

```sql
CREATE MATERIALIZED VIEW mv_daily
PARTITION BY date_trunc('day', dt)
DISTRIBUTED BY HASH(user_id) BUCKETS 8
REFRESH ASYNC
PROPERTIES (
    "partition_refresh_number" = "3"  -- 每次最多刷新 3 个分区
)
AS
SELECT dt, user_id, SUM(amount) AS total
FROM orders
GROUP BY dt, user_id;

-- 基表 orders 的 2024-03-15 分区有新数据写入
-- StarRocks 自动检测 → 仅刷新 MV 的 2024-03-15 分区
```

## MV on MV（级联物化视图）

部分引擎支持物化视图建立在物化视图之上，形成多层级联结构。

| 引擎 | MV on MV | 级联刷新 | 备注 |
|------|----------|---------|------|
| Oracle | 支持 | 按依赖顺序自动刷新 | `DBMS_MVIEW.REFRESH` 处理依赖 |
| ClickHouse | 支持 | INSERT 自动级联触发 | 常见模式 |
| StarRocks | 支持 (异步 MV) | 自动追踪依赖 | 2.5+ |
| Doris | 支持 (异步 MV) | 自动追踪依赖 | 2.1+ |
| Materialize | 支持 | 自动级联（流式） | 核心能力 |
| RisingWave | 支持 | 自动级联（流式） | 核心能力 |
| PostgreSQL | 支持 | 需手动按顺序刷新 | 无自动依赖管理 |
| BigQuery | 不支持 | - | MV 只能基于基表 |
| Snowflake | 不支持 | - | MV 只能基于基表 |

```sql
-- ClickHouse 级联 MV 示例
-- 原始数据表
CREATE TABLE raw_events (ts DateTime, user_id UInt32, event String)
ENGINE = MergeTree() ORDER BY ts;

-- 第一层 MV：按分钟聚合
CREATE MATERIALIZED VIEW mv_per_minute
ENGINE = SummingMergeTree() ORDER BY (minute, user_id)
AS SELECT
    toStartOfMinute(ts) AS minute,
    user_id,
    count() AS cnt
FROM raw_events GROUP BY minute, user_id;

-- 第二层 MV：按小时聚合（基于第一层）
CREATE MATERIALIZED VIEW mv_per_hour
ENGINE = SummingMergeTree() ORDER BY (hour, user_id)
AS SELECT
    toStartOfHour(minute) AS hour,
    user_id,
    sum(cnt) AS cnt
FROM mv_per_minute GROUP BY hour, user_id;

-- INSERT INTO raw_events → 自动触发 mv_per_minute → 自动触发 mv_per_hour
```

## 新鲜度容忍与一致性保证

不同引擎对"MV 数据允许多陈旧"的处理方式差异很大。

| 引擎 | 一致性模型 | 新鲜度控制 | 默认行为 |
|------|-----------|-----------|---------|
| Oracle (ON COMMIT) | 强一致 | 实时 | 事务提交时刷新 |
| Oracle (ON DEMAND) | 最终一致 | 手动/定时 | 用户控制 |
| SQL Server (Indexed View) | 强一致 | 实时 | DML 同步维护 |
| Db2 (IMMEDIATE) | 强一致 | 实时 | DML 同步维护 |
| BigQuery | 最终一致 | `max_staleness` | 自动刷新 + 容忍参数 |
| Snowflake | 最终一致 | 自动 | 微分区变更检测 |
| StarRocks (同步) | 强一致 | 实时 | 写入同步维护 |
| StarRocks (异步) | 可配置 | `mv_rewrite_staleness_second` | 超期不用于改写 |
| Doris (同步) | 强一致 | 实时 | 写入同步维护 |
| Doris (异步) | 可配置 | `grace_period` | 超期不用于改写 |
| Materialize | 强一致 | 实时 (流式) | 毫秒级延迟 |
| RisingWave | 最终一致 | 近实时 (barrier) | barrier 间隔 |
| PostgreSQL | 快照一致 | 刷新时间点 | 刷新后反映该时刻快照 |

**BigQuery `max_staleness` 示例**：

```sql
CREATE MATERIALIZED VIEW mv_stats
OPTIONS (max_staleness = INTERVAL '30' MINUTE)
AS SELECT region, SUM(revenue) FROM sales GROUP BY region;

-- 查询 SELECT region, SUM(revenue) FROM sales GROUP BY region 时:
-- 如果 MV 最后刷新时间距今 < 30 分钟 → 使用 MV（快）
-- 如果 MV 最后刷新时间距今 >= 30 分钟 → 扫描基表（慢但准确）
```

**StarRocks 新鲜度容忍**：

```sql
CREATE MATERIALIZED VIEW mv_report
REFRESH ASYNC EVERY(INTERVAL 10 MINUTE)
PROPERTIES ("mv_rewrite_staleness_second" = "300")
AS SELECT ...;

-- 即使最后一次刷新在 4 分钟前，只要 < 300 秒，查询改写仍然生效
-- 超过 300 秒，优化器不再将查询改写到此 MV
```

## 刷新监控与状态查询

```sql
-- Oracle: MV 状态、依赖、日志
SELECT mview_name, staleness, last_refresh_type, last_refresh_date,
       compile_state, refresh_mode, refresh_method FROM user_mviews;
SELECT * FROM user_mview_detail_relations WHERE mview_name = 'MV_NAME';
-- 检查 FAST 刷新可行性: DBMS_MVIEW.EXPLAIN_MVIEW('mv_name')

-- PostgreSQL
SELECT schemaname, matviewname, ispopulated FROM pg_matviews;

-- StarRocks / Doris
SHOW MATERIALIZED VIEWS [ LIKE 'pattern' ];
-- StarRocks: information_schema.task_runs
-- Doris: SELECT * FROM jobs("type"="mv"); / tasks("type"="mv")

-- BigQuery
SELECT table_name, mv_refresh_time, mv_stale_data_timestamp
FROM `project.dataset.INFORMATION_SCHEMA.MATERIALIZED_VIEWS`;
```

## MV vs Indexed View vs Projection

三种"预计算并存储"机制的设计哲学差异：

| 维度 | Materialized View | Indexed View (SQL Server) | Projection (Vertica) |
|------|------------------|--------------------------|---------------------|
| 本质 | 独立存储的查询结果 | 视图上的聚集索引 | 表数据的物理排列 |
| 独立性 | 独立对象 | 依附于视图 | 依附于表 |
| 存储 | 独立存储 | 独立存储 | 表数据的另一个副本 |
| 维护 | 异步/同步可选 | 强制同步 | 强制同步 |
| 查询改写 | 引擎各异 | Enterprise 自动 | 自动 |
| 支持的查询 | 通常无限制 | 严格限制 | 列子集+排序 |
| DML 影响 | 取决于刷新模式 | 每次 DML 同步开销 | 每次 DML 同步开销 |
| 创建方式 | 专用 DDL | 视图 + CREATE INDEX | 专用 DDL |

**Indexed View 的严格限制**（SQL Server）：必须 `SCHEMABINDING`；不支持 `OUTER JOIN`、`UNION`、子查询、`DISTINCT`；聚合仅限 `SUM`、`COUNT_BIG`（不支持 `MIN`/`MAX`/`AVG`）；必须包含 `COUNT_BIG(*)`；不支持 `FLOAT`/`TEXT`/`XML` 列；不能使用非确定性函数。

**Vertica Projection 的独特设计**：每个表至少有一个 super projection（包含所有列）。额外 projection 是数据按不同列排序的物理副本，DML 时同步维护，查询时优化器自动选择最优 projection。

## 对引擎开发者的实现建议

### 1. 元数据管理

MV 的元数据至少需要存储：

- **定义信息**：查询文本、基表列表、输出列定义
- **物理信息**：存储位置、分区方式、分布方式
- **刷新信息**：刷新模式、刷新策略、上次刷新时间、上次刷新 LSN/SCN
- **状态信息**：VALID/INVALID/STALE、编译状态
- **依赖关系**：基表列表、MV on MV 的依赖图

建议使用有向无环图（DAG）管理 MV 间的依赖关系，刷新时按拓扑序执行。

### 2. 全量刷新实现

基本方案：创建临时表 T' → `INSERT INTO T' AS SELECT` → 事务内原子交换（RENAME）。CONCURRENTLY 变体：执行查询得新结果集 → 与旧数据 diff（需 UNIQUE KEY）→ 事务内应用增量 DELETE + INSERT，刷新期间旧数据仍可读。

### 3. 增量刷新实现

增量刷新的核心是变更捕获与变更应用：

**变更捕获方案**：

| 方案 | 实现方式 | 优点 | 缺点 |
|------|---------|------|------|
| MV Log 表 | 基表触发器写日志 | 精确、支持 UPDATE | 写入放大 |
| WAL 位点 | 记录刷新时的 LSN，重放后续 WAL | 无写入放大 | 解析复杂 |
| 时间戳过滤 | `WHERE updated_at > last_refresh` | 简单 | 无法捕获 DELETE |
| 分区版本 | 记录每个分区的版本号 | 粒度适中 | 仅分区级 |
| CDC 流 | 订阅变更事件流 | 实时 | 架构复杂 |

**聚合 MV 的增量维护**：

对于 `SELECT key, SUM(val), COUNT(val) FROM t GROUP BY key`：
- INSERT 新行 `(k, v)`: 目标行 `SUM += v, COUNT += 1`
- DELETE 旧行 `(k, v)`: 目标行 `SUM -= v, COUNT -= 1`
- UPDATE `(k, v_old) → (k, v_new)`: 目标行 `SUM += (v_new - v_old)`

注意：`AVG` 不能直接增量维护，需拆分为 `SUM / COUNT`。`MIN` / `MAX` 在 DELETE 时可能需要全量重算（因为无法确定删除的是否是最小/最大值）。`COUNT(DISTINCT)` 增量维护非常困难，通常需要维护辅助的去重集合。

### 4. 查询改写实现

查询改写在优化器中作为规则/变换：对每个候选 MV 做 subsumption test（FROM 覆盖、JOIN 兼容、WHERE 谓词包含、GROUP BY 粒度、SELECT 列可导出），通过则构造改写查询并估算代价，选代价最低的方案。推荐参考 Apache Calcite 的 `MaterializedViewAggregateRule` 和 `MaterializedViewJoinRule`。

### 5. 新鲜度控制

建议引擎提供三级新鲜度策略：

1. **强一致（同步）**：写入时同步维护 MV，事务性保证。适合 OLTP 场景，但限制 MV 复杂度。
2. **有界过期（异步 + 容忍阈值）**：MV 可以过期，但不超过配置的阈值。优化器根据阈值决定是否使用 MV。适合大多数分析场景。
3. **尽力而为（异步无保证）**：MV 尽快刷新，但不保证新鲜度。适合离线报表场景。

### 6. 分区级增量刷新

StarRocks/Doris 验证过的高效模式：MV 与基表分区对齐 → 每个 MV 分区记录对应基表分区版本号 → 刷新时仅处理版本变更的分区。优势是刷新范围精确可控、可并行、失败可部分重试。

### 7. 同步 vs 异步的选择

建议同时支持两种模式。同步 MV 限制为单表预定义聚合（SUM/COUNT/MIN/MAX），实现为写入路径扩展（类似二级索引）。异步 MV 功能完整（支持 JOIN、子查询、窗口函数），实现为独立的后台刷新任务调度器。

### 8. 流式增量维护

Materialize/RisingWave 级别的流式 MV 要点：核心算法为 Differential Dataflow 或 IVM；变更以 `(row, diff, timestamp)` 三元组在算子间传播；JOIN 算子需维护双侧完整状态；需要 Barrier/Watermark 一致性机制；检查点与故障恢复是重大工程挑战。

### 9. 并发控制

关键问题：刷新期间查询应读到旧数据或新数据（不能读中间状态）；有依赖关系的 MV 按拓扑序刷新；基表 DDL 变更需使 MV 失效或自动适配；刷新任务应保证幂等性。

## 参考资料

- Oracle: [Materialized Views](https://docs.oracle.com/en/database/oracle/oracle-database/19/dwhsg/basic-materialized-views.html)
- PostgreSQL: [CREATE MATERIALIZED VIEW](https://www.postgresql.org/docs/current/sql-creatematerializedview.html)
- SQL Server: [Indexed Views](https://learn.microsoft.com/en-us/sql/relational-databases/views/create-indexed-views)
- BigQuery: [Materialized Views](https://cloud.google.com/bigquery/docs/materialized-views-intro)
- Snowflake: [Materialized Views](https://docs.snowflake.com/en/user-guide/views-materialized)
- ClickHouse: [Materialized Views](https://clickhouse.com/docs/en/guides/developer/cascading-materialized-views)
- Materialize: [CREATE MATERIALIZED VIEW](https://materialize.com/docs/sql/create-materialized-view/)
- RisingWave: [CREATE MATERIALIZED VIEW](https://docs.risingwave.com/docs/current/sql-create-mv/)
- StarRocks: [Materialized Views](https://docs.starrocks.io/docs/using_starrocks/Materialized_view/)
- Doris: [Materialized Views](https://doris.apache.org/docs/query-acceleration/materialized-view/)
- Db2: [Materialized Query Tables](https://www.ibm.com/docs/en/db2/11.5?topic=tables-materialized-query)
- Vertica: [Projections](https://www.vertica.com/docs/latest/HTML/Content/Authoring/AdministratorsGuide/Projections/Projections.htm)
- TimescaleDB: [Continuous Aggregates](https://docs.timescale.com/use-timescale/latest/continuous-aggregates/)
- Hive: [Materialized Views](https://cwiki.apache.org/confluence/display/Hive/Materialized+views)
- Apache Calcite: [Materialized View Rewriting](https://calcite.apache.org/docs/materialized_views.html)
