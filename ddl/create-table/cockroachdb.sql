-- CockroachDB: CREATE TABLE (v23.1+)
--
-- 参考资料:
--   [1] CockroachDB - SQL Statements
--       https://www.cockroachlabs.com/docs/stable/sql-statements
--   [2] CockroachDB - Functions and Operators
--       https://www.cockroachlabs.com/docs/stable/functions-and-operators
--   [3] CockroachDB - Data Types
--       https://www.cockroachlabs.com/docs/stable/data-types

-- CockroachDB is PostgreSQL wire-compatible
-- Most PostgreSQL CREATE TABLE syntax works directly

-- Basic table creation (same as PostgreSQL)
CREATE TABLE users (
    id         UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    username   VARCHAR(100) NOT NULL,
    email      VARCHAR(255) NOT NULL UNIQUE,
    age        INT,
    balance    DECIMAL(10,2),
    bio        TEXT,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- SERIAL uses unique_rowid() (not sequences like PostgreSQL)
CREATE TABLE orders (
    id         SERIAL PRIMARY KEY,             -- uses unique_rowid(), not auto-increment
    user_id    UUID NOT NULL REFERENCES users (id),
    amount     DECIMAL(10,2),
    order_date DATE NOT NULL DEFAULT CURRENT_DATE
);
-- Note: SERIAL generates unique_rowid() (64-bit, time-ordered, node-unique)
-- Unlike PostgreSQL, no sequence is created

-- INT8 DEFAULT unique_rowid() is equivalent to SERIAL
CREATE TABLE items (
    id   INT8 PRIMARY KEY DEFAULT unique_rowid(),
    name VARCHAR(100)
);

-- UUID primary keys (recommended for distributed tables)
CREATE TABLE products (
    id         UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    name       VARCHAR(255) NOT NULL,
    price      DECIMAL(10,2),
    category   VARCHAR(50)
);

-- Hash-sharded indexes (to avoid write hotspots on sequential keys)
CREATE TABLE events (
    id         UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    ts         TIMESTAMPTZ NOT NULL DEFAULT now(),
    event_type VARCHAR(50),
    data       JSONB,
    INDEX idx_events_ts (ts) USING HASH
);

-- Multi-region table (v21.1+)
-- Requires a multi-region database:
-- ALTER DATABASE mydb SET PRIMARY REGION 'us-east1';
-- ALTER DATABASE mydb ADD REGION 'us-west1';
-- ALTER DATABASE mydb ADD REGION 'eu-west1';
CREATE TABLE regional_users (
    id         UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    username   VARCHAR(100),
    region     crdb_internal_region NOT NULL DEFAULT gateway_region()::crdb_internal_region,
    email      VARCHAR(255)
) LOCALITY REGIONAL BY ROW;

-- GLOBAL table (optimized for low-latency reads from any region)
CREATE TABLE countries (
    code VARCHAR(2) PRIMARY KEY,
    name VARCHAR(100)
) LOCALITY GLOBAL;

-- REGIONAL BY TABLE (pin table to a specific region)
CREATE TABLE us_orders (
    id     UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    amount DECIMAL(10,2)
) LOCALITY REGIONAL BY TABLE IN PRIMARY REGION;

-- CREATE TABLE AS SELECT
CREATE TABLE users_backup AS
SELECT * FROM users WHERE created_at > '2024-01-01';

-- IF NOT EXISTS
CREATE TABLE IF NOT EXISTS users (
    id       UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    username VARCHAR(100)
);

-- Computed columns (same as PostgreSQL GENERATED ALWAYS AS)
CREATE TABLE products_v2 (
    id         UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    price      DECIMAL(10,2),
    tax_rate   DECIMAL(5,4),
    total      DECIMAL(10,2) GENERATED ALWAYS AS (price * (1 + tax_rate)) STORED
);

-- ARRAY and JSONB columns (same as PostgreSQL)
CREATE TABLE profiles (
    id       UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    tags     TEXT[],
    metadata JSONB
);

-- Column families (CockroachDB-specific: group columns for storage optimization)
CREATE TABLE wide_table (
    id    UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    name  VARCHAR(100),
    data  BYTES,
    FAMILY f_main (id, name),
    FAMILY f_data (data)
);

-- Note: CockroachDB does not support UNLOGGED tables
-- Note: CockroachDB does not support TEMPORARY tables (until v22.1)
-- Note: CockroachDB does not support table inheritance (INHERITS)
-- Note: CockroachDB does not support tablespaces (storage is distributed)
-- Note: Prefer UUID over SERIAL for distributed workloads
