-- StarRocks: 临时表与临时存储
--
-- 参考资料:
--   [1] StarRocks Documentation - CREATE TABLE
--       https://docs.starrocks.io/docs/sql-reference/sql-statements/data-definition/CREATE_TABLE/

-- StarRocks 不支持 CREATE TEMPORARY TABLE
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

SELECT * FROM staging_results;
DROP TABLE staging_results;

-- ============================================================
-- CREATE TABLE AS SELECT（CTAS，3.0+）
-- ============================================================

CREATE TABLE temp_result
PROPERTIES ("replication_num" = "1")
AS SELECT user_id, SUM(amount) AS total FROM orders GROUP BY user_id;

DROP TABLE temp_result;

-- 注意：StarRocks 不支持临时表
-- 注意：CTE 是推荐的临时数据组织方式
-- 注意：3.0+ 支持 CTAS 快速创建表
-- 注意：设置 replication_num = 1 减少临时表存储
