-- Materialize: 集合操作
--
-- 参考资料:
--   [1] Materialize Documentation - SELECT
--       https://materialize.com/docs/sql/select/
--   [2] Materialize Documentation - Set Operations
--       https://materialize.com/docs/sql/select/#set-operations

-- ============================================================
-- UNION / UNION ALL
-- ============================================================
SELECT id, name FROM employees
UNION
SELECT id, name FROM contractors;

SELECT id, name FROM employees
UNION ALL
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

SELECT name FROM employees
UNION ALL
SELECT name FROM contractors
ORDER BY name
LIMIT 10 OFFSET 20;

-- ============================================================
-- 在物化视图中使用集合操作
-- ============================================================
CREATE MATERIALIZED VIEW all_personnel AS
SELECT id, name, 'employee' AS type FROM employees
UNION ALL
SELECT id, name, 'contractor' AS type FROM contractors;

-- ============================================================
-- 注意事项
-- ============================================================
-- Materialize 兼容 PostgreSQL 语法，支持所有集合操作
-- 集合操作可用于物化视图定义
-- 增量计算特性使得集合操作在流数据上高效执行
-- 支持 ALL 变体
