-- MariaDB: UPDATE
-- MariaDB is a MySQL fork; only differences from MySQL are shown here.
--
-- 参考资料:
--   [1] MariaDB Knowledge Base
--       https://mariadb.com/kb/en/documentation/
--   [2] MariaDB vs MySQL Compatibility
--       https://mariadb.com/kb/en/mariadb-vs-mysql-compatibility/

-- Basic update (same as MySQL)
UPDATE users SET age = 26 WHERE username = 'alice';

-- Multi-column update (same as MySQL)
UPDATE users SET email = 'new@example.com', age = 26 WHERE username = 'alice';

-- UPDATE with LIMIT (same as MySQL)
UPDATE users SET status = 0 WHERE status = 1 ORDER BY created_at LIMIT 100;

-- Multi-table update (same as MySQL)
UPDATE users u
JOIN orders o ON u.id = o.user_id
SET u.status = 1
WHERE o.amount > 1000;

-- UPDATE ... RETURNING (10.5+): return data from updated rows
-- Not available in MySQL
UPDATE users SET age = 26 WHERE username = 'alice'
RETURNING id, username, age;

-- RETURNING with expressions
UPDATE users SET status = 0 WHERE last_login < '2023-01-01'
RETURNING id, username, CONCAT('deactivated: ', email) AS note;

-- RETURNING * for all columns
UPDATE users SET age = age + 1 WHERE id = 1
RETURNING *;

-- WITH CTE (10.2.1+, earlier than MySQL 8.0)
WITH vip AS (
    SELECT user_id FROM orders GROUP BY user_id HAVING SUM(amount) > 10000
)
UPDATE users u JOIN vip v ON u.id = v.user_id SET u.status = 2;

-- UPDATE for temporal tables (10.5+): update a portion of a period
-- For tables with application-time periods
UPDATE contracts FOR PORTION OF valid_period
    FROM '2024-01-01' TO '2024-06-01'
SET amount = 5000.00
WHERE client = 'Acme Corp';
-- This splits the original row and updates only the specified time portion

-- Subquery update (same as MySQL)
UPDATE users SET age = (SELECT AVG(age) FROM users) WHERE age IS NULL;

-- CASE expression (same as MySQL)
UPDATE users SET status = CASE
    WHEN age < 18 THEN 0
    WHEN age >= 65 THEN 2
    ELSE 1
END;

-- Histogram-based optimizer (10.0+)
-- MariaDB uses histogram statistics for better UPDATE query plans
ANALYZE TABLE users PERSISTENT FOR COLUMNS (age, city) INDEXES (idx_age);

-- Differences from MySQL 8.0:
-- RETURNING clause is MariaDB-specific (10.5+)
-- FOR PORTION OF temporal update is MariaDB-specific (10.5+)
-- CTEs available from 10.2.1 (earlier than MySQL 8.0)
-- Different optimizer behavior, often faster for complex updates
