-- openGauss/GaussDB: DELETE
-- PostgreSQL compatible syntax.
--
-- 参考资料:
--   [1] openGauss SQL Reference
--       https://docs.opengauss.org/zh/docs/latest/docs/SQLReference/SQL-reference.html
--   [2] GaussDB Documentation
--       https://support.huaweicloud.com/gaussdb/index.html

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
TRUNCATE TABLE users RESTART IDENTITY;    -- 重置序列
TRUNCATE TABLE users CASCADE;             -- 级联截断

-- RETURNING
DELETE FROM users WHERE status = 0 RETURNING id, username;

-- WITH CTE
WITH inactive AS (
    SELECT id FROM users WHERE last_login < '2023-01-01'
)
DELETE FROM users WHERE id IN (SELECT id FROM inactive);

-- 注意事项：
-- 使用 USING 子句替代 JOIN 进行多表删除
-- 支持 RETURNING 子句返回删除的行
-- TRUNCATE 是事务性的（可以回滚）
-- GaussDB 分布式版本中 DELETE 按分布键路由
-- 列存储表的 DELETE 是标记删除
