-- PostgreSQL: 子查询
--
-- 参考资料:
--   [1] PostgreSQL Documentation - Subqueries
--       https://www.postgresql.org/docs/current/functions-subquery.html
--   [2] PostgreSQL Documentation - SELECT
--       https://www.postgresql.org/docs/current/sql-select.html

-- 标量子查询
SELECT username, (SELECT COUNT(*) FROM orders WHERE user_id = users.id) AS order_count
FROM users;

-- WHERE 子查询
SELECT * FROM users WHERE id IN (SELECT user_id FROM orders WHERE amount > 100);
SELECT * FROM users WHERE id NOT IN (SELECT user_id FROM blacklist);

-- EXISTS
SELECT * FROM users u
WHERE EXISTS (SELECT 1 FROM orders o WHERE o.user_id = u.id);

-- 比较运算符 + 子查询
SELECT * FROM users WHERE age > (SELECT AVG(age) FROM users);
SELECT * FROM users WHERE age >= ALL (SELECT age FROM users WHERE city = 'Beijing');
SELECT * FROM users WHERE age > ANY (SELECT age FROM users WHERE city = 'Beijing');

-- FROM 子查询
SELECT t.city, t.cnt FROM (
    SELECT city, COUNT(*) AS cnt FROM users GROUP BY city
) t WHERE t.cnt > 10;

-- LATERAL 子查询（9.3+）
SELECT u.username, t.total
FROM users u,
LATERAL (SELECT SUM(amount) AS total FROM orders WHERE user_id = u.id) t;

-- 行子查询比较
SELECT * FROM users WHERE (city, age) IN (SELECT city, MIN(age) FROM users GROUP BY city);

-- 数组子查询
SELECT * FROM users WHERE id = ANY(ARRAY(SELECT user_id FROM orders WHERE amount > 100));

-- 子查询用在 SELECT 列表中的数组构造
SELECT username,
    ARRAY(SELECT amount FROM orders WHERE user_id = users.id) AS order_amounts
FROM users;
