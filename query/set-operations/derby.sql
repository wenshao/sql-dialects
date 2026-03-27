-- Apache Derby: 集合操作
--
-- 参考资料:
--   [1] Apache Derby Reference Manual - Set Operations
--       https://db.apache.org/derby/docs/10.16/ref/rrefsqlj13658.html
--   [2] Apache Derby Reference Manual - SELECT
--       https://db.apache.org/derby/docs/10.16/ref/rrefsqlj41360.html

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
-- FETCH FIRST 与集合操作
-- ============================================================
SELECT name FROM employees
UNION ALL
SELECT name FROM contractors
ORDER BY name
FETCH FIRST 10 ROWS ONLY;

-- OFFSET + FETCH（10.5+）
SELECT name FROM employees
UNION ALL
SELECT name FROM contractors
ORDER BY name
OFFSET 20 ROWS FETCH NEXT 10 ROWS ONLY;

-- ============================================================
-- 注意事项
-- ============================================================
-- Derby 完整支持 SQL 标准的集合操作（含 ALL 变体）
-- LONG VARCHAR 类型不能用于集合操作中的去重
-- 列的数据类型需要兼容
-- ORDER BY 只能使用列名或列号
