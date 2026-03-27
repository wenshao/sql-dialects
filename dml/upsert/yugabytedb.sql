-- YugabyteDB: UPSERT (YSQL, v2.x+)
--
-- 参考资料:
--   [1] YugabyteDB YSQL Reference
--       https://docs.yugabyte.com/stable/api/ysql/
--   [2] YugabyteDB PostgreSQL Compatibility
--       https://docs.yugabyte.com/stable/explore/ysql-language-features/

-- YugabyteDB uses PostgreSQL-compatible INSERT ... ON CONFLICT

-- ============================================================
-- INSERT ... ON CONFLICT DO UPDATE (upsert)
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

-- ============================================================
-- Batch upsert
-- ============================================================

-- Multiple rows upsert
INSERT INTO users (username, email, age) VALUES
    ('alice', 'alice@example.com', 25),
    ('bob', 'bob@example.com', 30),
    ('charlie', 'charlie@example.com', 35)
ON CONFLICT (username) DO UPDATE SET
    email = EXCLUDED.email,
    age = EXCLUDED.age,
    updated_at = now();

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

-- ============================================================
-- MERGE (not yet supported; use INSERT ... ON CONFLICT)
-- ============================================================

-- YugabyteDB does not support MERGE statement
-- Use INSERT ... ON CONFLICT as the primary upsert mechanism

-- Composite unique conflict
INSERT INTO order_items (order_id, item_id, quantity, price)
VALUES (1, 1, 5, 9.99)
ON CONFLICT (order_id, item_id) DO UPDATE SET
    quantity = EXCLUDED.quantity,
    price = EXCLUDED.price;

-- Note: Uses PostgreSQL ON CONFLICT syntax (no MERGE support)
-- Note: EXCLUDED refers to the row proposed for insertion
-- Note: RETURNING works with upsert operations
-- Note: Upserts are atomic across distributed tablets
-- Note: Performance is similar to INSERT for hash-sharded tables
-- Note: ON CONFLICT requires a unique index or constraint
