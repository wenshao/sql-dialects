-- 达梦（DM）: 集合操作
--
-- 参考资料:
--   [1] 达梦数据库 SQL 语言手册 - 集合操作
--       https://eco.dameng.com/document/dm/zh-cn/sql-dev/dmpl-sql-query.html
--   [2] 达梦数据库 SQL 语言手册 - SELECT
--       https://eco.dameng.com/document/dm/zh-cn/sql-dev/

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

-- ============================================================
-- MINUS（Oracle 兼容）
-- ============================================================
-- 达梦使用 MINUS（兼容 Oracle）
SELECT id FROM employees
MINUS
SELECT id FROM terminated_employees;

-- EXCEPT 也支持
SELECT id FROM employees
EXCEPT
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
-- 分页与集合操作
-- ============================================================
-- ROWNUM 方式（Oracle 兼容）
SELECT * FROM (
    SELECT name FROM employees
    UNION ALL
    SELECT name FROM contractors
    ORDER BY name
)
WHERE ROWNUM <= 10;

-- TOP 方式
SELECT TOP 10 * FROM (
    SELECT name FROM employees
    UNION ALL
    SELECT name FROM contractors
) combined
ORDER BY name;

-- LIMIT 方式
SELECT name FROM employees
UNION ALL
SELECT name FROM contractors
ORDER BY name
LIMIT 10;

-- ============================================================
-- 注意事项
-- ============================================================
-- 达梦兼容 Oracle 语法，使用 MINUS
-- 同时支持 EXCEPT 和 MINUS
-- 支持多种分页语法（ROWNUM / TOP / LIMIT）
-- LOB 类型列有集合操作限制
