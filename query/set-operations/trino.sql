-- Trino: 集合操作
--
-- 参考资料:
--   [1] Trino Documentation - Set Operations
--       https://trino.io/docs/current/sql/select.html#set-operations
--   [2] Trino Documentation - SELECT
--       https://trino.io/docs/current/sql/select.html

-- ============================================================
-- UNION / UNION ALL
-- ============================================================
SELECT id, name FROM employees
UNION
SELECT id, name FROM contractors;

SELECT id, name FROM employees
UNION ALL
SELECT id, name FROM contractors;

-- UNION DISTINCT
SELECT id, name FROM employees
UNION DISTINCT
SELECT id, name FROM contractors;

-- ============================================================
-- INTERSECT / INTERSECT ALL
-- ============================================================
SELECT id FROM employees
INTERSECT
SELECT id FROM project_members;

SELECT id FROM employees
INTERSECT ALL
SELECT id FROM project_members;

-- ============================================================
-- EXCEPT / EXCEPT ALL
-- ============================================================
SELECT id FROM employees
EXCEPT
SELECT id FROM terminated_employees;

SELECT id FROM employees
EXCEPT ALL
SELECT id FROM terminated_employees;

-- ============================================================
-- 嵌套与组合集合操作
-- ============================================================
-- INTERSECT 优先级高于 UNION 和 EXCEPT
(SELECT id FROM employees
 UNION
 SELECT id FROM contractors)
INTERSECT
SELECT id FROM project_members;

-- ============================================================
-- ORDER BY 与集合操作
-- ============================================================
SELECT name, salary FROM employees
UNION ALL
SELECT name, salary FROM contractors
ORDER BY salary DESC;

-- ============================================================
-- LIMIT / OFFSET 与集合操作
-- ============================================================
SELECT name FROM employees
UNION ALL
SELECT name FROM contractors
ORDER BY name
LIMIT 10;

-- OFFSET + LIMIT
SELECT name FROM employees
UNION ALL
SELECT name FROM contractors
ORDER BY name
OFFSET 20
LIMIT 10;

-- FETCH FIRST 语法
SELECT name FROM employees
UNION ALL
SELECT name FROM contractors
ORDER BY name
FETCH FIRST 10 ROWS ONLY;

-- ============================================================
-- 跨 Catalog 集合操作
-- ============================================================
-- Trino 可以在不同数据源之间做集合操作
SELECT id, name FROM hive.default.employees
UNION ALL
SELECT id, name FROM mysql.mydb.contractors;

-- ============================================================
-- 注意事项
-- ============================================================
-- Trino 完整支持 SQL 标准的集合操作（含 ALL 变体）
-- 支持跨数据源（Catalog）的集合操作
-- 类型转换遵循 Trino 的类型系统规则
-- MAP / ARRAY / ROW 类型可用于集合操作
