-- CockroachDB: UPSERT (v23.1+)
--
-- 参考资料:
--   [1] CockroachDB - SQL Statements
--       https://www.cockroachlabs.com/docs/stable/sql-statements
--   [2] CockroachDB - Functions and Operators
--       https://www.cockroachlabs.com/docs/stable/functions-and-operators
--   [3] CockroachDB - Data Types
--       https://www.cockroachlabs.com/docs/stable/data-types

-- CockroachDB supports both UPSERT and INSERT ... ON CONFLICT

-- ============================================================
-- UPSERT (CockroachDB shorthand)
-- ============================================================

-- UPSERT: insert or replace on primary key conflict
UPSERT INTO users (id, username, email, age) VALUES
    (gen_random_uuid(), 'alice', 'alice@example.com', 25);
-- If primary key exists, all columns are replaced

-- UPSERT multiple rows
UPSERT INTO users (id, username, email, age) VALUES
    (gen_random_uuid(), 'alice', 'alice@example.com', 25),
    (gen_random_uuid(), 'bob', 'bob@example.com', 30);

-- ============================================================
-- INSERT ... ON CONFLICT (PostgreSQL-compatible)
-- ============================================================

-- On conflict, update specific columns
INSERT INTO users (username, email, age) VALUES ('alice', 'alice@example.com', 26)
ON CONFLICT (username) DO UPDATE SET email = EXCLUDED.email, age = EXCLUDED.age;

-- ON CONFLICT DO NOTHING (skip if exists)
INSERT INTO users (username, email, age) VALUES ('alice', 'alice@example.com', 25)
ON CONFLICT (username) DO NOTHING;

-- ON CONFLICT with WHERE (conditional update)
INSERT INTO users (username, email, age) VALUES ('alice', 'alice@example.com', 26)
ON CONFLICT (username) DO UPDATE SET age = EXCLUDED.age
WHERE users.age < EXCLUDED.age;

-- ON CONFLICT on constraint name
INSERT INTO users (username, email, age) VALUES ('alice', 'alice@example.com', 26)
ON CONFLICT ON CONSTRAINT uq_username DO UPDATE SET email = EXCLUDED.email;

-- ON CONFLICT with RETURNING
INSERT INTO users (username, email, age) VALUES ('alice', 'alice@example.com', 26)
ON CONFLICT (username) DO UPDATE SET email = EXCLUDED.email, age = EXCLUDED.age
RETURNING id, username, email, age;

-- Batch upsert from query
INSERT INTO users (username, email, age)
SELECT username, email, age FROM staging_users
ON CONFLICT (username) DO UPDATE SET
    email = EXCLUDED.email,
    age = EXCLUDED.age,
    updated_at = now();

-- CTE + upsert
WITH new_data AS (
    SELECT 'alice' AS username, 'alice@example.com' AS email, 25 AS age
    UNION ALL
    SELECT 'bob', 'bob@example.com', 30
)
INSERT INTO users (username, email, age)
SELECT * FROM new_data
ON CONFLICT (username) DO UPDATE SET email = EXCLUDED.email, age = EXCLUDED.age;

-- Upsert with multiple conflict targets (composite unique)
INSERT INTO order_items (order_id, item_id, quantity, price)
VALUES (1, 1, 5, 9.99)
ON CONFLICT (order_id, item_id) DO UPDATE SET
    quantity = EXCLUDED.quantity,
    price = EXCLUDED.price;

-- Note: UPSERT is CockroachDB shorthand (replaces all columns on PK conflict)
-- Note: INSERT ... ON CONFLICT gives more control (update specific columns)
-- Note: EXCLUDED refers to the row proposed for insertion
-- Note: RETURNING works with upsert operations
-- Note: Upserts are atomic and transactional
