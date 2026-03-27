-- YugabyteDB: INSERT (YSQL, v2.x+)
--
-- 参考资料:
--   [1] YugabyteDB YSQL Reference
--       https://docs.yugabyte.com/stable/api/ysql/
--   [2] YugabyteDB PostgreSQL Compatibility
--       https://docs.yugabyte.com/stable/explore/ysql-language-features/

-- YugabyteDB uses PostgreSQL-compatible INSERT syntax

-- Single row insert
INSERT INTO users (username, email, age) VALUES ('alice', 'alice@example.com', 25);

-- Multiple rows
INSERT INTO users (username, email, age) VALUES
    ('alice', 'alice@example.com', 25),
    ('bob', 'bob@example.com', 30),
    ('charlie', 'charlie@example.com', 35);

-- INSERT ... RETURNING (same as PostgreSQL)
INSERT INTO users (username, email, age)
VALUES ('alice', 'alice@example.com', 25)
RETURNING id, username, created_at;

-- INSERT from query
INSERT INTO users_archive (username, email, age)
SELECT username, email, age FROM users WHERE age > 60;

-- CTE + INSERT
WITH new_users AS (
    SELECT 'alice' AS username, 'alice@example.com' AS email, 25 AS age
    UNION ALL
    SELECT 'bob', 'bob@example.com', 30
)
INSERT INTO users (username, email, age)
SELECT * FROM new_users;

-- Insert with UUID generation
INSERT INTO products (id, name, price)
VALUES (gen_random_uuid(), 'Widget', 9.99);

-- Insert JSONB data
INSERT INTO events (user_id, event_type, data)
VALUES (1, 'login', '{"source": "web", "browser": "chrome"}'::JSONB);

-- Insert ARRAY data
INSERT INTO profiles (user_id, tags)
VALUES (1, ARRAY['vip', 'active', 'premium']);

-- INSERT ... ON CONFLICT (upsert, see upsert module)
INSERT INTO users (username, email, age) VALUES ('alice', 'alice@example.com', 26)
ON CONFLICT (username) DO UPDATE SET email = EXCLUDED.email, age = EXCLUDED.age;

-- Batch insert with COPY (PostgreSQL-compatible)
-- COPY users (username, email, age) FROM '/path/to/data.csv' WITH CSV HEADER;

-- Insert into partitioned table (routes to correct partition)
INSERT INTO geo_orders (id, region, amount)
VALUES (1, 'us', 99.99);
-- Automatically inserted into geo_orders_us partition

-- Insert with sequence
INSERT INTO orders (user_id, amount)
VALUES (1, 99.99);
-- id auto-generated from BIGSERIAL sequence

-- Default values
INSERT INTO users (username, email) VALUES ('alice', 'alice@example.com');
-- Unspecified columns get DEFAULT or NULL

-- Insert with explicit partition (for list/range partitioned tables)
INSERT INTO geo_orders_us (id, region, amount)
VALUES (1, 'us', 99.99);

-- Note: INSERT performance benefits from batching multiple rows
-- Note: COPY is faster than individual INSERTs for bulk loading
-- Note: Distributed transactions ensure consistency across tablets
-- Note: RETURNING clause works the same as PostgreSQL
-- Note: Hash-sharded tables distribute inserts across tablets automatically
-- Note: Sequences are distributed (may produce non-contiguous values)
