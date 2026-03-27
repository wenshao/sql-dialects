-- Databricks: 集合操作
--
-- 参考资料:
--   [1] Databricks SQL Reference - Set Operators
--       https://docs.databricks.com/en/sql/language-manual/sql-ref-syntax-qry-select-setops.html
--   [2] Databricks SQL Reference - SELECT
--       https://docs.databricks.com/en/sql/language-manual/sql-ref-syntax-qry-select.html

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
-- INTERSECT 优先级高于 UNION 和 EXCEPT
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
-- Databricks 继承 Spark SQL 的集合操作支持
-- 完整支持 ALL 变体
-- 同时支持 EXCEPT 和 MINUS
-- 类型转换规则遵循 Spark 的类型提升规则
