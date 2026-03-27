-- CockroachDB: 集合操作
--
-- 参考资料:
--   [1] CockroachDB Documentation - Selection Queries
--       https://www.cockroachlabs.com/docs/stable/selection-queries
--   [2] CockroachDB Documentation - Set Operations
--       https://www.cockroachlabs.com/docs/stable/selection-queries#set-operations

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

-- ============================================================
-- 注意事项
-- ============================================================
-- CockroachDB 兼容 PostgreSQL 语法，完整支持所有集合操作
-- 支持 ALL 变体
-- 在分布式环境中，集合操作可能需要跨节点数据传输
-- 类型转换规则与 PostgreSQL 一致
