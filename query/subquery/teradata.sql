-- Teradata: Subqueries
--
-- 参考资料:
--   [1] Teradata SQL Reference
--       https://docs.teradata.com/r/Teradata-VantageTM-SQL-Functions-Expressions-and-Predicates
--   [2] Teradata Database Documentation
--       https://docs.teradata.com/

-- Scalar subquery
SELECT username, (SELECT COUNT(*) FROM orders WHERE user_id = users.id) AS order_count
FROM users;

-- WHERE subquery
SELECT * FROM users WHERE id IN (SELECT user_id FROM orders WHERE amount > 100);
SELECT * FROM users WHERE id NOT IN (SELECT user_id FROM blacklist);

-- EXISTS
SELECT * FROM users u
WHERE EXISTS (SELECT 1 FROM orders o WHERE o.user_id = u.id);

-- Comparison operators + subquery
SELECT * FROM users WHERE age > (SELECT AVG(age) FROM users);
SELECT * FROM users WHERE age >= ALL (SELECT age FROM users WHERE city = 'Beijing');
SELECT * FROM users WHERE age > ANY (SELECT age FROM users WHERE city = 'Beijing');

-- FROM subquery (derived table)
SELECT t.city, t.cnt FROM (
    SELECT city, COUNT(*) AS cnt FROM users GROUP BY city
) t WHERE t.cnt > 10;

-- Correlated subquery
SELECT u.username, u.age,
    (SELECT MAX(o.amount) FROM orders o WHERE o.user_id = u.id) AS max_order
FROM users u;

-- Row subquery comparison
SELECT * FROM users WHERE (city, age) IN (SELECT city, MIN(age) FROM users GROUP BY city);

-- Subquery with SAMPLE (Teradata-specific)
SELECT * FROM users WHERE id IN (
    SELECT id FROM users SAMPLE 100
);

-- QUALIFY with subquery (Teradata-specific: filter on window functions)
SELECT username, age,
    RANK() OVER (PARTITION BY city ORDER BY age DESC) AS rnk
FROM users
QUALIFY rnk = 1;

-- Subquery in HAVING
SELECT city, COUNT(*) AS cnt
FROM users
GROUP BY city
HAVING COUNT(*) > (SELECT AVG(city_count) FROM (SELECT COUNT(*) AS city_count FROM users GROUP BY city) t);

-- Nested subqueries
SELECT * FROM users
WHERE city IN (
    SELECT city FROM users
    GROUP BY city
    HAVING AVG(age) > (SELECT AVG(age) FROM users)
);

-- Note: subqueries can be expensive on Teradata if they cause redistribution
-- Note: correlated subqueries may execute once per AMP
-- Note: consider rewriting as JOINs for better parallel performance
