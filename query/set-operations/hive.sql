-- Hive: 集合操作
--
-- 参考资料:
--   [1] Apache Hive Language Manual - Union
--       https://cwiki.apache.org/confluence/display/Hive/LanguageManual+Union
--   [2] Apache Hive Documentation - SELECT
--       https://cwiki.apache.org/confluence/display/Hive/LanguageManual+Select

-- ============================================================
-- UNION ALL（全版本支持）
-- ============================================================
SELECT id, name FROM employees
UNION ALL
SELECT id, name FROM contractors;

-- ============================================================
-- UNION DISTINCT（1.2.0+）
-- ============================================================
-- 注意：Hive 1.2.0 之前只支持 UNION ALL
SELECT id, name FROM employees
UNION
SELECT id, name FROM contractors;

SELECT id, name FROM employees
UNION DISTINCT
SELECT id, name FROM contractors;

-- 1.2.0 之前模拟 UNION（去重）
SELECT DISTINCT * FROM (
    SELECT id, name FROM employees
    UNION ALL
    SELECT id, name FROM contractors
) combined;

-- ============================================================
-- INTERSECT（2.1.0+）
-- ============================================================
SELECT id FROM employees
INTERSECT
SELECT id FROM project_members;

-- INTERSECT DISTINCT（2.1.0+）
SELECT id FROM employees
INTERSECT DISTINCT
SELECT id FROM project_members;

-- 2.1.0 之前的替代方案
SELECT DISTINCT e.id FROM employees e
INNER JOIN project_members p ON e.id = p.id;

-- ============================================================
-- EXCEPT / MINUS（2.1.0+）
-- ============================================================
SELECT id FROM employees
EXCEPT
SELECT id FROM terminated_employees;

-- MINUS 作为别名
SELECT id FROM employees
MINUS
SELECT id FROM terminated_employees;

-- 2.1.0 之前的替代方案
SELECT e.id FROM employees e
LEFT JOIN terminated_employees t ON e.id = t.id
WHERE t.id IS NULL;

-- ============================================================
-- 嵌套与组合集合操作
-- ============================================================
-- Hive 支持使用子查询嵌套集合操作
SELECT * FROM (
    SELECT id FROM employees
    UNION ALL
    SELECT id FROM contractors
) combined
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
-- Hive 1.2.0 之前只支持 UNION ALL
-- INTERSECT 和 EXCEPT/MINUS 从 2.1.0 开始支持
-- 不支持 INTERSECT ALL 和 EXCEPT ALL
-- 集合操作的子查询中，列名和类型必须匹配
-- Hive 3.0 改进了集合操作的性能
