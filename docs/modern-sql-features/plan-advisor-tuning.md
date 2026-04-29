# SQL 调优顾问与索引建议 (SQL Tuning Advisor and Index Advisor)

DBA 拿到一条慢 SQL，最希望听到的不是"加点内存"，而是"在 (col_a, col_b) 上建覆盖索引可以从全表扫描变为索引查找，预计耗时从 12 秒降到 35 毫秒"——SQL 调优顾问 (SQL Tuning Advisor) 与索引顾问 (Index Advisor) 就是把这种判断从专家头脑搬进数据库内核的特性。它跨越了基于规则的启发式 (rule-based heuristics)、基于代价模型的 what-if 分析、以及最近十年兴起的机器学习 (ML-based) 自动调优三个时代。

## SQL 标准定义

**SQL 标准（ISO/IEC 9075）从未定义调优顾问、索引建议或自动调优相关的语法。** 这是一个完全由各厂商自行定义、缺乏标准化的领域，原因可以归结为以下几点：

1. **优化器是引擎私有领域**：SQL 标准只定义查询语义，不规定执行计划的形态，更不会规定如何"建议"一个执行计划。
2. **代价模型差异巨大**：行存与列存、本地与分布式、磁盘与内存的代价单位完全不同，不可能统一。
3. **索引体系差异巨大**：B-Tree、LSM、Bitmap、GIN、Inverted、ColumnStore 在不同引擎中的命名与语义完全不同。
4. **建议的输出形式无法标准化**：有的引擎输出 SQL profile，有的输出索引 DDL，有的输出 hint，有的直接自动落地。

因此，本文是一份纯粹的**实现对比**，不存在"标准与各引擎差异"这一维度的讨论。

## 支持矩阵（综合）

### 缺失索引提示与 SQL 调优顾问

| 引擎 | 缺失索引提示 | SQL 调优顾问 | 索引顾问 / Access Advisor | 查询计划建议 | 自动索引 / Auto-DOP | 云端 ML 调优 | 主要工具/接口 |
|------|------------|-------------|---------------------------|-------------|--------------------|-------------|--------------|
| Oracle | 通过 SQL Tuning Advisor | DBMS_SQLTUNE (10g+) | SQL Access Advisor (10g+) | SQL Plan Advisor | Auto-Index 19c | OCI Autonomous Database | DBMS_SQLTUNE / DBMS_ADVISOR |
| SQL Server | sys.dm_db_missing_index_* (2005+) | Database Tuning Advisor (2005+) | DTA (含索引/分区) | Query Store + Plan Forcing | Auto-Tuning 2017+ | Azure Automatic Tuning | DTA / sys.dm_db_tuning_recommendations |
| PostgreSQL | hypopg (社区扩展) | -- | pg_qualstats + PoWA | EXPLAIN + auto_explain | -- | RDS Performance Insights | hypopg / pg_qualstats |
| Aurora PostgreSQL | hypopg | DevOps Guru SQL Insights | RDS Performance Insights | Performance Insights | -- | Aurora ML Recommendations | DevOps Guru |
| Aurora MySQL | -- | DevOps Guru SQL Insights | -- | Performance Insights | -- | Aurora ML Recommendations | DevOps Guru |
| MySQL | -- | -- | -- | -- | -- | -- | Workbench Performance Reports / tuning-primer.sh |
| MariaDB | -- | -- | -- | -- | -- | -- | mysqltuner.pl |
| SQLite | -- | -- | -- | -- | -- | -- | EXPLAIN QUERY PLAN |
| DB2 | db2advis (设计顾问) | db2tuneutil | Design Advisor | Plan Lock | -- | -- | db2advis |
| Snowflake | -- | Query Profile 建议 | -- | Query Profile | Auto-Clustering / Search Optimization | Cortex ML hint | Query Profile |
| BigQuery | -- | Recommender (BigQuery Insights) | -- | Query Plan stages | -- | Recommender + ML | BigQuery Recommender |
| Redshift | -- | Advisor | Auto-Sortkey | Query Optimization | Auto-Distribute / Sort | -- | Redshift Advisor |
| Synapse | -- | -- | -- | DMV 建议 | -- | Auto-Statistics / Workload Mgmt | sys.dm_db_missing_index_* |
| Azure SQL | sys.dm_db_missing_index_* | DTA + Recommendations | Automatic Index Tuning (2017+) | Query Store | Auto-Tuning | Azure ML auto-tuning | Automatic Tuning |
| Teradata | -- | Index Wizard | Statistics Wizard | Visual Explain | -- | -- | Teradata Index Wizard |
| Vertica | -- | Database Designer | Database Designer | EXPLAIN | -- | -- | Database Designer |
| ClickHouse | -- | -- | -- | EXPLAIN | -- | -- | clickhouse-benchmark |
| DuckDB | -- | -- | -- | EXPLAIN ANALYZE | -- | -- | EXPLAIN |
| MonetDB | -- | -- | -- | TRACE / EXPLAIN | -- | -- | TRACE |
| Trino | -- | -- | -- | EXPLAIN ANALYZE | -- | -- | EXPLAIN |
| Presto | -- | -- | -- | EXPLAIN | -- | -- | EXPLAIN |
| Hive | -- | -- | -- | EXPLAIN | -- | -- | EXPLAIN EXTENDED |
| Spark SQL | -- | -- | -- | EXPLAIN COST | AQE 自适应 | -- | EXPLAIN |
| Databricks | -- | Photon Cost Advisor | -- | Query Profile | Predictive I/O | Genie ML hint | Query Profile |
| Flink SQL | -- | -- | -- | EXPLAIN | -- | -- | EXPLAIN |
| StarRocks | -- | -- | -- | EXPLAIN COSTS | -- | -- | EXPLAIN |
| Doris | -- | -- | -- | EXPLAIN | -- | -- | EXPLAIN |
| TiDB | Index Advisor (实验) | Statement Summary | -- | EXPLAIN ANALYZE | -- | -- | TiDB Dashboard |
| OceanBase | OutLine + Advisor | DBMS_SQLTUNE 兼容 | -- | EXPLAIN | -- | -- | DBMS_SQLTUNE |
| PolarDB | DAS Advisor | DAS SQL Advisor | DAS Index Advisor | DAS | DAS Auto-Index | DAS ML | DAS |
| GaussDB | DBMind | DBMind Advisor | DBMind Index Advisor | DBMind | -- | -- | DBMind |
| openGauss | DBMind | DBMind Advisor | DBMind Index Advisor | DBMind | -- | -- | DBMind |
| CockroachDB | EXPLAIN ANALYZE 提示 | -- | Index Recommendations | EXPLAIN | -- | DB Console Recommendations | DB Console |
| YugabyteDB | hypopg | -- | -- | EXPLAIN ANALYZE | -- | -- | hypopg |
| SingleStore | -- | -- | -- | EXPLAIN | -- | -- | EXPLAIN |
| Greenplum | -- | -- | -- | EXPLAIN | -- | -- | EXPLAIN |
| Yellowbrick | -- | -- | -- | EXPLAIN | -- | -- | EXPLAIN |
| Exasol | -- | -- | -- | PROFILE | -- | -- | PROFILE |
| Firebolt | -- | -- | -- | EXPLAIN | -- | -- | EXPLAIN |
| SAP HANA | Plan Stability Advisor | SQL Plan Cache 分析 | Index Advisor (HANA Studio) | Plan Visualizer | -- | -- | SAP HANA Studio |
| Informix | -- | -- | -- | EXPLAIN | -- | -- | SET EXPLAIN |
| Firebird | -- | -- | -- | -- | -- | -- | trace API |
| H2 | -- | -- | -- | EXPLAIN | -- | -- | EXPLAIN |
| HSQLDB | -- | -- | -- | EXPLAIN PLAN | -- | -- | EXPLAIN |
| Derby | -- | -- | -- | RUNTIMESTATISTICS | -- | -- | RUNTIMESTATISTICS |
| Athena | -- | -- | -- | EXPLAIN ANALYZE | -- | -- | Trino EXPLAIN |
| Spanner | -- | -- | -- | Query Stats (INFORMATION_SCHEMA) | -- | -- | Cloud Console |
| TimescaleDB | hypopg | -- | -- | EXPLAIN ANALYZE | -- | -- | timescaledb_toolkit |
| Crate DB | -- | -- | -- | EXPLAIN | -- | -- | EXPLAIN |
| QuestDB | -- | -- | -- | EXPLAIN | -- | -- | EXPLAIN |
| InfluxDB (SQL) | -- | -- | -- | EXPLAIN | -- | -- | EXPLAIN |
| Materialize | -- | -- | -- | EXPLAIN | -- | -- | EXPLAIN |
| RisingWave | -- | -- | -- | EXPLAIN | -- | -- | EXPLAIN |

> 统计：47+ 个引擎中，**仅 8 个商业数据库**提供了内置的 SQL 调优顾问 (Oracle/SQL Server/DB2/Teradata/Vertica/Redshift/Snowflake/SAP HANA)；**18+ 个引擎**通过 EXPLAIN 提供基础诊断信息；**10+ 个引擎**通过云控制台或第三方工具实现 ML 调优。

### 核心能力对比（仅商用与云数据库）

| 能力 | Oracle | SQL Server | Azure SQL | Snowflake | Redshift | BigQuery | DB2 | Aurora |
|------|--------|------------|-----------|-----------|----------|----------|-----|--------|
| 缺失索引检测 | Auto-Index | DMV | Automatic Tuning | -- | Advisor | Recommender | db2advis | DevOps Guru |
| What-if 索引分析 | SQL Access Advisor | DTA | DTA | -- | -- | -- | db2advis | -- |
| 自动索引创建 | Auto-Index 19c | Auto-Tuning 2017+ | Automatic 2017+ | -- | -- | -- | -- | -- |
| 计划重写建议 | SQL Tuning Advisor | DTA | DTA | -- | -- | -- | db2advis | -- |
| ML 模型调优 | OCI Autonomous | -- | Auto-Tuning | Cortex (limited) | Auto Sortkey | Recommender | -- | DevOps Guru |
| 计划强制 | SQL Plan Baselines | Plan Forcing | Plan Forcing | -- | -- | -- | Plan Lock | -- |
| 索引使用监控 | DBA_INDEX_USAGE | sys.dm_db_index_usage_stats | sys.dm_db_index_usage_stats | -- | -- | -- | MON_GET_INDEX | -- |
| 工作负载捕获 | AWR / Workload Repo | DTA Workload | Query Store | Query History | Workload Mgmt | INFORMATION_SCHEMA.JOBS | Workload | Performance Insights |

### 索引建议的算法分类

| 类别 | 代表实现 | 工作机制 |
|------|---------|---------|
| 基于规则 | MySQL Workbench Performance Reports | 阈值与启发式（如 `select scan>x%`） |
| 基于负载 + What-if | DTA, db2advis, SQL Access Advisor | 模拟 hypothetical 索引计算代价差 |
| 基于代价模型 | hypopg, pg_qualstats | 使用 PostgreSQL 优化器对虚拟索引计算代价 |
| 在线 ML 探索 | Oracle Auto-Index, Azure Automatic Tuning | 影子模式 + A/B 测试 + 自动回退 |
| 离线 ML 推理 | DevOps Guru, BigQuery Recommender | 历史负载 + ML 模型生成索引/SQL 建议 |
| 强化学习 | 学术原型（Bao, NEO, NoisePage） | 计划探索的 RL agent，未广泛商用 |

## 各引擎实现详解

### Oracle SQL Tuning Advisor（DBMS_SQLTUNE，10g 起）

Oracle 是 SQL 调优顾问的"鼻祖"。从 10g (2003) 开始，Oracle 在数据库内核中嵌入了一个完整的"自动 SQL 调优"框架，到 19c (2019) 进一步加入 Auto-Index 实现了"无人值守"的索引管理。

#### DBMS_SQLTUNE 基础用法

```sql
-- 1. 创建调优任务
DECLARE
    task_name VARCHAR2(30);
BEGIN
    task_name := DBMS_SQLTUNE.CREATE_TUNING_TASK(
        sql_text   => 'SELECT /*+ FULL(o) */ * FROM orders o WHERE o.customer_id = 100',
        bind_list  => sql_binds(anydata.ConvertNumber(100)),
        task_name  => 'tune_slow_orders',
        time_limit => 600,
        description => 'Tune the slow customer query'
    );
END;
/

-- 2. 执行任务
EXEC DBMS_SQLTUNE.EXECUTE_TUNING_TASK('tune_slow_orders');

-- 3. 查看建议报告
SELECT DBMS_SQLTUNE.REPORT_TUNING_TASK('tune_slow_orders') FROM DUAL;

-- 4. 接受 SQL Profile
EXEC DBMS_SQLTUNE.ACCEPT_SQL_PROFILE(
    task_name => 'tune_slow_orders',
    name      => 'profile_orders',
    force_match => TRUE);
```

#### Tuning Advisor 的内部分析步骤

Oracle 的 Tuning Advisor 内部会做四件事：

1. **统计信息分析（Statistics Analysis）**：检测过期、缺失或不准确的统计。
2. **SQL Profiling**：通过执行采样验证基数估计，生成调优过的 hint 集合（即 SQL Profile）。
3. **访问路径分析（Access Path Analysis）**：检查是否需要新索引（与 Access Advisor 协作）。
4. **SQL 结构分析（SQL Structure Analysis）**：识别明显低效的写法（如 `WHERE expr(col)` 阻碍索引）。

```sql
-- 自动选择高负载 SQL 进行调优
EXEC DBMS_SQLTUNE.CREATE_TUNING_TASK(
    begin_snap => 1000,
    end_snap   => 1010,
    sql_id     => '5q1y2v8w3y0qd',
    scope      => DBMS_SQLTUNE.scope_comprehensive,
    time_limit => 600,
    task_name  => 'tune_top_sql');
```

#### SQL Access Advisor（10g 起）

Access Advisor 是面向**索引、物化视图、分区**的设计顾问，工作流是：

```sql
-- 1. 创建 Advisor 任务
DECLARE
    task_id NUMBER;
    task_name VARCHAR2(30) := 'ADVISOR_DEMO';
BEGIN
    DBMS_ADVISOR.CREATE_TASK(
        advisor_name => 'SQL Access Advisor',
        task_name    => task_name);

    -- 2. 设置参数
    DBMS_ADVISOR.SET_TASK_PARAMETER(task_name, 'ANALYSIS_SCOPE', 'ALL');
    DBMS_ADVISOR.SET_TASK_PARAMETER(task_name, 'MODE',           'COMPREHENSIVE');
    DBMS_ADVISOR.SET_TASK_PARAMETER(task_name, 'TIME_LIMIT',     1800);

    -- 3. 添加工作负载（来自 SQL Tuning Set）
    DBMS_ADVISOR.ADD_STS_REF(task_name, NULL, 'MY_STS');

    -- 4. 执行
    DBMS_ADVISOR.EXECUTE_TASK(task_name);
END;
/

-- 5. 查看建议
SELECT command, attr1 FROM dba_advisor_actions WHERE task_name = 'ADVISOR_DEMO';

-- 6. 生成可执行脚本
SELECT DBMS_ADVISOR.GET_TASK_SCRIPT('ADVISOR_DEMO') FROM DUAL;
```

输出示例：

```sql
CREATE INDEX "SH"."ORD_CUSTOMER_IX"
    ON "SH"."ORDERS" ("CUSTOMER_ID","ORDER_DATE")
    COMPUTE STATISTICS;

CREATE MATERIALIZED VIEW "SH"."MV_SALES_BY_CUST"
    REFRESH FAST ON COMMIT
    AS SELECT customer_id, SUM(amount) FROM sales GROUP BY customer_id;
```

#### Auto-Index（19c 起）

Auto-Index 是 Oracle 19c 推出的**无人值守索引管理**，把 Access Advisor 从手动批处理变成了后台守护进程：

```sql
-- 1. 全局开启 Auto-Index
EXEC DBMS_AUTO_INDEX.CONFIGURE('AUTO_INDEX_MODE', 'IMPLEMENT');
-- 模式: OFF / REPORT ONLY / IMPLEMENT

-- 2. 设置保留期与表空间
EXEC DBMS_AUTO_INDEX.CONFIGURE('AUTO_INDEX_RETENTION_FOR_AUTO',  '373');
EXEC DBMS_AUTO_INDEX.CONFIGURE('AUTO_INDEX_DEFAULT_TABLESPACE', 'AUTO_TS');

-- 3. 排除特定 schema
EXEC DBMS_AUTO_INDEX.CONFIGURE('AUTO_INDEX_SCHEMA',
    schema => 'HR',
    allow  => FALSE);

-- 4. 查看自动创建的索引
SELECT index_name, table_name, auto, visibility
FROM dba_indexes WHERE auto = 'YES';

-- 5. 查看 Auto-Index 报告
SELECT DBMS_AUTO_INDEX.REPORT_ACTIVITY(
    activity_start => SYSTIMESTAMP - 7,
    activity_end   => SYSTIMESTAMP) FROM DUAL;
```

Auto-Index 的工作机制（参见后文"Oracle Auto-Index 19c 深度解析"一节）：

1. **每 15 分钟一次**捕获 SQL 工作负载
2. 对每条 SQL 用 Access Advisor 算法计算候选索引
3. 候选索引以 **INVISIBLE + UNUSABLE** 状态创建（不被 SQL 选用，但可以收集元数据）
4. 在影子环境中验证索引带来的性能改善
5. 满足阈值（默认改善 ≥ 30%）的索引被设为 **VISIBLE**
6. 长期未被使用的索引会被自动 DROP（默认 373 天）

### SQL Server Database Tuning Advisor (DTA) 与 Missing Index DMV

SQL Server 在 2005 年同时引入了两套机制：**DTA**（重量级离线工具）与 **Missing Index DMV**（轻量级在线诊断）。

#### Missing Index DMV（in-memory，毫秒级）

每次 SQL Server 优化器编译查询计划时，如果发现"如果有某个索引代价会更低"，就会把这个建议记录到 `sys.dm_db_missing_index_*` 系列 DMV：

```sql
-- 三个核心 DMV
-- sys.dm_db_missing_index_details      : 索引列定义（equality / inequality / included）
-- sys.dm_db_missing_index_groups       : 详情与统计数据的关联表
-- sys.dm_db_missing_index_group_stats  : 使用次数、平均代价、改进百分比

-- 经典查询：按改进收益排序
SELECT TOP 20
    'CREATE INDEX [IX_' + OBJECT_NAME(mid.object_id) + '_' +
    REPLACE(REPLACE(REPLACE(ISNULL(mid.equality_columns,''),', ','_'),'[',''),']','')
    + '] ON ' + mid.statement +
    ' (' + ISNULL(mid.equality_columns,'') +
    CASE WHEN mid.equality_columns IS NOT NULL AND mid.inequality_columns IS NOT NULL
         THEN ',' ELSE '' END +
    ISNULL(mid.inequality_columns,'') + ')' +
    ISNULL(' INCLUDE (' + mid.included_columns + ')','') AS create_index_statement,
    migs.user_seeks * migs.avg_total_user_cost * (migs.avg_user_impact * 0.01) AS improvement_measure,
    migs.last_user_seek,
    migs.user_seeks,
    migs.avg_total_user_cost,
    migs.avg_user_impact
FROM sys.dm_db_missing_index_groups       mig
JOIN sys.dm_db_missing_index_group_stats  migs ON mig.index_group_handle = migs.group_handle
JOIN sys.dm_db_missing_index_details      mid  ON mig.index_handle       = mid.index_handle
ORDER BY improvement_measure DESC;
```

DMV 的局限性（详见后文"SQL Server Missing Index DMV 细节"一节）：

- 仅追踪到 **500 个**缺失索引建议；超过的会被丢弃
- 不考虑现有索引的覆盖关系（可能建议与已有索引大量重叠的索引）
- 不区分 INCLUDE 列的最优顺序（详情列顺序无意义）
- 服务重启后清零
- 不会跨查询合并建议（同一表上不同 WHERE 条件会产生多条建议）

#### Database Tuning Advisor (DTA, 2005+)

DTA 是图形化 + 命令行的**离线设计顾问**：

```bash
# DTA 命令行
dta.exe -S localhost -d AdventureWorks
        -if workload.sql            # 工作负载文件
        -of recommendation.sql      # 输出 DDL 脚本
        -ox session.xml             # 会话日志
        -fa IDX_IV                  # 物理设计：索引 + 索引视图
        -fp NONE                    # 分区策略
        -fk ALL                     # 保留所有现有索引
        -A 60                       # 时间限制（分钟）
```

DTA 内部把"有哪些索引/索引视图/分区"的可能性视作搜索空间，对每条 SQL 评估 what-if 代价：

```
DTA 算法（2007 VLDB 论文 "Index Selection for Databases: A Hardness Study"）:

1. 候选生成 (Candidate Generation):
   - 解析 SQL，提取所有可索引列
   - 单列、双列、三列组合（受配置限制）
   - 加上 INCLUDE 列、过滤索引、列存索引

2. What-if 评估:
   - 通过 sp_executesql + WITH RECOMPILE 调用优化器
   - sys.dm_db_xtp_hash_index_stats 模拟统计信息
   - 优化器返回带有"假想"索引的执行计划与代价

3. 配置搜索:
   - 把候选索引集组合成"配置 (configuration)"
   - 受存储约束、最大索引数约束
   - 贪心或局部搜索找最优配置

4. 输出脚本:
   - CREATE INDEX, CREATE INDEXED VIEW, CREATE PARTITION SCHEME
```

#### Auto-Tuning（SQL Server 2017+ 与 Azure SQL）

```sql
-- 启用自动调优（2017+）
ALTER DATABASE current SET AUTOMATIC_TUNING (FORCE_LAST_GOOD_PLAN = ON);
ALTER DATABASE current SET AUTOMATIC_TUNING (CREATE_INDEX  = ON);  -- 仅 Azure SQL
ALTER DATABASE current SET AUTOMATIC_TUNING (DROP_INDEX    = ON);  -- 仅 Azure SQL

-- 查看自动调优建议
SELECT reason, score, state, details
FROM sys.dm_db_tuning_recommendations;

-- 查看自动应用的索引
SELECT * FROM sys.dm_db_tuning_recommendations
WHERE type = 'CreateIndex' AND state = 'Success';
```

`FORCE_LAST_GOOD_PLAN` 是基于 Query Store 的"自动计划修正"：

1. 在 Query Store 中识别**性能回退**（regression）的查询
2. 自动用上一个良好计划强制（force）
3. 验证强制后性能确实改善（CPU 时间、Logical Reads）
4. 验证失败则自动撤销

### Azure SQL Automatic Index Tuning

Azure SQL Database 在 2017 年扩展了 SQL Server 的自动调优，增加了**自动建索引/删索引**能力：

```sql
-- 启用所有自动调优选项
ALTER DATABASE current SET AUTOMATIC_TUNING = AUTO;

-- 单独控制
ALTER DATABASE current SET AUTOMATIC_TUNING (
    FORCE_LAST_GOOD_PLAN = ON,
    CREATE_INDEX         = ON,
    DROP_INDEX           = ON);
```

工作流：

1. 引擎从 Missing Index DMV、Query Store、QDS（Query Data Store）综合评估
2. 候选索引在**影子模式**下评估（不实际创建）
3. 通过后**自动 CREATE INDEX**
4. 创建后**18 小时观察期**：测量 CPU、duration、reads
5. 改善 → 保留；回退 → 自动 DROP INDEX

### PostgreSQL hypopg 与生态

PostgreSQL 核心从未提供索引顾问，但社区生态相当活跃：

#### hypopg（Hypothetical Indexes，社区扩展）

hypopg 由 Julien Rouhaud 开发，允许"假装"创建索引、用 EXPLAIN 看代价、然后丢弃，**不实际占用存储**。

```sql
-- 安装
CREATE EXTENSION hypopg;

-- 1. 创建假想索引
SELECT * FROM hypopg_create_index('CREATE INDEX ON orders (customer_id, order_date)');
-- indexrelid | indexname
-- -----------+-----------------------------
-- 16442      | <16442>btree_orders_customer_id_order_date

-- 2. EXPLAIN 看是否被使用
EXPLAIN SELECT * FROM orders WHERE customer_id = 100;
-- 应该看到 Index Scan using <16442>btree_orders_customer_id_order_date

-- 3. 列出所有假想索引
SELECT * FROM hypopg_list_indexes;

-- 4. 估计大小
SELECT * FROM hypopg_relation_size(16442);

-- 5. 丢弃
SELECT hypopg_reset();
```

hypopg 的工作机制：通过 hook 接管 PostgreSQL planner 的索引扫描代价计算，向优化器注入"虚拟索引"。**不会触及表数据，几毫秒内完成代价评估**。

#### pg_qualstats（谓词统计）

pg_qualstats 由 Julien Rouhaud 开发，记录所有 WHERE 子句中谓词的统计信息：

```sql
CREATE EXTENSION pg_qualstats;

-- pg_qualstats 视图
SELECT relname,
       array_agg(distinct attname) AS columns,
       sum(count) AS total_count,
       sum(nbfiltered) AS total_filtered,
       sum(execution_count) AS exec_count
FROM pg_qualstats() q
JOIN pg_class    c  ON c.oid = q.lrelid
JOIN pg_attribute a ON a.attrelid = c.oid AND a.attnum = q.lattnum
GROUP BY relname
ORDER BY total_count DESC LIMIT 20;
```

#### pg_advisor / PoWA（PostgreSQL Workload Analyzer）

PoWA 是 pg_qualstats + pg_stat_kcache + pg_stat_statements 的综合控制台，提供 Web UI 索引建议：

```bash
# PoWA 工作流
1. pg_stat_statements 记录"慢 SQL"
2. pg_qualstats 记录每个谓词的"过滤率"
3. PoWA 后端聚合：哪些列被过滤最多？
4. 用 hypopg 模拟候选索引
5. 输出"建议索引"列表 + 预估收益
```

PoWA 的索引建议逻辑（伪代码）：

```python
for column in columns_with_high_filter_count:
    candidate_index = f"CREATE INDEX ON {column.table} ({column.name})"

    # 用 hypopg 创建假想索引
    hypopg_create_index(candidate_index)

    # 重新规划负载中受影响的 SQL
    new_total_cost = sum(plan_cost(sql) for sql in affected_sqls)
    saving = original_total_cost - new_total_cost

    if saving > threshold:
        recommend(candidate_index, saving)

    hypopg_reset()
```

### MySQL Workbench Performance Reports 与 tuning-primer.sh

MySQL **没有**内置 SQL 调优顾问，社区生态主要靠脚本：

#### MySQL Workbench Performance Reports

Workbench 提供基于 `performance_schema` 的可视化报表：

- **High Cost SQL Statements**：`sum_timer_wait` 排序的慢 SQL
- **Top SQL Statements with Full Table Scans**：`SUM_NO_INDEX_USED > 0`
- **Statements with Errors or Warnings**：检测潜在问题
- **Statements that Use Temporary Tables**：内存与磁盘临时表使用
- **High Memory Usage**：events_statements_history 中的内存

```sql
-- Workbench 内部使用类似的查询
SELECT digest_text,
       count_star,
       sum_timer_wait/1e12 AS total_sec,
       avg_timer_wait/1e9 AS avg_ms,
       sum_rows_examined,
       sum_rows_sent,
       sum_no_index_used,
       sum_select_full_join
FROM performance_schema.events_statements_summary_by_digest
WHERE schema_name = 'app'
  AND sum_no_index_used > 0
ORDER BY sum_timer_wait DESC LIMIT 50;
```

#### tuning-primer.sh / mysqltuner.pl

老牌脚本工具，分析的是**配置参数**而非 SQL：

```bash
# 检查内存配置、缓冲池、临时表、慢查询设置
./tuning-primer.sh

# mysqltuner.pl 类似
mysqltuner.pl --user root --pass xxx
```

输出示例（mysqltuner 风格）：

```
[OK] Maximum reached memory usage: 4.5G (56% of installed RAM)
[!!] InnoDB buffer pool / data size: 1.0G/4.5G - too small
[OK] Slow queries: 0% (1/2k)
[!!] Joins performed without indexes: 12 - increase join_buffer_size
[OK] Temporary tables created on disk: 5%

Recommendations:
  innodb_buffer_pool_size (>= 4G)
  join_buffer_size (>= 4M, but joins should be indexed first)
  Run OPTIMIZE TABLE to defragment tables
```

### Snowflake Query Profile Suggestions

Snowflake 没有传统的"调优顾问"，但其 **Query Profile** UI 中会主动提示常见问题：

- **Most Expensive Nodes**：标红代价最高的 operator
- **Bytes Spilled to Local/Remote Storage**：警告内存不足
- **Cache Hit Ratio**：低于阈值时建议使用 Result Cache 或预热
- **Cluster Key Suggestion**：基于 micropartition 扫描建议聚集键

```sql
-- Query Profile 数据可通过 SQL 访问
SELECT query_id,
       compilation_time,
       execution_time,
       bytes_scanned,
       bytes_spilled_to_local_storage,
       bytes_spilled_to_remote_storage,
       partitions_scanned,
       partitions_total
FROM snowflake.account_usage.query_history
WHERE start_time >= DATEADD(day, -1, CURRENT_TIMESTAMP())
  AND bytes_spilled_to_remote_storage > 0
ORDER BY bytes_spilled_to_remote_storage DESC LIMIT 50;

-- 自动聚类 / Auto-Clustering 接近"自动索引"概念
ALTER TABLE orders CLUSTER BY (order_date, customer_id);
-- Snowflake 后台自动重组 micropartition 以匹配聚集键

-- Search Optimization Service（点查询加速）
ALTER TABLE orders ADD SEARCH OPTIMIZATION ON EQUALITY(order_id);
-- 后台自动构建 SOS 索引服务，无需运维
```

### BigQuery Query Plan Stages 与 Recommender

BigQuery 同样没有传统调优顾问，但提供两类机制：

#### Query Plan Stages

```sql
-- 在 INFORMATION_SCHEMA 中查看
SELECT job_id,
       statement_type,
       total_slot_ms,
       total_bytes_processed,
       cache_hit,
       query_info.optimization_details
FROM `project.region-us`.INFORMATION_SCHEMA.JOBS
WHERE creation_time > TIMESTAMP_SUB(CURRENT_TIMESTAMP(), INTERVAL 1 DAY)
  AND statement_type = 'SELECT'
ORDER BY total_slot_ms DESC LIMIT 50;
```

#### BigQuery Recommender (Recommender API)

Google Cloud 的 Recommender 服务对 BigQuery 提供基于 ML 的建议：

- **物化视图建议**：哪些重复 GROUP BY 适合做 MV
- **分区与聚类建议**：基于查询模式
- **保留期建议**：长期未访问的表

```bash
# gcloud 命令查看建议
gcloud recommender recommendations list \
    --project=$PROJECT \
    --location=global \
    --recommender=google.bigquery.materializedView.Recommender
```

## Oracle Auto-Index 19c 深度解析

Auto-Index 是 Oracle 19c 推出的、迄今为止最完整的"无人值守索引管理"实现。它把 Access Advisor 算法、SQL Plan Management、Workload Repository 整合成一个后台守护进程。

### Auto-Index 任务的生命周期

```
每 15 分钟（默认）一个任务周期:

阶段 1: 候选识别
  ┌─────────────────────────────────────┐
  │ AWR / SGA Cursor Cache              │
  │ ↓                                   │
  │ 抽取最近窗口内的 SQL                  │
  │ ↓                                   │
  │ 排除: AUTO_INDEX_SCHEMA = FALSE      │
  │ 排除: 系统/SYS schema                │
  │ 排除: 临时表、外部表、IOT             │
  │ ↓                                   │
  │ 输出: SQL Tuning Set                 │
  └─────────────────────────────────────┘

阶段 2: 候选生成
  ┌─────────────────────────────────────┐
  │ 用 Access Advisor 算法               │
  │ ↓                                   │
  │ 单列索引、复合索引、函数索引            │
  │ ↓                                   │
  │ 候选索引以 INVISIBLE + UNUSABLE 创建   │
  │ ↓                                   │
  │ DBA_INDEXES 中 AUTO = 'YES'          │
  └─────────────────────────────────────┘

阶段 3: What-if 验证（核心）
  ┌─────────────────────────────────────┐
  │ 把候选索引置为 INVISIBLE + USABLE     │
  │ ↓                                   │
  │ 在影子优化器中重新生成执行计划         │
  │ ↓                                   │
  │ 比较: 原计划代价 vs 新计划代价         │
  │ ↓                                   │
  │ 满足阈值 (默认改善 > 30%) → 通过       │
  └─────────────────────────────────────┘

阶段 4: A/B 测试
  ┌─────────────────────────────────────┐
  │ 对样本 SQL 真实执行                   │
  │ ↓                                   │
  │ 测量: 执行时间、CPU、I/O              │
  │ ↓                                   │
  │ 通过 → 索引设为 VISIBLE                │
  │ 失败 → 索引保持 INVISIBLE 并标记失败   │
  └─────────────────────────────────────┘

阶段 5: 后续监控
  ┌─────────────────────────────────────┐
  │ DBA_INDEX_USAGE 跟踪使用情况          │
  │ ↓                                   │
  │ 长期未使用 (默认 373 天) → 自动 DROP   │
  │ 持续监控因索引导致的回退 → 触发回退    │
  └─────────────────────────────────────┘
```

### 关键配置参数

```sql
-- 查看当前配置
SELECT parameter_name, parameter_value FROM dba_auto_index_config;

-- 主要参数
EXEC DBMS_AUTO_INDEX.CONFIGURE('AUTO_INDEX_MODE', 'IMPLEMENT');
-- OFF | REPORT ONLY | IMPLEMENT

EXEC DBMS_AUTO_INDEX.CONFIGURE('AUTO_INDEX_RETENTION_FOR_AUTO',  '373');
-- 自动索引未使用多久后被删除（天）

EXEC DBMS_AUTO_INDEX.CONFIGURE('AUTO_INDEX_RETENTION_FOR_MANUAL', NULL);
-- 手动索引未使用的删除策略（默认 NULL，不自动删手动索引）

EXEC DBMS_AUTO_INDEX.CONFIGURE('AUTO_INDEX_DEFAULT_TABLESPACE', 'AUTO_TS');
-- 自动索引的默认表空间

EXEC DBMS_AUTO_INDEX.CONFIGURE('AUTO_INDEX_SPACE_BUDGET', '50');
-- 自动索引最多占用多少 % 表空间
```

### Auto-Index 报告样例

```sql
SELECT DBMS_AUTO_INDEX.REPORT_ACTIVITY() FROM DUAL;
```

```
GENERAL INFORMATION
-------------------------------------------------------------------------------
 Activity start         : 25-OCT-2026 00:00:00
 Activity end           : 25-OCT-2026 23:59:59
 Executions completed   : 96
 Executions interrupted : 0
 Executions with fatal error : 0

SUMMARY (AUTO INDEXES)
-------------------------------------------------------------------------------
 Index candidates                          : 47
 Indexes created (visible / invisible)     : 12 / 5
 Space used                                : 3.2 GB (visible) / 1.4 GB (invisible)
 Indexes dropped                           : 2
 SQL statements verified                   : 124
 SQL statements improved (improvement >= 30%) : 89

SUMMARY (MANUAL INDEXES)
-------------------------------------------------------------------------------
 Unused indexes : 7
 Space used     : 0.8 GB
 Space reclaimed: 0 GB

INDEX DETAILS
-------------------------------------------------------------------------------
1. The following indexes were created:

  Schema  Index Name                   Table     Columns                Visible
  ------  --------------------------   --------  ---------------------  -------
  SH      SYS_AI_xxxxxxxxxxx           SALES     CUST_ID, TIME_ID       YES
  SH      SYS_AI_yyyyyyyyyyy           ORDERS    CUSTOMER_ID            YES

VERIFICATION DETAILS
-------------------------------------------------------------------------------
SQL ID: 5q1y2v8w3y0qd
  Original Plan Cost: 4823
  New Plan Cost: 215
  Improvement: 95.5%
  Verdict: PASS

SQL ID: a8b9c0d1e2f34
  Original Plan Cost: 1250
  New Plan Cost: 980
  Improvement: 21.6%
  Verdict: REJECT (improvement below 30% threshold)
```

### Auto-Index 的失败模式

实战中 Auto-Index 也会出问题，常见的几种：

1. **OLTP 写放大**：在写多读少表上加索引导致 INSERT 变慢，Auto-Index 默认不区分 OLTP/OLAP，需要手动排除。
2. **数据倾斜导致估计偏差**：基数估计在数据倾斜时不准，可能创建无效索引。
3. **多版本问题**：在 RAC 多实例中，索引创建会触发跨实例同步开销。
4. **第三方 ORM 生成的 SQL 多变**：`SELECT col1, col2, ..., colN` 中字段集变化会触发不同候选索引。

```sql
-- 关闭对特定 schema 的 Auto-Index
EXEC DBMS_AUTO_INDEX.CONFIGURE('AUTO_INDEX_SCHEMA',
    schema => 'OLTP_HOT', allow => FALSE);

-- 排除特定表
EXEC DBMS_AUTO_INDEX.CONFIGURE('AUTO_INDEX_TABLE',
    schema_name => 'SH', table_name => 'TX_LOG', allow => FALSE);
```

## SQL Server Missing Index DMV 细节

Missing Index DMV 是 SQL Server 调优中最被滥用、也最被误用的特性。理解其内部机制对正确使用至关重要。

### DMV 字段语义

```sql
-- sys.dm_db_missing_index_details 字段
-- equality_columns:    WHERE col = ?  (适合作为索引前导列)
-- inequality_columns:  WHERE col > ? / IN / BETWEEN
-- included_columns:    SELECT 列表中的非过滤列（INCLUDE 列）
-- statement:           对应的表名 [database].[schema].[table]
```

### 优化器何时记录建议？

SQL Server 优化器在**编译查询计划**时遵循以下规则：

```
对每个表扫描：
  1. 当前最优计划的代价 < 全表扫描代价 / 5：不记录建议
  2. 优化器在搜索空间中考虑过 hypothetical 索引但因约束放弃：记录
  3. 查询包含 OPTION (RECOMPILE)：每次都记录新建议
  4. 查询使用 LOCAL VARIABLE：基数估计不准，建议可能误导
```

### 经典误区

#### 误区 1：直接使用 DMV 输出的 CREATE INDEX

```sql
-- DMV 输出（错误的列顺序）
-- equality_columns: [region], [customer_id]
-- inequality_columns: [order_date]
-- included_columns: [amount], [status]

-- 直接照搬：
CREATE INDEX IX_orders_xxxx ON orders (region, customer_id, order_date)
    INCLUDE (amount, status);

-- 实际上：列顺序应该按选择性而非 DMV 输出排序
-- 如果 customer_id 选择性更高，应该改为：
CREATE INDEX IX_orders_better ON orders (customer_id, region, order_date)
    INCLUDE (amount, status);
```

#### 误区 2：建议数量等于建议价值

improvement_measure 才是关键：

```
improvement_measure = user_seeks * avg_total_user_cost * (avg_user_impact * 0.01)

含义：
- user_seeks: 假如有这个索引，会被用多少次
- avg_total_user_cost: 当前查询的平均代价
- avg_user_impact: 创建索引后代价能降低多少 %

只考虑前 20-50 条 improvement_measure 最大的建议。
```

#### 误区 3：DMV 在服务重启后清零

DMV 数据是**内存常驻**，不持久化。SQL Server 重启或 `DBCC FREESYSTEMCACHE` 之后清零。

#### 误区 4：500 条建议的硬上限

SQL Server 内部对 missing index 缓存大小有硬限制（约 500 条），超过会**驱逐旧建议**。在大量临时 SQL 的环境中，建议会很快被覆盖。

### 与 Auto-Tuning 的关系

```
Missing Index DMV  ──┐
                     ├──→ Tuning Recommendation Engine ──→ sys.dm_db_tuning_recommendations
Query Store        ──┘                                            │
                                                                  ↓
                                                          AUTOMATIC_TUNING (CREATE_INDEX)
                                                                  │
                                                                  ↓
                                                          自动 CREATE INDEX + 18 小时观察期
```

### 实战 SQL 模板

```sql
-- 1. 同表多个建议合并
WITH suggestions AS (
    SELECT mid.statement,
           mid.equality_columns,
           mid.inequality_columns,
           mid.included_columns,
           migs.user_seeks * migs.avg_total_user_cost * (migs.avg_user_impact * 0.01)
               AS improvement_measure
    FROM sys.dm_db_missing_index_details   mid
    JOIN sys.dm_db_missing_index_groups    mig ON mig.index_handle = mid.index_handle
    JOIN sys.dm_db_missing_index_group_stats migs ON mig.index_group_handle = migs.group_handle
    WHERE migs.user_seeks * migs.avg_total_user_cost * (migs.avg_user_impact * 0.01) > 1000
)
SELECT statement,
       STRING_AGG(equality_columns, ' | ') AS all_equality,
       SUM(improvement_measure) AS total_improvement
FROM suggestions
GROUP BY statement
ORDER BY total_improvement DESC;

-- 2. 验证建议未与现有索引冲突
SELECT TOP 50
    OBJECT_NAME(mid.object_id) AS table_name,
    mid.equality_columns,
    mid.inequality_columns,
    mid.included_columns,
    (SELECT STRING_AGG(c.name, ',')
     FROM sys.indexes i
     JOIN sys.index_columns ic ON i.object_id = ic.object_id AND i.index_id = ic.index_id
     JOIN sys.columns c ON ic.object_id = c.object_id AND ic.column_id = c.column_id
     WHERE i.object_id = mid.object_id) AS existing_index_columns,
    migs.avg_user_impact
FROM sys.dm_db_missing_index_details   mid
JOIN sys.dm_db_missing_index_groups    mig  ON mig.index_handle = mid.index_handle
JOIN sys.dm_db_missing_index_group_stats migs ON mig.index_group_handle = migs.group_handle
ORDER BY migs.avg_user_impact DESC;
```

## 云端 ML 自动调优趋势

最近 5 年，公有云数据库厂商把"自动调优"从规则系统进化到 ML 系统。代表方向：

### Aurora ML-based Recommendations

AWS Aurora（PostgreSQL/MySQL 兼容）通过 **Performance Insights + DevOps Guru** 提供 ML 调优：

```
数据收集：
  - Aurora 引擎层：每秒采集 active sessions、wait events、CPU
  - PG/MySQL 层：performance_schema / pg_stat_statements
  - DevOps Guru：聚合、异常检测

ML 分析：
  - 异常检测：哪些指标偏离基线？
  - 因果归因：异常是因为某条 SQL 还是负载激增？
  - 关联分析：哪些 SQL 共享相同的等待事件模式？

输出建议：
  - "高 CPU SQL：建议加索引 ..."
  - "锁等待激增：建议拆分事务 ..."
  - "回退检测：某条 SQL 计划变化，建议 pg_hint_plan 强制 ..."
```

### Azure SQL Automatic Tuning

```
观察期 (18 hours):
  ┌─────────────────────────────┐
  │ 候选 → CREATE INDEX (实际)   │
  │ ↓                           │
  │ 测量 18 小时的 CPU、Duration │
  │ ↓                           │
  │ 改善？保留                   │
  │ 回退？自动 DROP INDEX        │
  └─────────────────────────────┘

ML 模型:
  - 训练数据: 数百万 Azure SQL 实例的 Query Store
  - 输入: 查询特征向量 + 索引候选 + 系统状态
  - 输出: 创建索引的预期收益概率
  - 阈值: 概率 > 0.85 才进入 18 小时观察期
```

### BigQuery Recommender

```
ML 模型 (Google Cloud Recommender API):
  - 训练: 全球 BigQuery 工作负载（脱敏）
  - 输入特征: 查询模式、表大小、扫描行数、扫描字节、聚合模式
  - 输出: 建议物化视图 / 分区 / 聚类键

建议类型:
  - google.bigquery.materializedView.Recommender
  - google.bigquery.partitioning.Recommender (内部)
  - google.bigquery.cluster.Recommender (内部)
```

### Snowflake Cortex 与未来

```
Snowflake Cortex (2024 GA):
  - 基于 LLM 的"问数据"接口
  - 内嵌 Cost Advisor 提示
  - Snowsight UI 中的"Optimize this query" 按钮

Auto-Clustering & Search Optimization Service:
  - 严格意义不是"调优顾问"，但本质相同：
    用户声明意图 (CLUSTER BY / ADD SEARCH OPTIMIZATION)
    引擎后台自动维护实现 (无需 DBA 干预)
```

### 学术界趋势

```
1. Bao (CMU, 2020): 基于强化学习的查询计划提示
   - 不替换优化器，而是在优化器之上"打提示"
   - 用 RL agent 探索 hint 空间

2. NEO (MIT, 2019): 端到端神经查询优化器
   - 用神经网络替代 cost model
   - 学习 cardinality estimation 的偏差

3. NoisePage (CMU, 2020+): 自治数据库系统
   - 从 buffer pool tuning 到 index selection 全自动
   - 强化学习 + 工作负载预测
```

## 各引擎手动 EXPLAIN 提示提取

不支持调优顾问的引擎，DBA 通常自己从 EXPLAIN 提取信号。下面是各引擎中常见的 EXPLAIN 信号：

### PostgreSQL

```sql
EXPLAIN (ANALYZE, BUFFERS) SELECT * FROM orders WHERE customer_id = 100;

-- 关键信号：
-- Seq Scan ... rows=10000 actual=10000           : 全表扫描
-- Bitmap Index Scan ... rows=100 actual=10       : 估计偏差大 → 重新分析
-- Hash Cond: ... rows=1000 actual=10000          : JOIN 估计偏差
-- Sort Method: external merge  Disk: 200kB        : 工作内存不足
-- Buffers: shared read=10000                      : 大量物理读 → 缓冲池小
```

### MySQL

```sql
EXPLAIN ANALYZE SELECT * FROM orders WHERE customer_id = 100;

-- 关键信号：
-- type = ALL                                     : 全表扫描
-- key = NULL                                     : 未使用索引
-- rows = 1000000                                 : 扫描行数大
-- Extra = Using filesort                         : 排序无索引
-- Extra = Using temporary                        : 临时表
```

### Snowflake

```sql
-- Query Profile 关键警告：
-- "Local Disk Usage" / "Remote Disk Usage" 红色   : 内存不足
-- "Bytes scanned" 远大于 "Bytes returned"          : 缺少聚集键
-- "Pruning" 显示分区裁剪率低                       : 微分区不优
```

### CockroachDB

```sql
EXPLAIN ANALYZE SELECT * FROM orders WHERE customer_id = 100;

-- CockroachDB DB Console 中：
-- Index Recommendations 标签会显示候选索引
-- "Statements" 页面 → "Insights" 显示慢查询根因

-- SQL 中查看：
SELECT * FROM crdb_internal.index_recommendations;
```

### TiDB

```sql
EXPLAIN ANALYZE SELECT * FROM orders WHERE customer_id = 100;

-- TiDB Dashboard：
-- SQL 诊断 → 全表扫描 SQL
-- 慢查询日志聚合
-- 实验性的 Index Advisor (v6.6+)
```

## 调优顾问的实现机制

### What-if 分析的核心：Hypothetical Indexes

所有索引顾问的核心都是 **假装索引存在，让优化器重新算代价**。这一抽象有三种实现方式：

```
方式 1: 修改 catalog（脏方式）
  - 在 system catalog 中插入索引元数据
  - 标记为 "INVISIBLE" 让其他会话不可见
  - 缺点: 元数据需要清理，并发问题
  - 代表: Oracle INVISIBLE INDEX

方式 2: Hook 优化器（hypopg 方式）
  - Hook 进 planner_hook / get_relation_info_hook
  - 在内存中维护虚拟索引列表
  - 优化器询问索引列表时返回虚拟索引
  - 优点: 零开销、不污染 catalog
  - 代表: PostgreSQL hypopg

方式 3: 模拟运行（DTA 方式）
  - DTA 在专门的"假想模式"下提交查询
  - 通过 sp_executesql + WITH RECOMPILE
  - 接收优化器返回的"假如有索引"代价
  - 缺点: 需要 special hook，跨服务版本困难
  - 代表: SQL Server DTA
```

### 候选索引的搜索空间

```
对于一个 N 列的表：
  - 单列索引: N 个
  - 双列索引（有序）: N*(N-1)
  - 三列索引（有序）: N*(N-1)*(N-2)
  - ... 以此类推

总候选数: O(N!)，N=20 时已达 2.4 * 10^18

DTA / Access Advisor 的剪枝：
  1. 只考虑出现在 WHERE / JOIN / ORDER BY / GROUP BY 的列
  2. INCLUDE 列：只考虑出现在 SELECT 列表的列
  3. 列顺序：按选择性 + WHERE 频率排序
  4. 长度: 默认最多 5-7 列复合索引
  5. 工作负载约束: 至少被 N 条 SQL 用到才入选
```

### 代价模型的局限

```
hypopg 等工具的代价是优化器的代价，但优化器代价单位是"内部代价"：
  - PostgreSQL: 等价于"读 1 个 8KB 页 = 1.0"
  - 不等于"秒数"或"美元"

转换为时间需要乘以 cpu_tuple_cost / random_page_cost / seq_page_cost
但这些 GUC 默认值可能与硬件不匹配，导致建议偏差。

Oracle 的代价是"I/O 代价 + CPU 代价 + 网络代价"的加权和：
  - SYSSTAT 中的 SREADTIM / MREADTIM 可校准
  - 但跨数据库版本不兼容
```

### 工作负载捕获

```
不同引擎的工作负载来源：

Oracle:
  - SGA Cursor Cache (V$SQL)
  - AWR (DBA_HIST_SQLSTAT, DBA_HIST_SQLTEXT)
  - SQL Tuning Set (用户主动维护)

SQL Server:
  - Query Store (QDS)
  - Plan Cache (sys.dm_exec_query_stats)
  - Extended Events 捕获文件
  - SQL Trace (deprecated)
  - DTA Workload File (.trc)

PostgreSQL:
  - pg_stat_statements (聚合统计)
  - pg_stat_kcache (扩展)
  - 慢查询日志 + pgBadger 分析

DB2:
  - 包缓存 (MON_GET_PKG_CACHE_STMT)
  - 工作负载管理 (Workload Manager)

云数据库:
  - Snowflake: query_history (account_usage schema)
  - BigQuery: INFORMATION_SCHEMA.JOBS
  - Redshift: STL_QUERY / SVL_QUERY_SUMMARY
```

## 关键发现

经过 47+ 个引擎的对比与多个核心实现的剖析，可以得出几个核心结论：

### 1. SQL 调优顾问是商业数据库的"专属能力"

只有 Oracle、SQL Server、DB2、Teradata、Vertica、SAP HANA、Redshift、Snowflake 等少数商业 / 云数据库提供完整的调优顾问栈。开源关系数据库（MySQL、PostgreSQL、MariaDB、SQLite）核心都不提供。这与商业产品需要为 DBA 减负的市场需求一致：调优顾问是企业级竞争力的体现。

### 2. PostgreSQL 通过生态弥补内核缺失

hypopg / pg_qualstats / PoWA / pg_advisor 共同构成了 PostgreSQL 的索引建议生态。其优势是模块化、轻量、可组合；劣势是需要 DBA 自行整合，没有"一键调优"的体验。

### 3. Oracle 是"自动调优"的先驱

DBMS_SQLTUNE (10g, 2003) → SQL Access Advisor (10g) → SQL Plan Management (11g) → Auto-Index (19c, 2019) 是一条清晰的演进线。Oracle Auto-Index 是当前最完整的"无人值守索引"实现。

### 4. SQL Server Missing Index DMV 是"穷人版"建议

Missing Index DMV 提供了零成本的索引提示，但仅是优化器编译时的副产物，不能替代专业的 DTA 分析。500 条上限、不合并建议、不考虑现有索引是其主要缺陷。

### 5. 自动索引创建仍是高风险特性

即使 Oracle Auto-Index 和 Azure Automatic Tuning 都设有"观察期 + 自动回退"机制，OLTP 写多读少表上的自动索引仍可能造成写放大。最佳实践是：在指定 schema 上启用，长期观察，逐步扩大。

### 6. 云端 ML 调优是未来 5 年趋势

AWS DevOps Guru、Azure Automatic Tuning、Google BigQuery Recommender 都基于全球工作负载训练 ML 模型。这一趋势的核心是"私有云数据无法触及，但模式可以学习"——通过大量脱敏负载训练模型，再部署到具体实例。

### 7. 缺失索引提示 ≠ 应该立刻创建

无论是 Missing Index DMV 还是 hypopg + PoWA 的建议，都需要 DBA 二次校验：列顺序是否最优、是否与现有索引冲突、写放大代价是否可接受。直接照搬建议是反模式。

### 8. 计划稳定性与调优顾问的张力

调优顾问推动"使用更好的计划"，而 SQL Plan Management、Plan Forcing 强调"使用稳定的计划"。两者协同的最佳实践是：

```
新 SQL → 调优顾问推荐计划 → SQL Plan Baseline 锁定
负载演进 → Auto-Index 探索新候选 → 经验证才替换 baseline
```

### 9. EXPLAIN 是所有引擎的最终底盘

在所有 47+ 个引擎中，**EXPLAIN / EXPLAIN ANALYZE 是唯一通用的诊断工具**。即使在没有调优顾问的引擎上，DBA 也能从 EXPLAIN 中提取关键信号（全表扫描、估计偏差、临时表、排序、缓冲池命中）。引擎开发者应该确保 EXPLAIN 输出尽可能详尽且结构化（JSON 格式）。

### 10. 工作负载捕获是调优顾问的命脉

SQL Tuning Advisor 的质量上限取决于工作负载捕获的质量：

- Oracle AWR 默认 8 天保留期，不足以捕获月末批处理
- SQL Server Query Store 默认 30 天，但容量有限
- pg_stat_statements 仅聚合不保留原 SQL，丢失参数化信息
- BigQuery INFORMATION_SCHEMA.JOBS 保留 180 天，但仅在多 region 视图

引擎开发者应该提供：长期保留的工作负载存储 + 自定义 SQL Tuning Set + 与 ML 训练数据导出的标准接口。

## 对引擎开发者的实现建议

### 1. EXPLAIN 输出结构化与机器可读

```
建议:
  - 提供 JSON / Protobuf 格式的 EXPLAIN 输出（PostgreSQL EXPLAIN (FORMAT JSON), Oracle XPLAN, SQL Server SHOWPLAN_XML）
  - 节点级别提供:
    * 估计基数 vs 实际基数
    * 估计代价 vs 实际代价
    * 物理 I/O 与逻辑 I/O
    * 等待事件分布
  - 文本输出在调试时仍是首选，但 ML/LLM 集成需要结构化
```

### 2. Hypothetical Index 抽象

```
为社区生态打开 hook:
  - PostgreSQL: planner_hook + get_relation_info_hook (hypopg 模型)
  - 提供 system view 让虚拟索引可注入
  - INVISIBLE INDEX 是更"标准"的实现，但需要 DDL 与权限管理

避免反模式:
  - 不要要求实际创建索引才能评估代价 (DTA 早期版本的痛点)
  - 不要让 Hypothetical Index 跨会话泄漏
```

### 3. 工作负载捕获的最小集

```
基础数据:
  - SQL 文本（带参数化哈希）
  - 执行次数、总时间、平均时间
  - 实际行数、扫描行数、返回行数
  - 等待事件分布

进阶数据:
  - 谓词级统计 (pg_qualstats 模型)
  - 计划稳定性指标（同一 SQL 不同计划的代价分布）
  - 锁等待与回滚段使用
```

### 4. 自动索引的"验证-观察-回退"框架

```
强制模板:
  1. 候选索引仅在影子模式下评估
  2. 实际创建必须经过 N 个工作日的"观察期"
  3. 观察期内对比:
     - 性能改善 > 阈值
     - 写放大 < 阈值
     - 没有触发计划回退
  4. 失败必须自动回退（DROP INDEX / 标记 INVISIBLE）
  5. 所有动作必须可审计

参数化:
  - AUTO_INDEX_MIN_IMPROVEMENT (默认 30%)
  - AUTO_INDEX_OBSERVATION_PERIOD (默认 18 hours)
  - AUTO_INDEX_MAX_WRITE_REGRESSION (默认 10%)
  - AUTO_INDEX_RETENTION (默认 373 days)
```

### 5. 与计划管理的集成

```
调优顾问的输出应能直接对接计划管理:
  - SQL Profile / SQL Plan Baseline (Oracle)
  - Plan Guide / Plan Forcing (SQL Server)
  - pg_hint_plan (PostgreSQL)

避免:
  - 调优顾问推荐计划，但无法 lock-in
  - 计划管理 lock-in 计划，但调优顾问无法发现新候选
```

### 6. ML 调优的隐私与信任

```
当 ML 模型基于多租户负载训练时:
  - 必须有"我的数据是否被用于训练"的明确开关
  - 训练数据必须脱敏（SQL 文本中的字面量必须被替换）
  - 模型推理结果必须可解释（"为什么建议这个索引"）

信任问题:
  - 自动调优需要"先以 REPORT ONLY 模式运行 N 周"
  - 必须有完整的 audit log（每个动作的输入、输出、决策依据）
  - 必须可一键关闭并回退最近 K 次动作
```

## 参考资料

- Oracle: [DBMS_SQLTUNE Package](https://docs.oracle.com/en/database/oracle/oracle-database/19/arpls/DBMS_SQLTUNE.html)
- Oracle: [SQL Access Advisor](https://docs.oracle.com/en/database/oracle/oracle-database/19/tgsql/sql-access-advisor.html)
- Oracle: [Auto-Index in 19c](https://docs.oracle.com/en/database/oracle/oracle-database/19/tgsql/automatic-indexing.html)
- Oracle: [DBMS_AUTO_INDEX Package](https://docs.oracle.com/en/database/oracle/oracle-database/19/arpls/DBMS_AUTO_INDEX.html)
- SQL Server: [Database Engine Tuning Advisor](https://learn.microsoft.com/en-us/sql/relational-databases/performance/database-engine-tuning-advisor)
- SQL Server: [sys.dm_db_missing_index_details](https://learn.microsoft.com/en-us/sql/relational-databases/system-dynamic-management-views/sys-dm-db-missing-index-details-transact-sql)
- SQL Server: [Automatic Tuning](https://learn.microsoft.com/en-us/sql/relational-databases/automatic-tuning/automatic-tuning)
- Azure SQL: [Automatic Tuning](https://learn.microsoft.com/en-us/azure/azure-sql/database/automatic-tuning-overview)
- PostgreSQL: [hypopg Extension](https://github.com/HypoPG/hypopg)
- PostgreSQL: [pg_qualstats](https://github.com/powa-team/pg_qualstats)
- PostgreSQL: [PoWA - PostgreSQL Workload Analyzer](https://powa.readthedocs.io/)
- MySQL: [Workbench Performance Reports](https://dev.mysql.com/doc/workbench/en/wb-performance-reports.html)
- MySQL: [tuning-primer.sh](https://github.com/BMDan/tuning-primer.sh)
- MariaDB: [mysqltuner.pl](https://github.com/major/MySQLTuner-perl)
- DB2: [db2advis - Design Advisor](https://www.ibm.com/docs/en/db2/11.5?topic=tools-db2advis-db2-design-advisor)
- Snowflake: [Query Profile](https://docs.snowflake.com/en/user-guide/ui-query-profile)
- Snowflake: [Auto-Clustering](https://docs.snowflake.com/en/user-guide/tables-auto-reclustering)
- Snowflake: [Search Optimization Service](https://docs.snowflake.com/en/user-guide/search-optimization-service)
- BigQuery: [Recommender for BigQuery](https://cloud.google.com/bigquery/docs/recommendations-overview)
- Aurora: [DevOps Guru for RDS](https://aws.amazon.com/devops-guru/features/devops-guru-for-rds/)
- Redshift: [Advisor](https://docs.aws.amazon.com/redshift/latest/dg/advisor.html)
- CockroachDB: [Index Recommendations](https://www.cockroachlabs.com/docs/stable/ui-statements-page#table-of-contents)
- Teradata: [Index Wizard](https://docs.teradata.com/r/Teradata-Database-Performance-Management)
- SAP HANA: [Plan Stability Advisor](https://help.sap.com/docs/SAP_HANA_PLATFORM)
- Vertica: [Database Designer](https://www.vertica.com/docs/latest/HTML/Content/Authoring/AdministratorsGuide/Tuning/Database/DatabaseDesigner.htm)
- Chaudhuri, S., Narasayya, V. "An Efficient Cost-Driven Index Selection Tool for Microsoft SQL Server" (1997, VLDB)
- Marcus, R. et al. "Bao: Making Learned Query Optimization Practical" (2021, SIGMOD)
- Marcus, R. et al. "Neo: A Learned Query Optimizer" (2019, VLDB)
- Pavlo, A. et al. "Self-Driving Database Management Systems" (2017, CIDR)
