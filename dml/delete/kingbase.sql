-- KingbaseES (人大金仓): DELETE
-- PostgreSQL compatible syntax.
--
-- 参考资料:
--   [1] KingbaseES SQL Reference
--       https://help.kingbase.com.cn/v8/index.html
--   [2] KingbaseES Documentation
--       https://help.kingbase.com.cn/v8/index.html

-- 基本删除
DELETE FROM users WHERE username = 'alice';

-- USING 子句（PostgreSQL 风格的多表删除）
DELETE FROM users
USING blacklist
WHERE users.email = blacklist.email;

-- 子查询删除
DELETE FROM users WHERE id IN (SELECT user_id FROM blacklist);

-- EXISTS 删除
DELETE FROM users u
WHERE EXISTS (SELECT 1 FROM blacklist b WHERE b.email = u.email);

-- 删除所有行
DELETE FROM users;
TRUNCATE TABLE users;
TRUNCATE TABLE users RESTART IDENTITY;
TRUNCATE TABLE users CASCADE;

-- RETURNING
DELETE FROM users WHERE status = 0 RETURNING id, username;

-- WITH CTE
WITH inactive AS (
    SELECT id FROM users WHERE last_login < '2023-01-01'
)
DELETE FROM users WHERE id IN (SELECT id FROM inactive);

-- 注意事项：
-- 语法与 PostgreSQL 完全兼容
-- 使用 USING 子句进行多表删除
-- 支持 RETURNING 子句
-- TRUNCATE 是事务性的
