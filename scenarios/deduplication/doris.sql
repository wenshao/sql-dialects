-- Apache Doris: 数据去重策略（Deduplication）
--
-- 参考资料:
--   [1] Apache Doris Documentation
--       https://doris.apache.org/docs/sql-manual/

-- ============================================================
-- 示例数据上下文
-- ============================================================
-- 假设表结构:
--   users(user_id INT, email VARCHAR(255), username VARCHAR(64), created_at TIMESTAMP)

-- ============================================================
-- 1. 查找重复数据
-- ============================================================

SELECT email, COUNT(*) AS cnt
FROM users
GROUP BY email
HAVING COUNT(*) > 1;

SELECT u.*
FROM users u
JOIN (
    SELECT email FROM users GROUP BY email HAVING COUNT(*) > 1
) dup ON u.email = dup.email
ORDER BY u.email, u.created_at;

-- ============================================================
-- 2. 保留每组一行（ROW_NUMBER 方式）
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



-- 标准 DELETE 方式
DELETE FROM users
WHERE user_id NOT IN (
    SELECT keep_id FROM (
        SELECT MAX(user_id) AS keep_id
        FROM users
        GROUP BY email
    ) keepers
);

-- CTAS 方式（创建去重后的新表）
CREATE TABLE users_clean AS
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
-- 4. MERGE（防止重复插入）
-- ============================================================

MERGE INTO users target
USING new_users source
ON target.email = source.email
WHEN MATCHED THEN
    UPDATE SET target.username = source.username, target.created_at = source.created_at
WHEN NOT MATCHED THEN
    INSERT (email, username, created_at) VALUES (source.email, source.username, source.created_at);

-- ============================================================
-- 5. DISTINCT vs GROUP BY
-- ============================================================

SELECT DISTINCT email FROM users;
SELECT email FROM users GROUP BY email;

SELECT email, COUNT(*) AS cnt, MAX(created_at) AS latest
FROM users
GROUP BY email;

-- ============================================================
-- 近似去重（APPROX_COUNT_DISTINCT）
-- ============================================================

SELECT APPROX_COUNT_DISTINCT(email) AS approx_distinct_emails
FROM users;

-- ============================================================
-- 性能考量
-- ============================================================

-- Doris Unique 模型天然支持去重
-- 使用 Unique Key 表模型：
--   CREATE TABLE users (...) UNIQUE KEY(email) DISTRIBUTED BY HASH(email);
