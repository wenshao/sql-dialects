-- SQL Server: 数据去重策略（Deduplication）
--
-- 参考资料:
--   [1] Microsoft Docs - DELETE with CTE
--       https://learn.microsoft.com/en-us/sql/t-sql/statements/delete-transact-sql
--   [2] Microsoft Docs - MERGE
--       https://learn.microsoft.com/en-us/sql/t-sql/statements/merge-transact-sql
--   [3] Microsoft Docs - Ranking Functions
--       https://learn.microsoft.com/en-us/sql/t-sql/functions/ranking-functions-transact-sql

-- ============================================================
-- 示例数据上下文
-- ============================================================
-- 假设表结构:
--   users(user_id INT IDENTITY PRIMARY KEY, email VARCHAR(255), username VARCHAR(64), created_at DATETIME2)

-- ============================================================
-- 1. 查找重复数据
-- ============================================================

SELECT email, COUNT(*) AS cnt
FROM users
GROUP BY email
HAVING COUNT(*) > 1;

-- ============================================================
-- 2. 保留每组一行（ROW_NUMBER）
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
-- 3. 删除重复数据（SQL Server 经典方式：CTE + DELETE）
-- ============================================================

-- CTE + ROW_NUMBER 直接删除（SQL Server 支持在 CTE 上直接 DELETE）
WITH duplicates AS (
    SELECT user_id,
           ROW_NUMBER() OVER (
               PARTITION BY email
               ORDER BY created_at DESC
           ) AS rn
    FROM users
)
DELETE FROM duplicates WHERE rn > 1;

-- 保留最早记录
WITH duplicates AS (
    SELECT user_id,
           ROW_NUMBER() OVER (
               PARTITION BY email
               ORDER BY created_at ASC
           ) AS rn
    FROM users
)
DELETE FROM duplicates WHERE rn > 1;

-- 方法二：DELETE + JOIN
DELETE u1
FROM users u1
JOIN users u2
  ON u1.email = u2.email
  AND u1.user_id < u2.user_id;

-- ============================================================
-- 4. 防止重复（MERGE）
-- ============================================================

MERGE INTO users AS target
USING (VALUES ('a@b.com', 'alice', GETDATE())) AS source (email, username, created_at)
ON target.email = source.email
WHEN MATCHED THEN
    UPDATE SET username = source.username, created_at = source.created_at
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
-- 6. 去重到新表
-- ============================================================

SELECT *
INTO users_clean
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
-- 7. 性能考量
-- ============================================================

CREATE INDEX idx_users_email ON users (email);

-- CTE + DELETE 是 SQL Server 最优雅的去重方式（直接在 CTE 上删除）
-- MERGE 语句可以实现 upsert（插入或更新）
-- 大表去重建议使用 TOP + WHILE 循环分批删除
-- SQL Server 2019+ 的 APPROX_COUNT_DISTINCT 可做近似去重计数
-- APPROX_COUNT_DISTINCT(email) 比 COUNT(DISTINCT email) 更快
