-- OceanBase: 集合操作
--
-- 参考资料:
--   [1] OceanBase Documentation - UNION / INTERSECT / EXCEPT
--       https://www.oceanbase.com/docs/common-oceanbase-database-cn
--   [2] OceanBase Documentation - SELECT
--       https://www.oceanbase.com/docs/common-oceanbase-database-cn

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
-- INTERSECT（MySQL 模式 4.0+，Oracle 模式全版本）
-- ============================================================
SELECT id FROM employees
INTERSECT
SELECT id FROM project_members;

-- 注意：INTERSECT ALL 仅 Oracle 模式支持

-- ============================================================
-- EXCEPT / MINUS
-- ============================================================
-- MySQL 模式使用 EXCEPT
SELECT id FROM employees
EXCEPT
SELECT id FROM terminated_employees;

-- Oracle 模式使用 MINUS
SELECT id FROM employees
MINUS
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
-- LIMIT 与集合操作
-- ============================================================
-- MySQL 模式
SELECT name FROM employees
UNION ALL
SELECT name FROM contractors
ORDER BY name
LIMIT 10;

-- Oracle 模式
SELECT name FROM employees
UNION ALL
SELECT name FROM contractors
ORDER BY name
FETCH FIRST 10 ROWS ONLY;

-- ============================================================
-- 注意事项
-- ============================================================
-- OceanBase 支持 MySQL 和 Oracle 两种兼容模式
-- MySQL 模式使用 EXCEPT，Oracle 模式使用 MINUS
-- 两种模式下 UNION / UNION ALL 语法一致
-- Oracle 模式支持更完整的集合操作特性
