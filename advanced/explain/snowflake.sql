-- Snowflake: 执行计划与查询分析
--
-- 参考资料:
--   [1] Snowflake Documentation - EXPLAIN
--       https://docs.snowflake.com/en/sql-reference/sql/explain
--   [2] Snowflake Documentation - Query Profile
--       https://docs.snowflake.com/en/user-guide/ui-query-profile
--   [3] Snowflake Documentation - Query History
--       https://docs.snowflake.com/en/sql-reference/account-usage/query_history

-- ============================================================
-- 1. EXPLAIN 基本用法
-- ============================================================

EXPLAIN SELECT * FROM users WHERE username = 'alice';
EXPLAIN USING TABULAR SELECT * FROM users WHERE age > 25;
EXPLAIN USING JSON SELECT * FROM orders WHERE order_date > '2024-01-01';

-- 编程方式获取 JSON 格式计划:
SELECT SYSTEM$EXPLAIN_PLAN_JSON('SELECT * FROM users WHERE age > 25');

-- ============================================================
-- 2. 语法设计分析（对 SQL 引擎开发者）
-- ============================================================

-- 2.1 EXPLAIN vs Query Profile: 双层分析体系
-- Snowflake 的查询分析分为两个层次:
--
-- EXPLAIN (SQL 层): 估算型执行计划，不实际执行查询
--   输出: 操作树、分区统计（partitionsTotal / partitionsAssigned）
--   用途: 快速检查分区裁剪效果、查看操作符顺序
--   限制: 不显示实际执行时间、溢出信息、并行度
--
-- Query Profile (Web UI): 实际执行后的详细性能分析
--   输出: DAG 图形化操作符树、每个操作符的耗时/行数/溢出量
--   用途: 深入分析慢查询瓶颈、识别数据倾斜、检查溢出
--   限制: 需要在 Snowsight Web UI 中查看
--
-- 对比:
--   MySQL:      EXPLAIN + EXPLAIN ANALYZE（8.0.18+，实际执行）
--   PostgreSQL: EXPLAIN + EXPLAIN (ANALYZE, BUFFERS)（最详细的文本输出）
--   Oracle:     EXPLAIN PLAN + DBMS_XPLAN + AWR 报告
--   BigQuery:   Query Execution Details（Web UI，与 Snowflake Query Profile 类似）
--   Redshift:   EXPLAIN + SVL_QUERY_REPORT + STL_EXPLAIN
--   Databricks: EXPLAIN + Spark UI（图形化 DAG）
--
-- 对引擎开发者的启示:
--   Snowflake 的 EXPLAIN 文本输出信息有限（不如 PostgreSQL 详细），
--   将深度分析推到 Web UI（Query Profile）。这是 SaaS 产品的设计选择:
--   SQL 接口保持简洁，复杂分析通过图形界面提供。
--   对于开源或自建引擎，PostgreSQL 式的详细 EXPLAIN ANALYZE 更实用。

-- 2.2 分区裁剪: Snowflake 最核心的优化指标
-- 由于没有索引，查询性能几乎完全取决于分区裁剪效果。
-- EXPLAIN 输出的 partitionsAssigned / partitionsTotal 比例是最重要的指标:
--   1% → 优秀（只扫描 1% 的分区）
--   100% → 全表扫描（需要添加 CLUSTER BY 或调整查询条件）
--
-- 对比传统数据库:
--   MySQL/PostgreSQL: type = ALL (全表扫描) → 需要添加索引
--   Snowflake: partitionsAssigned = partitionsTotal → 需要添加 CLUSTER BY
--   本质相同: 都是减少扫描的数据量，手段不同

-- ============================================================
-- 3. 查询历史分析
-- ============================================================

-- 最近 1 小时的查询历史:
SELECT *
FROM TABLE(information_schema.query_history(
    DATEADD('hours', -1, CURRENT_TIMESTAMP()),
    CURRENT_TIMESTAMP(), 100
))
ORDER BY start_time DESC;

-- 通过 Account Usage 视图分析慢查询（延迟最多 45 分钟）:
SELECT query_id, query_text, execution_status,
       total_elapsed_time / 1000             AS elapsed_sec,
       bytes_scanned / 1048576               AS mb_scanned,
       rows_produced,
       partitions_scanned, partitions_total,
       compilation_time, execution_time
FROM snowflake.account_usage.query_history
WHERE start_time > DATEADD('day', -1, CURRENT_TIMESTAMP())
ORDER BY total_elapsed_time DESC
LIMIT 20;

-- ============================================================
-- 4. 关键性能指标
-- ============================================================

-- 4.1 分区裁剪效果
SELECT query_id,
       partitions_scanned, partitions_total,
       ROUND(partitions_scanned / NULLIF(partitions_total, 0) * 100, 2) AS pct_scanned
FROM snowflake.account_usage.query_history
WHERE start_time > DATEADD('day', -1, CURRENT_TIMESTAMP())
  AND partitions_total > 0
ORDER BY partitions_scanned DESC
LIMIT 10;

-- 4.2 数据溢出检测（Spilling）
-- 溢出到本地 SSD 或远程存储表示 Warehouse 内存不足
SELECT query_id, query_text,
       bytes_spilled_to_local_storage  / 1048576 AS mb_spilled_local,
       bytes_spilled_to_remote_storage / 1048576 AS mb_spilled_remote
FROM snowflake.account_usage.query_history
WHERE bytes_spilled_to_local_storage > 0
   OR bytes_spilled_to_remote_storage > 0
ORDER BY start_time DESC
LIMIT 10;

-- 溢出的对策:
--   溢出到本地 SSD: 可接受，性能影响较小
--   溢出到远程存储 (S3/Blob): 性能严重下降，需要更大的 Warehouse
--
-- 对比:
--   PostgreSQL: work_mem 参数控制排序/哈希内存，超出溢出到磁盘
--   MySQL:      sort_buffer_size / tmp_table_size 控制临时表内存
--   Snowflake:  无参数可调（通过 Warehouse 大小控制总内存）

-- ============================================================
-- 5. Query Profile 操作符说明
-- ============================================================

-- TableScan        — 扫描微分区（关注 partitions_scanned）
-- Filter           — 行级过滤（关注过滤比例）
-- JoinFilter       — JOIN 时的过滤（Bloom Filter 等）
-- Projection       — 列裁剪
-- Aggregate        — 聚合操作（关注数据量和溢出）
-- Sort             — 排序（关注溢出和数据量）
-- SortWithLimit    — 带 LIMIT 的排序（通常高效）
-- HashJoin         — 哈希连接（关注 build side 大小和溢出）
-- WindowFunction   — 窗口函数（关注分区大小）
-- UnionAll         — UNION ALL 操作
-- WithClause       — CTE 引用
-- ExternalScan     — 外部表扫描（通常较慢）
-- Result           — 结果返回
-- Flatten          — VARIANT 数组/对象展开

-- ============================================================
-- 6. 查询标记 (Query Tag)
-- ============================================================

ALTER SESSION SET QUERY_TAG = 'performance_test';
SELECT * FROM users WHERE age > 25;
ALTER SESSION UNSET QUERY_TAG;

-- 按标记分析查询:
SELECT query_tag, COUNT(*) AS query_count,
       AVG(total_elapsed_time) / 1000 AS avg_sec,
       SUM(bytes_scanned) / 1073741824 AS total_gb_scanned
FROM snowflake.account_usage.query_history
WHERE query_tag IS NOT NULL
  AND start_time > DATEADD('day', -7, CURRENT_TIMESTAMP())
GROUP BY query_tag
ORDER BY total_gb_scanned DESC;

-- 对引擎开发者的启示:
--   Query Tag 是 Snowflake 独有的查询分类机制。
--   传统数据库通过注释（/* tag */）或连接属性实现类似目的。
--   这对于多团队共用 Warehouse 的成本分摊非常有价值。

-- ============================================================
-- 7. 资源监控
-- ============================================================

-- Warehouse 负载历史:
SELECT *
FROM TABLE(information_schema.warehouse_load_history(
    date_range_start => DATEADD('hour', -4, CURRENT_TIMESTAMP())
));

-- Warehouse 计费历史:
SELECT start_time, warehouse_name, credits_used
FROM snowflake.account_usage.warehouse_metering_history
WHERE start_time > DATEADD('day', -7, CURRENT_TIMESTAMP())
ORDER BY credits_used DESC;

-- ============================================================
-- 横向对比: 查询分析能力矩阵
-- ============================================================
-- 能力              | Snowflake       | BigQuery      | PostgreSQL    | MySQL
-- 估算型计划        | EXPLAIN         | EXPLAIN       | EXPLAIN       | EXPLAIN
-- 实际执行计划      | Query Profile   | Execution Det | EXPLAIN ANAL  | EXPLAIN ANAL
-- 图形化分析        | Snowsight UI    | BigQuery UI   | pgAdmin等     | Workbench
-- 查询历史          | query_history   | INFORMATION_S | pg_stat_stat  | slow_query
-- 成本分析          | credits_used    | bytes_billed  | 无原生        | 无原生
-- 查询标记          | QUERY_TAG       | labels        | 无原生        | 无原生
-- 溢出检测          | bytes_spilled   | shuffle_out   | temp_blks_*   | Created_tmp_*
