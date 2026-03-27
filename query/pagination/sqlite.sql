-- SQLite: 分页
--
-- 参考资料:
--   [1] SQLite Documentation - SELECT (LIMIT/OFFSET)
--       https://www.sqlite.org/lang_select.html

-- LIMIT / OFFSET（所有版本）
SELECT * FROM users ORDER BY id LIMIT 10 OFFSET 20;

-- 简写形式
SELECT * FROM users ORDER BY id LIMIT 20, 10;

-- 3.25.0+: 窗口函数
SELECT * FROM (
    SELECT *, ROW_NUMBER() OVER (ORDER BY id) AS rn
    FROM users
) t
WHERE rn BETWEEN 21 AND 30;

-- 游标分页
SELECT * FROM users WHERE id > 100 ORDER BY id LIMIT 10;
