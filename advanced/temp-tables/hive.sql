-- Hive: 临时表与临时存储
--
-- 参考资料:
--   [1] Apache Hive Documentation - Temporary Tables
--       https://cwiki.apache.org/confluence/display/Hive/LanguageManual+DDL#LanguageManualDDL-TemporaryTables

-- ============================================================
-- CREATE TEMPORARY TABLE（Hive 0.14+）
-- ============================================================

CREATE TEMPORARY TABLE temp_users (
    id BIGINT, username STRING, email STRING
);

CREATE TEMPORARY TABLE temp_orders AS
SELECT user_id, SUM(amount) AS total FROM orders GROUP BY user_id;

-- 临时表特性：
-- 1. 会话级别，会话结束时自动删除
-- 2. 只对当前会话可见
-- 3. 存储在用户的临时目录中
-- 4. 不支持分区和索引

-- ============================================================
-- 使用临时表
-- ============================================================

INSERT INTO temp_users SELECT id, username, email FROM users WHERE status = 1;
SELECT * FROM temp_users;
DROP TABLE IF EXISTS temp_users;

-- ============================================================
-- CTE
-- ============================================================

WITH stats AS (
    SELECT user_id, SUM(amount) AS total FROM orders GROUP BY user_id
)
SELECT u.username, s.total FROM users u JOIN stats s ON u.id = s.user_id;

-- ============================================================
-- 分桶临时表（替代方案）
-- ============================================================

-- 创建临时的中间表用于 ETL
CREATE TABLE staging_orders
STORED AS ORC
AS SELECT * FROM raw_orders WHERE dt = '2024-01-01';

-- 处理后删除
DROP TABLE staging_orders;

-- 注意：Hive 临时表从 0.14 版本开始支持
-- 注意：临时表不支持分区
-- 注意：临时表数据存储在 HDFS 的临时目录中
-- 注意：CTE 是替代临时表的常用方式
-- 注意：ETL 场景通常使用 Staging 表
