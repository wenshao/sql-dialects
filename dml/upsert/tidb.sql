-- TiDB: UPSERT
-- TiDB is MySQL compatible; only differences from MySQL are shown here.
--
-- 参考资料:
--   [1] TiDB SQL Reference
--       https://docs.pingcap.com/tidb/stable/sql-statement-overview
--   [2] TiDB - MySQL Compatibility
--       https://docs.pingcap.com/tidb/stable/mysql-compatibility
--   [3] TiDB - Functions and Operators
--       https://docs.pingcap.com/tidb/stable/functions-and-operators-overview

-- ON DUPLICATE KEY UPDATE (same as MySQL)
INSERT INTO users (username, email, age)
VALUES ('alice', 'alice@example.com', 25)
ON DUPLICATE KEY UPDATE
    email = VALUES(email),
    age = VALUES(age);

-- Row alias syntax (same as MySQL 8.0.19+)
INSERT INTO users (username, email, age)
VALUES ('alice', 'alice@example.com', 25) AS new
ON DUPLICATE KEY UPDATE
    email = new.email,
    age = new.age;

-- REPLACE INTO (same as MySQL)
-- Warning: REPLACE deletes then inserts, which changes AUTO_RANDOM values
REPLACE INTO users (username, email, age)
VALUES ('alice', 'alice@example.com', 25);

-- INSERT IGNORE (same as MySQL)
INSERT IGNORE INTO users (username, email, age)
VALUES ('alice', 'alice@example.com', 25);

-- AUTO_RANDOM considerations:
-- ON DUPLICATE KEY UPDATE is preferred over REPLACE for AUTO_RANDOM tables
-- REPLACE causes DELETE + INSERT, generating a new AUTO_RANDOM value
-- ON DUPLICATE KEY UPDATE preserves the existing row's ID
INSERT INTO users (username, email, age)
VALUES ('alice', 'alice@example.com', 26)
ON DUPLICATE KEY UPDATE age = VALUES(age);
-- This preserves the original AUTO_RANDOM id

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

-- Limitations:
-- Same transaction size limits apply
-- ON DUPLICATE KEY UPDATE with AUTO_RANDOM: if conflict exists, the original id is kept
-- REPLACE INTO with AUTO_RANDOM: generates a new random id (original id lost)
-- No MERGE statement (use ON DUPLICATE KEY UPDATE instead)
-- Foreign key constraints (when enabled in 6.6+) are checked during upsert
