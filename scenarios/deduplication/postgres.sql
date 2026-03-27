-- PostgreSQL: 数据去重 (Deduplication)
--
-- 参考资料:
--   [1] PostgreSQL Documentation - DISTINCT ON
--       https://www.postgresql.org/docs/current/sql-select.html#SQL-DISTINCT

-- ============================================================
-- 1. 查找重复数据
-- ============================================================

SELECT email, COUNT(*) AS cnt FROM users GROUP BY email HAVING COUNT(*) > 1;

-- ============================================================
-- 2. DISTINCT ON: PostgreSQL 独有的去重利器
-- ============================================================

-- 每个 email 保留最新记录（最简洁方式）
SELECT DISTINCT ON (email) user_id, email, username, created_at
FROM users ORDER BY email, created_at DESC;

-- 多列 DISTINCT ON
SELECT DISTINCT ON (username, email) *
FROM users ORDER BY username, email, created_at DESC;

-- 设计分析: DISTINCT ON 的独特性
--   DISTINCT ON (expr) 保留每组的"第一行"——由 ORDER BY 决定哪行是"第一"。
--   这是 PostgreSQL 独有的非标准扩展，其他数据库无等价语法。
--
--   内部实现: 优化器将 DISTINCT ON 转换为:
--     (a) Sort + Unique（按 DISTINCT ON 列排序，去重）
--     (b) 或 Group + First Value（如果有索引支持）
--
--   对比:
--     MySQL:      无 DISTINCT ON（需 ROW_NUMBER 子查询或 GROUP BY 非标准行为）
--     Oracle:     无 DISTINCT ON（用 ROW_NUMBER + WHERE rn = 1）
--     SQL Server: 无 DISTINCT ON（同上）
--
--   DISTINCT ON 的限制:
--     ORDER BY 的前缀必须匹配 DISTINCT ON 的列列表。
--     不能用 DISTINCT ON (a) 但 ORDER BY (b)（语义矛盾）。

-- ============================================================
-- 3. ROW_NUMBER 方式（跨数据库通用）
-- ============================================================

SELECT * FROM (
    SELECT user_id, email, username, created_at,
           ROW_NUMBER() OVER (PARTITION BY email ORDER BY created_at DESC) AS rn
    FROM users
) ranked WHERE rn = 1;

-- ============================================================
-- 4. 删除重复数据
-- ============================================================

-- 方法 1: ctid（PostgreSQL 物理行 ID，适合无主键表）
DELETE FROM users WHERE ctid NOT IN (
    SELECT MIN(ctid) FROM users GROUP BY email
);

-- 方法 2: DELETE USING（保留最新记录）
DELETE FROM users a USING users b
WHERE a.email = b.email AND a.created_at < b.created_at;

-- 方法 3: CTE + ROW_NUMBER
WITH dups AS (
    SELECT user_id, ROW_NUMBER() OVER (PARTITION BY email ORDER BY created_at DESC) AS rn
    FROM users
)
DELETE FROM users WHERE user_id IN (SELECT user_id FROM dups WHERE rn > 1);

-- ============================================================
-- 5. 去重后创建新表
-- ============================================================

CREATE TABLE users_clean AS
SELECT DISTINCT ON (email) user_id, email, username, created_at
FROM users ORDER BY email, created_at DESC;

-- ============================================================
-- 6. 横向对比与对引擎开发者的启示
-- ============================================================

-- DISTINCT ON 是 PostgreSQL 最简洁的"分组取首行"方案:
--   比 ROW_NUMBER 子查询少一层嵌套，语义更直观。
--   但因为是非标准扩展，跨数据库迁移时需要改写为 ROW_NUMBER。
--
-- ctid 去重是 PostgreSQL 特有的技巧:
--   ctid（行的物理位置）可以在无主键表上唯一标识行。
--   对比: Oracle 有 ROWID（类似语义），MySQL 无等价概念。
--
-- 对引擎开发者:
--   DISTINCT ON 的实现成本很低（在现有 DISTINCT 基础上增加"分组"语义），
--   但对 "每组取第一行" 这个极高频需求提供了最优解。
