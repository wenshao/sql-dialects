-- H2: 集合操作
--
-- 参考资料:
--   [1] H2 Database Documentation - SELECT
--       https://h2database.com/html/commands.html#select
--   [2] H2 Database Documentation - Grammar
--       https://h2database.com/html/grammar.html

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
-- EXCEPT / EXCEPT ALL / MINUS
-- ============================================================
SELECT id FROM employees
EXCEPT
SELECT id FROM terminated_employees;

SELECT id FROM employees
EXCEPT ALL
SELECT id FROM terminated_employees;

-- MINUS 作为 EXCEPT 的别名
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
-- LIMIT / OFFSET 与集合操作
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

-- FETCH FIRST 语法
SELECT name FROM employees
UNION ALL
SELECT name FROM contractors
ORDER BY name
FETCH FIRST 10 ROWS ONLY;

-- ============================================================
-- 注意事项
-- ============================================================
-- H2 完整支持 SQL 标准的集合操作（含 ALL 变体）
-- 同时支持 EXCEPT 和 MINUS
-- 支持 LIMIT/OFFSET 和 FETCH FIRST 两种分页语法
-- 类型转换规则宽松
