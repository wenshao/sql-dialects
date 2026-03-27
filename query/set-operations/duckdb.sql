-- DuckDB: 集合操作
--
-- 参考资料:
--   [1] DuckDB Documentation - Set Operations
--       https://duckdb.org/docs/sql/query_syntax/setops
--   [2] DuckDB Documentation - SELECT
--       https://duckdb.org/docs/sql/query_syntax/select

-- ============================================================
-- UNION / UNION ALL
-- ============================================================
SELECT id, name FROM employees
UNION
SELECT id, name FROM contractors;

SELECT id, name FROM employees
UNION ALL
SELECT id, name FROM contractors;

-- UNION BY NAME（DuckDB 独有）: 按列名而非位置匹配
SELECT id, name, salary FROM employees
UNION ALL BY NAME
SELECT name, department, id FROM contractors;

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

-- LIMIT + OFFSET
SELECT name FROM employees
UNION ALL
SELECT name FROM contractors
ORDER BY name
LIMIT 10 OFFSET 20;

-- ============================================================
-- 从文件直接做集合操作
-- ============================================================
SELECT * FROM read_csv('employees.csv')
UNION ALL
SELECT * FROM read_csv('contractors.csv');

SELECT * FROM read_parquet('data_2023.parquet')
UNION ALL
SELECT * FROM read_parquet('data_2024.parquet');

-- ============================================================
-- 注意事项
-- ============================================================
-- DuckDB 完整支持所有 SQL 标准集合操作（含 ALL 变体）
-- UNION BY NAME 是 DuckDB 独有特性，按列名匹配而非位置
-- 支持直接对文件执行集合操作
-- 类型系统严格但会做安全的隐式转换
