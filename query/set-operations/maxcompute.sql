-- MaxCompute（ODPS）: 集合操作
--
-- 参考资料:
--   [1] MaxCompute Documentation - UNION
--       https://help.aliyun.com/zh/maxcompute/user-guide/union
--   [2] MaxCompute Documentation - SELECT
--       https://help.aliyun.com/zh/maxcompute/user-guide/select-syntax

-- ============================================================
-- UNION ALL（全版本支持）
-- ============================================================
SELECT id, name FROM employees
UNION ALL
SELECT id, name FROM contractors;

-- ============================================================
-- UNION DISTINCT / UNION（2.0+）
-- ============================================================
SELECT id, name FROM employees
UNION
SELECT id, name FROM contractors;

SELECT id, name FROM employees
UNION DISTINCT
SELECT id, name FROM contractors;

-- ============================================================
-- INTERSECT（2.0+）
-- ============================================================
SELECT id FROM employees
INTERSECT
SELECT id FROM project_members;

SELECT id FROM employees
INTERSECT DISTINCT
SELECT id FROM project_members;

-- INTERSECT ALL（2.0+）
SELECT id FROM employees
INTERSECT ALL
SELECT id FROM project_members;

-- ============================================================
-- EXCEPT / MINUS（2.0+）
-- ============================================================
SELECT id FROM employees
EXCEPT
SELECT id FROM terminated_employees;

-- MINUS 作为别名
SELECT id FROM employees
MINUS
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
-- LIMIT 与集合操作
-- ============================================================
SELECT name FROM employees
UNION ALL
SELECT name FROM contractors
ORDER BY name
LIMIT 10;

-- ============================================================
-- 注意事项
-- ============================================================
-- MaxCompute 1.0 仅支持 UNION ALL
-- MaxCompute 2.0 支持完整的集合操作
-- 大数据量下 UNION（去重）开销很大
-- 建议使用 UNION ALL 并在应用层去重
