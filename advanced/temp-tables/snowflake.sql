-- Snowflake: 临时表与瞬态表
--
-- 参考资料:
--   [1] Snowflake Documentation - Temporary and Transient Tables
--       https://docs.snowflake.com/en/user-guide/tables-temp-transient
--   [2] Snowflake Documentation - CREATE TABLE
--       https://docs.snowflake.com/en/sql-reference/sql/create-table

-- ============================================================
-- 1. 三种表类型
-- ============================================================

-- 1.1 永久表 (Permanent): 默认类型
CREATE TABLE users (id NUMBER, username VARCHAR);
-- Time Travel: 0-90 天（Enterprise 版）
-- Fail-safe: 7 天（Snowflake 托管的灾难恢复）
-- 适用: 生产数据

-- 1.2 临时表 (Temporary): 会话级
CREATE TEMPORARY TABLE temp_users (
    id       NUMBER,
    username VARCHAR(100),
    email    VARCHAR(200)
);
-- 仅对创建它的会话可见 | 会话结束自动删除
-- Time Travel: 0-1 天 | Fail-safe: 无
-- 适用: 中间计算结果、会话级暂存

-- 1.3 瞬态表 (Transient): 持久但低保护
CREATE TRANSIENT TABLE staging_data (
    id   NUMBER,
    data VARIANT
);
-- 对所有用户可见（与永久表一样） | 持久化存储
-- Time Travel: 0-1 天 | Fail-safe: 无（比永久表存储成本低）
-- 适用: ETL staging 表、可重新生成的数据

-- ============================================================
-- 2. 语法设计分析（对 SQL 引擎开发者）
-- ============================================================

-- 2.1 三级表类型: Snowflake 独特的存储成本优化设计
-- 传统数据库只有两种: 永久表 + 临时表。
-- Snowflake 增加了 TRANSIENT 表作为中间层次，原因:
--
--   永久表的存储成本 = 活跃存储 + Time Travel 存储 + Fail-safe 存储
--   Time Travel 90 天 + Fail-safe 7 天 → 最多保留 97 天的历史版本！
--   对于 staging 表、ETL 中间表，保留 97 天历史是巨大的成本浪费。
--
-- Transient 表消除了 Fail-safe（7 天），Time Travel 限制为 0-1 天。
-- 对于 TB 级别的数据，这可以节省 50%+ 的存储成本。
--
-- 对比:
--   MySQL/PostgreSQL/Oracle: 只有永久表和临时表，无 Transient 概念
--   BigQuery:    表有存储费用但无 Fail-safe 概念（自动 7 天 Time Travel）
--   Redshift:    无 Transient 表概念
--   Databricks:  无 Transient（Delta Lake 有 VACUUM 清理旧版本）
--
-- 对引擎开发者的启示:
--   Snowflake 的三级设计反映了云数仓的"存储也是成本"理念。
--   传统数据库存储在自有磁盘上，增量成本低；
--   云数仓存储在对象存储上，按 TB 计费 → 需要精细的存储层次控制。

-- 2.2 临时表的命名空间隔离
-- Snowflake 临时表可以与永久表同名（临时表优先）:
-- CREATE TABLE users (id NUMBER);             -- 永久表
-- CREATE TEMPORARY TABLE users (id NUMBER);   -- 临时表，优先访问
-- 会话内所有引用 'users' 都指向临时表
--
-- 对比:
--   PostgreSQL: 临时表也可以与永久表同名（search_path 中 pg_temp 优先）
--   MySQL:      临时表也可以与永久表同名（临时表优先）
--   Oracle:     全局临时表（GTT）是永久定义的，不存在命名冲突
--   SQL Server: 临时表使用 # 前缀（#temp），命名空间天然分离

-- ============================================================
-- 3. 创建方式
-- ============================================================

-- CTAS: 从查询创建
CREATE TEMPORARY TABLE temp_orders AS
SELECT user_id, SUM(amount) AS total, COUNT(*) AS cnt
FROM orders WHERE order_date >= '2024-01-01'
GROUP BY user_id;

-- CREATE OR REPLACE
CREATE OR REPLACE TEMPORARY TABLE temp_stats AS
SELECT user_id, SUM(amount) AS total FROM orders GROUP BY user_id;

-- 设置临时表的 Time Travel
CREATE TEMPORARY TABLE temp_with_travel (
    id NUMBER, data VARCHAR
) DATA_RETENTION_TIME_IN_DAYS = 1;

-- ============================================================
-- 4. RESULT_SCAN: 无需临时表的结果重用
-- ============================================================

-- 查询上一次查询的结果（无需创建临时表）:
SELECT * FROM TABLE(RESULT_SCAN(LAST_QUERY_ID()));

-- 通过 Query ID 获取历史查询结果:
SELECT * FROM TABLE(RESULT_SCAN('query-id-here'));

-- 将 RESULT_SCAN 结果保存到临时表:
CREATE TEMPORARY TABLE saved_results AS
SELECT * FROM TABLE(RESULT_SCAN(LAST_QUERY_ID()));

-- RESULT_SCAN 的设计意义:
--   传统工作流: 执行查询 → 存入临时表 → 引用临时表
--   RESULT_SCAN: 执行查询 → 直接引用上一次结果
--   减少了不必要的临时表创建，对交互式分析很有价值
--
-- 对比:
--   PostgreSQL: 无等价功能（必须用临时表或 CTE）
--   MySQL:      无等价功能
--   BigQuery:   临时结果自动缓存（但无显式 RESULT_SCAN 函数）

-- ============================================================
-- 5. Stage: 文件级临时存储
-- ============================================================

-- 创建临时 Stage
CREATE TEMPORARY STAGE temp_stage;

-- 将查询结果导出到 Stage
COPY INTO @temp_stage/results
FROM (SELECT * FROM users WHERE status = 1)
FILE_FORMAT = (TYPE = 'CSV');

-- 从 Stage 读回
SELECT $1, $2, $3 FROM @temp_stage/results
(FILE_FORMAT => (TYPE = 'CSV'));

-- Stage 是 Snowflake 特有的文件暂存概念:
--   Internal Stage: Snowflake 管理的存储（@~ 用户 Stage, @% 表 Stage）
--   External Stage: 指向 S3/Azure/GCS 的路径
--   临时 Stage: 会话级，会话结束自动清理

-- ============================================================
-- 6. 存储成本对比
-- ============================================================
-- 类型        | Time Travel | Fail-safe | 可见性    | 生命周期
-- Permanent   | 0-90 天     | 7 天      | 所有用户  | 永久
-- Transient   | 0-1 天      | 无        | 所有用户  | 永久
-- Temporary   | 0-1 天      | 无        | 当前会话  | 会话结束
--
-- 存储成本估算（假设 1 TB 数据, 每 TB $23/月）:
--   Permanent: 1 TB 数据 + 最多 90 天 Time Travel + 7 天 Fail-safe ≈ $23 × (1 + 2.9 + 0.23)
--   Transient: 1 TB 数据 + 最多 1 天 Time Travel ≈ $23 × (1 + 0.03)
--   Temporary: 会话结束即释放

-- ============================================================
-- 横向对比: 临时存储能力
-- ============================================================
-- 能力          | Snowflake     | BigQuery       | PostgreSQL  | MySQL
-- 临时表        | TEMPORARY     | 不支持(用子查)  | TEMPORARY   | TEMPORARY
-- 会话隔离      | 是            | N/A            | 是          | 是
-- Transient表   | 独有          | 无             | 无          | 无
-- 结果缓存引用  | RESULT_SCAN   | 缓存自动       | 无          | 无
-- 文件暂存      | Stage         | GCS bucket     | 无          | 无
-- 临时表持久化   | 否            | N/A            | 否(UNLOGGED) | 否
