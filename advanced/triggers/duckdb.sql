-- DuckDB: Triggers
--
-- 参考资料:
--   [1] DuckDB - SQL Reference
--       https://duckdb.org/docs/sql/introduction
--   [2] DuckDB - Functions
--       https://duckdb.org/docs/sql/functions/overview
--   [3] DuckDB - Data Types
--       https://duckdb.org/docs/sql/data_types/overview

-- DuckDB does NOT support triggers
-- As an embedded OLAP database, DuckDB focuses on analytical queries
-- rather than transactional event-driven behavior

-- Alternatives to triggers in DuckDB:

-- 1. Application-level logic
-- Handle "trigger-like" behavior in the application code:
-- Python example:
-- def insert_user(conn, username, email):
--     conn.execute("INSERT INTO users (username, email) VALUES (?, ?)", [username, email])
--     conn.execute("INSERT INTO audit_log (action, details) VALUES (?, ?)",
--                  ['INSERT', f'User {username} created'])

-- 2. Views for computed columns (instead of trigger-updated columns)
CREATE VIEW users_with_age_group AS
SELECT *,
    CASE
        WHEN age < 18 THEN 'minor'
        WHEN age < 65 THEN 'adult'
        ELSE 'senior'
    END AS age_group
FROM users;

-- 3. Generated columns (instead of trigger-computed values)
CREATE TABLE products (
    price    DECIMAL(10,2),
    quantity INTEGER,
    total    DECIMAL(10,2) GENERATED ALWAYS AS (price * quantity)
);

-- 4. CHECK constraints (instead of validation triggers)
CREATE TABLE users (
    id       BIGINT PRIMARY KEY,
    age      INTEGER CHECK (age >= 0 AND age <= 200),
    email    VARCHAR CHECK (email LIKE '%@%'),
    status   INTEGER CHECK (status IN (0, 1, 2))
);

-- 5. CTE-based audit pattern (manual, per-operation)
WITH inserted AS (
    INSERT INTO users (username, email) VALUES ('alice', 'alice@example.com') RETURNING *
)
INSERT INTO audit_log (table_name, action, record_id, timestamp)
SELECT 'users', 'INSERT', id, NOW() FROM inserted;

-- 6. CREATE OR REPLACE TABLE for bulk transformations
-- Instead of trigger-based data transformation:
CREATE OR REPLACE TABLE users AS
SELECT *,
    LOWER(email) AS normalized_email,
    NOW() AS updated_at
FROM users;

-- 7. Macros for enforcing business rules
CREATE MACRO safe_insert_user(p_username, p_email, p_age) AS TABLE
    SELECT CASE
        WHEN p_age < 0 OR p_age > 200 THEN error('Invalid age')
        WHEN p_email NOT LIKE '%@%' THEN error('Invalid email')
        ELSE 1
    END;
-- Use before inserting: SELECT * FROM safe_insert_user('alice', 'alice@example.com', 25);

-- Note: DuckDB has no CREATE TRIGGER statement
-- Note: DuckDB is designed for analytics, not OLTP with event-driven logic
-- Note: Use application code for trigger-like behavior
-- Note: Generated columns and CHECK constraints replace some trigger use cases
-- Note: For audit logging, use CTE + RETURNING pattern or application middleware
-- Note: For auto-updated timestamps, handle in the application layer
