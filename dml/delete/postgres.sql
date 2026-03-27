-- PostgreSQL: DELETE
--
-- 参考资料:
--   [1] PostgreSQL Documentation - DELETE
--       https://www.postgresql.org/docs/current/sql-delete.html
--   [2] PostgreSQL Documentation - TRUNCATE
--       https://www.postgresql.org/docs/current/sql-truncate.html

-- 基本删除
DELETE FROM users WHERE username = 'alice';

-- USING 子句（多表关联删除）
DELETE FROM users
USING blacklist
WHERE users.email = blacklist.email;

-- 子查询删除
DELETE FROM users WHERE id IN (SELECT user_id FROM blacklist);

-- RETURNING（返回被删除的行）
DELETE FROM users WHERE status = 0 RETURNING id, username;

-- CTE + DELETE
WITH inactive AS (
    SELECT id FROM users WHERE last_login < '2023-01-01'
)
DELETE FROM users WHERE id IN (SELECT id FROM inactive);

-- CTE + DELETE + RETURNING（归档后删除）
WITH deleted AS (
    DELETE FROM users WHERE status = 0 RETURNING *
)
INSERT INTO users_archive SELECT * FROM deleted;

-- 删除所有行
DELETE FROM users;
TRUNCATE TABLE users;                  -- 更快，不触发行级触发器
TRUNCATE TABLE users RESTART IDENTITY; -- 重置序列
TRUNCATE TABLE users CASCADE;          -- 级联截断引用表
