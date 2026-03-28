-- Hive: 视图 (Views & Materialized Views)
--
-- 参考资料:
--   [1] Apache Hive Language Manual - DDL: Views
--       https://cwiki.apache.org/confluence/display/Hive/LanguageManual+DDL#LanguageManualDDL-CreateView
--   [2] Apache Hive - Materialized Views
--       https://cwiki.apache.org/confluence/display/Hive/Materialized+views

-- ============================================================
-- 1. 普通视图 (Hive 0.6+)
-- ============================================================
CREATE VIEW active_users AS
SELECT id, username, email
FROM users
WHERE status = 'active';

-- 带列重命名
CREATE VIEW user_summary (user_id, user_name, order_count) AS
SELECT u.id, u.username, COUNT(o.id)
FROM users u
LEFT JOIN orders o ON u.id = o.user_id
GROUP BY u.id, u.username;

-- IF NOT EXISTS
CREATE VIEW IF NOT EXISTS daily_revenue AS
SELECT dt, SUM(amount) AS revenue, COUNT(*) AS order_count
FROM orders
GROUP BY dt;

-- 带注释和属性
CREATE VIEW tagged_view
TBLPROPERTIES ('creator' = 'admin', 'created_date' = '2024-01-01')
AS SELECT * FROM users WHERE age >= 18;

-- 修改视图
ALTER VIEW active_users AS
SELECT id, username, email, created_at
FROM users
WHERE status = 'active' AND created_at > '2024-01-01';

-- 删除视图
DROP VIEW IF EXISTS active_users;

-- 设计分析: Hive 视图 vs RDBMS 视图
-- Hive 视图的行为与传统 RDBMS 相似: 逻辑定义，查询时展开为子查询。
-- 但关键差异:
--   1. 不可更新: Hive 视图不支持通过视图做 INSERT/UPDATE/DELETE
--   2. 无 WITH CHECK OPTION: 因为不可更新所以不需要
--   3. 视图扩展发生在编译阶段: HiveQL → 视图展开 → 逻辑计划 → 优化 → 物理计划
--   4. 视图存储在 Metastore 中: 是跨引擎可见的（Spark/Trino 可以查询 Hive 视图）

-- ============================================================
-- 2. 物化视图 (Hive 3.0+)
-- ============================================================
-- 物化视图是 Hive 3.0 引入的重要特性，用于替代已废弃的索引功能
CREATE MATERIALIZED VIEW mv_daily_revenue
STORED AS ORC
AS
SELECT dt, region,
       SUM(amount) AS total_revenue,
       COUNT(*)    AS order_count
FROM orders
GROUP BY dt, region;

-- 查询物化视图（直接查询）
SELECT * FROM mv_daily_revenue WHERE dt = '2024-01-15';

-- 重建物化视图（数据过期后）
ALTER MATERIALIZED VIEW mv_daily_revenue REBUILD;

-- 删除物化视图
DROP MATERIALIZED VIEW IF EXISTS mv_daily_revenue;

-- 禁用/启用自动重写
ALTER MATERIALIZED VIEW mv_daily_revenue ENABLE REWRITE;
ALTER MATERIALIZED VIEW mv_daily_revenue DISABLE REWRITE;

-- 设计分析: 物化视图的自动查询重写
-- Hive 的物化视图支持自动查询重写:
-- 当用户查询 SELECT dt, SUM(amount) FROM orders GROUP BY dt
-- 优化器检测到 mv_daily_revenue 可以满足此查询，自动重写为:
-- SELECT dt, SUM(total_revenue) FROM mv_daily_revenue GROUP BY dt
--
-- 重写条件:
--   1. 物化视图的查询可以包含源查询（子集匹配）
--   2. 物化视图数据是最新的（或在可接受的过期范围内）
--   3. 需要启用 hive.materializedview.rewriting = true
--   4. 物化视图标记为 ENABLE REWRITE
--
-- 局限性:
--   1. 不自动刷新: 需要手动 REBUILD 或定时调度
--   2. 重建是全量重建: 不支持增量刷新（3.0 版本）
--   3. 源表变更后物化视图变为 stale: 查询重写不使用过期的物化视图

-- ============================================================
-- 3. SHOW 命令
-- ============================================================
SHOW VIEWS;                                  -- 列出所有视图
SHOW VIEWS IN database_name;                 -- 指定数据库
SHOW VIEWS LIKE 'mv_*';                     -- 模式匹配

-- ============================================================
-- 4. 跨引擎对比
-- ============================================================
-- 引擎           普通视图   物化视图    自动查询重写  增量刷新
-- Hive(3.0+)     支持       支持        支持          不支持
-- MySQL(5.x+)    支持       不支持      N/A           N/A
-- PostgreSQL     支持       支持(9.3+)  不支持        不支持
-- Oracle         支持       支持        支持(最成熟)  支持
-- BigQuery       支持       支持        不支持        支持
-- Spark SQL      支持       不支持      N/A           N/A
-- Trino          支持       不支持      N/A           N/A
-- ClickHouse     支持       支持(MV)    不支持        INSERT触发
-- MaxCompute     支持       不支持      N/A           N/A
--
-- ClickHouse 的物化视图设计独特: INSERT 触发增量计算并写入目标表，
-- 本质上是一个 INSERT 触发器 + 目标表的组合，与传统物化视图概念不同。
--
-- Oracle 的物化视图是行业标准: 支持 FAST REFRESH（增量刷新）、
-- QUERY REWRITE（自动查询重写）、REFRESH ON COMMIT/DEMAND。
-- Hive 3.0 的物化视图在设计上参考了 Oracle。

-- ============================================================
-- 5. 已知限制
-- ============================================================
-- 1. 视图不可更新: 不能通过视图 INSERT/UPDATE/DELETE
-- 2. 物化视图只支持 ORC 格式（与 ACID 相同的限制）
-- 3. 物化视图不支持分区（3.0 版本）
-- 4. 自动查询重写的匹配能力有限: 只能匹配简单的聚合查询
-- 5. 物化视图 REBUILD 是全量重建，大数据量下代价高
-- 6. 查询重写需要 CBO 开启（Cost-Based Optimizer）

-- ============================================================
-- 6. 对引擎开发者的启示
-- ============================================================
-- 1. 物化视图是分析引擎的"索引替代": Hive 废弃索引后选择物化视图，
--    本质上是用"预计算结果"替代"数据定位"——分析查询的本质是聚合而非点查
-- 2. 自动查询重写是物化视图的核心价值: 没有自动重写的物化视图只是一个定时 CTAS
-- 3. 增量刷新是物化视图的难点: 全量 REBUILD 的代价随数据量线性增长
--    Hive 的全量 REBUILD 限制了物化视图在大表上的实用性
-- 4. 视图元数据的跨引擎共享: Hive 视图存储在 Metastore 中，
--    Spark/Trino 可以直接使用——这是 Hive Metastore 作为元数据标准的价值
