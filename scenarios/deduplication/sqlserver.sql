-- SQL Server: 数据去重（Deduplication）
--
-- 参考资料:
--   [1] SQL Server - DELETE with CTE
--       https://learn.microsoft.com/en-us/sql/t-sql/statements/delete-transact-sql

-- ============================================================
-- 1. 查找重复数据
-- ============================================================
SELECT email, COUNT(*) AS cnt FROM users GROUP BY email HAVING COUNT(*) > 1;

-- ============================================================
-- 2. CTE + DELETE: SQL Server 最优雅的去重方式
-- ============================================================

-- SQL Server 允许直接在 CTE 上执行 DELETE——这是其独有的能力。
;WITH duplicates AS (
    SELECT user_id,
           ROW_NUMBER() OVER (PARTITION BY email ORDER BY created_at DESC) AS rn
    FROM users
)
DELETE FROM duplicates WHERE rn > 1;  -- 保留每个 email 的最新记录

-- 保留最早记录
;WITH duplicates AS (
    SELECT user_id,
           ROW_NUMBER() OVER (PARTITION BY email ORDER BY created_at ASC) AS rn
    FROM users
)
DELETE FROM duplicates WHERE rn > 1;

-- 设计分析（对引擎开发者）:
--   "可更新 CTE"是 SQL Server 的杀手级特性。
--   PostgreSQL 的等价需要子查询: DELETE FROM users WHERE id IN (SELECT id FROM ...)
--   MySQL 的等价更复杂: DELETE FROM users WHERE id NOT IN (SELECT MIN(id) FROM ...)
--   SQL Server 的方式最直观: 在 CTE 中标记要删除的行，然后直接 DELETE。

-- ============================================================
-- 3. DELETE + JOIN（替代方法）
-- ============================================================
DELETE u1 FROM users u1
JOIN users u2 ON u1.email = u2.email AND u1.user_id < u2.user_id;

-- ============================================================
-- 4. 去重到新表
-- ============================================================
SELECT * INTO users_clean
FROM (SELECT *, ROW_NUMBER() OVER (PARTITION BY email ORDER BY created_at DESC) AS rn
      FROM users) ranked
WHERE rn = 1;

-- ============================================================
-- 5. 大表分批去重
-- ============================================================
DECLARE @batch INT = 10000;
WHILE 1 = 1
BEGIN
    ;WITH duplicates AS (
        SELECT TOP (@batch) user_id,
               ROW_NUMBER() OVER (PARTITION BY email ORDER BY created_at DESC) AS rn
        FROM users
    )
    DELETE FROM duplicates WHERE rn > 1;
    IF @@ROWCOUNT < @batch BREAK;
END;

-- ============================================================
-- 6. APPROX_COUNT_DISTINCT（2019+, 近似去重计数）
-- ============================================================
SELECT APPROX_COUNT_DISTINCT(email) FROM users;
-- 比 COUNT(DISTINCT email) 快 10-100x，误差约 2%

-- ============================================================
-- 7. 防止未来重复
-- ============================================================
CREATE UNIQUE INDEX uk_email ON users (email);

-- 如果需要 NULL 值可重复（多行 email 为 NULL）:
CREATE UNIQUE INDEX uk_email ON users (email) WHERE email IS NOT NULL;
-- 过滤索引: 只对非 NULL 的 email 强制唯一

-- 横向对比:
--   PostgreSQL: CREATE UNIQUE INDEX ON t (col) WHERE col IS NOT NULL（同样支持）
--   MySQL:      UNIQUE 索引允许多个 NULL（默认行为）
--   Oracle:     NULL 不参与唯一索引（默认允许多个 NULL）
