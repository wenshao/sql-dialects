-- MySQL: DELETE
--
-- 参考资料:
--   [1] MySQL 8.0 Reference Manual - DELETE
--       https://dev.mysql.com/doc/refman/8.0/en/delete.html
--   [2] MySQL 8.0 Reference Manual - TRUNCATE TABLE
--       https://dev.mysql.com/doc/refman/8.0/en/truncate-table.html

-- 基本删除
DELETE FROM users WHERE username = 'alice';

-- 带 LIMIT / ORDER BY（MySQL 特有）
DELETE FROM users WHERE status = 0 ORDER BY created_at LIMIT 100;

-- 多表删除（JOIN）
DELETE u FROM users u
JOIN blacklist b ON u.email = b.email;

-- 同时从多个表删除
DELETE u, o FROM users u
JOIN orders o ON u.id = o.user_id
WHERE u.status = 0;

-- 子查询删除
DELETE FROM users WHERE id IN (SELECT user_id FROM blacklist);

-- 删除所有行
DELETE FROM users;
-- 更快的方式：TRUNCATE（重置自增，不触发触发器，不可回滚）
TRUNCATE TABLE users;

-- IGNORE（忽略外键约束错误）
DELETE IGNORE FROM users WHERE id = 1;

-- 8.0+: WITH CTE
WITH inactive AS (
    SELECT id FROM users WHERE last_login < '2023-01-01'
)
DELETE u FROM users u JOIN inactive i ON u.id = i.id;
