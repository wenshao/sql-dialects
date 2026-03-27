-- Apache Doris: 临时表与临时存储
--
-- 参考资料:
--   [1] Doris Documentation - CREATE TABLE
--       https://doris.apache.org/docs/sql-manual/sql-statements/Data-Definition-Statements/Create/CREATE-TABLE

-- Doris 不支持 CREATE TEMPORARY TABLE
-- 使用 CTE、子查询或 Staging 表

-- ============================================================
-- CTE
-- ============================================================

WITH stats AS (
    SELECT user_id, SUM(amount) AS total FROM orders GROUP BY user_id
)
SELECT u.username, s.total FROM users u JOIN stats s ON u.id = s.user_id;

-- ============================================================
-- Staging 表
-- ============================================================

CREATE TABLE staging_results (
    user_id BIGINT, total DECIMAL(10,2)
) DISTRIBUTED BY HASH(user_id) BUCKETS 8
PROPERTIES ("replication_num" = "1");

INSERT INTO staging_results
SELECT user_id, SUM(amount) FROM orders GROUP BY user_id;

-- 使用后删除
DROP TABLE staging_results;

-- ============================================================
-- INSERT INTO SELECT（物化中间结果）
-- ============================================================

-- 将中间结果写入持久表
INSERT INTO result_table
SELECT u.username, SUM(o.amount) AS total
FROM users u JOIN orders o ON u.id = o.user_id
GROUP BY u.username;

-- 注意：Doris 不支持临时表
-- 注意：CTE 是推荐的临时数据组织方式
-- 注意：Staging 表需要指定分桶策略
-- 注意：可以设置 replication_num = 1 减少 Staging 表的存储开销
