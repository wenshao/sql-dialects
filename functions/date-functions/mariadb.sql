-- MariaDB: Date Functions
-- MariaDB is a MySQL fork; only differences from MySQL are shown here.
--
-- 参考资料:
--   [1] MariaDB Knowledge Base
--       https://mariadb.com/kb/en/documentation/
--   [2] MariaDB vs MySQL Compatibility
--       https://mariadb.com/kb/en/mariadb-vs-mysql-compatibility/

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

-- ADD_MONTHS (10.6+, MariaDB-specific, Oracle-compatible)
-- Not available in MySQL
SELECT ADD_MONTHS('2024-01-31', 1);  -- '2024-02-29' (handles month-end correctly)
SELECT ADD_MONTHS('2024-01-15', -3); -- '2023-10-15'

-- System versioning date functions (10.3.4+)
-- Query historical data at a point in time
SELECT * FROM products FOR SYSTEM_TIME AS OF '2024-01-15 10:00:00';
SELECT * FROM products FOR SYSTEM_TIME
    BETWEEN '2024-01-01' AND '2024-06-01';
SELECT * FROM products FOR SYSTEM_TIME
    FROM '2024-01-01' TO '2024-06-01';
SELECT * FROM products FOR SYSTEM_TIME ALL;

-- TIMESTAMP type with system versioning
-- GENERATED ALWAYS AS ROW START / ROW END for versioning columns
-- These are implicitly managed by the system

-- FROM_DAYS / TO_DAYS (same as MySQL)
SELECT FROM_DAYS(730000);
SELECT TO_DAYS('2024-01-15');

-- LAST_DAY (same as MySQL)
SELECT LAST_DAY('2024-02-15');

-- Microsecond support (since MariaDB 5.3, earlier than MySQL 5.6.4)
SELECT NOW(6);
SELECT MICROSECOND(NOW(6));

-- SYSDATE() behavior:
-- MariaDB: SET sysdate_is_now = 1 makes SYSDATE() behave like NOW()
-- This is a MariaDB-specific optimization for replication safety

-- Differences from MySQL 8.0:
-- ADD_MONTHS function (10.6+, MariaDB-specific, Oracle-compatible)
-- FOR SYSTEM_TIME temporal queries (10.3.4+, MariaDB-specific)
-- Microsecond precision available since 5.3 (earlier than MySQL)
-- sysdate_is_now variable behavior may differ
-- Same date functions, same format specifiers
-- No functional differences in core date operations
