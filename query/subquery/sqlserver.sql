-- SQL Server: 子查询
--
-- 参考资料:
--   [1] SQL Server T-SQL - Subqueries
--       https://learn.microsoft.com/en-us/sql/t-sql/queries/subqueries-transact-sql
--   [2] SQL Server T-SQL - EXISTS
--       https://learn.microsoft.com/en-us/sql/t-sql/language-elements/exists-transact-sql

-- 标量子查询
SELECT username, (SELECT COUNT(*) FROM orders WHERE user_id = users.id) AS order_count
FROM users;

-- WHERE 子查询
SELECT * FROM users WHERE id IN (SELECT user_id FROM orders WHERE amount > 100);

-- EXISTS
SELECT * FROM users u
WHERE EXISTS (SELECT 1 FROM orders o WHERE o.user_id = u.id);

-- 比较运算符 + 子查询
SELECT * FROM users WHERE age > (SELECT AVG(age) FROM users);
SELECT * FROM users WHERE age >= ALL (SELECT age FROM users WHERE city = 'Beijing');
SELECT * FROM users WHERE age > ANY (SELECT age FROM users WHERE city = 'Beijing');
-- SOME 是 ANY 的同义词
SELECT * FROM users WHERE age > SOME (SELECT age FROM users WHERE city = 'Beijing');

-- FROM 子查询（必须有别名）
SELECT t.city, t.cnt FROM (
    SELECT city, COUNT(*) AS cnt FROM users GROUP BY city
) t WHERE t.cnt > 10;

-- CROSS APPLY / OUTER APPLY（替代 LATERAL，2005+）
SELECT u.username, t.total
FROM users u
CROSS APPLY (SELECT SUM(amount) AS total FROM orders WHERE user_id = u.id) t;

SELECT u.username, t.total
FROM users u
OUTER APPLY (SELECT SUM(amount) AS total FROM orders WHERE user_id = u.id) t;

-- 注意：SQL Server 不支持行子查询 (a, b) IN (SELECT ...)
-- 需要用 EXISTS 改写:
SELECT * FROM users u
WHERE EXISTS (
    SELECT 1 FROM (SELECT city, MIN(age) AS min_age FROM users GROUP BY city) t
    WHERE t.city = u.city AND t.min_age = u.age
);
