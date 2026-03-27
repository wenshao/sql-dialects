-- PostgreSQL: 数据去重策略（Deduplication）
--
-- 参考资料:
--   [1] PostgreSQL Documentation - DISTINCT ON
--       https://www.postgresql.org/docs/current/sql-select.html#SQL-DISTINCT
--   [2] PostgreSQL Documentation - DELETE USING
--       https://www.postgresql.org/docs/current/sql-delete.html
--   [3] PostgreSQL Documentation - Window Functions
--       https://www.postgresql.org/docs/current/tutorial-window.html

-- ============================================================
-- 示例数据上下文
-- ============================================================
-- 假设表结构:
--   users(user_id SERIAL, email VARCHAR(255), username VARCHAR(64), created_at TIMESTAMP)

-- ============================================================
-- 1. 查找重复数据
-- ============================================================

SELECT email, COUNT(*) AS cnt
FROM users
GROUP BY email
HAVING COUNT(*) > 1;

-- 查找重复并显示具体行
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
-- 3. DISTINCT ON（PostgreSQL 独有特性）
-- ============================================================

-- 每个 email 保留最新记录（最简洁方式）
SELECT DISTINCT ON (email)
       user_id, email, username, created_at
FROM users
ORDER BY email, created_at DESC;

-- 每个 email 保留最早记录
SELECT DISTINCT ON (email)
       user_id, email, username, created_at
FROM users
ORDER BY email, created_at ASC;

-- 多列 DISTINCT ON
SELECT DISTINCT ON (username, email)
       user_id, email, username, created_at
FROM users
ORDER BY username, email, created_at DESC;

-- ============================================================
-- 4. 删除重复数据
-- ============================================================

-- 方法一：使用 ctid（PostgreSQL 物理行 ID）
DELETE FROM users
WHERE ctid NOT IN (
    SELECT MIN(ctid)
    FROM users
    GROUP BY email
);

-- 方法二：DELETE USING（保留最新记录）
DELETE FROM users a
USING users b
WHERE a.email = b.email
  AND a.created_at < b.created_at;

-- 方法三：DELETE USING + ctid（同 email 保留第一条物理行）
DELETE FROM users a
USING users b
WHERE a.email = b.email
  AND a.ctid > b.ctid;

-- 方法四：CTE + ROW_NUMBER
WITH duplicates AS (
    SELECT user_id,
           ROW_NUMBER() OVER (
               PARTITION BY email
               ORDER BY created_at DESC
           ) AS rn
    FROM users
)
DELETE FROM users
WHERE user_id IN (
    SELECT user_id FROM duplicates WHERE rn > 1
);

-- ============================================================
-- 5. DISTINCT vs GROUP BY
-- ============================================================

-- DISTINCT 去重
SELECT DISTINCT email FROM users;

-- GROUP BY 去重（等价于上面）
SELECT email FROM users GROUP BY email;

-- GROUP BY + 聚合
SELECT email, COUNT(*) AS cnt, MAX(created_at) AS latest
FROM users
GROUP BY email;

-- ============================================================
-- 6. 去重后创建新表
-- ============================================================

CREATE TABLE users_clean AS
SELECT DISTINCT ON (email)
       user_id, email, username, created_at
FROM users
ORDER BY email, created_at DESC;

-- ============================================================
-- 7. 近似去重（HyperLogLog，需要 postgresql-hll 扩展）
-- ============================================================

-- 安装扩展
-- CREATE EXTENSION hll;

-- 近似不重复计数
-- SELECT hll_cardinality(hll_add_agg(hll_hash_text(email)))::BIGINT AS approx_distinct
-- FROM users;

-- PostgreSQL 内置 approx_count_distinct 不可用，但可以用 hll 扩展
-- 或使用 pg_trgm 扩展做模糊去重

-- ============================================================
-- 8. 性能考量
-- ============================================================

CREATE INDEX idx_users_email ON users (email);

-- DISTINCT ON 是 PostgreSQL 最简洁的去重方式
-- ctid 方式适合无主键表的去重
-- DELETE USING 比关联子查询更高效
-- 大表去重建议分批操作（避免长事务）
-- DISTINCT ON + 覆盖索引性能最优
