-- MariaDB: CREATE TABLE
-- MariaDB is a MySQL fork; only differences from MySQL are shown here.
--
-- 参考资料:
--   [1] MariaDB Knowledge Base
--       https://mariadb.com/kb/en/documentation/
--   [2] MariaDB vs MySQL Compatibility
--       https://mariadb.com/kb/en/mariadb-vs-mysql-compatibility/

-- Standard create (mostly identical to MySQL)
CREATE TABLE users (
    id         BIGINT       NOT NULL AUTO_INCREMENT,
    username   VARCHAR(64)  NOT NULL,
    email      VARCHAR(255) NOT NULL,
    age        INT,
    balance    DECIMAL(10,2) DEFAULT 0.00,
    bio        TEXT,
    created_at DATETIME     NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at DATETIME     NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
    PRIMARY KEY (id),
    UNIQUE KEY uk_username (username),
    UNIQUE KEY uk_email (email)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

-- INVISIBLE columns (10.3.3+): columns hidden from SELECT *
CREATE TABLE audit_events (
    id         BIGINT NOT NULL AUTO_INCREMENT,
    event      VARCHAR(255) NOT NULL,
    detail     TEXT,
    internal_flag TINYINT INVISIBLE DEFAULT 0,  -- not shown in SELECT *
    created_at DATETIME DEFAULT CURRENT_TIMESTAMP,
    PRIMARY KEY (id)
);
-- SELECT * won't include internal_flag; must explicitly: SELECT internal_flag FROM ...

-- Sequences (10.3+): Oracle-style sequences as an alternative to AUTO_INCREMENT
CREATE SEQUENCE seq_orders START WITH 1 INCREMENT BY 1 MINVALUE 1 CACHE 1000;
SELECT NEXT VALUE FOR seq_orders;           -- get next value
SELECT PREVIOUS VALUE FOR seq_orders;       -- get current value
DROP SEQUENCE seq_orders;

-- System-versioned (temporal) tables (10.3.4+)
-- Automatic row history tracking
CREATE TABLE products (
    id    BIGINT NOT NULL AUTO_INCREMENT,
    name  VARCHAR(255) NOT NULL,
    price DECIMAL(10,2) NOT NULL,
    PRIMARY KEY (id)
) WITH SYSTEM VERSIONING;

-- System versioning with explicit history columns
CREATE TABLE contracts (
    id         BIGINT NOT NULL AUTO_INCREMENT,
    client     VARCHAR(255),
    amount     DECIMAL(10,2),
    row_start  TIMESTAMP(6) GENERATED ALWAYS AS ROW START INVISIBLE,
    row_end    TIMESTAMP(6) GENERATED ALWAYS AS ROW END INVISIBLE,
    PERIOD FOR SYSTEM_TIME (row_start, row_end),
    PRIMARY KEY (id)
) WITH SYSTEM VERSIONING;

-- Query historical data
SELECT * FROM products FOR SYSTEM_TIME AS OF '2024-01-01';
SELECT * FROM products FOR SYSTEM_TIME BETWEEN '2024-01-01' AND '2024-06-01';
SELECT * FROM products FOR SYSTEM_TIME FROM '2024-01-01' TO '2024-06-01';
SELECT * FROM products FOR SYSTEM_TIME ALL;  -- all versions

-- WITHOUT OVERLAPS for period constraints (10.5.3+)
CREATE TABLE bookings (
    room_id    INT NOT NULL,
    start_date DATE NOT NULL,
    end_date   DATE NOT NULL,
    PERIOD FOR booking_period (start_date, end_date),
    UNIQUE (room_id, booking_period WITHOUT OVERLAPS)
);

-- CREATE OR REPLACE TABLE (MariaDB extension)
CREATE OR REPLACE TABLE temp_data (id INT, val VARCHAR(100));

-- IF NOT EXISTS (same as MySQL)
CREATE TABLE IF NOT EXISTS users (id BIGINT PRIMARY KEY);

-- Spider engine: built-in sharding (10.0+)
-- Distributes data across multiple MariaDB backend servers
CREATE TABLE sharded_orders (
    id     BIGINT NOT NULL AUTO_INCREMENT,
    amount DECIMAL(10,2),
    PRIMARY KEY (id)
) ENGINE=Spider
  COMMENT='wrapper "mysql", table "orders"'
  PARTITION BY HASH(id) (
    PARTITION p1 COMMENT = 'srv "shard1"',
    PARTITION p2 COMMENT = 'srv "shard2"'
);

-- CONNECT engine: access external data sources (CSV, JSON, XML, ODBC, etc.)
CREATE TABLE csv_data (
    id   INT NOT NULL,
    name VARCHAR(100),
    val  DOUBLE
) ENGINE=CONNECT TABLE_TYPE=CSV FILE_NAME='/data/input.csv' HEADER=1;

-- Limitations vs MySQL 8.0:
-- No CLONE plugin
-- No mysql_native_password deprecation (MariaDB keeps it)
-- Uses IGNORED/NOT IGNORED keywords for indexes instead of MySQL's INVISIBLE/VISIBLE (10.6+)
-- Different default authentication plugin
-- No MySQL 8.0 data dictionary (uses .frm files)
