-- MariaDB: Date/Time Types
-- MariaDB is a MySQL fork; only differences from MySQL are shown here.
--
-- 参考资料:
--   [1] MariaDB Knowledge Base
--       https://mariadb.com/kb/en/documentation/
--   [2] MariaDB vs MySQL Compatibility
--       https://mariadb.com/kb/en/mariadb-vs-mysql-compatibility/

-- All MySQL date/time types are supported:
-- DATE, TIME, DATETIME, TIMESTAMP, YEAR

CREATE TABLE events (
    id         BIGINT NOT NULL AUTO_INCREMENT PRIMARY KEY,
    event_date DATE,
    event_time TIME(3),
    created_at DATETIME(6),
    updated_at TIMESTAMP(6)
);

-- DATETIME vs TIMESTAMP (same as MySQL)
-- Range and behavior identical to MySQL

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

-- System-versioned tables: automatic row history timestamps (10.3.4+)
-- ROW START / ROW END columns for temporal tracking
CREATE TABLE products (
    id         BIGINT NOT NULL AUTO_INCREMENT,
    name       VARCHAR(255),
    price      DECIMAL(10,2),
    row_start  TIMESTAMP(6) GENERATED ALWAYS AS ROW START INVISIBLE,
    row_end    TIMESTAMP(6) GENERATED ALWAYS AS ROW END INVISIBLE,
    PERIOD FOR SYSTEM_TIME (row_start, row_end),
    PRIMARY KEY (id)
) WITH SYSTEM VERSIONING;

-- Query at a specific point in time
SELECT * FROM products FOR SYSTEM_TIME AS OF '2024-01-15 10:00:00';

-- Query history between two timestamps
SELECT * FROM products FOR SYSTEM_TIME
    BETWEEN '2024-01-01 00:00:00' AND '2024-06-01 00:00:00';

-- Application-time periods (10.5+)
-- PERIOD FOR user-defined temporal periods
CREATE TABLE contracts (
    id         BIGINT NOT NULL AUTO_INCREMENT,
    client     VARCHAR(255),
    amount     DECIMAL(10,2),
    valid_from DATE NOT NULL,
    valid_to   DATE NOT NULL,
    PERIOD FOR valid_period (valid_from, valid_to),
    PRIMARY KEY (id)
);

-- Temporal DML with FOR PORTION OF (10.5+)
UPDATE contracts FOR PORTION OF valid_period
    FROM '2024-01-01' TO '2024-06-01'
SET amount = 5000.00;

DELETE FROM contracts FOR PORTION OF valid_period
    FROM '2024-01-01' TO '2024-06-01'
WHERE client = 'Acme';

-- Date arithmetic (same as MySQL)
SELECT DATE_ADD(NOW(), INTERVAL 1 DAY);
SELECT DATE_SUB(NOW(), INTERVAL 1 HOUR);
SELECT DATEDIFF('2024-12-31', '2024-01-01');
SELECT TIMESTAMPDIFF(HOUR, '2024-01-01', NOW());

-- Date formatting (same as MySQL)
SELECT DATE_FORMAT(NOW(), '%Y-%m-%d %H:%i:%s');
SELECT STR_TO_DATE('2024-01-15', '%Y-%m-%d');

-- Unix timestamp (same as MySQL)
SELECT UNIX_TIMESTAMP();
SELECT FROM_UNIXTIME(1705276800);

-- Microsecond precision (same as MySQL, supported since 5.3)
-- MariaDB supported microsecond precision before MySQL 5.6.4

-- Differences from MySQL 8.0:
-- System versioning with ROW START/ROW END (10.3.4+, MariaDB-specific)
-- PERIOD FOR application-time periods (10.5+, MariaDB-specific)
-- FOR PORTION OF temporal DML (10.5+, MariaDB-specific)
-- FOR SYSTEM_TIME temporal queries (10.3.4+, MariaDB-specific)
-- Microsecond precision supported earlier than MySQL (5.3+)
-- Same TIMESTAMP 2038 limitation as MySQL
-- No functional differences in core date/time types vs MySQL
