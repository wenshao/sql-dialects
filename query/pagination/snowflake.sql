-- Snowflake: 分页
--
-- 参考资料:
--   [1] Snowflake SQL Reference - SELECT (LIMIT/OFFSET)
--       https://docs.snowflake.com/en/sql-reference/sql/select
--   [2] Snowflake SQL Reference
--       https://docs.snowflake.com/en/sql-reference/

-- LIMIT / OFFSET
SELECT * FROM users ORDER BY id LIMIT 10 OFFSET 20;

-- SQL 标准语法（FETCH FIRST）
SELECT * FROM users ORDER BY id OFFSET 20 ROWS FETCH FIRST 10 ROWS ONLY;

-- FETCH NEXT（等价于 FETCH FIRST）
SELECT * FROM users ORDER BY id OFFSET 20 ROWS FETCH NEXT 10 ROWS ONLY;

-- 取前 N 行
SELECT * FROM users ORDER BY id FETCH FIRST 10 ROWS ONLY;

-- 窗口函数分页
SELECT * FROM (
    SELECT *, ROW_NUMBER() OVER (ORDER BY id) AS rn
    FROM users
) t
WHERE rn BETWEEN 21 AND 30;

-- QUALIFY + ROW_NUMBER 分页（Snowflake 特有，更简洁）
SELECT * FROM users
QUALIFY ROW_NUMBER() OVER (ORDER BY id) BETWEEN 21 AND 30;

-- 游标分页
SELECT * FROM users WHERE id > 100 ORDER BY id LIMIT 10;

-- TOP N（等价于 LIMIT）
SELECT TOP 10 * FROM users ORDER BY id;

-- TABLESAMPLE
SELECT * FROM users TABLESAMPLE (10);

-- 注意：Snowflake 同时支持 LIMIT 和 FETCH FIRST 两种语法
-- 注意：大 OFFSET 性能较差，建议使用游标分页或 QUALIFY
