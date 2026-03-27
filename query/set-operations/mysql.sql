-- MySQL: 集合操作
--
-- 参考资料:
--   [1] MySQL 8.0 Reference Manual - UNION Clause
--       https://dev.mysql.com/doc/refman/8.0/en/union.html
--   [2] MySQL 8.0 Reference Manual - INTERSECT / EXCEPT
--       https://dev.mysql.com/doc/refman/8.4/en/intersect.html
--   [3] MySQL 8.0 Reference Manual - Set Operations with ORDER BY and LIMIT
--       https://dev.mysql.com/doc/refman/8.0/en/union.html#union-order-by-limit

-- ============================================================
-- UNION / UNION ALL（全版本支持）
-- ============================================================
SELECT id, name FROM employees
UNION
SELECT id, name FROM contractors;

SELECT id, name FROM employees
UNION ALL
SELECT id, name FROM contractors;

-- UNION DISTINCT 等价于 UNION
SELECT id, name FROM employees
UNION DISTINCT
SELECT id, name FROM contractors;

-- ============================================================
-- INTERSECT / INTERSECT ALL（8.0.31+）
-- ============================================================
-- 注意：8.0.31 之前不支持 INTERSECT
SELECT id FROM employees
INTERSECT
SELECT id FROM project_members;

SELECT id FROM employees
INTERSECT ALL
SELECT id FROM project_members;

-- 8.0.31 之前的替代方案
SELECT DISTINCT e.id FROM employees e
INNER JOIN project_members p ON e.id = p.id;

-- ============================================================
-- EXCEPT（8.0.31+）
-- ============================================================
-- 注意：8.0.31 之前不支持 EXCEPT
SELECT id FROM employees
EXCEPT
SELECT id FROM terminated_employees;

SELECT id FROM employees
EXCEPT ALL
SELECT id FROM terminated_employees;

-- 8.0.31 之前的替代方案
SELECT e.id FROM employees e
LEFT JOIN terminated_employees t ON e.id = t.id
WHERE t.id IS NULL;

-- 或使用 NOT EXISTS
SELECT id FROM employees e
WHERE NOT EXISTS (SELECT 1 FROM terminated_employees t WHERE t.id = e.id);

-- ============================================================
-- 嵌套与组合集合操作（8.0.31+）
-- ============================================================
-- 8.0.31+ 支持括号控制优先级
(SELECT id FROM employees
 UNION
 SELECT id FROM contractors)
INTERSECT
SELECT id FROM project_members;

-- ============================================================
-- ORDER BY 与集合操作
-- ============================================================
-- ORDER BY 作用于整个结果集
SELECT name, salary FROM employees
UNION ALL
SELECT name, salary FROM contractors
ORDER BY salary DESC;

-- 限制单个分支的排序（需括号，8.0+）
(SELECT name FROM employees ORDER BY name LIMIT 5)
UNION ALL
(SELECT name FROM contractors ORDER BY name LIMIT 5);

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

-- ============================================================
-- 注意事项
-- ============================================================
-- MySQL UNION 默认使用 DISTINCT（去重），性能较 UNION ALL 差
-- 如不需要去重，始终使用 UNION ALL
-- 列名取自第一个 SELECT
-- 列的数据类型会自动协调（如 VARCHAR + INT -> VARCHAR）
