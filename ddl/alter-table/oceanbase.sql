-- OceanBase: ALTER TABLE
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

-- Basic column operations (same as MySQL)
ALTER TABLE users ADD COLUMN phone VARCHAR(20) AFTER email;
ALTER TABLE users MODIFY COLUMN phone VARCHAR(32) NOT NULL;
ALTER TABLE users CHANGE COLUMN phone mobile VARCHAR(32);
ALTER TABLE users DROP COLUMN phone;

-- Online DDL: OceanBase supports online schema changes
-- Most ALTER TABLE operations do not block DML
ALTER TABLE users ADD COLUMN city VARCHAR(64), ALGORITHM=INPLACE;

-- Modify locality (replica distribution)
ALTER TABLE users LOCALITY = 'F@zone1, F@zone2, R@zone3';

-- Modify primary zone
ALTER TABLE users PRIMARY_ZONE = 'zone1';

-- Change tablegroup
ALTER TABLE orders TABLEGROUP = tg_new;

-- Partition management
ALTER TABLE logs ADD PARTITION (
    PARTITION p2025 VALUES LESS THAN (2026)
);
ALTER TABLE logs DROP PARTITION p2023;
ALTER TABLE logs TRUNCATE PARTITION p2024;

-- Add subpartition (4.0+)
ALTER TABLE sales REORGANIZE PARTITION p2024 INTO (
    PARTITION p2024_h1 VALUES LESS THAN ('2024-07-01'),
    PARTITION p2024_h2 VALUES LESS THAN ('2025-01-01')
);

-- Convert non-partitioned table to partitioned (4.0+)
ALTER TABLE users PARTITION BY HASH(id) PARTITIONS 8;

-- Rename table
ALTER TABLE users RENAME TO members;
RENAME TABLE users TO members;

-- Modify default value
ALTER TABLE users ALTER COLUMN status SET DEFAULT 0;

-- Character set conversion
ALTER TABLE users CONVERT TO CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;

-- ============================================================
-- Oracle Mode
-- ============================================================

-- Add column
ALTER TABLE users ADD (phone VARCHAR2(20));

-- Modify column
ALTER TABLE users MODIFY (phone VARCHAR2(32) NOT NULL);

-- Rename column
ALTER TABLE users RENAME COLUMN phone TO mobile;

-- Drop column
ALTER TABLE users DROP COLUMN phone;

-- Add constraint
ALTER TABLE users ADD CONSTRAINT chk_age CHECK (age >= 0);

-- Partition management (Oracle mode)
ALTER TABLE events ADD PARTITION p2025 VALUES LESS THAN (TO_DATE('2026-01-01', 'YYYY-MM-DD'));
ALTER TABLE events DROP PARTITION p2023;
ALTER TABLE events TRUNCATE PARTITION p2024;

-- Limitations:
-- ALGORITHM=INSTANT not supported
-- Some column type changes require table recreation
-- Concurrent DDL may queue behind other DDL operations
-- ALTER TABLE ... ORDER BY not supported
