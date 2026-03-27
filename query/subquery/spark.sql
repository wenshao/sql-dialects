-- Spark SQL: Subqueries (Spark 2.0+)
--
-- 参考资料:
--   [1] Spark SQL Reference
--       https://spark.apache.org/docs/latest/sql-ref.html
--   [2] Spark SQL - Built-in Functions
--       https://spark.apache.org/docs/latest/sql-ref-functions.html
--   [3] Spark SQL - Data Types
--       https://spark.apache.org/docs/latest/sql-ref-datatypes.html

-- Scalar subquery
SELECT username, (SELECT COUNT(*) FROM orders WHERE user_id = users.id) AS order_count
FROM users;

-- WHERE subquery
SELECT * FROM users WHERE id IN (SELECT user_id FROM orders WHERE amount > 100);
SELECT * FROM users WHERE id NOT IN (SELECT user_id FROM blacklist);

-- EXISTS (Spark 2.1+)
SELECT * FROM users u
WHERE EXISTS (SELECT 1 FROM orders o WHERE o.user_id = u.id);

-- NOT EXISTS
SELECT * FROM users u
WHERE NOT EXISTS (SELECT 1 FROM orders o WHERE o.user_id = u.id);

-- Comparison operators with subquery
SELECT * FROM users WHERE age > (SELECT AVG(age) FROM users);

-- FROM subquery (derived table)
SELECT t.city, t.cnt FROM (
    SELECT city, COUNT(*) AS cnt FROM users GROUP BY city
) t WHERE t.cnt > 10;

-- Correlated subquery in SELECT
SELECT username,
    (SELECT MAX(amount) FROM orders WHERE user_id = users.id) AS max_order
FROM users;

-- Correlated subquery in WHERE
SELECT * FROM users u
WHERE (SELECT SUM(amount) FROM orders WHERE user_id = u.id) > 1000;

-- Subquery in HAVING
SELECT city, COUNT(*) AS cnt
FROM users
GROUP BY city
HAVING COUNT(*) > (SELECT AVG(cnt) FROM (SELECT COUNT(*) AS cnt FROM users GROUP BY city));

-- Nested subqueries
SELECT * FROM users
WHERE city IN (
    SELECT city FROM users
    GROUP BY city
    HAVING AVG(age) > (SELECT AVG(age) FROM users)
);

-- Subquery with IN + multi-column (Spark 2.4+)
SELECT * FROM users WHERE (city, age) IN (SELECT city, MIN(age) FROM users GROUP BY city);

-- Subquery as table in JOIN
SELECT u.username, o.total
FROM users u
JOIN (
    SELECT user_id, SUM(amount) AS total
    FROM orders
    GROUP BY user_id
) o ON u.id = o.user_id;

-- LATERAL subquery (Spark 3.4+)
SELECT u.username, t.total
FROM users u,
LATERAL (SELECT SUM(amount) AS total FROM orders WHERE user_id = u.id) t;

-- LEFT SEMI JOIN (alternative to EXISTS subquery)
SELECT * FROM users u
LEFT SEMI JOIN orders o ON u.id = o.user_id;

-- LEFT ANTI JOIN (alternative to NOT EXISTS subquery)
SELECT * FROM users u
LEFT ANTI JOIN orders o ON u.id = o.user_id;

-- Subquery with LATERAL VIEW
SELECT u.username, tag
FROM users u
LATERAL VIEW EXPLODE(
    (SELECT collect_list(tag) FROM user_tags WHERE user_id = u.id)
) t AS tag;

-- Note: Spark supports scalar, IN, EXISTS, and correlated subqueries
-- Note: LATERAL subqueries added in Spark 3.4+
-- Note: LEFT SEMI/ANTI JOIN is often more efficient than EXISTS/NOT EXISTS
-- Note: ALL/ANY/SOME subquery operators have limited support
-- Note: Deeply nested correlated subqueries may have performance issues
