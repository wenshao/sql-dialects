-- Spark SQL: 集合操作 (Set Operations)
--
-- 参考资料:
--   [1] Spark SQL - Set Operators
--       https://spark.apache.org/docs/latest/sql-ref-syntax-qry-select-setops.html

-- ============================================================
-- 1. UNION / UNION ALL / UNION DISTINCT
-- ============================================================

-- UNION DISTINCT（去重，默认行为）
SELECT id, name FROM employees
UNION
SELECT id, name FROM contractors;

-- UNION ALL（保留重复）
SELECT id, name FROM employees
UNION ALL
SELECT id, name FROM contractors;

-- UNION DISTINCT（显式关键字）
SELECT id, name FROM employees
UNION DISTINCT
SELECT id, name FROM contractors;

-- ============================================================
-- 2. INTERSECT / INTERSECT ALL
-- ============================================================

SELECT id FROM employees
INTERSECT
SELECT id FROM project_members;

-- INTERSECT ALL: 保留重复（Spark 3.1+）
SELECT id FROM employees
INTERSECT ALL
SELECT id FROM project_members;

-- ============================================================
-- 3. EXCEPT / EXCEPT ALL / MINUS
-- ============================================================

SELECT id FROM employees
EXCEPT
SELECT id FROM terminated_employees;

-- EXCEPT ALL（Spark 3.1+）
SELECT id FROM employees
EXCEPT ALL
SELECT id FROM terminated_employees;

-- MINUS: EXCEPT 的别名（Oracle/Hive 兼容）
SELECT id FROM employees
MINUS
SELECT id FROM terminated_employees;

-- 设计分析:
--   MINUS 是 Oracle 和 Hive 的传统语法，SQL 标准使用 EXCEPT。
--   Spark 两者都支持——这是 Hive 兼容性的体现。
--   对比: PostgreSQL 只支持 EXCEPT（SQL 标准），不支持 MINUS。

-- ============================================================
-- 4. 优先级与组合
-- ============================================================

-- INTERSECT 优先级高于 UNION/EXCEPT（SQL 标准行为）
-- A UNION B INTERSECT C = A UNION (B INTERSECT C)

-- 使用括号控制优先级
(SELECT id FROM employees
 UNION
 SELECT id FROM contractors)
INTERSECT
SELECT id FROM project_members;

-- ============================================================
-- 5. ORDER BY / LIMIT 与集合操作
-- ============================================================

-- ORDER BY 作用于整个集合操作结果
SELECT name, salary FROM employees
UNION ALL
SELECT name, salary FROM contractors
ORDER BY salary DESC
LIMIT 10;

-- ============================================================
-- 6. 类型提升规则
-- ============================================================

-- 集合操作中的列类型必须兼容:
--   INT UNION BIGINT -> BIGINT（自动提升）
--   STRING UNION INT -> STRING（ANSI=false 时，ANSI=true 可能报错）
--   列名取自第一个查询

-- 对比:
--   PostgreSQL: 类型必须严格匹配或可隐式转换
--   MySQL:      类型宽松（自动转换）
--   Spark:      取决于 ANSI 模式设置

-- ============================================================
-- 7. 版本演进
-- ============================================================
-- Spark 2.0: UNION, UNION ALL, INTERSECT, EXCEPT, MINUS
-- Spark 3.1: INTERSECT ALL, EXCEPT ALL
--
-- 限制:
--   UNION 默认是 UNION DISTINCT（与 SQL 标准一致，但用户常误解为 UNION ALL）
--   集合操作要求两侧列数相同
--   INTERSECT ALL / EXCEPT ALL 仅 Spark 3.1+
--   无 UNION BY NAME（Spark 不支持按列名匹配——DuckDB 支持）
