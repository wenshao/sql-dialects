-- TiDB: Triggers
-- TiDB is MySQL compatible; only differences from MySQL are shown here.
--
-- 参考资料:
--   [1] TiDB SQL Reference
--       https://docs.pingcap.com/tidb/stable/sql-statement-overview
--   [2] TiDB - MySQL Compatibility
--       https://docs.pingcap.com/tidb/stable/mysql-compatibility
--   [3] TiDB - Functions and Operators
--       https://docs.pingcap.com/tidb/stable/functions-and-operators-overview

-- TRIGGERS ARE NOT SUPPORTED
-- TiDB does not support triggers at all
-- This is a fundamental limitation of the distributed architecture

-- The following MySQL trigger syntax will result in an error:

-- CREATE TRIGGER trg_users_before_insert     -- ERROR: not supported
-- BEFORE INSERT ON users
-- FOR EACH ROW
-- BEGIN
--     SET NEW.created_at = NOW();
-- END;

-- Workarounds for trigger-like behavior:

-- 1. Application-level logic
-- Move trigger logic to the application layer
-- Handle validation, default values, and audit logging in application code

-- 2. DEFAULT values (instead of BEFORE INSERT triggers for defaults)
CREATE TABLE users (
    id         BIGINT NOT NULL AUTO_RANDOM,
    username   VARCHAR(64) NOT NULL,
    created_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
    PRIMARY KEY (id)
);
-- DEFAULT CURRENT_TIMESTAMP and ON UPDATE CURRENT_TIMESTAMP replace
-- the most common BEFORE INSERT/UPDATE trigger use cases

-- 3. Generated columns (instead of triggers that compute values)
CREATE TABLE orders (
    id       BIGINT NOT NULL AUTO_RANDOM,
    price    DECIMAL(10,2),
    qty      INT,
    total    DECIMAL(10,2) AS (price * qty) STORED,  -- computed automatically
    PRIMARY KEY (id)
);

-- 4. CHECK constraints (instead of validation triggers)
ALTER TABLE users ADD CONSTRAINT chk_age CHECK (age >= 0 AND age <= 200);

-- 5. TiCDC (Change Data Capture, 4.0+)
-- Use TiCDC to capture row changes and process them asynchronously
-- Can replicate to Kafka, MySQL, or other TiDB clusters
-- Useful for audit logging, data synchronization, and event-driven architectures

-- 6. Application-level middleware
-- Use database middleware or ORM hooks for trigger-like behavior
-- Examples: Go's GORM hooks, Java's Hibernate interceptors

-- 7. Scheduled tasks for periodic operations
-- Instead of triggers that aggregate or maintain summary tables,
-- use scheduled batch jobs

-- Limitations:
-- No BEFORE INSERT / AFTER INSERT triggers
-- No BEFORE UPDATE / AFTER UPDATE triggers
-- No BEFORE DELETE / AFTER DELETE triggers
-- No INSTEAD OF triggers
-- No statement-level triggers
-- All trigger-like logic must be handled externally
-- TiCDC provides async change capture as a partial alternative
