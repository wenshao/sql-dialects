-- Apache Doris: 集合操作
--
-- 参考资料:
--   [1] Apache Doris Documentation - Set Operations
--       https://doris.apache.org/docs/sql-manual/sql-statements/query/set-operations/
--   [2] Apache Doris Documentation - SELECT
--       https://doris.apache.org/docs/sql-manual/sql-statements/query/SELECT/

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
-- INTERSECT（1.2+）
-- ============================================================
SELECT id FROM employees
INTERSECT
SELECT id FROM project_members;

-- 注意：Doris 不支持 INTERSECT ALL

-- ============================================================
-- EXCEPT / MINUS（1.2+）
-- ============================================================
SELECT id FROM employees
EXCEPT
SELECT id FROM terminated_employees;

-- MINUS 作为别名
SELECT id FROM employees
MINUS
SELECT id FROM terminated_employees;

-- 注意：Doris 不支持 EXCEPT ALL

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
-- INTERSECT 和 EXCEPT/MINUS 从 1.2 版本开始支持
-- 不支持 ALL 变体（INTERSECT ALL / EXCEPT ALL）
-- BITMAP 和 HLL 列类型不能直接用于集合操作
-- 在 MPP 架构下，UNION ALL 性能优于 UNION
