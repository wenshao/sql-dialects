-- TiDB: CREATE TABLE
-- TiDB is MySQL compatible; only differences from MySQL are shown here.
--
-- 参考资料:
--   [1] TiDB SQL Reference
--       https://docs.pingcap.com/tidb/stable/sql-statement-overview
--   [2] TiDB - MySQL Compatibility
--       https://docs.pingcap.com/tidb/stable/mysql-compatibility
--   [3] TiDB - Functions and Operators
--       https://docs.pingcap.com/tidb/stable/functions-and-operators-overview

-- AUTO_RANDOM: distributed alternative to AUTO_INCREMENT (3.1+)
-- Avoids write hotspot on single TiKV region by randomizing high bits of ID
CREATE TABLE users (
    id         BIGINT       NOT NULL AUTO_RANDOM,
    username   VARCHAR(64)  NOT NULL,
    email      VARCHAR(255) NOT NULL,
    age        INT,
    balance    DECIMAL(10,2) DEFAULT 0.00,
    bio        TEXT,
    created_at DATETIME     NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at DATETIME     NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
    PRIMARY KEY (id) CLUSTERED,
    UNIQUE KEY uk_username (username),
    UNIQUE KEY uk_email (email)
);

-- AUTO_RANDOM with shard bits (default 5 bits = 32 shards)
CREATE TABLE orders (
    id BIGINT NOT NULL AUTO_RANDOM(5),
    PRIMARY KEY (id)
);

-- SHARD_ROW_ID_BITS: shard implicit _tidb_rowid for tables without integer PK
-- Distributes writes across regions (reduces hotspot)
CREATE TABLE logs (
    ts      DATETIME NOT NULL,
    message TEXT
) SHARD_ROW_ID_BITS = 4 PRE_SPLIT_REGIONS = 3;

-- Clustered vs Non-Clustered index (5.0+)
-- CLUSTERED: row data stored in PK index (like InnoDB)
-- NONCLUSTERED: separate hidden _tidb_rowid, PK is secondary index
CREATE TABLE accounts (
    id   BIGINT NOT NULL,
    name VARCHAR(64),
    PRIMARY KEY (id) NONCLUSTERED
);

-- Placement rules: control data location across regions/zones (6.0+)
CREATE TABLE sensitive_data (
    id   BIGINT NOT NULL AUTO_RANDOM,
    data TEXT,
    PRIMARY KEY (id)
) PLACEMENT POLICY = us_east_policy;

-- Create placement policy
CREATE PLACEMENT POLICY us_east_policy
    PRIMARY_REGION = "us-east-1"
    REGIONS = "us-east-1,us-east-2"
    FOLLOWERS = 2;

-- TiFlash replica: columnar store for analytical queries (4.0+)
ALTER TABLE users SET TIFLASH REPLICA 1;

-- Partitioned table (same MySQL syntax, but distributes across TiKV regions)
CREATE TABLE events (
    id         BIGINT NOT NULL AUTO_RANDOM,
    event_date DATE NOT NULL,
    data       JSON,
    PRIMARY KEY (id, event_date)
) PARTITION BY RANGE (YEAR(event_date)) (
    PARTITION p2023 VALUES LESS THAN (2024),
    PARTITION p2024 VALUES LESS THAN (2025),
    PARTITION pmax  VALUES LESS THAN MAXVALUE
);

-- Temporary table (5.3+, both local and global temporary tables)
CREATE TEMPORARY TABLE temp_result (id BIGINT, val INT);
-- Global temporary table (5.3+)
CREATE GLOBAL TEMPORARY TABLE temp_session (
    id BIGINT, val INT
) ON COMMIT DELETE ROWS;

-- Limitations:
-- ENGINE is accepted but ignored (always uses TiKV storage)
-- FULLTEXT indexes not supported
-- SPATIAL indexes not supported
-- Generated columns supported (5.0+) but with some expression limitations
-- Foreign keys parsed but NOT enforced before 6.6.0
-- Foreign keys enforced starting from 6.6.0 (experimental)
