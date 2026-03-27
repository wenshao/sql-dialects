-- TiDB: Date Functions
-- TiDB is MySQL compatible; only differences from MySQL are shown here.
--
-- 参考资料:
--   [1] TiDB SQL Reference
--       https://docs.pingcap.com/tidb/stable/sql-statement-overview
--   [2] TiDB - MySQL Compatibility
--       https://docs.pingcap.com/tidb/stable/mysql-compatibility
--   [3] TiDB - Functions and Operators
--       https://docs.pingcap.com/tidb/stable/functions-and-operators-overview

-- All MySQL date functions are supported:
-- NOW, CURDATE, CURTIME, SYSDATE, UTC_TIMESTAMP
-- DATE_ADD, DATE_SUB, DATEDIFF, TIMESTAMPDIFF, TIMEDIFF
-- YEAR, MONTH, DAY, HOUR, MINUTE, SECOND, EXTRACT
-- DATE_FORMAT, STR_TO_DATE, MAKEDATE, MAKETIME
-- UNIX_TIMESTAMP, FROM_UNIXTIME
-- DAYOFWEEK, DAYOFYEAR, WEEKDAY, WEEK, LAST_DAY

-- Current time (same as MySQL)
SELECT NOW();
SELECT CURRENT_TIMESTAMP;
SELECT CURDATE();
SELECT CURTIME();
SELECT SYSDATE();
SELECT UTC_TIMESTAMP();

-- Date arithmetic (same as MySQL)
SELECT DATE_ADD('2024-01-15', INTERVAL 1 DAY);
SELECT DATE_ADD('2024-01-15', INTERVAL 3 MONTH);
SELECT DATE_SUB('2024-01-15', INTERVAL 1 YEAR);
SELECT '2024-01-15' + INTERVAL 7 DAY;

-- Date diff (same as MySQL)
SELECT DATEDIFF('2024-12-31', '2024-01-01');
SELECT TIMESTAMPDIFF(MONTH, '2024-01-01', '2024-06-15');
SELECT TIMESTAMPDIFF(HOUR, '2024-01-01 00:00:00', '2024-01-02 12:00:00');

-- Extract (same as MySQL)
SELECT YEAR('2024-01-15');
SELECT MONTH('2024-01-15');
SELECT DAY('2024-01-15');
SELECT EXTRACT(YEAR FROM '2024-01-15');

-- Formatting (same as MySQL)
SELECT DATE_FORMAT(NOW(), '%Y-%m-%d %H:%i:%s');
SELECT DATE_FORMAT(NOW(), '%W, %M %d, %Y');
SELECT STR_TO_DATE('2024-01-15', '%Y-%m-%d');

-- Unix timestamp (same as MySQL)
SELECT UNIX_TIMESTAMP();
SELECT UNIX_TIMESTAMP('2024-01-15');
SELECT FROM_UNIXTIME(1705276800);
SELECT FROM_UNIXTIME(1705276800, '%Y-%m-%d');

-- TiDB-specific: TSO-related time functions
-- TIDB_PARSE_TSO: convert TiDB timestamp oracle value to datetime
SELECT TIDB_PARSE_TSO(@@tidb_current_ts);

-- TIDB_BOUNDED_STALENESS: read data from a time range (5.0+)
-- Used with stale read feature for reading historical data
SELECT * FROM users AS OF TIMESTAMP TIDB_BOUNDED_STALENESS(
    NOW() - INTERVAL 5 SECOND,
    NOW()
);

-- Stale read: read historical data at a specific timestamp (5.1+)
SELECT * FROM users AS OF TIMESTAMP '2024-01-15 10:00:00';
SELECT * FROM users AS OF TIMESTAMP NOW() - INTERVAL 10 SECOND;

-- NOW() vs SYSDATE() in distributed context:
-- NOW(): fixed at statement start time, consistent across all nodes
-- SYSDATE(): actual execution time, may differ across TiDB nodes
-- Recommendation: use NOW() for consistency

-- Timezone-related
SET time_zone = '+08:00';
SELECT CONVERT_TZ('2024-01-15 10:00:00', '+00:00', '+08:00');

-- Limitations:
-- All MySQL date functions work identically
-- SYSDATE() may return slightly different times on different TiDB nodes
-- Timezone tables may need manual loading for named timezone support
-- AS OF TIMESTAMP for stale reads is TiDB-specific
-- TIDB_PARSE_TSO is TiDB-specific
