-- SQL Standard (ISO/IEC 9075): Views
--
-- 参考资料:
--   [1] ISO/IEC 9075-2:2023 - SQL/Foundation - CREATE VIEW
--       https://www.iso.org/standard/76584.html
--   [2] SQL Standard - Wikipedia
--       https://en.wikipedia.org/wiki/SQL:2023

-- ============================================
-- 基本视图 (SQL-92)
-- ============================================
CREATE VIEW active_users AS
SELECT id, username, email, created_at
FROM users
WHERE age >= 18;

-- ============================================
-- 可更新视图 + WITH CHECK OPTION (SQL-92)
-- ============================================
CREATE VIEW adult_users AS
SELECT id, username, email, age
FROM users
WHERE age >= 18
WITH CHECK OPTION;

-- WITH LOCAL CHECK OPTION (SQL-92)
CREATE VIEW premium_users AS
SELECT id, username, email, age
FROM adult_users
WHERE balance > 1000
WITH LOCAL CHECK OPTION;

-- WITH CASCADED CHECK OPTION（默认，SQL-92）
CREATE VIEW senior_users AS
SELECT id, username, email, age
FROM adult_users
WHERE age >= 65
WITH CASCADED CHECK OPTION;

-- SQL 标准定义的可更新视图条件：
-- 1. 基于单个基表
-- 2. 不包含 DISTINCT
-- 3. 不包含 GROUP BY / HAVING
-- 4. 不包含聚合函数
-- 5. 不包含 UNION / INTERSECT / EXCEPT
-- 6. FROM 子句不包含多个表引用

-- ============================================
-- 递归视图 (SQL:1999)
-- ============================================
CREATE RECURSIVE VIEW employee_hierarchy (id, name, manager_id, level) AS
    SELECT id, name, manager_id, 1
    FROM employees
    WHERE manager_id IS NULL
    UNION ALL
    SELECT e.id, e.name, e.manager_id, eh.level + 1
    FROM employees e
    JOIN employee_hierarchy eh ON e.manager_id = eh.id;

-- ============================================
-- 物化视图
-- SQL 标准未定义物化视图的标准语法
-- 各数据库有各自的实现
-- ============================================

-- ============================================
-- 删除视图 (SQL-92)
-- ============================================
DROP VIEW active_users CASCADE;              -- 级联删除依赖对象
DROP VIEW active_users RESTRICT;             -- 如有依赖对象则拒绝删除

-- SQL 标准要求指定 CASCADE 或 RESTRICT
-- 实际数据库中多数默认为 RESTRICT
