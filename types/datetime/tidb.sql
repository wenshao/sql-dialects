-- TiDB: Date/Time Types
-- TiDB is MySQL compatible; only differences from MySQL are shown here.
--
-- 参考资料:
--   [1] TiDB SQL Reference
--       https://docs.pingcap.com/tidb/stable/sql-statement-overview
--   [2] TiDB - MySQL Compatibility
--       https://docs.pingcap.com/tidb/stable/mysql-compatibility
--   [3] TiDB - Functions and Operators
--       https://docs.pingcap.com/tidb/stable/functions-and-operators-overview

-- All MySQL date/time types are supported:
-- DATE, TIME, DATETIME, TIMESTAMP, YEAR

CREATE TABLE events (
    id         BIGINT NOT NULL AUTO_RANDOM PRIMARY KEY,
    event_date DATE,
    event_time TIME(3),
    created_at DATETIME(6),
    updated_at TIMESTAMP(6)
);

-- DATETIME vs TIMESTAMP (same behavior as MySQL)
-- DATETIME: 8 bytes, no timezone conversion, range 1000-01-01 ~ 9999-12-31
-- TIMESTAMP: 4 bytes, stored as UTC, auto timezone conversion, 1970-01-01 ~ 2038-01-19

-- Current time functions (same as MySQL)
SELECT NOW();
SELECT CURRENT_TIMESTAMP;
SELECT CURDATE();
SELECT CURTIME();
SELECT UTC_TIMESTAMP();

-- ON UPDATE CURRENT_TIMESTAMP (same as MySQL)
CREATE TABLE t (
    updated_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP
);

-- Microsecond precision (same as MySQL)
SELECT NOW(6);  -- with microseconds

-- Timezone handling
-- TiDB supports per-session timezone
SET time_zone = '+08:00';
SET time_zone = 'Asia/Shanghai';  -- requires timezone tables loaded

-- TIMESTAMP behavior in distributed context:
-- All TiDB servers should use the same timezone configuration
-- TIMESTAMP values are stored as UTC in TiKV
-- Timezone conversion happens at the TiDB server layer

-- TSO (Timestamp Oracle):
-- TiDB uses a global timestamp oracle (TSO) for transaction ordering
-- TSO is a monotonically increasing timestamp from the PD server
-- This is different from MySQL's wall-clock based timestamps
SELECT TIDB_PARSE_TSO(@@tidb_current_ts);  -- convert TSO to human-readable time

-- Date arithmetic (same as MySQL)
SELECT DATE_ADD(NOW(), INTERVAL 1 DAY);
SELECT DATE_SUB(NOW(), INTERVAL 1 HOUR);
SELECT DATEDIFF('2024-12-31', '2024-01-01');
SELECT TIMESTAMPDIFF(HOUR, '2024-01-01', NOW());

-- Date formatting (same as MySQL)
SELECT DATE_FORMAT(NOW(), '%Y-%m-%d %H:%i:%s');
SELECT STR_TO_DATE('2024-01-15', '%Y-%m-%d');

-- Limitations:
-- Same TIMESTAMP 2038 limit as MySQL
-- Timezone must be consistently configured across all TiDB instances
-- Timezone tables (mysql.time_zone_*) may need manual loading
-- SYSDATE() returns actual execution time (same as MySQL, but may vary
--   slightly across distributed execution)
-- No functional differences in date/time types vs MySQL
