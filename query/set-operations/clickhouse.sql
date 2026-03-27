-- ClickHouse: 集合操作
--
-- 参考资料:
--   [1] ClickHouse Documentation - UNION
--       https://clickhouse.com/docs/en/sql-reference/statements/select/union
--   [2] ClickHouse Documentation - INTERSECT
--       https://clickhouse.com/docs/en/sql-reference/statements/select/intersect
--   [3] ClickHouse Documentation - EXCEPT
--       https://clickhouse.com/docs/en/sql-reference/statements/select/except

-- ============================================================
-- UNION ALL（默认行为）
-- ============================================================
-- ClickHouse 中 UNION 默认是 UNION ALL
SELECT id, name FROM employees
UNION ALL
SELECT id, name FROM contractors;

-- ============================================================
-- UNION DISTINCT（21.5+）
-- ============================================================
SELECT id, name FROM employees
UNION DISTINCT
SELECT id, name FROM contractors;

-- 设置默认行为
-- SET union_default_mode = 'DISTINCT';  -- 改变 UNION 默认行为

-- ============================================================
-- INTERSECT（21.12+）
-- ============================================================
SELECT id FROM employees
INTERSECT
SELECT id FROM project_members;

-- INTERSECT DISTINCT
SELECT id FROM employees
INTERSECT DISTINCT
SELECT id FROM project_members;

-- ============================================================
-- EXCEPT（21.12+）
-- ============================================================
SELECT id FROM employees
EXCEPT
SELECT id FROM terminated_employees;

-- EXCEPT DISTINCT
SELECT id FROM employees
EXCEPT DISTINCT
SELECT id FROM terminated_employees;

-- ============================================================
-- 嵌套与组合集合操作
-- ============================================================
(SELECT id FROM employees
 UNION ALL
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
-- 多表 UNION
-- ============================================================
-- ClickHouse 常用于合并多个分片表
SELECT * FROM events_2023
UNION ALL
SELECT * FROM events_2024
UNION ALL
SELECT * FROM events_2025;

-- ============================================================
-- 注意事项
-- ============================================================
-- ClickHouse UNION 默认行为是 UNION ALL（与 SQL 标准不同）
-- 可通过 union_default_mode 设置更改默认行为
-- INTERSECT 和 EXCEPT 从 21.12 版本开始支持
-- Nullable 列与非 Nullable 列在 UNION 中会自动转换为 Nullable
