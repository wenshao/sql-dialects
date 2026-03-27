-- SQL Server: 集合操作 (UNION, INTERSECT, EXCEPT)
--
-- 参考资料:
--   [1] SQL Server T-SQL - Set Operators
--       https://learn.microsoft.com/en-us/sql/t-sql/language-elements/set-operators-union-transact-sql

-- ============================================================
-- 1. UNION / UNION ALL
-- ============================================================

SELECT id, name FROM employees
UNION                                    -- 去重
SELECT id, name FROM contractors;

SELECT id, name FROM employees
UNION ALL                                -- 保留重复
SELECT id, name FROM contractors;

-- ============================================================
-- 2. INTERSECT / EXCEPT
-- ============================================================

SELECT id FROM employees
INTERSECT                                -- 交集
SELECT id FROM project_members;

SELECT id FROM employees
EXCEPT                                   -- 差集（SQL Server 使用 EXCEPT，不是 MINUS）
SELECT id FROM terminated_employees;

-- 设计分析（对引擎开发者）:
--   SQL Server 使用 EXCEPT（SQL 标准），Oracle 使用 MINUS（非标准）。
--   两者语义完全相同，但关键字不同。
--   迁移 Oracle → SQL Server 时，MINUS 需要改为 EXCEPT。
--
--   INTERSECT ALL / EXCEPT ALL:
--   SQL Server 不支持 ALL 变体。PostgreSQL 支持。
--   ALL 变体保留重复行的计数——INTERSECT ALL 返回 min(count_A, count_B) 个重复行。

-- 不支持 INTERSECT ALL 的替代方案:
SELECT id FROM (
    SELECT id, ROW_NUMBER() OVER (PARTITION BY id ORDER BY id) AS rn FROM employees
) e
INNER JOIN (
    SELECT id, ROW_NUMBER() OVER (PARTITION BY id ORDER BY id) AS rn FROM project_members
) p ON e.id = p.id AND e.rn = p.rn;

-- ============================================================
-- 3. 优先级规则
-- ============================================================

-- INTERSECT 的优先级高于 UNION 和 EXCEPT:
SELECT id FROM a
UNION
SELECT id FROM b
INTERSECT          -- INTERSECT 先执行（b INTERSECT c），然后 UNION a
SELECT id FROM c;

-- 使用括号控制优先级（SQL Server 2008+）:
(SELECT id FROM a UNION SELECT id FROM b)
INTERSECT
SELECT id FROM c;

-- 横向对比:
--   PostgreSQL: 同样 INTERSECT 优先级高于 UNION/EXCEPT
--   MySQL:      8.0.31+ 才支持 INTERSECT/EXCEPT
--   Oracle:     所有集合操作同优先级（从左到右执行）——这是 Oracle 独有行为

-- ============================================================
-- 4. ORDER BY 与集合操作
-- ============================================================

-- ORDER BY 只能出现在最后一个查询之后（对整个结果排序）:
SELECT name, salary FROM employees
UNION ALL
SELECT name, salary FROM contractors
ORDER BY salary DESC;

-- 限制单个分支（使用 TOP）:
SELECT TOP 5 name FROM employees ORDER BY name
UNION ALL
SELECT TOP 5 name FROM contractors ORDER BY name;

-- ============================================================
-- 5. 集合操作的类型限制
-- ============================================================

-- text/ntext/image 类型不能用于集合操作（已废弃，用 VARCHAR(MAX) 替代）
-- xml 类型不能用于 EXCEPT/INTERSECT（但可以用于 UNION）
-- 这些限制源于这些类型没有定义"相等"比较操作。
--
-- 对引擎开发者的启示:
--   集合操作的核心需求是行级相等比较（用于去重和差集计算）。
--   如果某个类型不支持相等比较（如 XML、JSON），就不能参与 INTERSECT/EXCEPT。
--   SQL Server 的 NVARCHAR(MAX) 可以存储 JSON 但支持相等比较——这是用
--   NVARCHAR(MAX) 替代专用 JSON 类型的一个优势。

-- ============================================================
-- 6. 与 CTE 结合
-- ============================================================

;WITH active_employees AS (
    SELECT id, name FROM employees WHERE active = 1
),
active_contractors AS (
    SELECT id, name FROM contractors WHERE active = 1
)
SELECT id, name FROM active_employees
UNION ALL
SELECT id, name FROM active_contractors
ORDER BY name;

-- CTE + EXCEPT 实现差集:
;WITH all_users AS (
    SELECT id FROM employees UNION SELECT id FROM contractors
)
SELECT id FROM all_users
EXCEPT
SELECT id FROM terminated_employees;

-- 版本说明:
-- SQL Server 2000+ : UNION, UNION ALL
-- SQL Server 2005+ : INTERSECT, EXCEPT
-- SQL Server 2008+ : 集合操作支持括号
-- 不支持: INTERSECT ALL, EXCEPT ALL, MINUS(Oracle 语法)
