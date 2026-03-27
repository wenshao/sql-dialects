-- OceanBase: Indexes
-- OceanBase has dual mode: MySQL mode and Oracle mode. Both shown where relevant.
--
-- 参考资料:
--   [1] OceanBase SQL Reference (MySQL Mode)
--       https://www.oceanbase.com/docs/common-oceanbase-database-cn
--   [2] OceanBase SQL Reference (Oracle Mode)
--       https://www.oceanbase.com/docs/common-oceanbase-database-cn

-- ============================================================
-- MySQL Mode
-- ============================================================

-- Basic indexes (same as MySQL)
CREATE INDEX idx_age ON users (age);
CREATE UNIQUE INDEX uk_email ON users (email);
CREATE INDEX idx_city_age ON users (city, age);

-- Prefix index (same as MySQL)
CREATE INDEX idx_email_prefix ON users (email(20));

-- Descending index
CREATE INDEX idx_created_desc ON orders (user_id ASC, created_at DESC);

-- Fulltext index (4.0+)
CREATE FULLTEXT INDEX idx_ft_bio ON users (bio);

-- Global vs Local index on partitioned tables
-- Local index: each partition has its own index (default)
CREATE INDEX idx_local ON logs (message) LOCAL;
-- Global index: single index spanning all partitions
CREATE INDEX idx_global ON logs (user_id) GLOBAL;
-- Global index avoids scanning all partitions for non-partition-key queries

-- Spatial index (4.0+, MySQL mode)
CREATE SPATIAL INDEX idx_location ON places (geo_point);

-- Function-based index (4.0+)
CREATE INDEX idx_upper_name ON users ((UPPER(username)));

-- Index on partitioned table with specific partition storage
CREATE INDEX idx_status ON logs (status)
    GLOBAL PARTITION BY HASH(status) PARTITIONS 4;

-- Online index creation (non-blocking)
ALTER TABLE users ADD INDEX idx_city (city);

-- Drop index
DROP INDEX idx_age ON users;

-- View indexes
SHOW INDEX FROM users;

-- ============================================================
-- Oracle Mode
-- ============================================================

-- Standard index
CREATE INDEX idx_age ON users (age);

-- Unique index
CREATE UNIQUE INDEX uk_email ON users (email);

-- Composite index
CREATE INDEX idx_city_age ON users (city, age);

-- Function-based index
CREATE INDEX idx_upper_name ON users (UPPER(username));

-- Local index (partition-level)
CREATE INDEX idx_local ON events (event_date) LOCAL;

-- Global index
CREATE INDEX idx_global ON events (id) GLOBAL;

-- Reverse key index (Oracle compatible)
-- Reverses bytes of indexed column to distribute sequential values
CREATE INDEX idx_id_rev ON orders (id) REVERSE;

-- Drop index (Oracle syntax)
DROP INDEX idx_age;

-- Rebuild index
ALTER INDEX idx_age REBUILD;

-- Limitations:
-- HASH index type (USING HASH) not supported
-- Invisible indexes supported in 4.0+ (MySQL mode)
-- Index creation is online but performance impact during creation
-- Global indexes have higher maintenance cost but better query performance
