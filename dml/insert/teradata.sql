-- Teradata: INSERT
--
-- 参考资料:
--   [1] Teradata SQL Reference
--       https://docs.teradata.com/r/Teradata-VantageTM-SQL-Functions-Expressions-and-Predicates
--   [2] Teradata Database Documentation
--       https://docs.teradata.com/

-- Single row insert
INSERT INTO users (username, email, age) VALUES ('alice', 'alice@example.com', 25);

-- Multiple rows (Teradata does not support multi-row VALUES natively)
-- Use INSERT ... SELECT with UNION ALL
INSERT INTO users (username, email, age)
SELECT 'alice', 'alice@example.com', 25 FROM (SELECT 1 AS x) t
UNION ALL
SELECT 'bob', 'bob@example.com', 30 FROM (SELECT 1 AS x) t
UNION ALL
SELECT 'charlie', 'charlie@example.com', 35 FROM (SELECT 1 AS x) t;

-- Insert from query
INSERT INTO users_archive (username, email, age)
SELECT username, email, age FROM users WHERE age > 60;

-- INSERT ... SELECT with aggregation
INSERT INTO city_stats (city, user_count, avg_age)
SELECT city, COUNT(*), AVG(age) FROM users GROUP BY city;

-- Default values
INSERT INTO users (username, email, age) VALUES ('alice', 'alice@example.com', DEFAULT);

-- CTAS (Create Table As Select) for bulk insert to new table
CREATE TABLE users_copy AS (
    SELECT * FROM users WHERE status = 1
) WITH DATA
PRIMARY INDEX (id);

-- INSERT with subquery
INSERT INTO vip_users (user_id, total_spent)
SELECT user_id, SUM(amount)
FROM orders
GROUP BY user_id
HAVING SUM(amount) > 10000;

-- Bulk loading utilities (not SQL, but essential for Teradata)
-- FastLoad:  parallel bulk loading to empty tables
-- MultiLoad: bulk load with updates/deletes, works on populated tables
-- TPump:     continuous/trickle loading
-- BTEQ:      batch SQL execution tool

-- FastLoad example (external utility):
-- .LOGON tdserver/username,password
-- .BEGIN LOADING users;
-- INSERT INTO users (username, email, age) VALUES (:username, :email, :age);
-- .END LOADING;

-- Using VOLATILE table as staging
CREATE VOLATILE TABLE vt_staging (
    username VARCHAR(64),
    email    VARCHAR(255)
) PRIMARY INDEX (username) ON COMMIT PRESERVE ROWS;

INSERT INTO vt_staging VALUES ('alice', 'alice@example.com');
INSERT INTO users (username, email)
SELECT username, email FROM vt_staging;
