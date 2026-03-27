-- DuckDB: CREATE TABLE (v0.9+)
--
-- 参考资料:
--   [1] DuckDB - SQL Reference
--       https://duckdb.org/docs/sql/introduction
--   [2] DuckDB - Functions
--       https://duckdb.org/docs/sql/functions/overview
--   [3] DuckDB - Data Types
--       https://duckdb.org/docs/sql/data_types/overview

-- Basic table creation (PostgreSQL-compatible syntax)
CREATE TABLE users (
    id         BIGINT       PRIMARY KEY,
    username   VARCHAR(64)  NOT NULL UNIQUE,
    email      VARCHAR(255) NOT NULL UNIQUE,
    age        INTEGER,
    balance    DECIMAL(10,2) DEFAULT 0.00,
    bio        VARCHAR,
    created_at TIMESTAMP    NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP    NOT NULL DEFAULT CURRENT_TIMESTAMP
);

-- DuckDB has no auto-increment / SERIAL; use sequences or generate with row_number
CREATE SEQUENCE users_id_seq START 1;
CREATE TABLE users (
    id         BIGINT       DEFAULT nextval('users_id_seq') PRIMARY KEY,
    username   VARCHAR      NOT NULL
);

-- CREATE OR REPLACE (replaces if exists)
CREATE OR REPLACE TABLE users (
    id       BIGINT PRIMARY KEY,
    username VARCHAR NOT NULL
);

-- CREATE TABLE IF NOT EXISTS
CREATE TABLE IF NOT EXISTS users (
    id       BIGINT PRIMARY KEY,
    username VARCHAR NOT NULL
);

-- Create table from query (CTAS)
CREATE TABLE active_users AS
SELECT * FROM users WHERE status = 1;

-- Create table from CSV/Parquet auto-detection
CREATE TABLE sales AS SELECT * FROM read_csv_auto('sales.csv');
CREATE TABLE events AS SELECT * FROM read_parquet('events.parquet');
CREATE TABLE logs AS SELECT * FROM read_json_auto('logs.json');

-- Create table from multiple Parquet files (glob)
CREATE TABLE all_events AS SELECT * FROM read_parquet('data/events_*.parquet');

-- Temporary table (session-scoped)
CREATE TEMP TABLE tmp_results AS SELECT * FROM users WHERE age > 30;
CREATE TEMPORARY TABLE tmp_results (id BIGINT, name VARCHAR);

-- DuckDB-specific types: LIST, STRUCT, MAP, UNION
CREATE TABLE complex_data (
    id      BIGINT PRIMARY KEY,
    tags    VARCHAR[],                                -- LIST of strings
    scores  INTEGER[3],                               -- Fixed-size list
    address STRUCT(street VARCHAR, city VARCHAR, zip VARCHAR),
    meta    MAP(VARCHAR, VARCHAR),                     -- Key-value pairs
    value   UNION(i INTEGER, s VARCHAR, f FLOAT)       -- Tagged union
);

-- ENUM type
CREATE TYPE mood AS ENUM ('happy', 'sad', 'neutral');
CREATE TABLE diary (
    id    BIGINT,
    entry VARCHAR,
    mood  mood
);

-- Generated columns (v0.8+)
CREATE TABLE products (
    price    DECIMAL(10,2),
    quantity INTEGER,
    total    DECIMAL(10,2) GENERATED ALWAYS AS (price * quantity)
);

-- Note: DuckDB has no triggers for auto-updating updated_at
-- Note: DuckDB has no tablespaces, schemas are supported
-- Note: DuckDB is in-process, no server configuration needed
