-- PostgreSQL: 分页
--
-- 参考资料:
--   [1] PostgreSQL Documentation - LIMIT and OFFSET
--       https://www.postgresql.org/docs/current/queries-limit.html
--   [2] PostgreSQL Documentation - SELECT
--       https://www.postgresql.org/docs/current/sql-select.html

-- LIMIT / OFFSET（所有版本）
SELECT * FROM users ORDER BY id LIMIT 10 OFFSET 20;

-- SQL 标准语法（8.4+）
SELECT * FROM users ORDER BY id OFFSET 20 ROWS FETCH FIRST 10 ROWS ONLY;

-- 窗口函数
SELECT * FROM (
    SELECT *, ROW_NUMBER() OVER (ORDER BY id) AS rn
    FROM users
) t
WHERE rn BETWEEN 21 AND 30;

-- 键集分页（Keyset Pagination，性能优于 OFFSET）
SELECT * FROM users WHERE id > 100 ORDER BY id LIMIT 10;
