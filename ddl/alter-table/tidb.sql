-- TiDB: ALTER TABLE
-- TiDB is MySQL compatible; only differences from MySQL are shown here.
--
-- 参考资料:
--   [1] TiDB SQL Reference
--       https://docs.pingcap.com/tidb/stable/sql-statement-overview
--   [2] TiDB - MySQL Compatibility
--       https://docs.pingcap.com/tidb/stable/mysql-compatibility
--   [3] TiDB - Functions and Operators
--       https://docs.pingcap.com/tidb/stable/functions-and-operators-overview

-- Basic column operations (same as MySQL)
ALTER TABLE users ADD COLUMN phone VARCHAR(20) AFTER email;
ALTER TABLE users MODIFY COLUMN phone VARCHAR(32) NOT NULL;
ALTER TABLE users DROP COLUMN phone;

-- TiDB supports most MySQL ALTER TABLE syntax, but execution differs:
-- All ALTER TABLE operations are online (non-blocking) by default
-- TiDB does NOT support ALGORITHM=INSTANT in most cases
-- DDL changes are applied asynchronously across the distributed cluster

-- Rename column (same as MySQL 8.0)
ALTER TABLE users RENAME COLUMN phone TO mobile;

-- Multi-schema change (6.2+): multiple DDL changes in one statement
ALTER TABLE users
    ADD COLUMN city VARCHAR(64),
    ADD COLUMN country VARCHAR(64),
    DROP COLUMN bio;

-- Set TiFlash replica for columnar analytics (4.0+)
ALTER TABLE users SET TIFLASH REPLICA 1;
ALTER TABLE users SET TIFLASH REPLICA 0;  -- remove TiFlash replica

-- Modify placement rules (6.0+)
ALTER TABLE users PLACEMENT POLICY = region_policy;
ALTER TABLE users PLACEMENT POLICY = DEFAULT;  -- remove placement policy

-- Partition management
ALTER TABLE events ADD PARTITION (
    PARTITION p2025 VALUES LESS THAN (2026)
);
ALTER TABLE events DROP PARTITION p2023;
ALTER TABLE events TRUNCATE PARTITION p2024;

-- Convert to/from partitioned table (6.1+)
ALTER TABLE users PARTITION BY HASH(id) PARTITIONS 16;
ALTER TABLE users REMOVE PARTITIONING;

-- Modify AUTO_RANDOM shard bits
-- Note: cannot change a table from AUTO_INCREMENT to AUTO_RANDOM or vice versa
-- after table creation

-- Change SHARD_ROW_ID_BITS
ALTER TABLE logs SHARD_ROW_ID_BITS = 6;

-- Character set conversion (same as MySQL)
ALTER TABLE users CONVERT TO CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;

-- Limitations:
-- ALGORITHM=INSTANT not generally supported (TiDB has its own online DDL)
-- ALTER TABLE ... ORDER BY not supported
-- Some column type changes may require full table rewrite
-- Concurrent DDL statements may queue (controlled by tidb_ddl_reorg_worker_cnt)
-- Adding/dropping indexes is online but may take time on large tables
-- Cannot change column type from one family to another in some cases
-- LOCK clause is parsed but ignored (DDL is always online)
