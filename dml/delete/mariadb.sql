-- MariaDB: DELETE
-- MariaDB is a MySQL fork; only differences from MySQL are shown here.
--
-- 参考资料:
--   [1] MariaDB Knowledge Base
--       https://mariadb.com/kb/en/documentation/
--   [2] MariaDB vs MySQL Compatibility
--       https://mariadb.com/kb/en/mariadb-vs-mysql-compatibility/

-- Basic delete (same as MySQL)
DELETE FROM users WHERE username = 'alice';

-- DELETE with LIMIT / ORDER BY (same as MySQL)
DELETE FROM users WHERE status = 0 ORDER BY created_at LIMIT 100;

-- Multi-table delete (same as MySQL)
DELETE u FROM users u
JOIN blacklist b ON u.email = b.email;

-- DELETE ... RETURNING (10.0+): return data from deleted rows
-- Not available in MySQL
DELETE FROM users WHERE status = 0
RETURNING id, username, email;

-- RETURNING with expressions
DELETE FROM users WHERE last_login < '2023-01-01'
RETURNING id, username, CONCAT('removed: ', email) AS note;

-- RETURNING * for all columns
DELETE FROM users WHERE id = 1
RETURNING *;

-- DELETE with CTE (10.2.1+, earlier than MySQL 8.0)
WITH inactive AS (
    SELECT id FROM users WHERE last_login < '2023-01-01'
)
DELETE u FROM users u JOIN inactive i ON u.id = i.id;

-- DELETE FOR PORTION OF (10.5+): delete part of a time period
-- For tables with application-time periods
DELETE FROM contracts FOR PORTION OF valid_period
    FROM '2024-01-01' TO '2024-06-01'
WHERE client = 'Acme Corp';
-- This narrows the existing row's period instead of fully deleting it

-- System-versioned table delete considerations:
-- DELETE on a system-versioned table does not truly remove old data
-- Old versions are kept in the history partition
DELETE FROM products WHERE id = 1;
-- Old versions still visible via:
-- SELECT * FROM products FOR SYSTEM_TIME ALL WHERE id = 1;

-- Purge history from system-versioned tables
DELETE HISTORY FROM products;
DELETE HISTORY FROM products BEFORE SYSTEM_TIME '2024-01-01';

-- TRUNCATE (same as MySQL)
TRUNCATE TABLE users;

-- DELETE IGNORE (same as MySQL)
DELETE IGNORE FROM users WHERE id = 1;

-- Subquery delete (same as MySQL)
DELETE FROM users WHERE id IN (SELECT user_id FROM blacklist);

-- Differences from MySQL 8.0:
-- RETURNING clause is MariaDB-specific (10.0+ for DELETE)
-- FOR PORTION OF temporal delete is MariaDB-specific (10.5+)
-- DELETE HISTORY for system-versioned tables is MariaDB-specific
-- CTEs available from 10.2.1 (earlier than MySQL 8.0)
