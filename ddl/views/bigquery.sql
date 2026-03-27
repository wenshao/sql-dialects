-- BigQuery: 视图（Views）
--
-- 参考资料:
--   [1] BigQuery SQL Reference - CREATE VIEW
--       https://cloud.google.com/bigquery/docs/reference/standard-sql/data-definition-language#create_view_statement
--   [2] BigQuery Documentation - Materialized Views
--       https://cloud.google.com/bigquery/docs/materialized-views-intro
--   [3] BigQuery Documentation - Authorized Views
--       https://cloud.google.com/bigquery/docs/authorized-views

-- ============================================================
-- 1. 基本视图
-- ============================================================

CREATE VIEW myproject.mydataset.active_users AS
SELECT id, username, email, created_at
FROM myproject.mydataset.users WHERE age >= 18;

CREATE OR REPLACE VIEW myproject.mydataset.active_users AS
SELECT id, username, email FROM myproject.mydataset.users WHERE age >= 18;

CREATE VIEW IF NOT EXISTS myproject.mydataset.active_users AS
SELECT id, username, email FROM myproject.mydataset.users WHERE age >= 18;

-- 带选项的视图
CREATE VIEW myproject.mydataset.order_summary
OPTIONS (
    description = 'Aggregated order summary by user',
    labels = [('env', 'prod')],
    expiration_timestamp = TIMESTAMP '2027-12-31'
) AS
SELECT user_id, COUNT(*) AS order_count, SUM(amount) AS total_amount
FROM myproject.mydataset.orders GROUP BY user_id;

DROP VIEW myproject.mydataset.active_users;
DROP VIEW IF EXISTS myproject.mydataset.active_users;

-- 视图不可更新: BigQuery 的视图只读，不能 INSERT/UPDATE/DELETE。
-- 没有 INSTEAD OF TRIGGER（BigQuery 不支持触发器）。
-- 需要修改数据时直接操作基表。

-- ============================================================
-- 2. 物化视图: 自动刷新 + 智能查询重写
-- ============================================================

-- BigQuery 物化视图的两大核心能力:
--   (a) 自动刷新: BigQuery 后台自动检测基表变更并刷新（默认 30 分钟）
--   (b) 智能查询重写: 查询基表时，优化器自动利用物化视图加速
--       用户查询 SELECT ... FROM orders，BigQuery 可能自动改为读物化视图

-- 基本物化视图
CREATE MATERIALIZED VIEW myproject.mydataset.mv_order_summary AS
SELECT user_id, COUNT(*) AS order_count, SUM(amount) AS total_amount
FROM myproject.mydataset.orders
GROUP BY user_id;

-- 自定义刷新设置
CREATE MATERIALIZED VIEW myproject.mydataset.mv_daily_stats
OPTIONS (
    enable_refresh = true,
    refresh_interval_minutes = 30,       -- 自动刷新间隔
    max_staleness = INTERVAL 4 HOUR      -- 允许最多 4 小时过期
) AS
SELECT DATE(order_date) AS day, COUNT(*) AS cnt, SUM(amount) AS total
FROM myproject.mydataset.orders
GROUP BY day;

-- 禁用自动刷新（手动控制）
CREATE MATERIALIZED VIEW myproject.mydataset.mv_manual
OPTIONS (enable_refresh = false) AS
SELECT user_id, COUNT(*) AS cnt
FROM myproject.mydataset.orders GROUP BY user_id;

-- 手动刷新
-- CALL BQ.REFRESH_MATERIALIZED_VIEW('myproject.mydataset.mv_manual');

-- 2.1 物化视图的限制（设计原因分析）
-- (a) 仅支持单表聚合查询（不支持 JOIN）
--     → 因为 BigQuery 的分布式刷新需要确定性地知道哪些分区变了
--     → JOIN 涉及多表，无法仅根据一个表的变更判断物化视图是否需要更新
--
-- (b) 聚合函数限于: COUNT, SUM, AVG, MIN, MAX, COUNT DISTINCT,
--     APPROX_COUNT_DISTINCT, HLL_COUNT.MERGE 等
--     → 这些聚合可以增量计算（旧结果 + 新数据 = 新结果）
--     → 不支持不可增量计算的聚合（如 MEDIAN, PERCENTILE）
--
-- (c) 基表必须有分区或聚集
--     → 刷新时只处理变更的分区，避免全表扫描
--
-- (d) 不支持 HAVING, ORDER BY, LIMIT, DISTINCT
--     → 这些操作在增量刷新中难以正确处理

-- 2.2 智能查询重写（Smart Tuning）
-- 用户直接查询基表:
-- SELECT user_id, SUM(amount) FROM orders GROUP BY user_id;
-- BigQuery 优化器检测到 mv_order_summary 可以回答这个查询
-- → 自动改为读物化视图（更快、更便宜）
-- 这对用户完全透明，不需要修改任何查询

-- 对比:
--   ClickHouse:  物化视图需要直接查询，没有自动重写
--   PostgreSQL:  不自动重写（需要显式查询物化视图）
--   Oracle:      QUERY REWRITE（需要启用，与 BigQuery 最接近）
--   SQL Server:  Indexed View 自动重写（Enterprise 版）

-- ============================================================
-- 3. 授权视图（Authorized View）: BigQuery 独有的安全机制
-- ============================================================

-- 场景: 视图定义在 dataset_a 中，引用 dataset_b 中的表。
-- 用户有权访问 dataset_a 但无权访问 dataset_b。
-- 授权视图允许用户通过视图访问 dataset_b 的数据，而不需要直接授权。
--
-- 设置方法（通过 API/CLI，非 SQL）:
-- 在 dataset_b 的权限中添加视图 dataset_a.my_view 为授权视图
--
-- 用途:
--   (a) 行级安全: 视图 WHERE 子句过滤敏感行
--   (b) 列级安全: 视图 SELECT 列表排除敏感列
--   (c) 跨团队共享: 数据团队管理基表，业务团队通过视图访问

-- 对比:
--   MySQL:      不需要（用户直接被授权到表/列级别）
--   PostgreSQL: security_definer 函数 + 视图（类似但更复杂）
--   ClickHouse: ROW POLICY 提供行级安全（更直接）

-- ============================================================
-- 4. 视图的成本影响（对引擎开发者）
-- ============================================================

-- BigQuery 按扫描量计费，视图的成本 = 底层查询的扫描量。
-- 嵌套视图（视图引用视图）可能导致意外的高成本:
--   view_a → view_b → view_c → 基表（10 TB）
--   查询 view_a 实际扫描 10 TB
-- 最佳实践: 避免深层嵌套视图，使用物化视图减少扫描

-- 物化视图的成本:
--   存储成本: 物化视图占用存储空间（与表相同计费）
--   刷新成本: 自动刷新消耗 slot 和扫描量（但只处理变更分区）
--   查询成本: 从物化视图读取 << 从基表扫描（成本显著降低）

DROP MATERIALIZED VIEW myproject.mydataset.mv_order_summary;
DROP MATERIALIZED VIEW IF EXISTS myproject.mydataset.mv_order_summary;

-- ============================================================
-- 5. 对比与引擎开发者启示
-- ============================================================
-- BigQuery 视图的核心设计:
--   (1) 自动刷新物化视图 → 无服务器，不需要手动 REFRESH
--   (2) 智能查询重写 → 用户无感知地利用物化视图
--   (3) 授权视图 → 集成到 IAM 安全模型中
--   (4) 成本感知 → 视图设计直接影响查询费用
--
-- 对引擎开发者的启示:
--   物化视图的自动刷新和智能重写是云数仓的竞争力:
--   用户不需要知道物化视图的存在，优化器自动选择最优路径。
--   ClickHouse 的 INSERT 触发模式更实时但需要用户显式查询物化视图。
--   BigQuery/Oracle 的自动重写模式更透明但刷新有延迟。
--   两种模式各有适用场景: 实时流处理 vs 批量分析。
