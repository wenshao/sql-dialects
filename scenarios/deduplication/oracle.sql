-- Oracle: 数据去重策略（Deduplication）
--
-- 参考资料:
--   [1] Oracle Documentation - DELETE
--       https://docs.oracle.com/en/database/oracle/oracle-database/19/sqlrf/DELETE.html
--   [2] Oracle Documentation - MERGE
--       https://docs.oracle.com/en/database/oracle/oracle-database/19/sqlrf/MERGE.html
--   [3] Oracle Documentation - Analytic Functions
--       https://docs.oracle.com/en/database/oracle/oracle-database/19/sqlrf/Analytic-Functions.html

-- ============================================================
-- 示例数据上下文
-- ============================================================
-- 假设表结构:
--   users(user_id NUMBER, email VARCHAR2(255), username VARCHAR2(64), created_at TIMESTAMP)

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
-- 3. 删除重复数据
-- ============================================================

-- 方法一：使用 ROWID（Oracle 物理行 ID）
DELETE FROM users
WHERE ROWID NOT IN (
    SELECT MIN(ROWID)
    FROM users
    GROUP BY email
);

-- 方法二：保留最新记录（使用 ROWID + 分析函数）
DELETE FROM users
WHERE ROWID IN (
    SELECT rid FROM (
        SELECT ROWID AS rid,
               ROW_NUMBER() OVER (
                   PARTITION BY email
                   ORDER BY created_at DESC
               ) AS rn
        FROM users
    ) WHERE rn > 1
);

-- 方法三：使用 KEEP (DENSE_RANK)
DELETE FROM users
WHERE ROWID NOT IN (
    SELECT MIN(ROWID) KEEP (DENSE_RANK FIRST ORDER BY created_at DESC)
    FROM users
    GROUP BY email
);

-- ============================================================
-- 4. 防止重复（MERGE）
-- ============================================================

MERGE INTO users target
USING (SELECT 'a@b.com' AS email, 'alice' AS username, SYSTIMESTAMP AS created_at FROM dual) source
ON (target.email = source.email)
WHEN MATCHED THEN
    UPDATE SET target.username = source.username, target.created_at = source.created_at
WHEN NOT MATCHED THEN
    INSERT (user_id, email, username, created_at)
    VALUES (user_seq.NEXTVAL, source.email, source.username, source.created_at);

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
-- 7. 近似去重（APPROX_COUNT_DISTINCT，Oracle 12c+）
-- ============================================================

-- 近似不重复计数（比 COUNT(DISTINCT) 快得多）
SELECT APPROX_COUNT_DISTINCT(email) AS approx_distinct_emails
FROM users;

-- ============================================================
-- 8. 性能考量
-- ============================================================

CREATE INDEX idx_users_email ON users (email);

-- ROWID 方式是 Oracle 去重的经典方式
-- KEEP (DENSE_RANK) 在 GROUP BY 中非常高效
-- MERGE 可实现 upsert
-- APPROX_COUNT_DISTINCT 使用 HyperLogLog 算法（Oracle 12c+）
-- 大表去重建议分批操作或使用 CTAS 重建表
