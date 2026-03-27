-- PostgreSQL: 集合操作（全版本支持）
--
-- 参考资料:
--   [1] PostgreSQL Documentation - UNION, INTERSECT, EXCEPT
--       https://www.postgresql.org/docs/current/queries-union.html
--   [2] PostgreSQL Documentation - SELECT
--       https://www.postgresql.org/docs/current/sql-select.html
--   [3] PostgreSQL Documentation - Type Conversion
--       https://www.postgresql.org/docs/current/typeconv-union-case.html

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
-- INTERSECT 优先级高于 UNION 和 EXCEPT
-- 可使用括号明确优先级
(SELECT id FROM employees
 UNION
 SELECT id FROM contractors)
INTERSECT
SELECT id FROM project_members;

-- ============================================================
-- ORDER BY 与集合操作
-- ============================================================
-- ORDER BY 作用于整个结果集，只能出现在最后
SELECT name, salary FROM employees
UNION ALL
SELECT name, salary FROM contractors
ORDER BY salary DESC;

-- 可按列号排序
SELECT name, salary FROM employees
UNION ALL
SELECT name, salary FROM contractors
ORDER BY 2 DESC;

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

-- FETCH FIRST 语法（8.4+）
SELECT name FROM employees
UNION ALL
SELECT name FROM contractors
ORDER BY name
FETCH FIRST 10 ROWS ONLY;

-- ============================================================
-- 子查询中限制单个分支的行数
-- ============================================================
(SELECT name FROM employees ORDER BY name LIMIT 5)
UNION ALL
(SELECT name FROM contractors ORDER BY name LIMIT 5);

-- ============================================================
-- 与 CTE 结合使用
-- ============================================================
WITH active AS (
    SELECT id, name FROM employees WHERE active = true
)
SELECT id, name FROM active
UNION
SELECT id, name FROM contractors;

-- ============================================================
-- 类型转换规则
-- ============================================================
-- PostgreSQL 会自动尝试类型转换（如 int + numeric -> numeric）
-- 如果无法自动转换会报错，可显式 CAST
SELECT id, name::text FROM employees
UNION
SELECT id, CAST(contractor_name AS text) FROM contractors;

-- 限制：集合操作中不支持 FOR UPDATE
