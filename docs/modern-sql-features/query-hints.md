# 查询提示 (Query Hints and Optimizer Directives)

完美的查询优化器是数据库领域的圣杯：给定一条 SQL，它应自动选出最优的连接顺序、连接方法、索引和并行度。但三十年的工程实践证明，这个目标至今没有达成——统计信息会过时，代价模型会有偏差，参数嗅探（parameter sniffing）会让计划在不同输入下灾难性退化。于是几乎每个商业级 RDBMS 都妥协地引入了"查询提示"（Query Hints）：让用户在特定 SQL 上手动覆盖优化器决策的"逃生通道"。

## 没有 SQL 标准

查询提示是 SQL 世界中最彻底的非标准化领域之一。SQL:1992 / SQL:2003 / SQL:2016 / SQL:2023 均未定义任何查询提示语法，标准委员会甚至在多份正式立场文件中将提示视为"反模式"（anti-pattern）：它们破坏声明式语义、把物理执行细节硬编码进应用代码、阻碍未来优化器的改进。

然而工程现实远比理论残酷。Oracle 在 v6/v7 时代（1990 年前后）就引入了 `/*+ */` 风格的注释提示，这一形式后来被 MySQL（5.7.7+）、TiDB、OceanBase、Doris、StarRocks 等几乎所有 MySQL 系产品继承；SQL Server 选择了完全不同的设计——把提示作为一等公民的 `OPTION` 子句和 `WITH (...)` 表提示；PostgreSQL 社区则坚持"无提示"哲学，把所有解决方案推给统计信息和扩展。这种割裂使得"查询提示的可移植性"几乎是负数：一段 Oracle 提示在 SQL Server 上不仅无效，连解析都会失败。

本文将系统对比 48+ 个数据库引擎在查询提示方面的支持情况，并对 Oracle 这个"提示帝国"和 PostgreSQL 这个"无提示坚守者"进行深入剖析。

## 支持矩阵（综合）

### 基础提示语法形式

| 引擎 | 注释式 `/*+ */` | SQL 关键字 | 表提示 `WITH(...)` | 会话级 SET | 备注 |
|------|----------------|-----------|--------------------|-----------|------|
| Oracle | 是 | -- | -- | 是 | `/*+ */` 起源者，100+ 提示 |
| SQL Server | -- | `OPTION (...)` | 是 `WITH (INDEX=, NOLOCK)` | 是 | 一等公民语法 |
| MySQL | 是 (5.7.7+) | `USE/FORCE/IGNORE INDEX` | -- | 是 | 双轨：注释提示 + 索引提示 |
| MariaDB | 是 (10.4+) | `USE/FORCE/IGNORE INDEX` | -- | 是 | 兼容 MySQL |
| PostgreSQL | -- | -- | -- | 是（`enable_*`） | 核心无提示，依赖 pg_hint_plan 扩展 |
| SQLite | -- | `INDEXED BY` | -- | -- | 仅索引提示 |
| DB2 | -- | `OPTIMIZE FOR n ROWS` | -- | 是 | 通过 optimization profile（XML）注入 |
| Snowflake | -- | -- | -- | 是（warehouse） | 设计哲学：无提示 |
| BigQuery | -- | -- | -- | 是（`@@`） | 设计哲学：无提示 |
| Redshift | -- | -- | -- | 是 | 极少量（`STATUPDATE`，分发提示） |
| DuckDB | -- | -- | -- | 是（`PRAGMA`） | 设计哲学：自动优化 |
| ClickHouse | -- | `SETTINGS` 子句 | -- | 是 | 查询级 SETTINGS |
| Trino | -- | -- | -- | 是（`SET SESSION`） | 设计哲学：无提示 |
| Presto | -- | -- | -- | 是 | 同 Trino |
| Spark SQL | 是 | -- | -- | 是 | `BROADCAST/REPARTITION/COALESCE` 等 |
| Hive | 是 | `STREAMTABLE/MAPJOIN` | -- | 是 | 早期注释提示 |
| Flink SQL | 是 | -- | -- | 是 | `LOOKUP/STATE_TTL/BROADCAST` |
| Databricks | 是 | -- | -- | 是 | 继承 Spark SQL，扩展更多 |
| Teradata | -- | -- | -- | 是 | 几乎不需要提示（PE 强大） |
| Greenplum | -- | -- | -- | 是 | 继承 PostgreSQL，无核心提示 |
| CockroachDB | -- | -- | -- | 是 | 极少量（`@primary` 索引提示） |
| TiDB | 是 | `USE/FORCE/IGNORE INDEX` | -- | 是 | MySQL 兼容 + TiDB 专属 |
| OceanBase | 是 | `USE/FORCE/IGNORE INDEX` | -- | 是 | MySQL/Oracle 双模式 |
| YugabyteDB | -- | -- | -- | 是 | 移植 pg_hint_plan |
| SingleStore | -- | -- | -- | 是 | 极少（`OPTION` 风格） |
| Vertica | 是 | -- | -- | 是 | `/*+ */` 注释提示 |
| Impala | 是 | `STRAIGHT_JOIN` | -- | 是 | `/*+ */` 和 `[+...]` |
| StarRocks | 是 | -- | -- | 是 | MySQL 兼容 + `[_SYNC]` |
| Doris | 是 | -- | -- | 是 | MySQL 兼容 |
| MonetDB | -- | -- | -- | 是 | 几乎无提示 |
| CrateDB | -- | -- | -- | 是 | 无提示 |
| TimescaleDB | -- | -- | -- | 是 | 继承 PG，可装 pg_hint_plan |
| QuestDB | -- | -- | -- | -- | 无提示 |
| Exasol | -- | -- | -- | 是 | 极少量提示 |
| SAP HANA | 是 | `WITH HINT(...)` | -- | 是 | 双语法 |
| Informix | -- | -- | -- | 是 | optimizer directives 风格类似注释提示 |
| Firebird | -- | `+0` / 表达式技巧 | -- | -- | 隐式提示 |
| H2 | -- | -- | -- | -- | 无 |
| HSQLDB | -- | -- | -- | -- | 无 |
| Derby | -- | `--DERBY-PROPERTIES` | -- | -- | 注释属性 |
| Amazon Athena | -- | -- | -- | 是 | 继承 Trino |
| Azure Synapse | -- | `OPTION (LABEL=...)` | 是 | 是 | 继承 SQL Server 部分 |
| Google Spanner | -- | `@{...}` 语句提示 | `@{FORCE_INDEX=}` | -- | 自有花括号语法 |
| Materialize | -- | -- | -- | 是 | 无提示（流处理） |
| RisingWave | -- | -- | -- | 是 | 无提示 |
| InfluxDB (SQL) | -- | -- | -- | -- | 无 |
| Databend | -- | -- | -- | 是（`SETTINGS`） | 无传统提示 |
| Yellowbrick | -- | -- | -- | 是 | 继承 PG，少量 |
| Firebolt | -- | -- | -- | 是 | 无传统提示 |

> 统计：约 22 个引擎提供某种"代码内提示"机制（注释或语句级关键字），约 26 个引擎完全依赖会话/参数控制或自动优化。

### 连接方法提示（Hash / Merge / Nested Loop）

| 引擎 | Hash Join | Merge Join | Nested Loop | Broadcast | 备注 |
|------|-----------|------------|-------------|-----------|------|
| Oracle | `USE_HASH(t)` | `USE_MERGE(t)` | `USE_NL(t)` | -- | 标准 Oracle 提示 |
| SQL Server | `HASH JOIN` | `MERGE JOIN` | `LOOP JOIN` | -- | OPTION 子句或 join 关键字内 |
| MySQL | `HASH_JOIN()` | -- | `NO_HASH_JOIN()` | -- | 8.0.18+ |
| PostgreSQL | `HashJoin(t1 t2)` | `MergeJoin(...)` | `NestLoop(...)` | -- | pg_hint_plan |
| DB2 | -- | -- | -- | -- | 通过 optimization profile XML |
| Spark SQL | `SHUFFLE_HASH(t)` | `SHUFFLE_MERGE(t)` | -- | `BROADCAST(t)` | 完整一套 |
| Hive | -- | -- | -- | `MAPJOIN(t)` | 老语法 |
| Flink SQL | -- | -- | `LOOKUP(...)` | `BROADCAST(t)` | 流批不同 |
| Trino/Presto | -- | -- | -- | -- | 仅 session 级 `join_distribution_type` |
| Snowflake | -- | -- | -- | -- | 无提示 |
| BigQuery | -- | -- | -- | -- | 无提示 |
| TiDB | `HASH_JOIN(t)` | `MERGE_JOIN(t)` | `INL_JOIN(t)` (索引嵌套) | `BROADCAST_JOIN(t)` | 完整 |
| OceanBase | `USE_HASH(t)` | `USE_MERGE(t)` | `USE_NL(t)` | -- | 兼容 Oracle |
| StarRocks | -- | -- | -- | `BROADCAST` | 仅广播 |
| Doris | -- | -- | -- | `BROADCAST` / `SHUFFLE` | |
| Vertica | `JTYPE(HJ)` | `JTYPE(MJ)` | -- | -- | |
| Impala | `SHUFFLE` / `BROADCAST` | -- | -- | 是 | join 分发提示 |
| SAP HANA | `USE_HASH_JOIN` | -- | -- | -- | |
| Informix | `USE_HASH` | -- | -- | -- | |

### 连接顺序提示（ORDERED / LEADING）

| 引擎 | 语法 | 强制度 |
|------|------|-------|
| Oracle | `/*+ ORDERED */` 或 `/*+ LEADING(t1 t2 t3) */` | 强制 |
| SQL Server | `OPTION (FORCE ORDER)` 或 `INNER LOOP JOIN` 写死 | 强制 |
| MySQL | `/*+ JOIN_ORDER(t1, t2) */` (8.0.21+) | 强制 |
| PostgreSQL | `Leading((t1 t2) t3)` (pg_hint_plan) | 强制 |
| DB2 | optimization profile | 强制 |
| Spark SQL | -- | -- |
| TiDB | `/*+ LEADING(t1, t2) */` | 强制 |
| OceanBase | `/*+ LEADING(t1 t2) */` 或 `/*+ ORDERED */` | 强制 |
| Snowflake/BigQuery/Trino | -- | -- |
| Vertica | `JFMT(...)` | 强制 |
| Impala | `STRAIGHT_JOIN` | 按 FROM 顺序 |
| Hive | `STRAIGHT_JOIN` | 同上 |
| MySQL/MariaDB | `STRAIGHT_JOIN` (关键字) | 按 FROM 顺序 |
| SAP HANA | `JOIN_ORDER` | 强制 |

### 索引提示（USE / FORCE / IGNORE INDEX）

| 引擎 | 选择索引 | 强制索引 | 禁用索引 | 强制全表扫描 |
|------|---------|---------|---------|-------------|
| Oracle | `INDEX(t idx)` | 同 | `NO_INDEX(t idx)` | `FULL(t)` |
| SQL Server | `WITH (INDEX(idx))` | 同 | -- | `WITH (INDEX(0))` |
| MySQL | `USE INDEX(idx)` | `FORCE INDEX(idx)` | `IGNORE INDEX(idx)` | `IGNORE INDEX FOR JOIN` |
| MariaDB | 同 MySQL | 同 | 同 | 同 |
| SQLite | `INDEXED BY idx` | 同 | `NOT INDEXED` | -- |
| PostgreSQL | -- | -- | `SET enable_indexscan=off` | 同 |
| pg_hint_plan | `IndexScan(t idx)` | `IndexOnlyScan(...)` | `NoIndexScan(t)` | `SeqScan(t)` |
| DB2 | optimization profile | 同 | 同 | 同 |
| Snowflake | -- | -- | -- | -- |
| BigQuery | -- | -- | -- | -- |
| Redshift | -- | -- | -- | -- |
| ClickHouse | -- | `force_index_by_date` | -- | -- |
| Trino/Presto | -- | -- | -- | -- |
| Spark SQL | -- | -- | -- | -- |
| TiDB | `USE_INDEX(t, idx)` | `FORCE_INDEX` (兼容) | `IGNORE_INDEX(t, idx)` | -- |
| OceanBase | `INDEX(t idx)` 或 `USE INDEX` | 同 | `NO_INDEX(t idx)` | `FULL(t)` |
| CockroachDB | `t@idx` 或 `t@{FORCE_INDEX=idx}` | 同 | -- | -- |
| Spanner | `t@{FORCE_INDEX=idx}` | 同 | -- | -- |
| StarRocks/Doris | -- | -- | -- | -- |
| Vertica | `/*+ KV(...) */` | 间接 | -- | -- |
| SAP HANA | `INDEX("idx")` | 同 | `NO_INDEX(...)` | -- |
| Informix | `--+ INDEX(t idx)` (directive) | 同 | `--+ AVOID_INDEX` | `--+ FULL(t)` |
| Firebird | `+0` 数学技巧禁用索引 | -- | 同 | -- |
| Derby | `--DERBY-PROPERTIES index=idx` | 同 | -- | -- |

### 并行度提示（PARALLEL n）

| 引擎 | 语法 | 备注 |
|------|------|------|
| Oracle | `/*+ PARALLEL(t, 8) */` 或 `/*+ PARALLEL(8) */` | 经典；DOP 控制 |
| SQL Server | `OPTION (MAXDOP 8)` | DOP 上限 |
| MySQL | -- | 8.0 仅特定查询自动并行 |
| PostgreSQL | -- (会话 `max_parallel_workers_per_gather`) | 无查询级 |
| pg_hint_plan | `Parallel(t 4 hard)` | 是 |
| DB2 | `CURRENT DEGREE = '8'` (会话) | 无查询提示 |
| Snowflake | -- (warehouse 大小) | 无 |
| BigQuery | -- | 自动 |
| Redshift | -- | 自动 |
| ClickHouse | `SETTINGS max_threads=8` | 查询级 |
| Trino/Presto | -- (`task.concurrency`) | 仅 session |
| Spark SQL | `/*+ COALESCE(8) */` 或 `REPARTITION(8)` | 控制分区数 |
| Hive | `set mapreduce.job.reduces=8` | 会话 |
| Flink SQL | -- | 算子级 parallelism |
| TiDB | `/*+ TIDB_HASHAGG_FINAL_CONCURRENCY(8) */` 等 | 多个细粒度提示 |
| OceanBase | `/*+ PARALLEL(8) */` | 兼容 Oracle |
| Vertica | -- | 自动 |
| Impala | `SET MT_DOP=8` | 会话/查询 |
| StarRocks/Doris | `SET pipeline_dop=8` | 会话 |
| SAP HANA | `WITH HINT(PARALLEL_EXECUTION)` | 是 |
| Greenplum | `gp_resqueue_priority` | 资源队列 |

### 计划缓存提示（NO_PLAN_CACHE / USE_PLAN）

| 引擎 | 禁用缓存 | 固定计划 | 强制重编译 |
|------|---------|---------|------------|
| Oracle | `/*+ NO_RESULT_CACHE */` | SQL Plan Baseline | `/*+ DYNAMIC_SAMPLING */` |
| SQL Server | -- | `OPTION (USE PLAN N'...xml...')` | `OPTION (RECOMPILE)` |
| MySQL | `SQL_NO_CACHE` (废弃 8.0) | -- | -- |
| PostgreSQL | -- | -- | `DISCARD PLANS` (会话) |
| DB2 | -- | optimization profile | `REOPT ALWAYS` |
| Snowflake | `USE_CACHED_RESULT=FALSE` (会话) | -- | -- |
| BigQuery | `@@dataset_project_id` 等参数 | -- | -- |
| ClickHouse | `SETTINGS use_query_cache=0` | -- | -- |
| Spark SQL | -- | -- | -- |
| TiDB | `/*+ IGNORE_PLAN_CACHE() */` | `/*+ SET_VAR(...) */` | -- |
| OceanBase | `/*+ NO_USE_PLAN_CACHE */` | Outline (类似 baseline) | -- |
| SAP HANA | `WITH HINT(NO_RESULT_CACHE)` | `WITH HINT(USE_REMOTE_CACHE)` | -- |

### 视图/子查询物化提示（NO_MERGE / MATERIALIZE）

| 引擎 | 强制内联 | 强制物化 | 备注 |
|------|---------|---------|------|
| Oracle | `/*+ MERGE */` | `/*+ NO_MERGE */` 或 `/*+ MATERIALIZE */` (CTE) | 经典 |
| SQL Server | -- | -- | 无（CTE 总是内联） |
| MySQL | `MERGE` (5.7+) | `NO_MERGE` | 派生表 |
| PostgreSQL | -- | `WITH ... AS MATERIALIZED` (12+) | SQL 关键字而非提示 |
| DB2 | -- | -- | optimization profile |
| Snowflake | -- | -- | -- |
| BigQuery | -- | -- | -- |
| Spark SQL | -- | -- | -- |
| TiDB | `/*+ MERGE() */` | `/*+ NO_MERGE() */` | |
| OceanBase | `/*+ MERGE */` | `/*+ NO_MERGE */` | |
| SAP HANA | -- | `WITH HINT(NO_INLINE)` | |

### 基数 / 行数提示（CARDINALITY / ROWS）

| 引擎 | 语法 | 备注 |
|------|------|------|
| Oracle | `/*+ CARDINALITY(t 1000) */` | 私有但常用 |
| SQL Server | -- | 无（仅旧 Trace Flag 9481 等） |
| MySQL | -- | -- |
| PostgreSQL | `Rows(t1 t2 #1000)` (pg_hint_plan) | 是 |
| DB2 | optimization profile `<CARDINALITY>` | 是 |
| TiDB | -- | -- |
| OceanBase | `/*+ CARDINALITY(t 1000) */` | 兼容 Oracle |
| SAP HANA | `WITH HINT(ESTIMATION_SAMPLES(...))` | 间接 |

### OPTIMIZE FOR / OPTION (RECOMPILE) 等查询级控制

| 引擎 | OPTIMIZE FOR 值 | RECOMPILE / 重优化 | LABEL |
|------|----------------|--------------------|-------|
| Oracle | `BIND_AWARE` (等价) | `DYNAMIC_SAMPLING(11)` | `MARKER` 注释 |
| SQL Server | `OPTION (OPTIMIZE FOR (@p = 100))` | `OPTION (RECOMPILE)` | `OPTION (LABEL='x')` |
| DB2 | `OPTIMIZE FOR n ROWS` (SQL 标准式) | `REOPT ONCE/ALWAYS` | -- |
| MySQL | -- | -- | -- |
| PostgreSQL | -- | -- | -- |
| Synapse | -- | `OPTION (LABEL='...')` | 是 |
| Teradata | -- | -- | `QUERY_BAND` |
| Snowflake | -- | -- | `QUERY_TAG` (会话) |

## 各引擎语法详解

### Oracle（提示帝国）

Oracle 是查询提示这一概念的发明者和集大成者。`/*+ ... */` 注释紧跟在 `SELECT/INSERT/UPDATE/DELETE/MERGE` 关键字之后，被解析器识别为提示而非普通注释（普通注释为 `/* ... */`，无 `+` 号）。Oracle 19c/21c 文档列出了超过 100 个有效提示。

```sql
-- 完整示例：组合多个提示
SELECT /*+ LEADING(o c) USE_HASH(c) PARALLEL(o, 8) INDEX(o orders_dt_idx) */
       o.order_id, c.cust_name
FROM   orders o, customers c
WHERE  o.cust_id = c.cust_id
   AND o.order_date >= DATE '2025-01-01';

-- 全表扫描提示
SELECT /*+ FULL(o) */ * FROM orders o WHERE order_id = 12345;

-- 物化 CTE
WITH big_cte AS (
    SELECT /*+ MATERIALIZE */ cust_id, SUM(amount) total
    FROM orders GROUP BY cust_id
)
SELECT * FROM big_cte WHERE total > 10000;

-- 基数提示（告诉优化器某个表/谓词的预估行数）
SELECT /*+ CARDINALITY(t 1) */ * FROM big_table t WHERE rare_flag = 'Y';

-- 结果缓存
SELECT /*+ RESULT_CACHE */ COUNT(*) FROM huge_table;

-- 禁用查询转换
SELECT /*+ NO_QUERY_TRANSFORMATION */ ... ;

-- 第一行优化（OLTP）
SELECT /*+ FIRST_ROWS(10) */ * FROM logs ORDER BY ts DESC;

-- 全部行优化（OLAP）
SELECT /*+ ALL_ROWS */ ... ;
```

Oracle 的提示按作用域大致分为六类：

1. **优化目标**：`ALL_ROWS`、`FIRST_ROWS(n)`
2. **访问路径**：`FULL`、`INDEX`、`INDEX_FFS`、`INDEX_SS`、`NO_INDEX`、`CLUSTER`、`HASH`
3. **连接顺序**：`ORDERED`、`LEADING`
4. **连接方法**：`USE_NL`、`USE_HASH`、`USE_MERGE`、`USE_NL_WITH_INDEX`
5. **并行执行**：`PARALLEL`、`NO_PARALLEL`、`PQ_DISTRIBUTE`、`PARALLEL_INDEX`
6. **查询转换**：`MERGE`/`NO_MERGE`、`UNNEST`/`NO_UNNEST`、`PUSH_PRED`、`MATERIALIZE`、`STAR_TRANSFORMATION`、`USE_CONCAT`

如果一个提示语法错误或引用了不存在的表，Oracle**不会报错**，而是默默忽略——这是 Oracle 提示最让人困惑的"特性"。验证提示是否生效的唯一方法是看 `EXPLAIN PLAN` 输出。

### SQL Server（一等公民语法）

SQL Server 选择了完全不同的设计：提示不是注释，而是 SQL 语法的一部分。语法错误会导致编译失败。

```sql
-- OPTION 子句（位于查询末尾）
SELECT o.order_id, c.cust_name
FROM   orders o
INNER  HASH JOIN customers c ON o.cust_id = c.cust_id   -- 内联连接提示
WHERE  o.order_date >= '2025-01-01'
OPTION (
    MAXDOP 8,                    -- 并行度上限
    RECOMPILE,                   -- 强制每次重编译
    OPTIMIZE FOR (@p = 100),     -- 假装参数为 100 来生成计划
    FORCE ORDER,                 -- 严格按 FROM 顺序连接
    HASH JOIN, MERGE JOIN,       -- 允许的连接方法
    LOOP JOIN,
    LABEL = 'monthly_report'     -- 用于监控的标签
);

-- 表提示（位于表名后）
SELECT * FROM dbo.orders WITH (INDEX(idx_order_date), NOLOCK, READPAST)
WHERE order_date >= '2025-01-01';

-- 强制使用某索引
SELECT * FROM dbo.orders WITH (INDEX = idx_cust_date) WHERE cust_id = 100;

-- 强制全表扫描
SELECT * FROM dbo.orders WITH (INDEX(0));

-- 计划固定（USE PLAN，使用先前生成的 XML 计划）
SELECT * FROM big_table WHERE col = 5
OPTION (USE PLAN N'<ShowPlanXML>...</ShowPlanXML>');
```

SQL Server 的"参数嗅探"（parameter sniffing）问题催生了 `OPTIMIZE FOR UNKNOWN` 和 `RECOMPILE` 提示，这是它的独特贡献。Plan Guides（DDL 级别的提示）允许 DBA 在不修改应用代码的情况下为特定 SQL 强制计划。

### MySQL（双轨制：注释提示 + 索引提示）

MySQL 历史上长期只有 `USE/FORCE/IGNORE INDEX` 三个 SQL 级索引提示。5.7.7（2015 年）引入了 Oracle 风格的 `/*+ */` 优化器提示，8.0 持续扩展。

```sql
-- 索引提示（SQL 关键字，老语法）
SELECT * FROM orders USE INDEX (idx_date) WHERE order_date >= '2025-01-01';
SELECT * FROM orders FORCE INDEX (idx_cust) WHERE cust_id = 100;
SELECT * FROM orders IGNORE INDEX (idx_status) WHERE status = 'OPEN';

-- 优化器提示（注释式，5.7.7+）
SELECT /*+ MAX_EXECUTION_TIME(1000) */ * FROM big_table;          -- 1 秒超时
SELECT /*+ NO_INDEX_MERGE(orders) */ ... ;
SELECT /*+ BKA(orders, customers) */ ... ;                         -- Batched Key Access
SELECT /*+ HASH_JOIN(o, c) */ ... ;                                -- 8.0.18+
SELECT /*+ JOIN_ORDER(t1, t2, t3) */ ... ;                         -- 8.0.21+
SELECT /*+ SET_VAR(optimizer_switch='mrr=on') */ ... ;             -- 8.0+

-- 连接关键字（与 Oracle ORDERED 类似）
SELECT STRAIGHT_JOIN o.*, c.* FROM orders o, customers c WHERE ...;
```

MySQL 8.0 的 `SET_VAR` 提示尤其强大，它允许在单条查询内临时覆盖任何系统变量值，无需 `SET SESSION`。

### PostgreSQL（无提示哲学 + pg_hint_plan）

PostgreSQL 核心团队几十年来明确拒绝在主干引入查询提示。官方 wiki 的"OptimizerHintsDiscussion"页面列出了反对理由：

1. 提示会阻碍优化器改进——开发者会优先修 bug，而非依赖用户写死的计划。
2. 应用代码不应承担物理执行细节。
3. 数据库版本升级后，硬编码提示可能反而劣化。
4. 99% 的"需要提示"问题实际上是统计信息或 SQL 写法问题。

PostgreSQL 提供的"替代品"是会话级开关，如 `enable_seqscan`、`enable_hashjoin`、`enable_mergejoin`、`enable_nestloop`、`enable_indexscan`、`random_page_cost` 等。这些可以在事务内 SET，但作用范围远宽于单条查询。

```sql
-- 仅本会话禁用 nested loop（粗粒度，不是真正的提示）
SET LOCAL enable_nestloop = off;
SELECT * FROM big_a JOIN big_b ON big_a.id = big_b.id;
RESET enable_nestloop;
```

**pg_hint_plan**：日本 NTT 开源的扩展，是 PostgreSQL 生态中最流行的提示工具。它通过解析 SQL 注释来注入提示，语法刻意模仿 Oracle：

```sql
-- 安装
CREATE EXTENSION pg_hint_plan;
LOAD 'pg_hint_plan';
SET pg_hint_plan.enable_hint = on;

-- 使用
/*+ HashJoin(a b) IndexScan(a idx_a_id) Leading((a b) c) */
SELECT * FROM a, b, c WHERE a.id = b.id AND b.cid = c.id;

-- 完整示例
/*+ SeqScan(orders)
    IndexScan(customers customers_pkey)
    NestLoop(orders customers)
    Rows(orders #1000)
    Parallel(orders 4 hard) */
SELECT * FROM orders, customers WHERE orders.cust_id = customers.id;
```

pg_hint_plan 支持的提示类别完整对标 Oracle：扫描方法（`SeqScan/IndexScan/IndexOnlyScan/BitmapScan/TidScan/NoSeqScan/...`）、连接方法（`HashJoin/MergeJoin/NestLoop`）、连接顺序（`Leading`）、行数提示（`Rows`）、并行度（`Parallel`）、GUC 修改（`Set`）等。许多托管 PostgreSQL 服务（如 Aiven、AWS RDS 部分版本、阿里云 RDS）默认安装 pg_hint_plan。

YugabyteDB 直接 fork 了 pg_hint_plan 作为其官方解决方案；TimescaleDB、Greenplum 也均可安装。

### TiDB（MySQL 兼容 + 分布式扩展）

TiDB 完全继承 MySQL 的 `/*+ */` 语法，并为分布式架构添加了独特的提示。

```sql
-- 选择存储引擎（行存 TiKV 或列存 TiFlash）
SELECT /*+ READ_FROM_STORAGE(TIFLASH[t]) */ COUNT(*) FROM t WHERE region='cn';
SELECT /*+ READ_FROM_STORAGE(TIKV[t]) */ * FROM t WHERE id = 100;

-- 连接提示
SELECT /*+ HASH_JOIN(t1, t2) */ * FROM t1, t2 WHERE t1.id = t2.id;
SELECT /*+ INL_JOIN(t2) */ * FROM t1, t2 WHERE t1.id = t2.id;       -- index nested loop
SELECT /*+ BROADCAST_JOIN(t1) */ * FROM t1, t2 WHERE t1.id = t2.id;
SELECT /*+ MERGE_JOIN(t1, t2) */ * FROM t1, t2 WHERE t1.id = t2.id;

-- 连接顺序
SELECT /*+ LEADING(t1, t3, t2) */ * FROM t1, t2, t3 WHERE ...;

-- 索引
SELECT /*+ USE_INDEX(t, idx_a) */ * FROM t WHERE a = 10;
SELECT /*+ IGNORE_INDEX(t, idx_a) */ * FROM t WHERE a = 10;

-- 查询执行控制
SELECT /*+ MAX_EXECUTION_TIME(2000) */ COUNT(*) FROM big_t;        -- 2 秒超时
SELECT /*+ MEMORY_QUOTA(1024 MB) */ * FROM huge_t;                 -- 内存上限
SELECT /*+ IGNORE_PLAN_CACHE() */ ... ;
SELECT /*+ SET_VAR(tidb_isolation_read_engines = 'tiflash') */ ... ;

-- 聚合并发度
SELECT /*+ TIDB_HASHAGG_FINAL_CONCURRENCY(8) */ ... ;
```

`READ_FROM_STORAGE` 是 TiDB 的标志性提示，因为其 HTAP 架构允许同一表同时拥有行存和列存副本。

### ClickHouse（SETTINGS 而非提示）

ClickHouse 选择"查询级 SETTINGS"作为提示等价物，没有 Oracle 风格的注释提示。

```sql
SELECT count() FROM events
WHERE date >= '2025-01-01'
SETTINGS
    max_threads = 16,
    max_memory_usage = 10000000000,
    use_query_cache = 0,
    join_algorithm = 'hash',
    optimize_read_in_order = 1,
    distributed_aggregation_memory_efficient = 1;
```

ClickHouse 有数百个可在查询级覆盖的 settings，覆盖了从执行算法到 I/O 行为的几乎所有维度。这种设计在哲学上更接近"会话变量"而非传统提示，但实际效果类似。

### Snowflake / BigQuery（坚定的"无提示"派）

Snowflake 和 BigQuery 都明确拒绝引入查询提示。它们的论点是：

1. 云数据仓库的存储计算分离架构使统计信息维护成本极低，优化器有充足元数据。
2. 用户调整 warehouse 大小（Snowflake）或 slots（BigQuery）即可控制资源，这比提示更直观。
3. 多租户、自动扩缩容场景下，硬编码提示会导致严重的可移植性问题。

Snowflake 唯一接近"提示"的机制是 `QUERY_TAG`（用于审计/监控，不影响计划）和 `USE_CACHED_RESULT` 会话参数：

```sql
ALTER SESSION SET QUERY_TAG = 'monthly_report';
ALTER SESSION SET USE_CACHED_RESULT = FALSE;
SELECT ...;
```

BigQuery 同理，仅有 `@@dataset_project_id` 等少数 query parameter，没有计划干预手段。

### Spark SQL / Databricks（侧重数据分布）

Spark SQL 的提示集中于"数据分布"——这正是分布式计算的核心瓶颈。

```sql
-- 广播 Join（小表）
SELECT /*+ BROADCAST(small_t) */ * FROM big_t JOIN small_t ON big_t.id = small_t.id;

-- 等价别名
SELECT /*+ BROADCASTJOIN(small_t) */ ... ;
SELECT /*+ MAPJOIN(small_t) */ ... ;             -- Hive 风格

-- 强制 Shuffle Hash Join
SELECT /*+ SHUFFLE_HASH(t1, t2) */ * FROM t1 JOIN t2 ON t1.id = t2.id;

-- 强制 Sort Merge Join
SELECT /*+ SHUFFLE_MERGE(t1, t2) */ ... ;

-- 强制 Shuffle Replicate Nested Loop（小表的笛卡尔积）
SELECT /*+ SHUFFLE_REPLICATE_NL(t1) */ ... ;

-- 控制分区数
SELECT /*+ COALESCE(8) */ * FROM huge_t;              -- 减少到 8 个分区
SELECT /*+ REPARTITION(100) */ * FROM huge_t;          -- 重分区到 100
SELECT /*+ REPARTITION(100, col1) */ ... ;             -- 按列重分区
SELECT /*+ REPARTITION_BY_RANGE(col1) */ ... ;
SELECT /*+ REBALANCE */ ... ;                          -- AQE 重平衡
```

Databricks 在 Spark 基础上扩展了更多提示（如 `SKEW`、`RANGE_JOIN`），用于优化倾斜数据和范围连接。

### Hive

```sql
-- Map Join（广播小表，等价 Spark BROADCAST）
SELECT /*+ MAPJOIN(small_t) */ * FROM big_t, small_t WHERE big_t.id = small_t.id;

-- Stream Table（建议为最大表）
SELECT /*+ STREAMTABLE(big_t) */ * FROM big_t, mid_t, small_t WHERE ...;

-- 严格按 FROM 顺序
SELECT /*+ STRAIGHT_JOIN */ * FROM ...;
```

### Flink SQL

```sql
-- 维表 Lookup Join
SELECT /*+ LOOKUP('table'='dim_t', 'async'='true') */ ...;

-- State TTL（流处理特有）
SELECT /*+ STATE_TTL('orders' = '1d', 'customers' = '7d') */ ...;

-- Broadcast
SELECT /*+ BROADCAST(small_t) */ ...;
```

### CockroachDB / Spanner（花括号语法）

```sql
-- CockroachDB
SELECT * FROM orders@orders_date_idx WHERE order_date >= '2025-01-01';
SELECT * FROM orders@{FORCE_INDEX=orders_date_idx,ASC} WHERE ...;
SELECT * FROM orders@{NO_INDEX_JOIN};

-- Google Spanner
SELECT * FROM orders@{FORCE_INDEX=orders_date_idx} WHERE order_date >= '2025-01-01';
@{USE_ADDITIONAL_PARALLELISM=TRUE}
SELECT COUNT(*) FROM huge_table;
@{JOIN_METHOD=HASH_JOIN}
SELECT * FROM a JOIN b ON a.id = b.id;
```

### SAP HANA（双语法）

```sql
-- 注释式
SELECT /*+ USE_HASH_JOIN */ * FROM a, b WHERE a.id = b.id;

-- WITH HINT 子句
SELECT * FROM a, b WHERE a.id = b.id WITH HINT (USE_HASH_JOIN, NO_INDEX("idx_a"));
SELECT * FROM big_t WITH HINT (PARALLEL_EXECUTION, NO_RESULT_CACHE);
```

### Impala

```sql
-- /*+ */ 或 [+ ...] 双语法
SELECT /*+ STRAIGHT_JOIN */ * FROM a, b WHERE a.id = b.id;
SELECT * FROM a JOIN [SHUFFLE] b ON a.id = b.id;
SELECT * FROM a JOIN [BROADCAST] b ON a.id = b.id;
INSERT INTO t /*+ NOSHUFFLE */ SELECT * FROM source;
```

### DB2（optimization profile：XML 注入）

DB2 几乎没有"代码内"提示，但提供了一种独特的机制：**optimization profile**。DBA 把提示写在 XML 文件里，注册到数据库，然后通过 `CURRENT OPTIMIZATION PROFILE` 寄存器关联到 SQL。

```xml
<OPTPROFILE>
  <STMTPROFILE ID='daily_report'>
    <STMTKEY><![CDATA[SELECT * FROM orders WHERE order_date >= ?]]></STMTKEY>
    <OPTGUIDELINES>
      <IXSCAN TABLE="orders" INDEX="idx_order_date"/>
      <HSJOIN><IXSCAN TABLE="orders"/><TBSCAN TABLE="customers"/></HSJOIN>
    </OPTGUIDELINES>
  </STMTPROFILE>
</OPTPROFILE>
```

```sql
SET CURRENT OPTIMIZATION PROFILE = 'MYPROF';
SELECT * FROM orders WHERE order_date >= '2025-01-01';
```

`OPTIMIZE FOR n ROWS` 是 DB2 较早实现的标准 SQL 子句（非 DB2 专属，但 DB2 用得最多）：

```sql
SELECT * FROM orders WHERE region = 'CN' ORDER BY order_date OPTIMIZE FOR 10 ROWS;
```

### Teradata

Teradata 的 PE（Parsing Engine）以"几乎不需要提示"著称，因此原生提示极少。常见的"提示"实际上是工具：
- `EXPLAIN` 与 `COLLECT STATISTICS` 是首选调优手段；
- `QUERYBAND` 用于打标签（类似 Snowflake QUERY_TAG）；
- `LOCKING ROW FOR ACCESS` 等修饰符可视为隔离级提示。

### OceanBase（双模式：MySQL + Oracle）

OceanBase 同时支持 MySQL 和 Oracle 两种 SQL 兼容模式，提示语法也相应分两套：

```sql
-- MySQL 模式（兼容 MySQL 8.0 hint）
SELECT /*+ HASH_JOIN(t1, t2) USE_INDEX(t1, idx_a) */ * FROM t1, t2 WHERE ...;

-- Oracle 模式（兼容 Oracle 经典 hint）
SELECT /*+ USE_HASH(t2) INDEX(t1 idx_a) PARALLEL(8) */ * FROM t1, t2 WHERE ...;

-- OceanBase 专属：分区裁剪、远程执行控制
SELECT /*+ NO_USE_PX */ ... ;
SELECT /*+ NO_REWRITE */ ... ;
```

### StarRocks / Doris

```sql
-- 广播 vs Shuffle
SELECT /*+ SET_VAR(broadcast_row_limit=1000000) */ ...;
SELECT /*+ BROADCAST */ * FROM small_t JOIN big_t ON ...;
SELECT /*+ SHUFFLE */ * FROM t1 JOIN t2 ON ...;

-- 同步 / 异步物化视图选择
SELECT /*+ SET_VAR(force_query_mv=true) */ ...;
```

## Oracle 提示帝国深度剖析

Oracle 的提示生态是 30 年累积的产物，理解它需要把握几条主线。

### 提示的优先级

Oracle 优化器对提示的处理优先级（从高到低）：
1. **SQL Plan Baseline / SQL Patch**（DBA 注册的固定计划，最高优先级）
2. **Outline / Stored Outline**（旧机制，等价 baseline）
3. **SQL 中的 hint**
4. **Session 参数**（`OPTIMIZER_MODE`、`OPTIMIZER_INDEX_COST_ADJ` 等）
5. **System 参数**

这意味着 baseline 一旦生效，SQL 中的 hint 会被忽略。这是 Oracle DBA 常见的"我加了 hint 为什么没生效"的根因之一。

### 提示的"全局"和"局部"作用域

Oracle 提示分为语句级（影响整个 SQL）和对象级（仅作用于某个表或别名）。例如：

```sql
-- 语句级
SELECT /*+ ALL_ROWS */ * FROM ...;

-- 对象级（必须使用别名而非真实表名）
SELECT /*+ INDEX(o orders_date_idx) */ *
FROM orders o WHERE o.order_date >= DATE '2025-01-01';

-- 跨子查询的全局提示（使用查询块名）
SELECT /*+ INDEX(@subq o orders_date_idx) */ *
FROM (SELECT /*+ QB_NAME(subq) */ * FROM orders o WHERE o.order_date >= ...) v;
```

`QB_NAME` 命名查询块，使得外层提示可以精确定位内层对象——这对优化器重写后的复杂 SQL 至关重要。

### 提示静默失效（Silent Failure）

Oracle 在以下情况下会静默忽略提示：
- 表名/别名拼写错误；
- 提示与查询语义冲突（如对没有索引的列指定 `INDEX`）；
- 优化器判定无法实现（如 hash join 在没有等值条件时）；
- 提示之间互相冲突（最早出现的胜出）；
- SQL 经过视图合并后表别名变化。

唯一可靠的验证方法：

```sql
EXPLAIN PLAN FOR SELECT /*+ ... */ ... ;
SELECT * FROM TABLE(DBMS_XPLAN.DISPLAY(NULL, NULL, 'BASIC +HINT_REPORT'));
```

19c 引入的 `HINT_REPORT` 输出会明确告诉你哪些提示被使用、哪些被忽略及原因——这是 Oracle 提示调优的关键工具。

### 常用提示速查（按使用频率）

| 提示 | 作用 |
|------|------|
| `INDEX(t idx)` | 强制使用某索引 |
| `FULL(t)` | 强制全表扫描 |
| `USE_HASH(t)` | 对 t 使用 hash join |
| `USE_NL(t)` | 对 t 使用 nested loop |
| `LEADING(t1 t2 ...)` | 指定连接顺序 |
| `PARALLEL(t, n)` | 设置并行度 |
| `NO_PARALLEL(t)` | 禁用并行 |
| `MATERIALIZE` | 物化 CTE |
| `INLINE` | 内联 CTE |
| `MERGE` / `NO_MERGE` | 视图合并控制 |
| `UNNEST` / `NO_UNNEST` | 子查询解嵌套控制 |
| `PUSH_PRED` | 谓词下推 |
| `FIRST_ROWS(n)` | 优化前 n 行响应 |
| `ALL_ROWS` | 优化总吞吐量 |
| `RESULT_CACHE` | 结果缓存 |
| `CARDINALITY(t n)` | 告诉优化器某表预估行数 |
| `DYNAMIC_SAMPLING(n)` | 强制动态采样级别 |
| `APPEND` | 直接路径插入 |
| `GATHER_PLAN_STATISTICS` | 收集运行时统计供 `+ALLSTATS` 使用 |

## PostgreSQL 的"无提示"哲学

PostgreSQL 拒绝提示的立场已成为开源数据库哲学讨论的经典案例。理解这一立场需要回到核心：

### 反对理由（核心团队官方观点）

1. **优化器的进化优先**：如果用户被允许写死计划，社区改进优化器的动机就会下降。"宁可优化器有 bug 也要修，不要让 bug 长期存在"。
2. **代价模型应当反映现实**：当代价模型与实测不符时，正确做法是改进 `random_page_cost`、`effective_cache_size`、`work_mem` 等参数或重收集统计，而非用提示绕过。
3. **统计信息的力量**：`ANALYZE`、`pg_statistic` 多列统计、扩展统计（`CREATE STATISTICS`）通常足以解决 95% 的"需要提示"场景。
4. **可移植性**：提示是版本相关的，PG 升级常带来计划改善，硬编码提示反而劣化。

### 替代方案的层次

PostgreSQL 用户不需要提示也能"控制"计划，方法分四层：

1. **改写 SQL**：等价改写常常比提示更有效。`EXISTS` vs `IN`、JOIN 顺序、CTE 物化等。
2. **`enable_*` 会话开关**：`enable_seqscan`、`enable_hashjoin` 等十余个布尔开关，可在会话/事务级粗粒度禁用某种算法。
3. **代价参数**：`random_page_cost`、`cpu_tuple_cost`、`effective_cache_size`、`work_mem` 的精细调整。
4. **CTE 物化标记**：PG 12+ 提供 `WITH ... AS MATERIALIZED` / `NOT MATERIALIZED` 关键字，这是标准 SQL 的一部分而非提示。

```sql
-- CTE 物化（PG 12+，SQL 关键字）
WITH big AS MATERIALIZED (
    SELECT cust_id, SUM(amount) total FROM orders GROUP BY cust_id
)
SELECT * FROM big WHERE total > 10000;
```

### pg_hint_plan：现实的妥协

尽管核心团队拒绝，现实场景中确实存在优化器无法处理的 corner case，特别是：

- 大表上不准的多列相关性导致基数估计偏差极大；
- 复杂 OLTP 应用对计划稳定性的硬性需求（参数嗅探导致的偶发慢查询）；
- 从 Oracle 迁移过来的应用，原本依赖 Oracle 提示。

NTT 的 pg_hint_plan 扩展应运而生。它的工作原理是 hook 进 PostgreSQL 的 planner_hook 和 join_search_hook，在生成计划前注入约束。

```sql
-- 完整的 pg_hint_plan 示例
LOAD 'pg_hint_plan';
SET pg_hint_plan.enable_hint = on;
SET pg_hint_plan.message_level = info;     -- 让 hint 是否生效可见

/*+ Leading((customers (orders order_items)))
    HashJoin(customers orders order_items)
    IndexScan(customers customers_pkey)
    SeqScan(orders)
    Rows(orders order_items #50000)
    Parallel(orders 8 hard) */
SELECT c.name, SUM(oi.amount)
FROM customers c
JOIN orders o ON o.cust_id = c.id
JOIN order_items oi ON oi.order_id = o.id
WHERE c.region = 'CN'
GROUP BY c.name;
```

pg_hint_plan 还支持"hint table"——把 SQL 与 hint 的对应关系存到一张表中，对生产环境的应用代码无侵入：

```sql
INSERT INTO hint_plan.hints (norm_query_string, application_name, hints) VALUES
('SELECT * FROM orders WHERE order_date >= ?;', '', 'IndexScan(orders idx_date)');
```

YugabyteDB 直接将 pg_hint_plan 作为官方推荐方案，证明了它的实用价值。

## 关键发现

1. **没有任何 SQL 标准定义查询提示**。SQL:1992 至 SQL:2023 都把它视为反模式。所有提示都是 100% 厂商专有，零可移植性。

2. **三大语法流派**：
   - **注释式 `/*+ */`**：Oracle 起源（1990s），被 MySQL（2015 起）、TiDB、OceanBase、StarRocks、Doris、Spark SQL、Hive、Vertica、SAP HANA、Impala、Flink SQL 等广泛采用。
   - **SQL 关键字 / OPTION 子句**：SQL Server 独树一帜的设计，提示是一等公民语法，错误会编译失败。
   - **会话/查询参数**：ClickHouse 的 `SETTINGS`、PostgreSQL 的 `enable_*`、Snowflake 的 `ALTER SESSION` 等；这是云数据仓库和"无提示派"的统一选择。

3. **Oracle 是绝对的提示之王**：100+ 个提示，覆盖从访问路径到查询转换的每个维度，1990 年至今积累。`HINT_REPORT`（19c）才解决了"提示是否生效"的可观测性难题。

4. **SQL Server 的独特贡献**：`OPTION (RECOMPILE)` 和 `OPTIMIZE FOR` 是为应对参数嗅探而生，这一问题在其他数据库中通常用 prepared statement 缓存策略解决。`USE PLAN` 允许直接用 XML 计划替换优化器决策，是工业界最激进的"计划固定"手段。

5. **MySQL 的双轨**：长期只有 `USE/FORCE/IGNORE INDEX`，5.7.7 引入 Oracle 风格 `/*+ */` 后才走向"现代提示"；8.0 的 `SET_VAR` 提示允许在单 SQL 内覆盖任何系统变量，极为灵活。

6. **PostgreSQL 的"无提示"是有意而非缺失**。核心团队明确拒绝，但生态用 pg_hint_plan（NTT）填补了空缺。pg_hint_plan 已成为 PG 生态事实上的提示方案，并被 YugabyteDB 等 fork 数据库直接采纳。

7. **云数据仓库一致选择"无提示"**：Snowflake、BigQuery、Redshift、Trino、Presto、Databend、Firebolt、Materialize 都没有传统提示。它们的论点是统计信息+自动优化+按需扩缩容已足以处理绝大多数场景，硬编码提示与多租户云架构相悖。

8. **分布式数据库的提示创新**：
   - **TiDB** 的 `READ_FROM_STORAGE(TIFLASH[t])` 利用 HTAP 行列双副本架构；
   - **Spark SQL** 的 `BROADCAST`、`COALESCE`、`REPARTITION` 聚焦数据分布而非访问路径，反映分布式计算的真正瓶颈在 shuffle；
   - **CockroachDB / Spanner** 的 `@{...}` 花括号语法是注释式之外的第三种风格。

9. **索引提示几乎所有引擎都有**——即使最坚持"无提示"的 Spanner 和 CockroachDB 也提供了 `FORCE_INDEX`。这暗示索引选择是优化器最常出错的领域。

10. **静默失效是 Oracle 风格提示的最大陷阱**。表名拼错、视图合并后别名变化、提示冲突等都会让提示被悄悄忽略。Oracle 19c 的 `HINT_REPORT` 是行业内最成熟的解决方案；pg_hint_plan 的 `message_level` 也提供类似可观测性。MySQL 风格的 hint 则相对沉默。

11. **DB2 的 optimization profile** 是工业界最严肃的"代码外提示"机制：DBA 写 XML 注册到数据库，零侵入应用代码。这与 SQL Server 的 Plan Guides、Oracle 的 SQL Plan Baseline 一道构成了"DBA 级提示"的三大方案。

12. **基数提示（Cardinality）极其稀缺**：仅 Oracle、pg_hint_plan、OceanBase、DB2 提供。这是因为基数提示本质上是"告诉优化器数据分布"，正确做法应当是改进统计信息——但当统计信息确实无法收集时（如临时表、复杂表达式），基数提示是最后的逃生通道。

13. **OPTIMIZE FOR n ROWS** 是少数几个进入 SQL 标准草案讨论的提示之一（DB2 最早实现）。它告诉优化器"我只关心前 n 行的响应时间"，等价于 Oracle 的 `FIRST_ROWS(n)`。

14. **Hive 的 `MAPJOIN`、Spark 的 `BROADCAST` 是同一概念的两次发明**——把小表广播到所有执行节点以避免 shuffle。这说明分布式 SQL 引擎的提示需求与单机数据库截然不同。

15. **Snowflake 的 QUERY_TAG / Teradata 的 QUERYBAND / Synapse 的 LABEL** 是"非干预型提示"——它们不影响计划，仅用于审计、计费和监控。这是云时代提示设计的新方向：让 DBA 看见查询，而非让用户操控计划。
