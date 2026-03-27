-- H2: DELETE
--
-- 参考资料:
--   [1] H2 SQL Reference - Commands
--       https://h2database.com/html/commands.html
--   [2] H2 - Data Types
--       https://h2database.com/html/datatypes.html
--   [3] H2 - Functions
--       https://h2database.com/html/functions.html

-- 基本删除
DELETE FROM users WHERE username = 'alice';

-- 删除所有行
DELETE FROM users;

-- 子查询删除
DELETE FROM users WHERE id IN (SELECT user_id FROM blacklist);

-- EXISTS 子查询
DELETE FROM users
WHERE EXISTS (SELECT 1 FROM blacklist b WHERE b.email = users.email);

-- 关联子查询
DELETE FROM users WHERE id NOT IN (
    SELECT DISTINCT user_id FROM orders
);

-- LIMIT（限制删除行数）
DELETE FROM users WHERE status = 0 LIMIT 100;

-- CTE + DELETE
WITH inactive AS (
    SELECT id FROM users WHERE last_login < '2023-01-01'
)
DELETE FROM users WHERE id IN (SELECT id FROM inactive);

-- TRUNCATE（清空表，更快）
TRUNCATE TABLE users;

-- TRUNCATE 重置 IDENTITY
TRUNCATE TABLE users RESTART IDENTITY;

-- 删除表
DROP TABLE users;
DROP TABLE IF EXISTS users;

-- 多个表
DROP TABLE IF EXISTS users, orders, products;

-- 注意：DELETE 支持 LIMIT 子句
-- 注意：TRUNCATE 比 DELETE 更快（不记录行级日志）
-- 注意：TRUNCATE RESTART IDENTITY 重置自增列
-- 注意：不支持多表 JOIN 删除
-- 注意：不支持 RETURNING 子句
