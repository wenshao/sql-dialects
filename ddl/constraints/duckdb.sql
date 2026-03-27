-- DuckDB: Constraints (v0.8+)
--
-- 参考资料:
--   [1] DuckDB - SQL Reference
--       https://duckdb.org/docs/sql/introduction
--   [2] DuckDB - Functions
--       https://duckdb.org/docs/sql/functions/overview
--   [3] DuckDB - Data Types
--       https://duckdb.org/docs/sql/data_types/overview

-- PRIMARY KEY
CREATE TABLE users (
    id BIGINT PRIMARY KEY
);
-- Composite primary key
CREATE TABLE order_items (
    order_id BIGINT NOT NULL,
    item_id  BIGINT NOT NULL,
    PRIMARY KEY (order_id, item_id)
);

-- UNIQUE
CREATE TABLE users (
    id    BIGINT PRIMARY KEY,
    email VARCHAR UNIQUE
);
-- Named unique constraint
CREATE TABLE users (
    id    BIGINT,
    email VARCHAR,
    UNIQUE (email)
);

-- NOT NULL
CREATE TABLE users (
    id       BIGINT NOT NULL,
    username VARCHAR NOT NULL,
    email    VARCHAR NOT NULL
);

-- DEFAULT
CREATE TABLE users (
    id         BIGINT PRIMARY KEY,
    status     INTEGER DEFAULT 1,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

-- CHECK
CREATE TABLE users (
    id  BIGINT PRIMARY KEY,
    age INTEGER CHECK (age >= 0 AND age <= 200)
);
-- Named check constraint
CREATE TABLE users (
    id  BIGINT PRIMARY KEY,
    age INTEGER,
    CONSTRAINT chk_age CHECK (age >= 0 AND age <= 200)
);
-- Multi-column check
CREATE TABLE events (
    start_date DATE,
    end_date   DATE,
    CHECK (end_date > start_date)
);

-- FOREIGN KEY (v0.8+, enforced)
CREATE TABLE orders (
    id      BIGINT PRIMARY KEY,
    user_id BIGINT REFERENCES users(id)
);
-- With actions
CREATE TABLE orders (
    id      BIGINT PRIMARY KEY,
    user_id BIGINT,
    FOREIGN KEY (user_id) REFERENCES users(id)
        ON DELETE CASCADE
        ON UPDATE CASCADE
);
-- Actions: CASCADE / SET NULL / SET DEFAULT / RESTRICT / NO ACTION

-- Composite foreign key
CREATE TABLE order_details (
    order_id BIGINT,
    item_id  BIGINT,
    FOREIGN KEY (order_id, item_id) REFERENCES order_items(order_id, item_id)
);

-- Generated columns as constraints
CREATE TABLE products (
    price    DECIMAL(10,2) NOT NULL CHECK (price > 0),
    quantity INTEGER NOT NULL CHECK (quantity >= 0),
    total    DECIMAL(10,2) GENERATED ALWAYS AS (price * quantity)
);

-- Note: DuckDB enforces PRIMARY KEY, UNIQUE, NOT NULL, CHECK, and FOREIGN KEY
-- Note: No EXCLUDE constraints (PostgreSQL-specific)
-- Note: No DEFERRABLE constraints
-- Note: No NOT VALID / VALIDATE CONSTRAINT (constraints are always validated)
-- Note: ALTER TABLE ADD CONSTRAINT supported for UNIQUE constraints (v0.8+)
-- Note: Some constraint types can only be defined at table creation time
