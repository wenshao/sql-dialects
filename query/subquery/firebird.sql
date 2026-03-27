-- Firebird: Subqueries
--
-- 参考资料:
--   [1] Firebird SQL Reference
--       https://firebirdsql.org/en/reference-manuals/
--   [2] Firebird Release Notes
--       https://firebirdsql.org/file/documentation/release_notes/html/en/4_0/rlsnotes40.html

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

-- SOME (synonym for ANY)
SELECT * FROM users WHERE age > SOME (SELECT age FROM users WHERE city = 'Beijing');

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

-- Subquery in HAVING
SELECT city, COUNT(*) AS cnt
FROM users
GROUP BY city
HAVING COUNT(*) > (SELECT AVG(cnt) FROM (SELECT COUNT(*) AS cnt FROM users GROUP BY city) t);

-- Selectable stored procedure as subquery source (Firebird unique)
SELECT * FROM users
WHERE id IN (SELECT user_id FROM get_active_user_ids);

-- Subquery with PLAN
SELECT * FROM users
WHERE id IN (SELECT user_id FROM orders WHERE amount > 100)
PLAN (users NATURAL, orders INDEX (idx_amount));

-- Nested subqueries
SELECT * FROM users
WHERE city IN (
    SELECT city FROM users
    GROUP BY city
    HAVING AVG(age) > (SELECT AVG(age) FROM users)
);

-- SINGULAR (Firebird-specific: true if subquery returns exactly one row)
SELECT * FROM users u
WHERE SINGULAR (SELECT 1 FROM orders o WHERE o.user_id = u.id);

-- Note: Firebird does not support LATERAL subqueries
-- Note: use selectable stored procedures for correlated derived tables
-- Note: SINGULAR is unique to Firebird (true if exactly 1 row)
