-- MariaDB: String Types
-- MariaDB is a MySQL fork; only differences from MySQL are shown here.
--
-- 参考资料:
--   [1] MariaDB Knowledge Base
--       https://mariadb.com/kb/en/documentation/
--   [2] MariaDB vs MySQL Compatibility
--       https://mariadb.com/kb/en/mariadb-vs-mysql-compatibility/

-- All MySQL string types are supported:
-- CHAR(n), VARCHAR(n), TINYTEXT, TEXT, MEDIUMTEXT, LONGTEXT
-- BINARY(n), VARBINARY(n), TINYBLOB, BLOB, MEDIUMBLOB, LONGBLOB
-- ENUM, SET

CREATE TABLE examples (
    code       CHAR(10),
    name       VARCHAR(255),
    content    TEXT,
    big_data   LONGTEXT
);

-- Character sets and collations
-- MariaDB default charset: latin1 (until 10.6), utf8mb3 (10.6+)
-- MySQL 8.0 default: utf8mb4
-- Note: MariaDB 10.6+ changed default from latin1 to utf8mb3 (not utf8mb4!)
-- Explicit utf8mb4 recommended:
CREATE TABLE t (
    name VARCHAR(100) CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci
);

-- utf8mb3 vs utf8mb4:
-- MariaDB uses "utf8" as alias for utf8mb3 (3-byte UTF-8, no emoji support)
-- MySQL 8.0 uses "utf8" as alias for utf8mb4 (deprecated utf8mb3 alias)
-- In MariaDB: utf8 = utf8mb3; must explicitly use utf8mb4 for full Unicode

-- Collation differences:
-- MariaDB does NOT support utf8mb4_0900_ai_ci (MySQL 8.0 default)
-- MariaDB has its own collations: utf8mb4_uca1400_ai_ci (10.10+)
-- uca1400 collations based on Unicode 14.0 (MariaDB-specific)
CREATE TABLE t (
    name VARCHAR(100) COLLATE utf8mb4_uca1400_ai_ci  -- 10.10+
);

-- INET4 and INET6 types (10.10+, MariaDB-specific)
-- Native IP address storage types, not available in MySQL
CREATE TABLE servers (
    id   BIGINT NOT NULL AUTO_INCREMENT,
    ipv4 INET4,           -- 4 bytes, stores IPv4 address
    ipv6 INET6,           -- 16 bytes, stores IPv6 address (also accepts IPv4)
    PRIMARY KEY (id)
);
INSERT INTO servers (ipv4, ipv6) VALUES ('192.168.1.1', '::ffff:192.168.1.1');
SELECT * FROM servers WHERE ipv4 = '192.168.1.1';

-- UUID type (10.7+, MariaDB-specific)
-- Native UUID storage, more efficient than VARCHAR(36)
CREATE TABLE sessions (
    id   UUID DEFAULT UUID(),
    data TEXT
);

-- ENUM and SET (same as MySQL)
CREATE TABLE t (
    status ENUM('active', 'inactive', 'deleted'),
    tags   SET('tag1', 'tag2', 'tag3')
);

-- Oracle-compatible types (when sql_mode includes ORACLE)
-- VARCHAR2, CLOB, RAW available in Oracle-compatible sql_mode
-- SET sql_mode = 'ORACLE';

-- Differences from MySQL 8.0:
-- Default charset: utf8mb3 in 10.6+ (MySQL 8.0 uses utf8mb4)
-- "utf8" alias: utf8mb3 in MariaDB, utf8mb4 in MySQL 8.0
-- utf8mb4_0900_ai_ci NOT available (use utf8mb4_uca1400_ai_ci in 10.10+)
-- INET4, INET6 native types (MariaDB-specific, 10.10+)
-- UUID native type (MariaDB-specific, 10.7+)
-- uca1400 collation series (MariaDB-specific, 10.10+)
