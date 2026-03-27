-- SQL Server: UPDATE
--
-- 参考资料:
--   [1] SQL Server T-SQL - UPDATE
--       https://learn.microsoft.com/en-us/sql/t-sql/queries/update-transact-sql
--   [2] SQL Server T-SQL - FROM Clause
--       https://learn.microsoft.com/en-us/sql/t-sql/queries/from-transact-sql

-- 基本更新
UPDATE users SET age = 26 WHERE username = 'alice';

-- 多列更新
UPDATE users SET email = 'new@example.com', age = 26 WHERE username = 'alice';

-- TOP 限制更新行数
UPDATE TOP (100) users SET status = 0 WHERE status = 1;

-- JOIN 更新（FROM 子句）
UPDATE u SET u.status = 1
FROM users u
JOIN orders o ON u.id = o.user_id
WHERE o.amount > 1000;

-- 子查询更新
UPDATE users SET age = (SELECT AVG(age) FROM users) WHERE age IS NULL;

-- OUTPUT（返回更新前后的值）
UPDATE users SET age = 26
OUTPUT deleted.age AS old_age, inserted.age AS new_age
WHERE username = 'alice';

-- CTE + UPDATE
WITH vip AS (
    SELECT user_id FROM orders GROUP BY user_id HAVING SUM(amount) > 10000
)
UPDATE u SET status = 2
FROM users u JOIN vip v ON u.id = v.user_id;

-- CASE 表达式
UPDATE users SET status = CASE
    WHEN age < 18 THEN 0
    WHEN age >= 65 THEN 2
    ELSE 1
END;

-- 变量赋值 + 更新（同时更新并获取值）
DECLARE @old_age INT;
UPDATE users SET @old_age = age, age = 26 WHERE username = 'alice';
