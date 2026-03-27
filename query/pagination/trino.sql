-- Trino: 分页
--
-- 参考资料:
--   [1] Trino - SELECT (LIMIT/OFFSET)
--       https://trino.io/docs/current/sql/select.html
--   [2] Trino - SQL Statement List
--       https://trino.io/docs/current/sql.html

-- LIMIT（取前 N 行）
SELECT * FROM users ORDER BY id LIMIT 10;

-- LIMIT / OFFSET
SELECT * FROM users ORDER BY id LIMIT 10 OFFSET 20;

-- SQL 标准语法（FETCH FIRST）
SELECT * FROM users ORDER BY id OFFSET 20 ROWS FETCH FIRST 10 ROWS ONLY;

-- FETCH NEXT（等价于 FETCH FIRST）
SELECT * FROM users ORDER BY id OFFSET 20 ROWS FETCH NEXT 10 ROWS ONLY;

-- 取前 N 行（标准语法）
SELECT * FROM users ORDER BY id FETCH FIRST 10 ROWS ONLY;

-- 窗口函数分页
SELECT * FROM (
    SELECT *, ROW_NUMBER() OVER (ORDER BY id) AS rn
    FROM users
) t
WHERE rn BETWEEN 21 AND 30;

-- 游标分页
SELECT * FROM users WHERE id > 100 ORDER BY id LIMIT 10;

-- TABLESAMPLE（取决于连接器支持）
SELECT * FROM users TABLESAMPLE SYSTEM (10);

-- 注意：Trino 同时支持 LIMIT 和 FETCH FIRST 两种语法
-- 注意：Trino 语法高度符合 SQL 标准
-- 注意：分页性能取决于底层连接器（Hive、MySQL 等）
-- 注意：大 OFFSET 性能较差，建议使用游标分页
