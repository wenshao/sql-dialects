-- MariaDB: 集合操作 (UNION / INTERSECT / EXCEPT)
-- INTERSECT 和 EXCEPT 从 10.3+ 支持, 比 MySQL 8.0.31 更早
--
-- 参考资料:
--   [1] MariaDB Knowledge Base - UNION
--       https://mariadb.com/kb/en/union/
--   [2] MariaDB Knowledge Base - INTERSECT
--       https://mariadb.com/kb/en/intersect/

-- ============================================================
-- 1. UNION
-- ============================================================
SELECT username, email FROM users WHERE age >= 18
UNION
SELECT username, email FROM archived_users WHERE age >= 18;

SELECT username FROM users
UNION ALL
SELECT username FROM archived_users;

-- ============================================================
-- 2. INTERSECT (10.3+)
-- ============================================================
SELECT username FROM users
INTERSECT
SELECT username FROM premium_users;

-- INTERSECT ALL (10.5+): 保留重复
SELECT username FROM users
INTERSECT ALL
SELECT username FROM premium_users;

-- ============================================================
-- 3. EXCEPT (10.3+)
-- ============================================================
SELECT username FROM users
EXCEPT
SELECT username FROM blacklisted_users;

-- EXCEPT ALL (10.5+)
SELECT username FROM users
EXCEPT ALL
SELECT username FROM blacklisted_users;

-- ============================================================
-- 4. 优先级和组合
-- ============================================================
-- MariaDB 10.4+: INTERSECT 优先级高于 UNION/EXCEPT
-- A UNION B INTERSECT C = A UNION (B INTERSECT C)
-- 这符合 SQL 标准, 也与 PostgreSQL 一致
-- MySQL 8.0.31: 也遵循相同优先级

-- ============================================================
-- 5. 对引擎开发者的启示
-- ============================================================
-- INTERSECT/EXCEPT 的实现可基于:
--   1. Sort-based: 两边排序后做归并 (类似 merge join)
--   2. Hash-based: 一边建 hash table, 另一边探测
-- MariaDB 和 PostgreSQL 选择 hash-based 实现
-- MySQL 8.0.31 的实现也是 hash-based
-- ALL 变体需要维护计数器: INTERSECT ALL 取最小计数, EXCEPT ALL 做差
