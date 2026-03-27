-- OceanBase: Subquery
-- OceanBase has dual mode: MySQL mode and Oracle mode. Both shown where relevant.
--
-- 参考资料:
--   [1] OceanBase SQL Reference (MySQL Mode)
--       https://www.oceanbase.com/docs/common-oceanbase-database-cn
--   [2] OceanBase SQL Reference (Oracle Mode)
--       https://www.oceanbase.com/docs/common-oceanbase-database-cn

-- ============================================================
-- MySQL Mode (same as MySQL with optimizer differences)
-- ============================================================

-- Scalar subquery
SELECT username, (SELECT COUNT(*) FROM orders WHERE user_id = users.id) AS order_count
FROM users;

-- WHERE IN subquery
SELECT * FROM users WHERE id IN (SELECT user_id FROM orders WHERE amount > 100);

-- EXISTS
SELECT * FROM users u
WHERE EXISTS (SELECT 1 FROM orders o WHERE o.user_id = u.id);

-- FROM subquery (derived table)
SELECT t.city, t.cnt FROM (
    SELECT city, COUNT(*) AS cnt FROM users GROUP BY city
) t WHERE t.cnt > 10;

-- LATERAL derived table (4.0+)
SELECT u.username, t.total
FROM users u,
LATERAL (SELECT SUM(amount) AS total FROM orders WHERE user_id = u.id) t;

-- Comparison operators
SELECT * FROM users WHERE age > (SELECT AVG(age) FROM users);
SELECT * FROM users WHERE age >= ALL (SELECT age FROM users WHERE city = 'Beijing');

-- ============================================================
-- Oracle Mode
-- ============================================================

-- Scalar subquery (same syntax)
SELECT username, (SELECT COUNT(*) FROM orders WHERE user_id = users.id) AS order_count
FROM users;

-- WHERE IN subquery
SELECT * FROM users WHERE id IN (SELECT user_id FROM orders WHERE amount > 100);

-- EXISTS
SELECT * FROM users u
WHERE EXISTS (SELECT 1 FROM orders o WHERE o.user_id = u.id);

-- FROM subquery (no alias required in Oracle mode)
SELECT * FROM (
    SELECT city, COUNT(*) AS cnt FROM users GROUP BY city
) WHERE cnt > 10;

-- ROWNUM (Oracle-specific, used in subqueries for limiting)
SELECT * FROM (
    SELECT u.*, ROWNUM AS rn FROM users u WHERE ROWNUM <= 20
) WHERE rn > 10;

-- Correlated subquery (Oracle mode)
SELECT * FROM users u
WHERE u.age > (SELECT AVG(age) FROM users WHERE city = u.city);

-- WITH clause as subquery (Oracle CTE style)
SELECT * FROM (
    WITH active AS (SELECT * FROM users WHERE status = 1)
    SELECT * FROM active WHERE age > 25
);

-- Multiset subqueries (Oracle mode, 4.0+)
-- Limited support for MULTISET operators

-- Optimizer hints for subqueries
SELECT /*+ UNNEST */ * FROM users
WHERE id IN (SELECT user_id FROM orders WHERE amount > 100);

SELECT /*+ NO_UNNEST */ * FROM users
WHERE id IN (SELECT user_id FROM orders WHERE amount > 100);

-- Limitations:
-- MySQL mode: mostly identical to MySQL subquery behavior
-- Oracle mode: ROWNUM available, no alias required for inline views
-- Subquery flattening/unnesting controlled by optimizer
-- Complex correlated subqueries may not always be decorrelated
