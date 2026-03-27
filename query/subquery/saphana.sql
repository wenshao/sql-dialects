-- SAP HANA: Subqueries
--
-- 参考资料:
--   [1] SAP HANA SQL Reference
--       https://help.sap.com/docs/SAP_HANA_PLATFORM/4fe29514fd584807ac9f2a04f6754767/
--   [2] SAP HANA SQLScript Reference
--       https://help.sap.com/docs/SAP_HANA_PLATFORM/de2486ee947e43e684d39702027f8a94/

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

-- CROSS APPLY / OUTER APPLY (lateral subquery)
SELECT u.username, latest.amount
FROM users u
CROSS APPLY (
    SELECT TOP 1 amount FROM orders WHERE user_id = u.id ORDER BY created_at DESC
) AS latest;

SELECT u.username, latest.amount
FROM users u
OUTER APPLY (
    SELECT TOP 1 amount FROM orders WHERE user_id = u.id ORDER BY created_at DESC
) AS latest;

-- Correlated subquery
SELECT u.username, u.age,
    (SELECT MAX(o.amount) FROM orders o WHERE o.user_id = u.id) AS max_order
FROM users u;

-- Row subquery comparison
SELECT * FROM users WHERE (city, age) IN (SELECT city, MIN(age) FROM users GROUP BY city);

-- Subquery with hierarchy functions
SELECT * FROM users
WHERE department IN (
    SELECT node_id FROM HIERARCHY (
        SOURCE dept_hier
        START WHERE parent_id IS NULL
    ) WHERE level <= 2
);

-- Nested subqueries
SELECT * FROM users
WHERE city IN (
    SELECT city FROM users
    GROUP BY city
    HAVING AVG(age) > (SELECT AVG(age) FROM users)
);

-- Subquery in HAVING
SELECT city, COUNT(*) AS cnt
FROM users
GROUP BY city
HAVING COUNT(*) > (SELECT AVG(cnt) FROM (SELECT COUNT(*) AS cnt FROM users GROUP BY city) t);

-- Note: SAP HANA in-memory engine optimizes subqueries aggressively
-- Note: column store engine can push down predicates into subqueries
