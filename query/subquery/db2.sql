-- IBM Db2: Subqueries
--
-- 参考资料:
--   [1] Db2 SQL Reference
--       https://www.ibm.com/docs/en/db2/11.5?topic=sql
--   [2] Db2 Built-in Functions
--       https://www.ibm.com/docs/en/db2/11.5?topic=functions-built-in

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

-- LATERAL subquery (Db2 9.1+)
SELECT u.username, t.total
FROM users u,
LATERAL (SELECT SUM(amount) AS total FROM orders WHERE user_id = u.id) t;

-- Row subquery comparison
SELECT * FROM users WHERE (city, age) IN (SELECT city, MIN(age) FROM users GROUP BY city);

-- Correlated subquery
SELECT u.username, u.age,
    (SELECT MAX(o.amount) FROM orders o WHERE o.user_id = u.id) AS max_order
FROM users u;

-- Subquery in HAVING
SELECT city, COUNT(*) AS cnt
FROM users
GROUP BY city
HAVING COUNT(*) > (SELECT AVG(cnt) FROM (SELECT COUNT(*) AS cnt FROM users GROUP BY city) t);

-- XMLTABLE subquery (process XML data)
SELECT u.username, x.phone
FROM users u,
XMLTABLE('$d/phones/phone' PASSING u.contact_xml AS "d"
    COLUMNS phone VARCHAR(20) PATH '.') AS x;

-- Nested subqueries
SELECT * FROM users
WHERE city IN (
    SELECT city FROM users
    GROUP BY city
    HAVING AVG(age) > (SELECT AVG(age) FROM users)
);

-- TABLE function as subquery (Db2 specific)
SELECT * FROM TABLE(SYSPROC.ADMIN_GET_TAB_INFO('MYSCHEMA', 'USERS')) AS t;

-- Note: Db2 optimizer may flatten subqueries into joins
-- Note: RUNSTATS helps optimizer choose best subquery strategy
