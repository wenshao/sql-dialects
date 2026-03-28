-- Apache Doris: 集合操作
--
-- 参考资料:
--   [1] Doris Documentation - Set Operations
--       https://doris.apache.org/docs/sql-manual/sql-statements/

SELECT id, name FROM employees UNION SELECT id, name FROM contractors;
SELECT id, name FROM employees UNION ALL SELECT id, name FROM contractors;
SELECT id, name FROM employees UNION DISTINCT SELECT id, name FROM contractors;

-- INTERSECT (1.2+)
SELECT id FROM employees INTERSECT SELECT id FROM project_members;

-- EXCEPT / MINUS (1.2+)
SELECT id FROM employees EXCEPT SELECT id FROM terminated;
SELECT id FROM employees MINUS SELECT id FROM terminated;

-- 嵌套
(SELECT id FROM employees UNION SELECT id FROM contractors)
INTERSECT SELECT id FROM project_members;

-- ORDER BY / LIMIT
SELECT name FROM employees UNION ALL SELECT name FROM contractors
ORDER BY name LIMIT 10;

-- 限制: 不支持 INTERSECT ALL / EXCEPT ALL。
-- 对比: PostgreSQL 支持 ALL 变体。ClickHouse 不支持 INTERSECT/EXCEPT。
