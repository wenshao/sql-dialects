-- MariaDB: Pagination
-- MariaDB is a MySQL fork; only differences from MySQL are shown here.
--
-- 参考资料:
--   [1] MariaDB Knowledge Base
--       https://mariadb.com/kb/en/documentation/
--   [2] MariaDB vs MySQL Compatibility
--       https://mariadb.com/kb/en/mariadb-vs-mysql-compatibility/

-- LIMIT / OFFSET (same as MySQL)
SELECT * FROM users ORDER BY id LIMIT 10 OFFSET 20;

-- Shorthand form (same as MySQL)
SELECT * FROM users ORDER BY id LIMIT 20, 10;

-- Window function pagination (10.2+, earlier than MySQL 8.0)
SELECT * FROM (
    SELECT *, ROW_NUMBER() OVER (ORDER BY id) AS rn
    FROM users
) t
WHERE rn BETWEEN 21 AND 30;

-- Cursor-based pagination (same as MySQL)
SELECT * FROM users WHERE id > 100 ORDER BY id LIMIT 10;

-- LIMIT ROWS EXAMINED (MariaDB-specific, 10.0+)
-- Limits the total number of rows examined (not returned) by the query
-- Useful to prevent runaway queries
SELECT * FROM users WHERE status = 1 ORDER BY created_at
LIMIT 10
ROWS EXAMINED 10000;
-- Query stops after examining 10000 rows, even if 10 results not yet found
-- Returns however many rows were found within the examination limit

-- OFFSET ... FETCH (10.6+, SQL:2008 standard syntax)
SELECT * FROM users ORDER BY id
OFFSET 20 ROWS FETCH NEXT 10 ROWS ONLY;

-- FETCH FIRST (10.6+)
SELECT * FROM users ORDER BY id
FETCH FIRST 10 ROWS ONLY;

-- FETCH with TIES (10.6+): include rows tied at the boundary
SELECT * FROM users ORDER BY age DESC
FETCH FIRST 10 ROWS WITH TIES;

-- FETCH with PERCENT (10.6+)
SELECT * FROM users ORDER BY age DESC
FETCH FIRST 10 PERCENT ROWS ONLY;

-- SQL_CALC_FOUND_ROWS (same as MySQL, but not deprecated)
-- MySQL 8.0.17 deprecated SQL_CALC_FOUND_ROWS; MariaDB has not
SELECT SQL_CALC_FOUND_ROWS * FROM users ORDER BY id LIMIT 10;
SELECT FOUND_ROWS();  -- total matching rows without LIMIT

-- Prepared statement with LIMIT (same as MySQL)
PREPARE stmt FROM 'SELECT * FROM users ORDER BY id LIMIT ? OFFSET ?';
SET @limit = 10;
SET @offset = 20;
EXECUTE stmt USING @limit, @offset;

-- Differences from MySQL 8.0:
-- LIMIT ROWS EXAMINED is MariaDB-specific
-- OFFSET FETCH / FETCH FIRST supported from 10.6+
-- SQL_CALC_FOUND_ROWS not deprecated (MySQL deprecated it in 8.0.17)
-- Window functions for pagination available from 10.2+
-- Same large OFFSET performance characteristics as MySQL
