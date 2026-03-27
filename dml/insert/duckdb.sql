-- DuckDB: INSERT (v0.8+)
--
-- 参考资料:
--   [1] DuckDB - SQL Reference
--       https://duckdb.org/docs/sql/introduction
--   [2] DuckDB - Functions
--       https://duckdb.org/docs/sql/functions/overview
--   [3] DuckDB - Data Types
--       https://duckdb.org/docs/sql/data_types/overview

-- Single row insert
INSERT INTO users (username, email, age) VALUES ('alice', 'alice@example.com', 25);

-- Multi-row insert
INSERT INTO users (username, email, age) VALUES
    ('alice', 'alice@example.com', 25),
    ('bob', 'bob@example.com', 30),
    ('charlie', 'charlie@example.com', 35);

-- Insert from query
INSERT INTO users_archive (username, email, age)
SELECT username, email, age FROM users WHERE age > 60;

-- RETURNING (v0.9+)
INSERT INTO users (username, email, age)
VALUES ('alice', 'alice@example.com', 25)
RETURNING id, username;

INSERT INTO users (username, email, age)
VALUES ('alice', 'alice@example.com', 25)
RETURNING *;

-- Default values
INSERT INTO users (username, email, age) VALUES ('alice', 'alice@example.com', DEFAULT);

-- INSERT OR REPLACE (upsert by primary key)
INSERT OR REPLACE INTO users (id, username, email) VALUES (1, 'alice', 'alice_new@example.com');

-- INSERT OR IGNORE (skip on conflict)
INSERT OR IGNORE INTO users (id, username, email) VALUES (1, 'alice', 'alice@example.com');

-- Insert from CSV/Parquet/JSON files directly
INSERT INTO users SELECT * FROM read_csv_auto('users.csv');
INSERT INTO users SELECT * FROM read_parquet('users.parquet');
INSERT INTO users SELECT * FROM read_json_auto('users.json');

-- Insert from multiple files using glob
INSERT INTO events SELECT * FROM read_parquet('data/events_*.parquet');

-- CTE + INSERT
WITH new_users AS (
    SELECT 'alice' AS username, 'alice@example.com' AS email
)
INSERT INTO users (username, email)
SELECT username, email FROM new_users;

-- Insert with complex types
INSERT INTO complex_data (id, tags, address, meta) VALUES (
    1,
    ['tag1', 'tag2', 'tag3'],
    {'street': '123 Main St', 'city': 'NYC', 'zip': '10001'},
    MAP {'key1': 'val1', 'key2': 'val2'}
);

-- COPY for bulk loading (faster than INSERT for large data)
COPY users FROM 'users.csv' (FORMAT CSV, HEADER TRUE);
COPY users FROM 'users.parquet' (FORMAT PARQUET);
COPY users FROM 'users.json' (FORMAT JSON);

-- COPY with options
COPY users FROM 'users.csv' (
    FORMAT CSV,
    HEADER TRUE,
    DELIMITER '|',
    NULL 'NA',
    QUOTE '"'
);

-- Export data with COPY
COPY users TO 'output.parquet' (FORMAT PARQUET);
COPY (SELECT * FROM users WHERE age > 30) TO 'seniors.csv' (FORMAT CSV, HEADER TRUE);

-- Note: DuckDB supports INSERT OR REPLACE / INSERT OR IGNORE (SQLite-style)
-- Note: ON CONFLICT clause is also supported (PostgreSQL-style, v0.9+)
-- Note: COPY is preferred for bulk operations
-- Note: Direct file reading (read_csv, read_parquet) is a unique DuckDB strength
