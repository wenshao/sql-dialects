-- Greenplum: 临时表与临时存储
--
-- 参考资料:
--   [1] Greenplum Documentation - CREATE TABLE
--       https://docs.vmware.com/en/VMware-Greenplum/7/greenplum-database/ref_guide-sql_commands-CREATE_TABLE.html

-- ============================================================
-- CREATE TEMPORARY TABLE
-- ============================================================

CREATE TEMPORARY TABLE temp_users (
    id BIGINT,
    username VARCHAR(100),
    email VARCHAR(200)
) DISTRIBUTED BY (id);

CREATE TEMP TABLE temp_orders AS
SELECT user_id, SUM(amount) AS total FROM orders GROUP BY user_id
DISTRIBUTED BY (user_id);

-- ON COMMIT 行为
CREATE TEMP TABLE temp_tx (id INT, val INT)
ON COMMIT DELETE ROWS
DISTRIBUTED BY (id);

CREATE TEMP TABLE temp_session (id INT, val INT)
ON COMMIT PRESERVE ROWS  -- 默认
DISTRIBUTED BY (id);

-- ============================================================
-- 分布策略（Greenplum 特有）
-- ============================================================

-- 指定分布键（减少 Motion 操作）
CREATE TEMP TABLE temp_data (
    user_id BIGINT, amount NUMERIC
) DISTRIBUTED BY (user_id);

-- 随机分布
CREATE TEMP TABLE temp_random (
    id INT, data TEXT
) DISTRIBUTED RANDOMLY;

-- 复制分布（6.0+）
CREATE TEMP TABLE temp_replicated (
    id INT, name VARCHAR
) DISTRIBUTED REPLICATED;

-- ============================================================
-- CTE
-- ============================================================

WITH stats AS (
    SELECT user_id, SUM(amount) AS total
    FROM orders GROUP BY user_id
)
SELECT u.username, s.total
FROM users u JOIN stats s ON u.id = s.user_id;

-- 可写 CTE
WITH deleted AS (
    DELETE FROM staging_orders WHERE processed = true RETURNING *
)
INSERT INTO archive_orders SELECT * FROM deleted;

-- 注意：Greenplum 临时表支持分布键（DISTRIBUTED BY）
-- 注意：选择正确的分布键减少 Motion 操作
-- 注意：DISTRIBUTED REPLICATED 适合小型查找表
-- 注意：临时表在会话结束时自动删除
-- 注意：Greenplum 基于 PostgreSQL，CTE 语法兼容
