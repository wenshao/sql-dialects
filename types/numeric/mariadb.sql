-- MariaDB: Numeric Types
-- MariaDB is a MySQL fork; only differences from MySQL are shown here.
--
-- 参考资料:
--   [1] MariaDB Knowledge Base
--       https://mariadb.com/kb/en/documentation/
--   [2] MariaDB vs MySQL Compatibility
--       https://mariadb.com/kb/en/mariadb-vs-mysql-compatibility/

-- All MySQL numeric types are supported:
-- TINYINT, SMALLINT, MEDIUMINT, INT, BIGINT
-- FLOAT, DOUBLE
-- DECIMAL/NUMERIC
-- BIT(M)
-- BOOL/BOOLEAN

CREATE TABLE examples (
    tiny_val   TINYINT,
    small_val  SMALLINT,
    int_val    INT,
    big_val    BIGINT,
    pos_val    INT UNSIGNED,
    flag       TINYINT(1)
);

-- BOOL/BOOLEAN (same as MySQL)
CREATE TABLE t (active BOOLEAN DEFAULT TRUE);

-- DECIMAL (same as MySQL)
CREATE TABLE prices (
    price    DECIMAL(10,2),
    rate     DECIMAL(5,4)
);

-- Display width: INT(11) style display width
-- MariaDB has NOT deprecated display width (MySQL 8.0.17 deprecated it)
-- INT(11), INT(5), etc. still work and are not warned about
CREATE TABLE t (
    val INT(5) ZEROFILL      -- zero-padded display (still functional in MariaDB)
);

-- UNSIGNED: not deprecated for any type
-- MySQL 8.0.17 deprecated UNSIGNED on FLOAT/DOUBLE/DECIMAL
-- MariaDB has NOT deprecated it
CREATE TABLE t (
    val FLOAT UNSIGNED        -- no deprecation warning in MariaDB
);

-- FLOAT(M,D) / DOUBLE(M,D): not deprecated
-- MySQL 8.0.17 deprecated this syntax; MariaDB keeps it
CREATE TABLE t (
    val FLOAT(10,2)           -- still valid in MariaDB, no warning
);

-- AUTO_INCREMENT (same as MySQL)
CREATE TABLE t (id BIGINT NOT NULL AUTO_INCREMENT PRIMARY KEY);
-- MariaDB auto-increment is always persistent (not affected by MySQL 8.0 bug fix)

-- Sequences (10.3+): alternative to AUTO_INCREMENT
-- Not available in MySQL
CREATE SEQUENCE seq_id START WITH 1 INCREMENT BY 1
    MINVALUE 1 MAXVALUE 9999999999 CACHE 1000 CYCLE;

SELECT NEXT VALUE FOR seq_id;       -- get next value
SELECT PREVIOUS VALUE FOR seq_id;   -- get current value (MariaDB-specific)
SELECT NEXTVAL(seq_id);             -- alternative syntax (10.3+)
SELECT LASTVAL(seq_id);             -- alternative syntax (10.3+)

-- Sequence as DEFAULT
CREATE TABLE orders (
    id     BIGINT DEFAULT (NEXT VALUE FOR seq_id),
    amount DECIMAL(10,2)
);

-- BIT type (same as MySQL)
CREATE TABLE t (flags BIT(8));

-- Differences from MySQL 8.0:
-- Display width (INT(11)) not deprecated (MySQL deprecated in 8.0.17)
-- UNSIGNED on FLOAT/DOUBLE/DECIMAL not deprecated
-- FLOAT(M,D) / DOUBLE(M,D) syntax not deprecated
-- Sequences (10.3+) as alternative to AUTO_INCREMENT
-- PREVIOUS VALUE FOR / LASTVAL() for sequences (not in MySQL)
-- Auto-increment persistence was never an issue (MySQL fixed in 8.0)
