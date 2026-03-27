-- Snowflake: 集合操作
--
-- 参考资料:
--   [1] Snowflake Documentation - Set Operators
--       https://docs.snowflake.com/en/sql-reference/operators-query
--   [2] Snowflake Documentation - SELECT
--       https://docs.snowflake.com/en/sql-reference/sql/select
--   [3] Snowflake Documentation - MINUS / EXCEPT
--       https://docs.snowflake.com/en/sql-reference/operators-query#except-minus

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
-- INTERSECT
-- ============================================================
SELECT id FROM employees
INTERSECT
SELECT id FROM project_members;

-- 注意：Snowflake 不支持 INTERSECT ALL

-- ============================================================
-- EXCEPT / MINUS
-- ============================================================
-- Snowflake 同时支持 EXCEPT 和 MINUS
SELECT id FROM employees
EXCEPT
SELECT id FROM terminated_employees;

SELECT id FROM employees
MINUS
SELECT id FROM terminated_employees;

-- 注意：Snowflake 不支持 EXCEPT ALL / MINUS ALL

-- ============================================================
-- 嵌套与组合集合操作
-- ============================================================
-- 支持括号控制优先级
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

-- LIMIT + OFFSET
SELECT name FROM employees
UNION ALL
SELECT name FROM contractors
ORDER BY name
LIMIT 10 OFFSET 20;

-- FETCH FIRST 也支持
SELECT name FROM employees
UNION ALL
SELECT name FROM contractors
ORDER BY name
FETCH FIRST 10 ROWS ONLY;

-- ============================================================
-- 与 CTE 结合
-- ============================================================
WITH active AS (
    SELECT id, name FROM employees WHERE active = TRUE
)
SELECT id, name FROM active
UNION ALL
SELECT id, name FROM contractors
ORDER BY name;

-- ============================================================
-- 注意事项
-- ============================================================
-- VARIANT / OBJECT / ARRAY 类型不能直接用于 UNION（需先转换）
-- MINUS 和 EXCEPT 功能完全相同
-- 集合操作会自动做类型兼容转换
