-- StarRocks: 集合操作
--
-- 参考资料:
--   [1] StarRocks Documentation - UNION
--       https://docs.starrocks.io/docs/sql-reference/sql-statements/query/SELECT/#union
--   [2] StarRocks Documentation - INTERSECT / EXCEPT
--       https://docs.starrocks.io/docs/sql-reference/sql-statements/query/SELECT/

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
-- INTERSECT
-- ============================================================
SELECT id FROM employees
INTERSECT
SELECT id FROM project_members;

-- 注意：StarRocks 不支持 INTERSECT ALL

-- ============================================================
-- EXCEPT / MINUS
-- ============================================================
SELECT id FROM employees
EXCEPT
SELECT id FROM terminated_employees;

-- MINUS 作为别名
SELECT id FROM employees
MINUS
SELECT id FROM terminated_employees;

-- 注意：StarRocks 不支持 EXCEPT ALL

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
-- 注意事项
-- ============================================================
-- StarRocks 支持 UNION / INTERSECT / EXCEPT
-- 不支持 ALL 变体
-- BITMAP / HLL 类型列不能直接用于集合操作
-- MPP 架构下建议优先使用 UNION ALL
