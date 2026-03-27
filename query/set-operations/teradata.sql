-- Teradata: 集合操作
--
-- 参考资料:
--   [1] Teradata SQL Reference - Set Operators
--       https://docs.teradata.com/r/Teradata-VantageTM-SQL-Data-Manipulation-Language/July-2021/Set-Operators
--   [2] Teradata SQL Reference - SELECT
--       https://docs.teradata.com/r/Teradata-VantageTM-SQL-Data-Manipulation-Language/July-2021/SELECT-Statement

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
-- INTERSECT
-- ============================================================
SELECT id FROM employees
INTERSECT
SELECT id FROM project_members;

-- 注意：Teradata 不支持 INTERSECT ALL

-- ============================================================
-- EXCEPT / MINUS
-- ============================================================
-- Teradata 同时支持 EXCEPT 和 MINUS
SELECT id FROM employees
EXCEPT
SELECT id FROM terminated_employees;

SELECT id FROM employees
MINUS
SELECT id FROM terminated_employees;

-- 注意：Teradata 不支持 EXCEPT ALL / MINUS ALL

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
-- TOP / FETCH FIRST 与集合操作
-- ============================================================
-- 使用 TOP 限制结果集
SELECT TOP 10 * FROM (
    SELECT name FROM employees
    UNION ALL
    SELECT name FROM contractors
) combined
ORDER BY name;

-- FETCH FIRST（16.20+）
SELECT name FROM employees
UNION ALL
SELECT name FROM contractors
ORDER BY name
FETCH FIRST 10 ROWS ONLY;

-- ============================================================
-- 注意事项
-- ============================================================
-- Teradata 不支持 INTERSECT ALL 和 EXCEPT ALL
-- MINUS 是 EXCEPT 的别名
-- 集合操作中列的数据类型必须兼容
-- 大数据集上的 UNION（去重）性能开销较大
