-- MaxCompute (ODPS): Views
--
-- 参考资料:
--   [1] MaxCompute Documentation - CREATE VIEW
--       https://help.aliyun.com/zh/maxcompute/user-guide/view-operations
--   [2] MaxCompute Documentation - Materialized View
--       https://help.aliyun.com/zh/maxcompute/user-guide/materialized-view-operations

-- ============================================================
-- 1. 基本视图
-- ============================================================

CREATE VIEW active_users AS
SELECT id, username, email, created_at
FROM users
WHERE age >= 18;

CREATE OR REPLACE VIEW active_users AS
SELECT id, username, email, created_at
FROM users
WHERE age >= 18;

CREATE VIEW IF NOT EXISTS active_users AS
SELECT id, username, email, created_at
FROM users
WHERE age >= 18;

-- 带注释的视图
CREATE VIEW order_summary
COMMENT '按用户聚合的订单统计'
AS
SELECT user_id, COUNT(*) AS order_count, SUM(amount) AS total_amount
FROM orders
GROUP BY user_id;

-- 设计分析: MaxCompute 视图在查询时展开执行
--   与所有批处理引擎相同: 视图只是存储的 SQL 文本
--   查询时优化器将视图定义内联到主查询中
--   不存储数据，不消耗存储空间
--   不影响计费（按实际查询扫描量计费）
--
--   对比 OLTP 引擎:
--     MySQL:      可更新视图（通过视图 INSERT/UPDATE/DELETE）
--     PostgreSQL: 可更新视图 + INSTEAD OF 触发器
--     MaxCompute: 视图不可更新（批处理引擎不支持行级操作）

-- ============================================================
-- 2. 物化视图（2.0+）—— 预计算加速
-- ============================================================

CREATE MATERIALIZED VIEW mv_order_summary
LIFECYCLE 30                                -- 物化视图也有 LIFECYCLE
AS
SELECT user_id, COUNT(*) AS order_count, SUM(amount) AS total_amount
FROM orders
GROUP BY user_id;

-- 刷新物化视图（手动触发重新计算）
ALTER MATERIALIZED VIEW mv_order_summary REBUILD;

-- 设计决策: MaxCompute 物化视图的核心价值是查询自动改写
--   当用户查询 SELECT user_id, SUM(amount) FROM orders GROUP BY user_id 时
--   优化器检测到 mv_order_summary 包含匹配的预计算结果
--   自动将查询重写为 SELECT user_id, total_amount FROM mv_order_summary
--   前提: 物化视图数据足够新鲜（由 REBUILD 刷新策略决定）

-- 禁用/启用自动改写
ALTER MATERIALIZED VIEW mv_order_summary DISABLE REWRITE;
ALTER MATERIALIZED VIEW mv_order_summary ENABLE REWRITE;

-- 物化视图的实现机制:
--   底层: 物化视图是一张实际的表（存储在 AliORC 中）
--   REBUILD: 重新执行视图定义的 SQL，用 INSERT OVERWRITE 写入结果
--   改写匹配: 优化器基于查询的 SQL 结构和物化视图的定义做等价判断
--   与 CBO 集成: HBO（历史优化器）可以学习哪些查询适合改写

-- 分区物化视图:
CREATE MATERIALIZED VIEW mv_daily_orders
LIFECYCLE 30
PARTITIONED BY (dt)
AS
SELECT dt, user_id, COUNT(*) AS cnt, SUM(amount) AS total
FROM orders
GROUP BY dt, user_id;

-- 分区物化视图的优势: 增量刷新只需重建变化的分区

-- ============================================================
-- 3. 参数化视图（Script Mode）
-- ============================================================

-- MaxCompute 不支持传统参数化视图
-- 但 Script Mode 中可以用变量实现类似效果:
-- SET @start_date = '20240101';
-- SET @end_date = '20240131';
-- SELECT * FROM orders WHERE dt >= @start_date AND dt <= @end_date;

-- 对比:
--   PostgreSQL: 无参数化视图（用函数替代）
--   Oracle:     无参数化视图（用 SYS_CONTEXT 或 V$ 变量）
--   SQL Server: 无参数化视图（用内联表值函数）
--   BigQuery:   无参数化视图（用 DECLARE 变量 + CREATE TEMP TABLE）

-- ============================================================
-- 4. 删除视图
-- ============================================================

DROP VIEW active_users;
DROP VIEW IF EXISTS active_users;
DROP MATERIALIZED VIEW mv_order_summary;
DROP MATERIALIZED VIEW IF EXISTS mv_order_summary;

-- ============================================================
-- 5. 横向对比: 视图能力
-- ============================================================

-- 基本视图:
--   MaxCompute: 支持，查询时展开    | 所有引擎均支持
-- 可更新视图:
--   MaxCompute: 不支持              | MySQL/PG/Oracle: 支持
-- 物化视图:
--   MaxCompute: 2.0+ 支持           | Oracle: 最成熟（增量刷新、查询改写）
--   BigQuery:   支持（自动刷新）    | Snowflake: 支持（Enterprise+）
--   PostgreSQL: 支持（无自动改写）  | MySQL: 不支持（8.0 仍无）
--   ClickHouse: 支持（INSERT 触发增量更新，非查询改写模式）
--   Hive:       3.0+ 支持（与 MaxCompute 类似）
-- WITH CHECK OPTION:
--   MaxCompute: 不支持              | MySQL/PG/Oracle: 支持
-- RECURSIVE VIEW:
--   MaxCompute: 不支持              | PostgreSQL: 支持

-- 物化视图自动查询改写对比:
--   Oracle:     最成熟，支持复杂的等价匹配规则
--   MaxCompute: 支持基本的聚合查询改写
--   BigQuery:   支持（对 GROUP BY/JOIN 查询有效）
--   Snowflake:  Enterprise+ 功能
--   PostgreSQL: 不支持（物化视图只是手动缓存）

-- ============================================================
-- 6. 物化视图 vs ETL 预计算表
-- ============================================================

-- 传统方式: 在 DataWorks 调度中创建预计算表
-- INSERT OVERWRITE TABLE daily_summary PARTITION (dt = '${bizdate}')
-- SELECT ... FROM orders WHERE dt = '${bizdate}' GROUP BY ...;

-- 物化视图方式: 声明式定义 + 自动改写
-- CREATE MATERIALIZED VIEW mv_daily_summary AS SELECT ... GROUP BY ...;

-- 物化视图的优势:
--   1. 声明式: 只需定义"要什么"，不需要管理刷新调度
--   2. 自动改写: 用户查询无需修改，优化器自动利用
--   3. 一致性: REBUILD 保证视图与源表数据一致
--
-- 物化视图的局限:
--   1. 刷新策略简单: 只有手动 REBUILD，不如 DataWorks 灵活
--   2. 增量刷新有限: 复杂 JOIN 场景可能需要全量重建
--   3. 存储成本: 物化视图占用额外存储（有 LIFECYCLE 控制）

-- ============================================================
-- 7. 对引擎开发者的启示
-- ============================================================

-- 1. 批处理引擎的视图应重点投资物化视图，而非可更新视图
-- 2. 查询自动改写是物化视图的核心价值，比手动使用更重要
-- 3. LIFECYCLE 与物化视图结合: 自动清理过期的预计算结果
-- 4. 分区物化视图支持增量刷新，是大数据场景的关键优化
-- 5. 视图的安全价值: 可以限制用户只能通过视图访问敏感数据
-- 6. Oracle 的物化视图查询改写是行业标杆，值得参考其等价匹配算法
