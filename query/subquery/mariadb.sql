-- MariaDB: Subquery
-- MariaDB is a MySQL fork; only differences from MySQL are shown here.
--
-- 参考资料:
--   [1] MariaDB Knowledge Base
--       https://mariadb.com/kb/en/documentation/
--   [2] MariaDB vs MySQL Compatibility
--       https://mariadb.com/kb/en/mariadb-vs-mysql-compatibility/

-- Standard subqueries work the same as MySQL:
-- Scalar, WHERE IN, EXISTS, FROM (derived table)

-- Scalar subquery (same as MySQL)
SELECT username, (SELECT COUNT(*) FROM orders WHERE user_id = users.id) AS order_count
FROM users;

-- WHERE IN subquery (same as MySQL, but better optimized)
SELECT * FROM users WHERE id IN (SELECT user_id FROM orders WHERE amount > 100);
-- MariaDB's optimizer is often better at converting IN subqueries to semi-joins
-- than MySQL 5.7 (MySQL 8.0 improved this significantly)

-- EXISTS (same as MySQL)
SELECT * FROM users u
WHERE EXISTS (SELECT 1 FROM orders o WHERE o.user_id = u.id);

-- FROM subquery (same as MySQL)
SELECT t.city, t.cnt FROM (
    SELECT city, COUNT(*) AS cnt FROM users GROUP BY city
) t WHERE t.cnt > 10;

-- LATERAL derived table (11.0+)
SELECT u.username, t.total
FROM users u,
LATERAL (SELECT SUM(amount) AS total FROM orders WHERE user_id = u.id) t;

-- Semi-join optimizations (different strategies from MySQL)
-- MariaDB supports these semi-join strategies:
-- - FirstMatch
-- - Materialization (with/without scan)
-- - LooseScan
-- - DuplicateWeedout
-- Control via optimizer_switch:
SET optimizer_switch = 'firstmatch=on,materialization=on,loosescan=on,duplicateweedout=on';

-- Subquery cache (MariaDB-specific)
-- MariaDB caches results of correlated subqueries to avoid re-execution
-- for repeated values of the correlation column
SET optimizer_switch = 'subquery_cache=on';  -- enabled by default
-- This can significantly speed up correlated subqueries

-- Example that benefits from subquery cache:
SELECT username, (SELECT MAX(amount) FROM orders WHERE user_id = users.id)
FROM users;
-- If multiple users share the same id pattern, cache avoids re-executing

-- Condition pushdown into subqueries (10.4+)
-- MariaDB can push WHERE conditions from outer query into derived tables
SELECT * FROM (
    SELECT city, COUNT(*) AS cnt FROM users GROUP BY city
) t WHERE t.city = 'Beijing';
-- MariaDB pushes city = 'Beijing' into the derived table

-- NOT IN / NOT EXISTS optimization
-- MariaDB handles NOT IN with NULLs better than early MySQL versions
SELECT * FROM users WHERE id NOT IN (SELECT user_id FROM blacklist);

-- Comparison operators (same as MySQL)
SELECT * FROM users WHERE age > (SELECT AVG(age) FROM users);
SELECT * FROM users WHERE age >= ALL (SELECT age FROM users WHERE city = 'Beijing');

-- Differences from MySQL 8.0:
-- Subquery cache is MariaDB-specific (significant performance benefit)
-- Different semi-join strategy selection
-- Condition pushdown into derived tables (10.4+)
-- LATERAL available from 11.0+ (MySQL from 8.0.14+)
-- Generally better subquery optimization than MySQL 5.7, comparable to MySQL 8.0
