-- YugabyteDB: 集合操作
--
-- 参考资料:
--   [1] YugabyteDB Documentation - UNION, INTERSECT, EXCEPT
--       https://docs.yugabyte.com/preview/api/ysql/the-sql-language/statements/dml_select/
--   [2] YugabyteDB Documentation - SELECT
--       https://docs.yugabyte.com/preview/api/ysql/the-sql-language/statements/dml_select/

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
-- YugabyteDB YSQL 兼容 PostgreSQL，完整支持所有集合操作
-- 支持所有 ALL 变体
-- 分布式环境中集合操作可能需要跨节点数据传输
-- 性能受数据分布和分片策略影响
