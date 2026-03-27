-- CockroachDB: Constraints (v23.1+)
--
-- 参考资料:
--   [1] CockroachDB - SQL Statements
--       https://www.cockroachlabs.com/docs/stable/sql-statements
--   [2] CockroachDB - Functions and Operators
--       https://www.cockroachlabs.com/docs/stable/functions-and-operators
--   [3] CockroachDB - Data Types
--       https://www.cockroachlabs.com/docs/stable/data-types

-- CockroachDB supports all standard PostgreSQL constraints
-- All constraints are enforced (unlike some cloud databases)

-- ============================================================
-- PRIMARY KEY
-- ============================================================

CREATE TABLE users (
    id       UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    username VARCHAR(100) NOT NULL
);

-- Composite primary key
CREATE TABLE order_items (
    order_id INT NOT NULL,
    item_id  INT NOT NULL,
    PRIMARY KEY (order_id, item_id)
);

-- Hash-sharded primary key (avoid hotspots)
CREATE TABLE events (
    id UUID DEFAULT gen_random_uuid(),
    ts TIMESTAMPTZ NOT NULL,
    PRIMARY KEY (ts) USING HASH
);

-- ALTER PRIMARY KEY (CockroachDB-specific)
ALTER TABLE users ALTER PRIMARY KEY USING COLUMNS (id, region);

-- ============================================================
-- UNIQUE
-- ============================================================

CREATE TABLE users2 (
    id       UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    email    VARCHAR(255) UNIQUE,
    username VARCHAR(100),
    CONSTRAINT uq_username UNIQUE (username)
);

-- Partial unique (same as PostgreSQL)
ALTER TABLE users ADD CONSTRAINT uq_active_email
    UNIQUE (email) WHERE (status = 1);

-- ============================================================
-- NOT NULL
-- ============================================================

CREATE TABLE orders (
    id     UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    amount DECIMAL(10,2) NOT NULL,
    status INT NOT NULL DEFAULT 1
);

ALTER TABLE users ALTER COLUMN email SET NOT NULL;
ALTER TABLE users ALTER COLUMN phone DROP NOT NULL;

-- ============================================================
-- CHECK
-- ============================================================

CREATE TABLE accounts (
    id      UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    balance DECIMAL(10,2) CHECK (balance >= 0),
    age     INT,
    CONSTRAINT chk_age CHECK (age >= 0 AND age <= 150)
);

ALTER TABLE users ADD CONSTRAINT chk_status CHECK (status IN (0, 1, 2));

-- ============================================================
-- FOREIGN KEY
-- ============================================================

CREATE TABLE orders2 (
    id      UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id UUID NOT NULL REFERENCES users (id),
    amount  DECIMAL(10,2)
);

-- Named foreign key with actions
ALTER TABLE orders ADD CONSTRAINT fk_orders_user
    FOREIGN KEY (user_id) REFERENCES users (id)
    ON DELETE CASCADE
    ON UPDATE CASCADE;

-- ON DELETE options: CASCADE, SET NULL, SET DEFAULT, RESTRICT, NO ACTION
-- ON UPDATE options: CASCADE, SET NULL, SET DEFAULT, RESTRICT, NO ACTION

-- MATCH FULL / MATCH SIMPLE
ALTER TABLE orders ADD CONSTRAINT fk_orders_user
    FOREIGN KEY (user_id) REFERENCES users (id) MATCH FULL;

-- NOT VALID (add without validating existing data)
ALTER TABLE orders ADD CONSTRAINT fk_orders_user
    FOREIGN KEY (user_id) REFERENCES users (id) NOT VALID;
ALTER TABLE orders VALIDATE CONSTRAINT fk_orders_user;

-- ============================================================
-- DEFAULT
-- ============================================================

CREATE TABLE defaults_example (
    id         UUID DEFAULT gen_random_uuid(),
    status     INT DEFAULT 1,
    created_at TIMESTAMPTZ DEFAULT now(),
    region     VARCHAR(20) DEFAULT gateway_region()  -- multi-region default
);

ALTER TABLE users ALTER COLUMN status SET DEFAULT 0;
ALTER TABLE users ALTER COLUMN status DROP DEFAULT;

-- ============================================================
-- EXCLUDE (not supported)
-- ============================================================

-- CockroachDB does not support EXCLUDE constraints
-- Use application-level logic or CHECK constraints instead

-- ============================================================
-- Drop constraints
-- ============================================================

ALTER TABLE users DROP CONSTRAINT chk_age;
ALTER TABLE orders DROP CONSTRAINT fk_orders_user;
ALTER TABLE users DROP CONSTRAINT IF EXISTS uq_email;

-- View constraints
SELECT * FROM information_schema.table_constraints WHERE table_name = 'users';
SELECT * FROM information_schema.key_column_usage WHERE table_name = 'users';
SHOW CONSTRAINTS FROM users;

-- Note: All constraints are enforced (not informational)
-- Note: EXCLUDE constraints are not supported
-- Note: Foreign keys work across distributed nodes (may impact performance)
-- Note: CHECK constraints cannot reference other tables
-- Note: NOT VALID allows adding constraints without blocking writes
