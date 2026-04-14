#  物化视图刷新策略 (Materialized View Refresh Strategies)

物化视图的价值不在于"预计算"本身，而在于"如何保持预计算结果与源数据的同步"。刷新策略是物化视图（Materialized View，MV）设计中真正困难的部分：它在**数据新鲜度 (freshness)**、**查询延迟 (query latency)**、**写入放大 (write amplification)** 和 **存储成本 (storage cost)** 之间做权衡。一个团队决定使用 MV 的那一刻起，下一个要回答的问题永远是："你打算怎么刷新它？"

这篇文章专注于刷新语义 (refresh semantics)。关于物化视图本身的语法与定义，参见 [`materialized-views.md`](materialized-views.md)；关于常见使用模式与反模式，参见 [`materialized-view-patterns.md`](materialized-view-patterns.md)。

## 为什么刷新策略是 MV 的核心设计决策

在一个没有物化视图的世界里，查询总是看到最新数据——代价是每次查询都要重新计算。引入 MV 之后，查询看到的是"某一时刻的快照"，快照与现实之间的差距，就是**陈旧度 (staleness)**。围绕这个陈旧度，刷新策略大致分布在一条光谱上：

```
同步强一致 <-------------------------------------------> 完全异步
   |                                                          |
ON COMMIT              定时刷新                     增量流式维护
(SQL Server 索引视图)  (pg_cron)                    (Materialize)
   |                                                          |
写入极慢                 有窗口延迟                   写入延迟最低
查询总是最新             查询可能陈旧                 查询总是最新
```

没有"最好的"刷新策略，只有"最适合当前工作负载"的策略。OLAP 场景可以容忍 15 分钟陈旧度换来廉价的全量刷新；金融风控必须 ON COMMIT 同步；流式场景干脆放弃"视图"概念，直接让 MV 成为一条 dataflow。

## ISO SQL 标准对 MV 刷新完全未定义

令人意外的是，**ISO/IEC SQL 标准从未定义过物化视图**，更不用说刷新语义。SQL:2003 只引入了 `CREATE VIEW ... WITH [NO] CHECK OPTION` 的常规视图；SQL:2008 以后各个修订版也没有把 MV 纳入标准。

这意味着所有数据库的 MV 语法、刷新命令、增量语义都是**各自为政的厂商扩展**。即使是看起来相似的 `REFRESH MATERIALIZED VIEW`（PostgreSQL、Oracle、Redshift、Snowflake 都用这个命令），其内部行为差异巨大：

- **Oracle** 的 `REFRESH` 可以是 FAST / COMPLETE / FORCE / ALWAYS
- **PostgreSQL** 的 `REFRESH` 永远是全量（除了 `CONCURRENTLY` 改变并发度，不改变量）
- **Snowflake** 的 `REFRESH` 实际上由后台进程自动触发，用户命令只是占位
- **ClickHouse** 根本没有 `REFRESH` 命令——它的 MV 是 INSERT 触发器

这种碎片化是本文之所以要对比 45+ 引擎的根本原因：同样一个词，含义完全不同。

## 支持矩阵（45+ 数据库）

### 矩阵 1：手动 REFRESH 命令

| 引擎 | 是否有 MV | 手动 REFRESH 命令 | 版本 |
|------|----------|-----------------|------|
| PostgreSQL | 是 | `REFRESH MATERIALIZED VIEW` | 9.3+ |
| MySQL | 否 | -- | -- |
| MariaDB | 否 | -- | -- |
| SQLite | 否 | -- | -- |
| Oracle | 是 | `DBMS_MVIEW.REFRESH` / `EXEC` | 8i+ |
| SQL Server | 索引视图 | 无（同步自动） | 2000+ |
| DB2 | 是 (MQT) | `REFRESH TABLE` | v8+ |
| Snowflake | 是 | 无显式命令（自动） | GA 2020 |
| BigQuery | 是 | `BQ.REFRESH_MATERIALIZED_VIEW()` | GA 2020 |
| Redshift | 是 | `REFRESH MATERIALIZED VIEW` | 2019+ |
| DuckDB | 否 | -- | -- |
| ClickHouse | 是（触发器式）| 无（`REFRESHABLE` 模式：`SYSTEM REFRESH VIEW`）| 23.12+ |
| Trino | 是 | `REFRESH MATERIALIZED VIEW` | 398+ |
| Presto | 部分 | `REFRESH MATERIALIZED VIEW` | 0.245+ |
| Spark SQL | 否 (Delta 代替) | -- | -- |
| Hive | 是 | `ALTER MATERIALIZED VIEW ... REBUILD` | 3.0+ |
| Flink SQL | 动态表 | 无（持续流）| -- |
| Databricks | 是 (DLT) | `REFRESH` / DLT pipeline | GA |
| Teradata | 是（Join Index）| `COLLECT STATISTICS` 风格 | 很早 |
| Greenplum | 是 | `REFRESH MATERIALIZED VIEW` | 6.2+ |
| CockroachDB | 是 | `REFRESH MATERIALIZED VIEW` | 20.2+ |
| TiDB | 否 | -- | -- |
| OceanBase | 是 | `REFRESH MATERIALIZED VIEW` | 4.3+ |
| YugabyteDB | 是 | `REFRESH MATERIALIZED VIEW` | 2.4+ |
| SingleStore | 否（管道代替）| -- | -- |
| Vertica | 否（Projection 代替）| 无 | -- |
| Impala | 否（Hive MV）| 继承 Hive | -- |
| StarRocks | 是（异步 MV）| `REFRESH MATERIALIZED VIEW` | 2.4+ |
| Doris | 是 | `REFRESH MATERIALIZED VIEW` | 2.0+ |
| MonetDB | 否 | -- | -- |
| CrateDB | 否 | -- | -- |
| TimescaleDB | 连续聚合 | `CALL refresh_continuous_aggregate()` | 1.3+ |
| QuestDB | 是 | `REFRESH MATERIALIZED VIEW` | 8.0+ (2024) |
| Exasol | 否 | -- | -- |
| SAP HANA | 否（Calc View 代替）| -- | -- |
| Informix | 否 | -- | -- |
| Firebird | 否 | -- | -- |
| H2 | 否 | -- | -- |
| HSQLDB | 否 | -- | -- |
| Derby | 否 | -- | -- |
| Amazon Athena | 否 | -- | -- |
| Azure Synapse | 是 | 自动（索引视图）| GA |
| Google Spanner | 否 | -- | -- |
| Materialize | 是 | 无（持续增量）| GA |
| RisingWave | 是 | 无（持续增量）| GA |
| InfluxDB | 连续查询 | 无 | -- |
| DatabendDB | 是 | `REFRESH MATERIALIZED VIEW` | GA |
| Yellowbrick | 是 | `REFRESH MATERIALIZED VIEW` | GA |
| Firebolt | 是（聚合索引）| 无（自动）| GA |

> 统计：约 27 个引擎有某种"物化视图"概念，约 20 个引擎完全不支持或用其他机制代替。注意 MySQL、SQLite、DuckDB、SAP HANA 等常见引擎都没有真正的 MV。

### 矩阵 2：ON COMMIT 同步刷新

ON COMMIT 刷新意味着：每次基表事务提交时，MV 在同一事务内被同步更新。查询总是看到最新数据，代价是写入延迟显著增加。

| 引擎 | ON COMMIT | 触发粒度 | 限制 |
|------|----------|---------|------|
| PostgreSQL | 否 | -- | 必须手动或定时 |
| Oracle | 是 | 事务 / 语句 (12c+) | 需要 MV LOG；有聚合函数限制 |
| SQL Server | 是（索引视图）| 隐式每行 | `SCHEMABINDING`; 确定性函数 |
| DB2 | 是（`REFRESH IMMEDIATE`）| 事务 | 需满足 MQT 约束 |
| Snowflake | 否 | -- | 异步后台 |
| BigQuery | 否 | -- | 异步 |
| Redshift | 否 | -- | 手动或 `AUTO REFRESH YES` |
| ClickHouse | 是（INSERT 触发）| 每个 INSERT 块 | 仅追加可见 |
| Trino | 否 | -- | -- |
| Hive | 否 | -- | -- |
| Databricks | 否（DLT 连续模式除外）| -- | -- |
| Greenplum | 否 | -- | 继承 PG |
| CockroachDB | 否 | -- | -- |
| OceanBase | 是 | 事务 | 继承 Oracle 兼容模式 |
| YugabyteDB | 否 | -- | 继承 PG |
| StarRocks | 否（但有"同步 MV"基于单表）| -- | -- |
| Doris | 否（同步 MV 另一机制）| -- | -- |
| TimescaleDB | 否 | -- | 必须 policy |
| QuestDB | 否 | -- | -- |
| Materialize | 事实上是 | 连续 | dataflow 始终最新 |
| RisingWave | 事实上是 | 连续 | 同上 |
| Azure Synapse | 是（索引视图）| 隐式 | 同 SQL Server |

Oracle 是传统 RDBMS 中对 ON COMMIT 支持最完整的，但其对可增量维护的 MV 定义形式有严格限制（见后文 FAST 刷新章节）。SQL Server 的"索引视图"本质上就是 ON COMMIT 模型，不过它不叫"刷新"——因为视图物理上总是与基表同步。

### 矩阵 3：增量 / Fast / Delta 刷新

| 引擎 | 增量刷新 | 依赖结构 | 术语 |
|------|---------|---------|------|
| PostgreSQL | 否（仅全量）| -- | -- |
| Oracle | 是 | MV LOG + rowid | `REFRESH FAST` |
| SQL Server | 是（隐式）| 索引维护 | 索引视图 |
| DB2 | 是 | staging 表 | `REFRESH INCREMENTAL` |
| Snowflake | 是 | 后台 micro-partition 跟踪 | 自动 |
| BigQuery | 是 | 基表 change log | 自动 |
| Redshift | 是 | 增量计算图 | `AUTO REFRESH YES` |
| ClickHouse | 是（本质上增量）| 每次 INSERT 重新聚合 | 触发器模型 |
| Trino | 是（部分 connector）| 分区感知 | Iceberg 增量 |
| Hive | 是 | 事务表 | `REBUILD` 优化器决定 |
| Databricks (DLT) | 是 | Delta change feed | LIVE TABLE |
| Greenplum | 否 | -- | -- |
| CockroachDB | 否 | -- | -- |
| OceanBase | 是 | MV LOG | FAST（兼容 Oracle）|
| YugabyteDB | 否 | -- | -- |
| StarRocks | 是 | partition-level | 分区刷新 |
| Doris | 是 | partition-level | 同上 |
| TimescaleDB | 是 | invalidation log | 连续聚合 |
| QuestDB | 是 | WAL 游标 | incremental |
| Materialize | 是（唯一主业）| differential dataflow | 总是增量 |
| RisingWave | 是 | streaming operator | 总是增量 |
| DatabendDB | 否（目前全量）| -- | -- |
| Yellowbrick | 否 | -- | -- |
| Firebolt | 是 | 聚合索引 | 自动 |

### 矩阵 4：自动刷新 / 后台维护

| 引擎 | 自动刷新机制 | 默认开关 | 备注 |
|------|-------------|---------|------|
| PostgreSQL | 无内建 | -- | 需 `pg_cron` / `pg_timetable` |
| Oracle | DBMS_SCHEDULER + `START WITH ... NEXT` | 可配置 | `REFRESH ... NEXT SYSDATE+1/24` |
| SQL Server | 索引视图同步 | 默认 | 不是"刷新"模型 |
| DB2 | `REFRESH IMMEDIATE` 同步 | 按定义 | -- |
| Snowflake | 后台自动（Enterprise Edition）| 是 | 查询时对比 base change |
| BigQuery | 增量后台刷新 | 是（可禁用）| `refresh_interval_minutes` |
| Redshift | `AUTO REFRESH YES` | 可配置 | 2021+ 自动调度 |
| ClickHouse | INSERT 触发 + `REFRESHABLE` cron | 触发自动 | 23.12+ 加定时 |
| Trino | 无 | 需外部调度 | -- |
| Hive | 无 | -- | 需 Oozie / Airflow |
| Databricks | DLT pipeline | pipeline 运行时 | Continuous/Triggered |
| Greenplum | 无 | -- | -- |
| CockroachDB | 无 | -- | -- |
| OceanBase | 是 | 可配置 | -- |
| YugabyteDB | 无 | -- | -- |
| StarRocks | 是（`ASYNC`）| `REFRESH ASYNC EVERY` | 内建调度 |
| Doris | 是 | `BUILD IMMEDIATE REFRESH AUTO` | 内建 |
| TimescaleDB | 是 | `add_continuous_aggregate_policy` | 后台 worker |
| QuestDB | 是 | WAL driven | 自动 |
| Materialize | 是 | 连续 | 就是这套系统 |
| RisingWave | 是 | 连续 | 同上 |
| Firebolt | 是 | 查询时自动 | -- |
| Azure Synapse | 是（索引视图）| 是 | -- |

### 矩阵 5：REFRESH CONCURRENTLY / 非阻塞刷新

| 引擎 | 非阻塞刷新 | 机制 | 限制 |
|------|----------|------|------|
| PostgreSQL | 是 | `REFRESH MATERIALIZED VIEW CONCURRENTLY` | 需要 UNIQUE INDEX |
| Oracle | 是（atomic_refresh=false）| ATOMIC_REFRESH=FALSE | 两阶段 |
| SQL Server | 不适用 | 同步 | -- |
| DB2 | 是 | 支持后台影子 | -- |
| Snowflake | 是 | 后台 | 对用户透明 |
| BigQuery | 是 | 后台 | 透明 |
| Redshift | 否（AccessLock）| -- | 刷新期间只读 |
| ClickHouse | 是（REFRESHABLE 模式）| 原子切换 | 23.12+ |
| Trino | 部分 | connector 相关 | -- |
| Greenplum | 是 | 继承 PG | 9.6+ |
| CockroachDB | 否 | -- | -- |
| OceanBase | 是 | -- | -- |
| YugabyteDB | 是 | 继承 PG | 2.6+ |
| StarRocks | 是 | 原子 swap | -- |
| Doris | 是 | 同上 | -- |
| TimescaleDB | 是 | 增量 policy 天然不阻塞读 | -- |
| Materialize | 是 | 连续维护 | -- |
| RisingWave | 是 | 同上 | -- |

> 统计：不到半数支持"非阻塞刷新"。大多数传统数据库的全量 `REFRESH` 会持有独占锁，导致 MV 在刷新期间不可用。这是 PostgreSQL 9.4 引入 `CONCURRENTLY` 的动机。

## 各引擎详解

### PostgreSQL：极简语义，极大心智负担

PostgreSQL 在 9.3（2013）引入 `CREATE MATERIALIZED VIEW`，9.4（2014）补上 `REFRESH MATERIALIZED VIEW CONCURRENTLY`。从那之后语法没有本质变化：

```sql
CREATE MATERIALIZED VIEW sales_daily AS
SELECT
    date_trunc('day', ordered_at) AS day,
    region,
    SUM(amount)                    AS revenue,
    COUNT(*)                       AS orders
FROM orders
GROUP BY 1, 2
WITH DATA;

-- 阻塞刷新（AccessExclusiveLock）
REFRESH MATERIALIZED VIEW sales_daily;

-- 非阻塞刷新（只持有 ExclusiveLock，允许并发 SELECT）
REFRESH MATERIALIZED VIEW CONCURRENTLY sales_daily;
```

关键事实：

1. **永远是全量**。PG 的 MV 没有增量机制，每次 `REFRESH` 都会重算整个 SELECT。
2. **没有内建调度器**。想要定时刷新必须用 `pg_cron` 扩展、OS crontab 或外部调度系统（Airflow、Dagster）。
3. **CONCURRENTLY 要求唯一索引**。否则 PG 无法判断新旧快照之间的行差异。
4. **CONCURRENTLY 代价不小**。它内部构造一个临时新表，然后通过 `FULL OUTER JOIN` 比较旧 MV 与新结果，生成 `INSERT/UPDATE/DELETE` diff 应用到原 MV。对于大 MV，这比非并发刷新慢得多，但不阻塞读。

PostgreSQL 社区对"真正的增量刷新"讨论了十年以上，至今未进主线。生态方案包括 `pg_ivm` 扩展、Materialize（作为外部引擎）、`pg_cron` 定时全量。

### Oracle：工业级 MV 的参考实现

Oracle 在 8i（1999）就引入了完整的物化视图，至今仍是功能最丰富的实现。Oracle MV 的刷新模式是一个正交的两维空间：

**触发时机 (refresh mode)**：
- `ON DEMAND`：手动或调度
- `ON COMMIT`：基表事务提交时同步
- `ON STATEMENT`（12c+）：每条 DML 语句完成时

**刷新算法 (refresh method)**：
- `COMPLETE`：清空 MV 并重新执行定义查询
- `FAST`：增量应用 MV LOG 中的变更
- `FORCE`：优先 FAST，不满足条件时 fall back COMPLETE
- `NEVER`：禁止自动刷新

```sql
-- 启用 FAST 刷新前，必须建 MV LOG
CREATE MATERIALIZED VIEW LOG ON orders
WITH ROWID, SEQUENCE (order_id, region, amount, ordered_at)
INCLUDING NEW VALUES;

CREATE MATERIALIZED VIEW sales_daily
BUILD IMMEDIATE
REFRESH FAST ON COMMIT
ENABLE QUERY REWRITE
AS
SELECT
    TRUNC(ordered_at)  AS day,
    region,
    SUM(amount)        AS revenue,
    COUNT(*)           AS orders,
    COUNT(amount)      AS cnt_amount   -- FAST 要求 COUNT(expr)
FROM orders
GROUP BY TRUNC(ordered_at), region;

-- 手动触发
BEGIN
    DBMS_MVIEW.REFRESH('SALES_DAILY', method => 'F');  -- F=FAST
END;
/

-- 定时刷新
CREATE MATERIALIZED VIEW sales_hourly
REFRESH COMPLETE
START WITH SYSDATE
NEXT SYSDATE + 1/24
AS SELECT ...;
```

Oracle 的 FAST 刷新对 MV 定义有严苛限制（详见后文）。成功配置 FAST ON COMMIT 是 DBA 的一个小胜利。

### SQL Server：索引视图是另一种物种

SQL Server 从 2000 版本开始支持**索引视图 (Indexed View)**——一个带有聚簇索引的视图。它不是"物化视图 + 刷新"，而是"视图定义 + 物理索引"。一旦视图上建了聚簇索引，SQL Server 就会在每次基表 DML 时**同步**更新视图的物理数据，就像维护一个额外的索引。

```sql
CREATE VIEW dbo.sales_daily
WITH SCHEMABINDING
AS
SELECT
    CAST(ordered_at AS DATE) AS day,
    region,
    SUM(amount)              AS revenue,
    COUNT_BIG(*)             AS orders
FROM dbo.orders
GROUP BY CAST(ordered_at AS DATE), region;
GO

CREATE UNIQUE CLUSTERED INDEX IX_sales_daily
    ON dbo.sales_daily(day, region);
```

约束：
- 必须 `WITH SCHEMABINDING`
- 必须使用两段式对象名 (`dbo.orders`)
- 聚合必须包含 `COUNT_BIG(*)`
- 视图中的函数必须是确定性的
- 不允许 `OUTER JOIN`、子查询、`UNION`、`TOP` 等

SQL Server 从不使用"refresh"一词，因为概念上这些视图根本没有"陈旧"状态。代价是：所有基表的写入都在一个事务里额外维护视图索引。在 OLTP 工作负载上，索引视图的写入放大可能很惊人。

### Snowflake：云原生自动维护

Snowflake 从 2020 年 GA 的物化视图（Enterprise Edition）走了一条不同的路：

```sql
CREATE MATERIALIZED VIEW sales_daily AS
SELECT
    DATE_TRUNC('day', ordered_at) AS day,
    region,
    SUM(amount)                   AS revenue
FROM orders
GROUP BY 1, 2;
```

没有 `REFRESH` 命令。Snowflake 在后台维护一个名为 `Materialized View Maintenance Service` 的常驻进程，它观察基表的 micro-partition 变更，并异步地更新 MV。查询 MV 时，如果发现基表有尚未合并进 MV 的变更，Snowflake 会**在查询时动态融合** MV 结果与增量变更，返回最新答案——这是其他传统 MV 做不到的：**查询总是看到最新数据，即使 MV 本身陈旧**。

限制：只允许基于**单个表**的 MV，不允许 JOIN，不允许 `HAVING`，不允许窗口函数，不允许 `UNION`。这些限制反过来让它可以做到增量自动维护。

### BigQuery：智能刷新

BigQuery MV（2020 GA）类似 Snowflake：后台自动增量刷新，且查询时实时融合基表未合并变更。额外地，BigQuery 提供：

```sql
CREATE MATERIALIZED VIEW project.dataset.sales_daily
OPTIONS (
    enable_refresh = true,
    refresh_interval_minutes = 30,
    max_staleness = INTERVAL 1 HOUR
)
AS
SELECT DATE(ordered_at) AS day, region, SUM(amount) revenue
FROM project.dataset.orders
GROUP BY 1, 2;

-- 手动强制
CALL BQ.REFRESH_MATERIALIZED_VIEW('project.dataset.sales_daily');
```

`max_staleness` 选项很有意思：它告诉 BigQuery "只要 MV 陈旧度不超过 1 小时，就允许查询直接读 MV 而不做实时融合"。这是一个显式的"freshness vs latency"旋钮。

### Databricks：声明式 DLT

Databricks 的物化视图围绕 **Delta Live Tables (DLT)** 构建。你写的是一个声明式 pipeline，Databricks 生成并维护数据流：

```python
import dlt

@dlt.table(name="sales_daily")
def sales_daily():
    return (
        dlt.read_stream("orders")
            .groupBy("day", "region")
            .agg(sum("amount").alias("revenue"))
    )
```

或 SQL：

```sql
CREATE OR REFRESH LIVE TABLE sales_daily
AS SELECT day, region, SUM(amount) revenue
FROM LIVE.orders
GROUP BY day, region;
```

DLT pipeline 有两种运行模式：
- **Triggered**：执行一次全量/增量后停止
- **Continuous**：持续运行，像流处理一样增量维护

Databricks 还有独立的"Materialized Views"（基于 Delta 的元数据表），由 Unity Catalog 管理，内部实现是一个 DLT pipeline。

### ClickHouse：触发器式 MV 的独特模型

ClickHouse 的 `MATERIALIZED VIEW` 本质是**一个挂在源表 INSERT 上的触发器**。它没有"刷新"的概念，而是在每次源表 INSERT 时，将新到达的数据块通过 SELECT 变换写入目标表：

```sql
CREATE MATERIALIZED VIEW sales_daily_mv
ENGINE = SummingMergeTree
ORDER BY (day, region)
AS
SELECT
    toDate(ordered_at) AS day,
    region,
    sum(amount)        AS revenue
FROM orders
GROUP BY day, region;
```

关键后果：
1. **只处理 INSERT 之后的数据**。创建 MV 之前已经在 `orders` 里的行不会被聚合，除非用 `POPULATE`（有竞态风险）或手动回填。
2. **UPDATE / DELETE 不传递**。ClickHouse 的 `ALTER TABLE ... UPDATE` 是 mutation，不触发 MV。
3. **逐块处理**。INSERT 的每个数据块作为独立 SELECT 的输入，聚合是"局部的"——需要目标表是 `SummingMergeTree`/`AggregatingMergeTree` 这类能合并局部结果的引擎。

ClickHouse 在 23.12（2023-12）引入了**可刷新物化视图 (Refreshable MV)**，它更接近传统 MV：

```sql
CREATE MATERIALIZED VIEW sales_hourly
REFRESH EVERY 1 HOUR
TO sales_hourly_target
AS SELECT ...;
```

这种模式支持定时全量替换，与触发器模式并存。

### DB2：MQT 与 REFRESH IMMEDIATE/DEFERRED

DB2 把物化视图叫做 **Materialized Query Table (MQT)**。两种刷新模式：

```sql
CREATE TABLE sales_daily AS (
    SELECT
        DATE(ordered_at) AS day,
        region,
        SUM(amount)      AS revenue,
        COUNT(*)         AS orders
    FROM orders
    GROUP BY DATE(ordered_at), region
)
DATA INITIALLY DEFERRED
REFRESH IMMEDIATE;     -- 或 REFRESH DEFERRED

-- DEFERRED 模式手动触发
REFRESH TABLE sales_daily;
```

`REFRESH IMMEDIATE` 等价 Oracle 的 `REFRESH ON COMMIT`，`REFRESH DEFERRED` 等价 `ON DEMAND`。DB2 对 MQT 的增量维护（staging table）实现很完整，但和 Oracle 一样对表达式有限制。

### Redshift：自动刷新（2021+）

Redshift 在 2019 引入 MV，2021 加入 `AUTO REFRESH YES`：

```sql
CREATE MATERIALIZED VIEW sales_daily
AUTO REFRESH YES
AS
SELECT DATE_TRUNC('day', ordered_at) day, region, SUM(amount) revenue
FROM orders GROUP BY 1, 2;
```

Redshift 的增量刷新引擎会分析 MV 定义，如果可以增量维护则自动增量，否则回退全量。支持的算子包括聚合、inner join、where、group by，限制类似 Snowflake。`AUTO REFRESH` 调度由 Redshift workload manager 决定，用户不能精确控制时间——用户想要精确控制就得 `AUTO REFRESH NO` + 手动。

### Materialize：把增量计算做成数据库

Materialize 是为数不多"增量为第一公民"的数据库。它基于 **Differential Dataflow** —— 一种把 SQL 编译为增量数据流的技术。所有"物化视图"本质上都是一个 dataflow operator，基表变更立即沿 dataflow 传播。

```sql
CREATE MATERIALIZED VIEW sales_daily AS
SELECT date_trunc('day', ordered_at) day, region, SUM(amount) revenue
FROM orders
GROUP BY 1, 2;

SELECT * FROM sales_daily;  -- 始终最新，延迟毫秒级
```

没有 `REFRESH` 命令——概念上不存在"陈旧"。代价是：所有 MV 的状态常驻内存/磁盘，写入时 dataflow 持续运行，资源占用远高于批量 MV。RisingWave 走的是同样的路线。

## Oracle REFRESH FAST 深度解析

Oracle FAST 刷新是所有传统数据库中最复杂、也最值得研究的 MV 机制。它回答了一个根本问题：**在不重算整个 SELECT 的前提下，如何把基表的增量变更精确反映到聚合结果上？**

### MV LOG：变更捕获机制

FAST 刷新依赖源表的 **Materialized View Log**：

```sql
CREATE MATERIALIZED VIEW LOG ON orders
WITH ROWID, SEQUENCE, PRIMARY KEY (order_id, region, amount, ordered_at)
INCLUDING NEW VALUES;
```

MV LOG 是一张隐藏表（`MLOG$_ORDERS`），记录 `orders` 的每一次 INSERT/UPDATE/DELETE。`WITH SEQUENCE` 保证顺序可重放，`INCLUDING NEW VALUES` 保留更新前后镜像（聚合 MV 必需）。

### FAST 刷新的限制

一个 MV 能否 FAST 刷新，取决于 Oracle 能否找到增量维护算法。粗略规则：

- **简单 SELECT-PROJECT（无聚合）**：几乎总能 FAST
- **聚合 MV**：必须包含 `COUNT(*)`；若有 `SUM(x)`，必须同时有 `COUNT(x)`；若有 `AVG(x)`，必须同时有 `COUNT(x)` 和 `SUM(x)`；若有 `VAR`/`STDDEV`，要求更复杂
- **JOIN MV**：所有源表都要有 MV LOG 且带 `ROWID`，且 MV 的 SELECT 必须包含所有源表的 rowid
- **嵌套聚合、`HAVING`、`CONNECT BY`、分析函数**：通常不支持 FAST

可以用 `DBMS_MVIEW.EXPLAIN_MVIEW` 诊断：

```sql
BEGIN
    DBMS_MVIEW.EXPLAIN_MVIEW('SALES_DAILY');
END;
/

SELECT capability_name, possible, msgtxt
FROM mv_capabilities_table
WHERE mvname = 'SALES_DAILY'
  AND capability_name LIKE '%FAST%';
```

### COMPLETE vs FAST 选型

| 指标 | COMPLETE | FAST |
|------|---------|------|
| 每次刷新代价 | O(|源表|) | O(|变更|) |
| 实现难度 | 平凡 | 要求 MV LOG 且表达式受限 |
| 对基表写入的影响 | 无 | 每次 DML 写 MV LOG |
| 可以 ON COMMIT | 理论可以（代价大）| 推荐 |
| 适合场景 | 低频更新、复杂查询 | 高频小变更、常见聚合 |

Oracle 的 `REFRESH FORCE`（默认值）是一种保险：先尝试 FAST，失败则 COMPLETE。生产环境建议显式写 `FAST` 并通过 `EXPLAIN_MVIEW` 验证可行性，避免意外退化到 COMPLETE。

## PostgreSQL REFRESH CONCURRENTLY 机制

PostgreSQL 的 `REFRESH MATERIALIZED VIEW` 默认获取 `AccessExclusiveLock`——刷新期间连 `SELECT` 也被阻塞。9.4 引入的 `CONCURRENTLY` 改变了这一点：

```sql
-- 必须有唯一索引
CREATE UNIQUE INDEX ON sales_daily (day, region);

REFRESH MATERIALIZED VIEW CONCURRENTLY sales_daily;
```

内部机制：

1. 在一张临时表里物化新的 SELECT 结果
2. `FULL OUTER JOIN` 新临时表与旧 MV，按唯一键对齐
3. 生成 diff：新表有旧表没有 = INSERT；旧有新无 = DELETE；两边都有且不等 = UPDATE
4. 在一个事务里把 diff 应用到 MV；仅持有 `ExclusiveLock`，允许并发 SELECT

代价分析：

- **时间**：大约 2x 非并发刷新（需要两次完整扫描 + 一次 diff）
- **空间**：临时表占用与 MV 同样大的空间
- **写放大**：对一个几乎全新的快照，diff 近似等于全表重写

因此，CONCURRENTLY 的适用场景是**高读取并发 + 低变更比例**的 MV。对于每日全量刷新一个大 MV 的场景，反而是非并发 + 短窗口锁更好。

## Snowflake / BigQuery 的自动维护魔法

云数仓的 MV 实现有两个共同技巧，这两个技巧传统数据库难以复制：

### 技巧 1：后台服务 + micro-partition 跟踪

Snowflake 和 BigQuery 的存储都是不可变的列存分区（Snowflake 的 micro-partition、BigQuery 的 capacitor block）。基表的写入总是生成新的不可变分区，既有分区不会被原地修改。这让"增量变更"天然可被识别——**新分区就是增量**。

后台 MV 维护服务周期性扫描"自上次维护以来新增的分区"，对这些分区执行 MV 定义查询，然后合并进 MV 存储。因为是不可变分区，合并过程无需考虑并发更新冲突。

### 技巧 2：查询时融合 (Query-Time Merge)

最有意思的点：即使后台维护落后，查询也能看到最新结果。查询优化器知道"MV 覆盖了基表的前 N 个分区"，对于剩下的 M 个新分区，它在查询时动态执行 MV 定义的 SELECT，与 MV 结果 UNION 后返回。

这就是为什么 Snowflake/BigQuery 的 MV 没有"陈旧度"这个问题——陈旧度只影响性能（查询时要多算一些分区），不影响正确性。BigQuery 的 `max_staleness` 选项允许用户显式牺牲正确性换性能，默认是关闭的。

传统事务型数据库做不到这一点，因为它们的存储原地可变，"哪些行是新的"需要专门的变更日志来识别。Oracle MV LOG 是这种日志的典型实现，代价是所有写入都要额外记录。

## ClickHouse 触发器式 MV 的取舍

把 MV 当成 INSERT 触发器有什么好处？写入吞吐。ClickHouse 设计成按大批量 INSERT 优化（建议每次 INSERT 至少数万行），MV 作为触发器意味着**MV 的成本与 INSERT 摊销在同一批量里**——不需要额外的 IO 周期，不需要后台进程，不需要 WAL 重放。

代价：

1. **失去了"视图"语义**。真正的视图是"对基表某个子集的投影"，ClickHouse MV 是"未来所有 INSERT 的处理管道"。历史数据需要手动回填。
2. **不支持 DELETE/UPDATE 传播**。ClickHouse 本身不鼓励频繁 UPDATE，这与 MV 模型刚好匹配，但对需要反映删除的聚合场景是痛点。
3. **需要目标表是合并引擎**。`SummingMergeTree` 合并相同 ORDER BY 键的行；`AggregatingMergeTree` 存储聚合状态。最终结果 = 目标表的 `FINAL` 查询或 `GROUP BY` + 聚合状态合并。

对于纯追加的时序/日志工作负载，ClickHouse MV 是最快的增量聚合方案之一——因为它几乎没有额外的调度开销。对于需要修正的数据（退款、订单撤销），它就是反模式。`REFRESHABLE` 模式（23.12+）填补了这部分缺口，但概念上是另一种机制。

## 关键发现

1. **ISO SQL 从未定义物化视图，更未定义刷新语义**。所有语法都是厂商扩展，相似关键字（`REFRESH MATERIALIZED VIEW`）在不同引擎中行为差异巨大——PostgreSQL 是全量、Oracle 可以是 FAST、Snowflake 是占位、Redshift 可能是增量。阅读文档比读关键字更重要。

2. **45+ 数据库中只有约 27 个有 MV 概念**。MySQL、MariaDB、SQLite、DuckDB、SAP HANA、Informix、Firebird、H2、HSQLDB、Derby、SingleStore、Vertica、MonetDB、CrateDB、Exasol 等常见引擎都没有真正的物化视图。MySQL 的"物化视图"社区方案基本都是"触发器 + 汇总表"手工模拟。

3. **刷新策略的真正权衡是三元的**：freshness（数据新鲜度）、write amplification（写入放大）、query latency（查询延迟）。ON COMMIT 牺牲写入换新鲜度，定时全量牺牲新鲜度换写入，自动增量（Snowflake/BigQuery）是三者兼得的理想，但需要不可变存储支持。

4. **PostgreSQL 是 MV 能力最弱的"一线"数据库**。没有增量、没有 ON COMMIT、没有调度、`CONCURRENTLY` 代价高。这在云原生时代逐渐成为选型痛点，生态用 `pg_ivm`、Materialize、pg_cron 来弥补。

5. **Oracle 的 FAST REFRESH 至今仍是传统 RDBMS 中最完整的增量 MV 实现**，但 MV LOG 的写开销和表达式限制让它在云时代显得笨重。OceanBase 继承了 Oracle 的语义。

6. **SQL Server 的索引视图不是 MV——是带物化的视图**。同步维护意味着没有"刷新"概念，但写入放大直接作用于 OLTP。Azure Synapse 的自动 MV 基于类似机制。

7. **云数仓（Snowflake、BigQuery、Redshift、Firebolt）走的是"后台自动增量 + 查询时融合"路线**，这只在不可变列存分区上才能高效实现。它们的用户体验最接近"零心智负担"——创建后无需关心刷新。

8. **ClickHouse 的触发器模型是独一无二的**，只在大批量追加型工作负载下工作良好。23.12 引入的 `REFRESHABLE` 模式是对传统模型的追赶。

9. **流式数据库（Materialize、RisingWave、Flink SQL）把"增量维护"推到极致**：MV 不是偶尔刷新的缓存，而是常驻的 dataflow，基表变更立即沿图传播。这是 CPU 和内存换低延迟 + 高新鲜度。

10. **StarRocks / Doris 代表 OLAP 新势力的折中方案**：内建异步调度、分区级增量、非阻塞刷新。它们接受"秒到分钟级陈旧度"作为默认，把 MV 的易用性做到接近云数仓，但不需要云原生存储。

11. **Databricks DLT 把 MV 抽象为 pipeline**，模糊了"MV 刷新"和"流式 ETL"的边界——这可能是传统 MV 概念的未来演化方向：声明式的数据 pipeline，而不是命令式的 `REFRESH`。

12. **没有一种刷新策略适合所有场景**。选型的起点永远是两个数字：业务容忍的最大陈旧度，以及基表的写入吞吐。先确定这两个数，再选能满足的最便宜方案。对于超过 95% 的 OLAP 场景，"定时全量 + CONCURRENTLY"足够；ON COMMIT 和流式增量只在少数高价值场景下值得复杂度代价。
