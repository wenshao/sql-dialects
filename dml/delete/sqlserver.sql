-- SQL Server: DELETE
--
-- 参考资料:
--   [1] SQL Server T-SQL - DELETE
--       https://learn.microsoft.com/en-us/sql/t-sql/statements/delete-transact-sql
--   [2] SQL Server T-SQL - TRUNCATE TABLE
--       https://learn.microsoft.com/en-us/sql/t-sql/statements/truncate-table-transact-sql

-- 基本删除
DELETE FROM users WHERE username = 'alice';

-- TOP 限制
DELETE TOP (100) FROM users WHERE status = 0;

-- JOIN 删除（FROM 子句）
DELETE u FROM users u
JOIN blacklist b ON u.email = b.email;

-- 子查询删除
DELETE FROM users WHERE id IN (SELECT user_id FROM blacklist);

-- OUTPUT（返回被删除的行）
DELETE FROM users
OUTPUT deleted.id, deleted.username
WHERE status = 0;

-- OUTPUT INTO（被删除行插入到另一个表）
DELETE FROM users
OUTPUT deleted.* INTO users_archive
WHERE status = 0;

-- CTE + DELETE
WITH inactive AS (
    SELECT id FROM users WHERE last_login < '2023-01-01'
)
DELETE FROM users WHERE id IN (SELECT id FROM inactive);

-- 删除所有行
DELETE FROM users;
TRUNCATE TABLE users;   -- 更快，重置 IDENTITY，可在事务中回滚，不触发触发器
