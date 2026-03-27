-- Trino (formerly PrestoSQL): 数据去重策略（Deduplication）
--
-- 参考资料:
--   [1] Trino Documentation - Window Functions
--       https://trino.io/docs/current/functions/window.html
--   [2] Trino Documentation - MERGE
--       https://trino.io/docs/current/sql/merge.html

-- ============================================================
-- 示例数据上下文
-- ============================================================
-- 假设表结构:
--   users(user_id INTEGER, email VARCHAR, username VARCHAR, created_at TIMESTAMP)

-- ============================================================
-- 1. 查找重复数据
-- ============================================================

SELECT email, COUNT(*) AS cnt
FROM users
GROUP BY email
HAVING COUNT(*) > 1;

-- ============================================================
-- 2. 保留每组一行
-- ============================================================

SELECT *
FROM (
    SELECT user_id, email, username, created_at,
           ROW_NUMBER() OVER (
               PARTITION BY email
               ORDER BY created_at DESC
           ) AS rn
    FROM users
) ranked
WHERE rn = 1;

-- ============================================================
-- 3. 删除重复数据
-- ============================================================

-- MERGE 方式（Trino 支持部分连接器的 MERGE）
MERGE INTO users target
USING (
    SELECT user_id FROM (
        SELECT user_id,
               ROW_NUMBER() OVER (PARTITION BY email ORDER BY created_at DESC) AS rn
        FROM users
    ) WHERE rn > 1
) dups
ON target.user_id = dups.user_id
WHEN MATCHED THEN DELETE;

-- CTAS 方式
CREATE TABLE users_clean AS
SELECT *
FROM (
    SELECT user_id, email, username, created_at,
           ROW_NUMBER() OVER (
               PARTITION BY email
               ORDER BY created_at DESC
           ) AS rn
    FROM users
) WHERE rn = 1;

-- ============================================================
-- 4. 近似去重
-- ============================================================

SELECT approx_distinct(email) AS approx_distinct_emails
FROM users;

-- ============================================================
-- 5. DISTINCT vs GROUP BY
-- ============================================================

SELECT DISTINCT email FROM users;
SELECT email FROM users GROUP BY email;

-- ============================================================
-- 6. 性能考量
-- ============================================================

-- Trino 是 MPP 查询引擎
-- approx_distinct 使用 HyperLogLog
-- MERGE 支持取决于连接器（Hive, Iceberg, Delta Lake）
-- 注意：Trino 不支持 QUALIFY
