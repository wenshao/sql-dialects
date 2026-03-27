-- Spark SQL: 集合操作
--
-- 参考资料:
--   [1] Spark SQL Documentation - Set Operators
--       https://spark.apache.org/docs/latest/sql-ref-syntax-qry-select-setops.html
--   [2] Spark SQL Documentation - SELECT
--       https://spark.apache.org/docs/latest/sql-ref-syntax-qry-select.html

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
-- INTERSECT / INTERSECT ALL（3.1+）
-- ============================================================
SELECT id FROM employees
INTERSECT
SELECT id FROM project_members;

-- INTERSECT ALL（Spark 3.1+）
SELECT id FROM employees
INTERSECT ALL
SELECT id FROM project_members;

-- ============================================================
-- EXCEPT / EXCEPT ALL / MINUS
-- ============================================================
SELECT id FROM employees
EXCEPT
SELECT id FROM terminated_employees;

-- EXCEPT ALL（Spark 3.1+）
SELECT id FROM employees
EXCEPT ALL
SELECT id FROM terminated_employees;

-- MINUS 等价于 EXCEPT
SELECT id FROM employees
MINUS
SELECT id FROM terminated_employees;

-- ============================================================
-- 嵌套与组合集合操作
-- ============================================================
-- INTERSECT 优先级最高
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

-- ============================================================
-- 注意事项
-- ============================================================
-- Spark SQL 中 UNION 等价于 UNION DISTINCT（与 SQL 标准一致）
-- MINUS 是 EXCEPT 的别名
-- INTERSECT ALL 和 EXCEPT ALL 从 Spark 3.1 开始支持
-- 集合操作中的列名取自第一个查询
-- 类型提升遵循 Spark 的类型转换规则
