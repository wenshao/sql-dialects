-- Oracle: 集合操作（全版本支持）
--
-- 参考资料:
--   [1] Oracle SQL Language Reference - Set Operators
--       https://docs.oracle.com/en/database/oracle/oracle-database/23/sqlrf/Set-Operators.html
--   [2] Oracle SQL Language Reference - SELECT
--       https://docs.oracle.com/en/database/oracle/oracle-database/23/sqlrf/SELECT.html
--   [3] Oracle Database SQL Tuning Guide
--       https://docs.oracle.com/en/database/oracle/oracle-database/23/tgsql/

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
-- INTERSECT（全版本支持）
-- ============================================================
SELECT id FROM employees
INTERSECT
SELECT id FROM project_members;

-- INTERSECT ALL（21c+）
SELECT id FROM employees
INTERSECT ALL
SELECT id FROM project_members;

-- 21c 之前模拟 INTERSECT ALL
SELECT id FROM (
    SELECT id, ROW_NUMBER() OVER (PARTITION BY id ORDER BY id) AS rn FROM employees
) e
INNER JOIN (
    SELECT id, ROW_NUMBER() OVER (PARTITION BY id ORDER BY id) AS rn FROM project_members
) p ON e.id = p.id AND e.rn = p.rn;

-- ============================================================
-- MINUS（Oracle 专有，等价于 EXCEPT）
-- ============================================================
-- Oracle 使用 MINUS 而非 SQL 标准的 EXCEPT
SELECT id FROM employees
MINUS
SELECT id FROM terminated_employees;

-- MINUS ALL（21c+）
SELECT id FROM employees
MINUS ALL
SELECT id FROM terminated_employees;

-- EXCEPT（21c+ 同时支持 EXCEPT 作为 MINUS 的别名）
SELECT id FROM employees
EXCEPT
SELECT id FROM terminated_employees;

-- ============================================================
-- 嵌套与组合集合操作
-- ============================================================
-- Oracle 没有隐式优先级，按从上到下顺序执行
-- 使用子查询或括号控制优先级
SELECT id FROM (
    SELECT id FROM employees
    UNION
    SELECT id FROM contractors
)
INTERSECT
SELECT id FROM project_members;

-- 多重组合
SELECT id FROM table_a
UNION ALL
SELECT id FROM table_b
MINUS
SELECT id FROM table_c;

-- ============================================================
-- ORDER BY 与集合操作
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

-- ============================================================
-- 分页与集合操作
-- ============================================================
-- ROWNUM 方式（传统）
SELECT * FROM (
    SELECT name FROM employees
    UNION ALL
    SELECT name FROM contractors
    ORDER BY name
)
WHERE ROWNUM <= 10;

-- FETCH FIRST 方式（12c+）
SELECT name FROM employees
UNION ALL
SELECT name FROM contractors
ORDER BY name
FETCH FIRST 10 ROWS ONLY;

-- OFFSET + FETCH（12c+）
SELECT name FROM employees
UNION ALL
SELECT name FROM contractors
ORDER BY name
OFFSET 20 ROWS FETCH NEXT 10 ROWS ONLY;

-- ============================================================
-- 注意事项
-- ============================================================
-- Oracle UNION 中不允许使用 FOR UPDATE
-- LONG / LONG RAW 列不能用于集合操作
-- BLOB / CLOB 列不能直接用于 UNION（需先转换）
-- 从 21c 开始同时支持 MINUS 和 EXCEPT
