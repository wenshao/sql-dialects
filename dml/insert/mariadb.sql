-- MariaDB: INSERT
-- MariaDB is a MySQL fork; only differences from MySQL are shown here.
--
-- 参考资料:
--   [1] MariaDB Knowledge Base
--       https://mariadb.com/kb/en/documentation/
--   [2] MariaDB vs MySQL Compatibility
--       https://mariadb.com/kb/en/mariadb-vs-mysql-compatibility/

-- Basic insert (same as MySQL)
INSERT INTO users (username, email, age) VALUES ('alice', 'alice@example.com', 25);

-- Multi-row insert (same as MySQL)
INSERT INTO users (username, email, age) VALUES
    ('alice', 'alice@example.com', 25),
    ('bob', 'bob@example.com', 30),
    ('charlie', 'charlie@example.com', 35);

-- INSERT IGNORE (same as MySQL)
INSERT IGNORE INTO users (username, email, age) VALUES ('alice', 'alice@example.com', 25);

-- INSERT ... RETURNING (10.5+): return data from inserted rows
-- Not available in MySQL
INSERT INTO users (username, email, age) VALUES ('alice', 'alice@example.com', 25)
RETURNING id, username, created_at;

-- INSERT ... RETURNING with expressions
INSERT INTO users (username, email, age) VALUES ('bob', 'bob@example.com', 30)
RETURNING id, CONCAT(username, '@', id) AS user_ref;

-- RETURNING works with multi-row inserts too
INSERT INTO users (username, email, age) VALUES
    ('carol', 'carol@example.com', 28),
    ('dave', 'dave@example.com', 35)
RETURNING *;

-- INSERT ... ON DUPLICATE KEY UPDATE (same as MySQL)
INSERT INTO users (username, email, age) VALUES ('alice', 'alice@example.com', 25)
ON DUPLICATE KEY UPDATE email = VALUES(email), age = VALUES(age);

-- INSERT ... SELECT (same as MySQL)
INSERT INTO users_archive (username, email, age)
SELECT username, email, age FROM users WHERE age > 60;

-- REPLACE INTO (same as MySQL)
REPLACE INTO users (username, email, age) VALUES ('alice', 'alice@example.com', 25);

-- SET syntax (same as MySQL)
INSERT INTO users SET username = 'alice', email = 'alice@example.com', age = 25;

-- Using sequences (10.3+)
INSERT INTO orders (id, user_id, amount)
VALUES (NEXT VALUE FOR seq_orders, 1, 99.99);

-- LAST_INSERT_ID()
INSERT INTO users (username, email) VALUES ('alice', 'alice@example.com');
SELECT LAST_INSERT_ID();

-- Bulk insert with LOAD DATA (same as MySQL)
LOAD DATA LOCAL INFILE '/path/to/data.csv'
INTO TABLE users
FIELDS TERMINATED BY ','
LINES TERMINATED BY '\n'
(username, email, age);

-- Differences from MySQL 8.0:
-- RETURNING clause is MariaDB-specific (10.5+)
-- Sequence support via NEXT VALUE FOR (10.3+)
-- No VALUES row alias syntax (MySQL 8.0.19+)
-- No TABLE statement for INSERT (MySQL 8.0.19+)
