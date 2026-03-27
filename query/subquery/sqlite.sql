-- SQLite: 子查询
--
-- 参考资料:
--   [1] SQLite Documentation - SELECT (Subqueries)
--       https://www.sqlite.org/lang_select.html

-- ============================================================
-- 1. 标量子查询（返回单个值）
-- ============================================================

SELECT username, age,
       (SELECT AVG(age) FROM users) AS avg_age
FROM users;

SELECT * FROM users WHERE age > (SELECT AVG(age) FROM users);

-- ============================================================
-- 2. IN / NOT IN 子查询
-- ============================================================

SELECT * FROM users WHERE id IN (SELECT user_id FROM orders WHERE amount > 100);
SELECT * FROM users WHERE id NOT IN (SELECT user_id FROM blacklist);
-- 注意: NOT IN 遇到 NULL 会返回空结果! 建议用 NOT EXISTS 替代

-- ============================================================
-- 3. EXISTS / NOT EXISTS
-- ============================================================

SELECT * FROM users u
WHERE EXISTS (SELECT 1 FROM orders o WHERE o.user_id = u.id AND o.amount > 100);

SELECT * FROM users u
WHERE NOT EXISTS (SELECT 1 FROM orders o WHERE o.user_id = u.id);

-- EXISTS vs IN 的性能差异:
-- SQLite 的优化器会将 IN 子查询转换为 EXISTS（如果可能）。
-- 大多数情况下性能相同，但 NOT EXISTS 比 NOT IN 更安全（NULL 处理）。

-- ============================================================
-- 4. FROM 子句子查询（派生表）
-- ============================================================

SELECT username, order_stats.total_amount
FROM users u
JOIN (
    SELECT user_id, SUM(amount) AS total_amount
    FROM orders GROUP BY user_id
) order_stats ON u.id = order_stats.user_id;

-- ============================================================
-- 5. 相关子查询（Correlated Subquery）
-- ============================================================

-- 相关子查询对外部查询的每一行执行一次:
SELECT u.username,
       (SELECT COUNT(*) FROM orders o WHERE o.user_id = u.id) AS order_count
FROM users u;

-- 相关子查询在 UPDATE 中:
UPDATE users SET order_count = (
    SELECT COUNT(*) FROM orders WHERE orders.user_id = users.id
);

-- ============================================================
-- 6. 不支持的子查询（设计分析）
-- ============================================================

-- SQLite 不支持:
-- LATERAL JOIN（PostgreSQL 9.3+，MySQL 8.0.14+）
-- → 替代: 相关子查询或 CTE
-- ANY / ALL 操作符 → 用 IN / EXISTS 替代
-- ARRAY 子查询 → 用 json_group_array 替代

-- ============================================================
-- 7. 对比与引擎开发者启示
-- ============================================================
-- SQLite 子查询的设计:
--   标量/IN/EXISTS/FROM/相关子查询全部支持
--   不支持 LATERAL JOIN（嵌入式场景不常需要）
--   优化器会尝试将 IN 转为 EXISTS（去相关化）
--
-- 对引擎开发者的启示:
--   子查询去相关化（decorrelation）是优化器的核心能力。
--   SQLite 的优化器在这方面做得不错（考虑到其代码量）。
--   EXISTS 比 IN 更安全（NULL 处理），应该在文档中推荐。
