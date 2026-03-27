-- SQL Server: 集合操作（全版本支持）
--
-- 参考资料:
--   [1] Microsoft Docs - Set Operators (UNION, EXCEPT, INTERSECT)
--       https://learn.microsoft.com/en-us/sql/t-sql/language-elements/set-operators-union-transact-sql
--   [2] Microsoft Docs - SELECT - ORDER BY Clause
--       https://learn.microsoft.com/en-us/sql/t-sql/queries/select-order-by-clause-transact-sql
--   [3] Microsoft Docs - EXCEPT and INTERSECT
--       https://learn.microsoft.com/en-us/sql/t-sql/language-elements/set-operators-except-and-intersect-transact-sql

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

-- 注意：SQL Server 不支持 INTERSECT ALL
-- 替代方案
SELECT id FROM (
    SELECT id, ROW_NUMBER() OVER (PARTITION BY id ORDER BY id) AS rn FROM employees
) e
INNER JOIN (
    SELECT id, ROW_NUMBER() OVER (PARTITION BY id ORDER BY id) AS rn FROM project_members
) p ON e.id = p.id AND e.rn = p.rn;

-- ============================================================
-- EXCEPT
-- ============================================================
SELECT id FROM employees
EXCEPT
SELECT id FROM terminated_employees;

-- 注意：SQL Server 不支持 EXCEPT ALL
-- 替代方案
SELECT id FROM (
    SELECT id, ROW_NUMBER() OVER (PARTITION BY id ORDER BY id) AS rn FROM employees
) e
WHERE NOT EXISTS (
    SELECT 1 FROM (
        SELECT id, ROW_NUMBER() OVER (PARTITION BY id ORDER BY id) AS rn FROM terminated_employees
    ) t WHERE e.id = t.id AND e.rn = t.rn
);

-- ============================================================
-- 嵌套与组合集合操作
-- ============================================================
-- INTERSECT 优先级高于 UNION 和 EXCEPT
-- 可使用括号控制优先级（2008+）
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
-- TOP / OFFSET-FETCH 与集合操作
-- ============================================================
-- TOP 不能直接用于集合操作的最终结果，需包装子查询
SELECT TOP 10 * FROM (
    SELECT name FROM employees
    UNION ALL
    SELECT name FROM contractors
) AS combined
ORDER BY name;

-- OFFSET-FETCH（2012+）
SELECT name FROM employees
UNION ALL
SELECT name FROM contractors
ORDER BY name
OFFSET 20 ROWS FETCH NEXT 10 ROWS ONLY;

-- ============================================================
-- 限制单个分支
-- ============================================================
SELECT TOP 5 name FROM employees
UNION ALL
SELECT TOP 5 name FROM contractors;

-- ============================================================
-- 与 CTE 结合
-- ============================================================
WITH active_employees AS (
    SELECT id, name FROM employees WHERE active = 1
),
active_contractors AS (
    SELECT id, name FROM contractors WHERE active = 1
)
SELECT id, name FROM active_employees
UNION ALL
SELECT id, name FROM active_contractors
ORDER BY name;

-- ============================================================
-- 注意事项
-- ============================================================
-- text / ntext / image 类型不能用于 UNION（已废弃，用 VARCHAR(MAX) 替代）
-- xml 类型不能直接用于 EXCEPT / INTERSECT
-- 使用 UNION 而非 UNION ALL 时，SQL Server 会执行隐式 DISTINCT
