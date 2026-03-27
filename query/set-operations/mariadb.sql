-- MariaDB: 集合操作
--
-- 参考资料:
--   [1] MariaDB Documentation - UNION
--       https://mariadb.com/kb/en/union/
--   [2] MariaDB Documentation - INTERSECT
--       https://mariadb.com/kb/en/intersect/
--   [3] MariaDB Documentation - EXCEPT
--       https://mariadb.com/kb/en/except/

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
-- INTERSECT / INTERSECT ALL（10.3+）
-- ============================================================
SELECT id FROM employees
INTERSECT
SELECT id FROM project_members;

SELECT id FROM employees
INTERSECT ALL
SELECT id FROM project_members;

-- 10.3 之前的替代方案
SELECT DISTINCT e.id FROM employees e
INNER JOIN project_members p ON e.id = p.id;

-- ============================================================
-- EXCEPT / EXCEPT ALL（10.3+）
-- ============================================================
SELECT id FROM employees
EXCEPT
SELECT id FROM terminated_employees;

SELECT id FROM employees
EXCEPT ALL
SELECT id FROM terminated_employees;

-- 10.3 之前的替代方案
SELECT e.id FROM employees e
LEFT JOIN terminated_employees t ON e.id = t.id
WHERE t.id IS NULL;

-- ============================================================
-- 嵌套与组合集合操作（10.4+）
-- ============================================================
-- 10.4+ 支持括号控制优先级
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

-- 限制单个分支（需括号）
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
-- MariaDB 10.3 引入 INTERSECT 和 EXCEPT
-- MariaDB 10.4 引入括号控制集合操作优先级
-- INTERSECT 优先级高于 UNION 和 EXCEPT
-- BLOB 列不能直接用于集合操作中的去重
