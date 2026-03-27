-- TiDB: 集合操作
--
-- 参考资料:
--   [1] TiDB Documentation - UNION
--       https://docs.pingcap.com/tidb/stable/sql-statement-select#union
--   [2] TiDB Documentation - INTERSECT / EXCEPT
--       https://docs.pingcap.com/tidb/stable/sql-statement-select

-- ============================================================
-- UNION / UNION ALL（全版本支持）
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
-- INTERSECT / INTERSECT ALL（6.4+）
-- ============================================================
-- 注意：TiDB 6.4 之前不支持 INTERSECT
SELECT id FROM employees
INTERSECT
SELECT id FROM project_members;

SELECT id FROM employees
INTERSECT ALL
SELECT id FROM project_members;

-- 6.4 之前的替代方案
SELECT DISTINCT e.id FROM employees e
INNER JOIN project_members p ON e.id = p.id;

-- ============================================================
-- EXCEPT / EXCEPT ALL（6.4+）
-- ============================================================
SELECT id FROM employees
EXCEPT
SELECT id FROM terminated_employees;

SELECT id FROM employees
EXCEPT ALL
SELECT id FROM terminated_employees;

-- 6.4 之前的替代方案
SELECT e.id FROM employees e
LEFT JOIN terminated_employees t ON e.id = t.id
WHERE t.id IS NULL;

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

-- 限制单个分支
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

SELECT name FROM employees
UNION ALL
SELECT name FROM contractors
ORDER BY name
LIMIT 10 OFFSET 20;

-- ============================================================
-- 注意事项
-- ============================================================
-- TiDB 兼容 MySQL 语法
-- INTERSECT 和 EXCEPT 从 6.4 版本开始支持（含 ALL 变体）
-- 之前版本需使用 JOIN 或 NOT EXISTS 替代
-- 分布式架构下 UNION（去重）可能触发跨节点排序
