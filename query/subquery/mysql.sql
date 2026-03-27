-- MySQL: 子查询
--
-- 参考资料:
--   [1] MySQL 8.0 Reference Manual - Subqueries
--       https://dev.mysql.com/doc/refman/8.0/en/subqueries.html
--   [2] MySQL 8.0 Reference Manual - Derived Tables
--       https://dev.mysql.com/doc/refman/8.0/en/derived-tables.html
--   [3] MySQL 8.0 Reference Manual - Subquery Optimization
--       https://dev.mysql.com/doc/refman/8.0/en/subquery-optimization.html

-- 标量子查询（返回单个值）
SELECT username, (SELECT COUNT(*) FROM orders WHERE user_id = users.id) AS order_count
FROM users;

-- WHERE 子查询
SELECT * FROM users WHERE id IN (SELECT user_id FROM orders WHERE amount > 100);
SELECT * FROM users WHERE id NOT IN (SELECT user_id FROM blacklist);

-- EXISTS
SELECT * FROM users u
WHERE EXISTS (SELECT 1 FROM orders o WHERE o.user_id = u.id);
SELECT * FROM users u
WHERE NOT EXISTS (SELECT 1 FROM orders o WHERE o.user_id = u.id);

-- 比较运算符 + 子查询
SELECT * FROM users WHERE age > (SELECT AVG(age) FROM users);
SELECT * FROM users WHERE age >= ALL (SELECT age FROM users WHERE city = 'Beijing');
SELECT * FROM users WHERE age > ANY (SELECT age FROM users WHERE city = 'Beijing');

-- FROM 子查询（派生表，必须有别名）
SELECT t.city, t.cnt FROM (
    SELECT city, COUNT(*) AS cnt FROM users GROUP BY city
) t WHERE t.cnt > 10;

-- 8.0.14+: 派生表可以引用外部列（LATERAL 派生表）
SELECT u.username, t.total
FROM users u,
LATERAL (SELECT SUM(amount) AS total FROM orders WHERE user_id = u.id) t;

-- 注意：5.5 及之前版本子查询性能较差，优化器可能不会将 IN 子查询转为 JOIN
-- 5.6+: semijoin 优化引入，子查询性能大幅改进
-- 8.0+: 进一步改进（支持 anti-join、子查询物化等）
