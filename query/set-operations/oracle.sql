-- Oracle: 集合操作 (Set Operations)
--
-- 参考资料:
--   [1] Oracle SQL Language Reference - Set Operators
--       https://docs.oracle.com/en/database/oracle/oracle-database/23/sqlrf/Set-Operators.html

-- ============================================================
-- 1. UNION / UNION ALL
-- ============================================================

SELECT id, name FROM employees
UNION
SELECT id, name FROM contractors;

SELECT id, name FROM employees
UNION ALL
SELECT id, name FROM contractors;

-- ============================================================
-- 2. INTERSECT
-- ============================================================

SELECT id FROM employees
INTERSECT
SELECT id FROM project_members;

-- INTERSECT ALL（21c+）
SELECT id FROM employees
INTERSECT ALL
SELECT id FROM project_members;

-- ============================================================
-- 3. MINUS（Oracle 独有关键字，等价于 SQL 标准的 EXCEPT）
-- ============================================================

-- Oracle 使用 MINUS 而非 EXCEPT（这是 Oracle 最显著的语法差异之一）
SELECT id FROM employees
MINUS
SELECT id FROM terminated_employees;

-- MINUS ALL（21c+）
SELECT id FROM employees
MINUS ALL
SELECT id FROM terminated_employees;

-- 21c+ 同时支持 EXCEPT（兼容 SQL 标准）
SELECT id FROM employees
EXCEPT
SELECT id FROM terminated_employees;

-- 设计分析: MINUS vs EXCEPT
--   Oracle 从最早版本就使用 MINUS，而 SQL 标准选择了 EXCEPT。
--   21c 之前: 只有 MINUS
--   21c+:    MINUS 和 EXCEPT 都支持（EXCEPT 是 MINUS 的别名）
--
-- 横向对比:
--   Oracle:     MINUS (所有版本) + EXCEPT (21c+)
--   PostgreSQL: EXCEPT (所有版本)
--   MySQL:      EXCEPT (8.0.31+)
--   SQL Server: EXCEPT (所有版本)
--   BigQuery:   EXCEPT DISTINCT / EXCEPT ALL
--
-- 对引擎开发者的启示:
--   使用 SQL 标准关键字 EXCEPT，如果需要 Oracle 兼容则同时支持 MINUS。
--   ALL 变体（UNION ALL 除外）直到 21c 才加入，说明这些操作实际需求不高。

-- ============================================================
-- 4. 21c 之前模拟 INTERSECT ALL / MINUS ALL
-- ============================================================

-- INTERSECT ALL 模拟（使用 ROW_NUMBER）
SELECT id FROM (
    SELECT id, ROW_NUMBER() OVER (PARTITION BY id ORDER BY id) AS rn
    FROM employees
) e
JOIN (
    SELECT id, ROW_NUMBER() OVER (PARTITION BY id ORDER BY id) AS rn
    FROM project_members
) p ON e.id = p.id AND e.rn = p.rn;

-- ============================================================
-- 5. '' = NULL 对集合操作的影响
-- ============================================================

-- UNION/INTERSECT/MINUS 中 NULL 的比较规则:
-- 集合操作使用"两个 NULL 相等"的语义（与 WHERE 中 NULL != NULL 不同）
-- 这意味着:
--   SELECT '' FROM DUAL UNION SELECT NULL FROM DUAL;
-- 只返回一行（因为 '' = NULL，集合操作认为它们相同）

-- 对比 WHERE 中的行为:
--   WHERE '' = NULL  → UNKNOWN (false)
--   集合操作中 '' 和 NULL → 被视为相同值（去重合并）

-- ============================================================
-- 6. ORDER BY 与集合操作
-- ============================================================

-- ORDER BY 只能出现在最后
SELECT name, salary FROM employees
UNION ALL
SELECT name, salary FROM contractors
ORDER BY salary DESC;

-- 可使用列号
SELECT name, salary FROM employees
UNION ALL
SELECT name, salary FROM contractors
ORDER BY 2 DESC;

-- 集合操作 + 分页（12c+）
SELECT name FROM employees
UNION ALL
SELECT name FROM contractors
ORDER BY name
FETCH FIRST 10 ROWS ONLY;

-- ============================================================
-- 7. 嵌套集合操作与优先级
-- ============================================================

-- Oracle 集合操作没有隐式优先级，按从上到下顺序执行。
-- 使用子查询控制优先级:
SELECT id FROM (
    SELECT id FROM employees
    UNION
    SELECT id FROM contractors
)
INTERSECT
SELECT id FROM project_members;

-- ============================================================
-- 8. 限制与注意事项
-- ============================================================

-- LONG / LONG RAW 列不能用于集合操作
-- BLOB / CLOB 列不能直接用于 UNION（需先转换为 VARCHAR2）
-- Oracle UNION 中不允许使用 FOR UPDATE
-- 列的类型需要兼容（Oracle 会尝试隐式转换）

-- ============================================================
-- 9. 对引擎开发者的总结
-- ============================================================
-- 1. MINUS 是 Oracle 独有关键字，标准是 EXCEPT，新引擎应两者都支持。
-- 2. 集合操作中的 NULL 比较语义与 WHERE 不同（NULL = NULL 为 true），
--    这是 SQL 标准的一个不一致之处，实现时需要特别注意。
-- 3. ALL 变体（INTERSECT ALL、EXCEPT ALL）实际需求不高，可以延迟实现。
-- 4. '' = NULL 影响去重行为: Oracle 中空字符串和 NULL 被视为同一值。
