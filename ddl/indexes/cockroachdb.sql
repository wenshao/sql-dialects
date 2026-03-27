-- CockroachDB: Indexes (v23.1+)
--
-- 参考资料:
--   [1] CockroachDB - SQL Statements
--       https://www.cockroachlabs.com/docs/stable/sql-statements
--   [2] CockroachDB - Functions and Operators
--       https://www.cockroachlabs.com/docs/stable/functions-and-operators
--   [3] CockroachDB - Data Types
--       https://www.cockroachlabs.com/docs/stable/data-types

-- CockroachDB supports PostgreSQL-compatible indexes
-- Key difference: hash-sharded indexes to avoid hotspots

-- ============================================================
-- Standard indexes (B-tree, default)
-- ============================================================

CREATE INDEX idx_users_email ON users (email);
CREATE INDEX IF NOT EXISTS idx_users_email ON users (email);

-- Unique index
CREATE UNIQUE INDEX idx_users_email_uniq ON users (email);

-- Multi-column index
CREATE INDEX idx_users_city_age ON users (city, age);

-- Descending index
CREATE INDEX idx_users_age_desc ON users (age DESC);

-- Partial index (same as PostgreSQL)
CREATE INDEX idx_active_users ON users (username) WHERE status = 1;

-- Covering index (STORING / INCLUDE, same as PostgreSQL)
CREATE INDEX idx_users_email_cover ON users (email) STORING (username, age);
-- STORING is CockroachDB preferred syntax (INCLUDE also works)

-- Expression index
CREATE INDEX idx_users_lower_email ON users (lower(email));
CREATE INDEX idx_users_jsonb_name ON users ((metadata->>'name'));

-- ============================================================
-- Hash-sharded indexes (CockroachDB-specific)
-- ============================================================

-- Prevents write hotspots on sequential keys
CREATE INDEX idx_events_ts ON events (ts) USING HASH;

-- Hash-sharded with bucket count
CREATE INDEX idx_events_ts_sharded ON events (ts) USING HASH WITH (bucket_count = 8);

-- Hash-sharded primary key
CREATE TABLE timeseries (
    ts   TIMESTAMPTZ NOT NULL,
    data JSONB,
    PRIMARY KEY (ts) USING HASH
);

-- ============================================================
-- GIN indexes (for JSONB, arrays, full-text)
-- ============================================================

-- JSONB inverted index
CREATE INVERTED INDEX idx_metadata ON users (metadata);
-- Or PostgreSQL-compatible syntax:
CREATE INDEX idx_metadata_gin ON users USING GIN (metadata);

-- Array inverted index
CREATE INVERTED INDEX idx_tags ON users (tags);

-- Partial inverted index
CREATE INVERTED INDEX idx_active_metadata ON users (metadata) WHERE status = 1;

-- Multi-column inverted index (v21.2+)
CREATE INVERTED INDEX idx_type_metadata ON users (user_type, metadata);

-- ============================================================
-- Spatial indexes (v20.2+)
-- ============================================================

CREATE INDEX idx_location ON places USING GIST (location);

-- ============================================================
-- Trigram indexes (v22.2+)
-- ============================================================

-- Requires pg_trgm extension
-- SET CLUSTER SETTING sql.defaults.extension_schema = 'public';
CREATE INDEX idx_trgm_name ON users USING GIN (username gin_trgm_ops);

-- ============================================================
-- Index management
-- ============================================================

-- Drop index
DROP INDEX idx_users_email;
DROP INDEX IF EXISTS idx_users_email;

-- Rename index
ALTER INDEX idx_users_email RENAME TO idx_email;

-- Configure zone for index (placement/replication)
ALTER INDEX idx_users_email CONFIGURE ZONE USING num_replicas = 5;

-- Make index not visible (v22.2+)
ALTER INDEX idx_users_email NOT VISIBLE;
ALTER INDEX idx_users_email VISIBLE;

-- Show indexes
SHOW INDEXES FROM users;
SHOW INDEX FROM users;

-- Note: All indexes are distributed across nodes
-- Note: USING HASH prevents sequential key hotspots (most impactful optimization)
-- Note: STORING stores extra columns in index to avoid table lookups
-- Note: CockroachDB uses INVERTED INDEX instead of GIN for JSONB/arrays
-- Note: Index creation is online and non-blocking
-- Note: No BRIN, HASH (PostgreSQL-style), or SP-GiST index types
