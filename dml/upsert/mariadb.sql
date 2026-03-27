-- MariaDB: UPSERT
-- MariaDB is a MySQL fork; only differences from MySQL are shown here.
--
-- 参考资料:
--   [1] MariaDB Knowledge Base
--       https://mariadb.com/kb/en/documentation/
--   [2] MariaDB vs MySQL Compatibility
--       https://mariadb.com/kb/en/mariadb-vs-mysql-compatibility/

-- ON DUPLICATE KEY UPDATE (same as MySQL)
INSERT INTO users (username, email, age)
VALUES ('alice', 'alice@example.com', 25)
ON DUPLICATE KEY UPDATE
    email = VALUES(email),
    age = VALUES(age);
-- Note: MariaDB still uses VALUES() in UPDATE clause
-- MySQL 8.0.19+ deprecated VALUES() in favor of row alias; MariaDB has not

-- REPLACE INTO (same as MySQL)
REPLACE INTO users (username, email, age)
VALUES ('alice', 'alice@example.com', 25);

-- INSERT IGNORE (same as MySQL)
INSERT IGNORE INTO users (username, email, age)
VALUES ('alice', 'alice@example.com', 25);

-- INSERT ... ON DUPLICATE KEY UPDATE ... RETURNING (10.5+)
-- Combines upsert with RETURNING, unique to MariaDB
INSERT INTO users (username, email, age)
VALUES ('alice', 'alice@example.com', 25)
ON DUPLICATE KEY UPDATE email = VALUES(email), age = VALUES(age)
RETURNING id, username, age;

-- REPLACE ... RETURNING (10.5+)
REPLACE INTO users (username, email, age)
VALUES ('alice', 'alice@example.com', 25)
RETURNING *;

-- Multi-row upsert
INSERT INTO users (username, email, age) VALUES
    ('alice', 'alice@example.com', 25),
    ('bob', 'bob@example.com', 30)
ON DUPLICATE KEY UPDATE
    email = VALUES(email),
    age = VALUES(age);

-- Upsert with INSERT ... SELECT
INSERT INTO user_stats (user_id, order_count, total_amount)
SELECT user_id, COUNT(*), SUM(amount) FROM orders GROUP BY user_id
ON DUPLICATE KEY UPDATE
    order_count = VALUES(order_count),
    total_amount = VALUES(total_amount);

-- Differences from MySQL 8.0:
-- No row alias syntax (INSERT ... VALUES ... AS new ON DUPLICATE KEY UPDATE new.col)
-- RETURNING clause available with upsert (MariaDB-specific)
-- VALUES() function in ON DUPLICATE KEY UPDATE is not deprecated (unlike MySQL 8.0.19+)
-- No MERGE statement
