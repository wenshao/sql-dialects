-- MariaDB: ALTER TABLE
-- MariaDB is a MySQL fork; only differences from MySQL are shown here.
--
-- 参考资料:
--   [1] MariaDB Knowledge Base
--       https://mariadb.com/kb/en/documentation/
--   [2] MariaDB vs MySQL Compatibility
--       https://mariadb.com/kb/en/mariadb-vs-mysql-compatibility/

-- Basic column operations (same as MySQL)
ALTER TABLE users ADD COLUMN phone VARCHAR(20) AFTER email;
ALTER TABLE users MODIFY COLUMN phone VARCHAR(32) NOT NULL;
ALTER TABLE users CHANGE COLUMN phone mobile VARCHAR(32);
ALTER TABLE users DROP COLUMN phone;

-- IF EXISTS / IF NOT EXISTS (10.0+, earlier than MySQL 8.0)
ALTER TABLE users ADD COLUMN IF NOT EXISTS phone VARCHAR(20);
ALTER TABLE users DROP COLUMN IF EXISTS phone;
ALTER TABLE users MODIFY COLUMN IF EXISTS phone VARCHAR(32);

-- INSTANT column operations (10.3.2+)
-- MariaDB supported INSTANT ADD COLUMN before MySQL 8.0.12
ALTER TABLE users ADD COLUMN tag VARCHAR(32), ALGORITHM=INSTANT;

-- INSTANT DROP COLUMN (10.4+): instant metadata-only drop
-- Column data cleaned up lazily during subsequent operations
ALTER TABLE users DROP COLUMN tag, ALGORITHM=INSTANT;

-- Rename column (10.5.2+, same as MySQL 8.0)
ALTER TABLE users RENAME COLUMN phone TO mobile;

-- System versioning: add/remove versioning
ALTER TABLE products ADD SYSTEM VERSIONING;
ALTER TABLE products DROP SYSTEM VERSIONING;

-- Add period and versioning columns explicitly
ALTER TABLE contracts
    ADD COLUMN row_start TIMESTAMP(6) GENERATED ALWAYS AS ROW START INVISIBLE,
    ADD COLUMN row_end   TIMESTAMP(6) GENERATED ALWAYS AS ROW END INVISIBLE,
    ADD PERIOD FOR SYSTEM_TIME (row_start, row_end),
    ADD SYSTEM VERSIONING;

-- INVISIBLE columns (10.3.3+)
ALTER TABLE users ADD COLUMN internal_note TEXT INVISIBLE;
ALTER TABLE users MODIFY COLUMN internal_note TEXT VISIBLE;

-- ADD PERIOD FOR (10.5+): application-time periods
ALTER TABLE bookings ADD PERIOD FOR booking_period (start_date, end_date);

-- WITHOUT OVERLAPS constraint (10.5.3+)
ALTER TABLE bookings ADD UNIQUE (room_id, booking_period WITHOUT OVERLAPS);

-- ALGORITHM options: DEFAULT, COPY, INPLACE, INSTANT, NOCOPY
-- NOCOPY (10.3.7+): MariaDB-specific, allows changes that don't touch row data
ALTER TABLE users MODIFY COLUMN age INT DEFAULT 0, ALGORITHM=NOCOPY;

-- LOCK options (same as MySQL): DEFAULT, NONE, SHARED, EXCLUSIVE

-- Partition management (same as MySQL)
ALTER TABLE logs ADD PARTITION (PARTITION p2025 VALUES LESS THAN (2026));
ALTER TABLE logs DROP PARTITION p2023;

-- Convert to partitioned
ALTER TABLE users PARTITION BY HASH(id) PARTITIONS 8;

-- Rename table
ALTER TABLE users RENAME TO members;

-- Differences from MySQL 8.0:
-- INSTANT DROP COLUMN supported (MySQL 8.0.29+ only started supporting this)
-- NOCOPY algorithm is MariaDB-specific
-- System versioning ALTER operations are MariaDB-specific
-- IF EXISTS on MODIFY COLUMN (MariaDB-specific)
-- Uses IGNORED/NOT IGNORED instead of MySQL 8.0's INVISIBLE/VISIBLE index syntax
