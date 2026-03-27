-- CockroachDB: Subqueries (v23.1+)
--
-- 参考资料:
--   [1] CockroachDB - SQL Statements
--       https://www.cockroachlabs.com/docs/stable/sql-statements
--   [2] CockroachDB - Functions and Operators
--       https://www.cockroachlabs.com/docs/stable/functions-and-operators
--   [3] CockroachDB - Data Types
--       https://www.cockroachlabs.com/docs/stable/data-types

-- CockroachDB supports all PostgreSQL subquery types

-- Scalar subquery
SELECT username, (SELECT COUNT(*) FROM orders WHERE user_id = users.id) AS order_count
FROM users;

-- WHERE subquery
SELECT * FROM users WHERE id IN (SELECT user_id FROM orders WHERE amount > 100);
SELECT * FROM users WHERE id NOT IN (SELECT user_id FROM blacklist);

-- EXISTS
SELECT * FROM users u
WHERE EXISTS (SELECT 1 FROM orders o WHERE o.user_id = u.id);
SELECT * FROM users u
WHERE NOT EXISTS (SELECT 1 FROM orders o WHERE o.user_id = u.id);

-- Comparison operators + subquery
SELECT * FROM users WHERE age > (SELECT AVG(age) FROM users);

-- ANY / ALL / SOME
SELECT * FROM users WHERE age > ANY (SELECT age FROM users WHERE city = 'NYC');
SELECT * FROM users WHERE age > ALL (SELECT age FROM users WHERE city = 'NYC');

-- FROM subquery (derived table)
SELECT t.city, t.cnt FROM (
    SELECT city, COUNT(*) AS cnt FROM users GROUP BY city
) t WHERE t.cnt > 10;

-- Correlated subquery
SELECT u.username,
    (SELECT MAX(amount) FROM orders o WHERE o.user_id = u.id) AS max_order
FROM users u;

-- Lateral subquery (same as PostgreSQL)
SELECT u.username, latest.amount, latest.order_date
FROM users u
LEFT JOIN LATERAL (
    SELECT amount, order_date FROM orders WHERE user_id = u.id
    ORDER BY order_date DESC LIMIT 3
) latest ON true;

-- Subquery with array
SELECT * FROM users WHERE 'admin' = ANY(tags);

-- CTE (preferred over deeply nested subqueries)
WITH high_value_orders AS (
    SELECT user_id, SUM(amount) AS total
    FROM orders GROUP BY user_id HAVING SUM(amount) > 1000
)
SELECT u.username, h.total
FROM users u JOIN high_value_orders h ON u.id = h.user_id;

-- Subquery in SELECT with ARRAY constructor
SELECT username,
    ARRAY(SELECT amount FROM orders WHERE user_id = users.id ORDER BY amount DESC) AS order_amounts
FROM users;

-- Subquery in UPDATE
UPDATE users SET status = 2
WHERE id IN (SELECT user_id FROM orders GROUP BY user_id HAVING SUM(amount) > 10000);

-- Subquery in DELETE
DELETE FROM users
WHERE id NOT IN (SELECT DISTINCT user_id FROM orders);

-- Note: All PostgreSQL subquery types supported
-- Note: ANY, ALL, SOME operators supported (unlike BigQuery)
-- Note: LATERAL subqueries supported
-- Note: Correlated subqueries may be decorrelated by the optimizer
-- Note: CTEs are recommended over deeply nested subqueries
