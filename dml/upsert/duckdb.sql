-- DuckDB: UPSERT (v0.9+)
--
-- 参考资料:
--   [1] DuckDB - SQL Reference
--       https://duckdb.org/docs/sql/introduction
--   [2] DuckDB - Functions
--       https://duckdb.org/docs/sql/functions/overview
--   [3] DuckDB - Data Types
--       https://duckdb.org/docs/sql/data_types/overview

-- INSERT OR REPLACE (SQLite-compatible, by primary key)
INSERT OR REPLACE INTO users (id, username, email, age)
VALUES (1, 'alice', 'alice_new@example.com', 26);

-- INSERT OR IGNORE (skip on primary key conflict)
INSERT OR IGNORE INTO users (id, username, email, age)
VALUES (1, 'alice', 'alice@example.com', 25);

-- ON CONFLICT (PostgreSQL-compatible, v0.9+)
INSERT INTO users (username, email, age)
VALUES ('alice', 'alice@example.com', 25)
ON CONFLICT (username)
DO UPDATE SET
    email = EXCLUDED.email,
    age = EXCLUDED.age;

-- ON CONFLICT DO NOTHING
INSERT INTO users (username, email, age)
VALUES ('alice', 'alice@example.com', 25)
ON CONFLICT (username) DO NOTHING;

-- ON CONFLICT with WHERE (conditional update)
INSERT INTO users (username, email, age)
VALUES ('alice', 'alice@example.com', 25)
ON CONFLICT (username)
DO UPDATE SET
    email = EXCLUDED.email,
    age = EXCLUDED.age
WHERE users.age < EXCLUDED.age;

-- Multi-row upsert
INSERT INTO users (username, email, age) VALUES
    ('alice', 'alice@example.com', 25),
    ('bob', 'bob@example.com', 30),
    ('charlie', 'charlie@example.com', 35)
ON CONFLICT (username)
DO UPDATE SET
    email = EXCLUDED.email,
    age = EXCLUDED.age;

-- Upsert from query
INSERT INTO users (username, email, age)
SELECT username, email, age FROM staging_users
ON CONFLICT (username)
DO UPDATE SET
    email = EXCLUDED.email,
    age = EXCLUDED.age;

-- Upsert from file
INSERT INTO users
SELECT * FROM read_csv_auto('new_users.csv')
ON CONFLICT (id)
DO UPDATE SET
    username = EXCLUDED.username,
    email = EXCLUDED.email;

-- RETURNING with upsert (v0.9+)
INSERT INTO users (username, email, age)
VALUES ('alice', 'alice@example.com', 25)
ON CONFLICT (username)
DO UPDATE SET email = EXCLUDED.email
RETURNING id, username, email;

-- Note: DuckDB supports both SQLite-style (INSERT OR REPLACE/IGNORE) and
--       PostgreSQL-style (ON CONFLICT) upsert syntax
-- Note: INSERT OR REPLACE deletes the old row and inserts a new one
--       (resets columns not in the INSERT list to defaults)
-- Note: ON CONFLICT DO UPDATE only updates specified columns
-- Note: No MERGE statement (use ON CONFLICT instead)
-- Note: EXCLUDED refers to the row that was proposed for insertion
