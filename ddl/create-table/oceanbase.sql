-- OceanBase: CREATE TABLE
-- OceanBase has dual mode: MySQL mode and Oracle mode. Both shown where relevant.
--
-- 参考资料:
--   [1] OceanBase SQL Reference (MySQL Mode)
--       https://www.oceanbase.com/docs/common-oceanbase-database-cn
--   [2] OceanBase SQL Reference (Oracle Mode)
--       https://www.oceanbase.com/docs/common-oceanbase-database-cn

-- ============================================================
-- MySQL Mode (MySQL 5.7/8.0 compatible syntax)
-- ============================================================

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
);

-- Tablegroup: co-locate tables on the same set of OBServer nodes
-- Improves join performance for related tables
CREATE TABLEGROUP tg_order;
CREATE TABLE orders (
    id      BIGINT NOT NULL AUTO_INCREMENT,
    user_id BIGINT NOT NULL,
    amount  DECIMAL(10,2),
    PRIMARY KEY (id)
) TABLEGROUP = tg_order;

-- Primary zone: control leader replica placement
CREATE TABLE hot_data (
    id   BIGINT NOT NULL AUTO_INCREMENT,
    data VARCHAR(256),
    PRIMARY KEY (id)
) PRIMARY_ZONE = 'zone1';

-- Locality: control replica distribution
ALTER TABLE users LOCALITY = 'F@zone1, F@zone2, R@zone3';
-- F = Full replica, R = Readonly replica

-- Partition by key (OceanBase extension)
CREATE TABLE big_table (
    id      BIGINT NOT NULL,
    name    VARCHAR(64),
    PRIMARY KEY (id)
) PARTITION BY KEY(id) PARTITIONS 16;

-- Key partition (supports non-integer columns like VARCHAR)
CREATE TABLE session_data (
    session_id VARCHAR(128) NOT NULL,
    data       TEXT,
    PRIMARY KEY (session_id)
) PARTITION BY KEY(session_id) PARTITIONS 8;

-- Range partition
CREATE TABLE logs (
    id         BIGINT NOT NULL AUTO_INCREMENT,
    log_date   DATE NOT NULL,
    message    TEXT,
    PRIMARY KEY (id, log_date)
) PARTITION BY RANGE(YEAR(log_date)) (
    PARTITION p2023 VALUES LESS THAN (2024),
    PARTITION p2024 VALUES LESS THAN (2025),
    PARTITION pmax  VALUES LESS THAN MAXVALUE
);

-- Range columns + subpartition (4.0+)
CREATE TABLE sales (
    id        BIGINT NOT NULL,
    region    VARCHAR(32) NOT NULL,
    sale_date DATE NOT NULL,
    amount    DECIMAL(10,2),
    PRIMARY KEY (id, region, sale_date)
) PARTITION BY RANGE COLUMNS(sale_date)
  SUBPARTITION BY KEY(region) SUBPARTITIONS 4 (
    PARTITION p2023 VALUES LESS THAN ('2024-01-01'),
    PARTITION p2024 VALUES LESS THAN ('2025-01-01')
);

-- ============================================================
-- Oracle Mode
-- ============================================================

-- Oracle mode uses Oracle-compatible syntax
CREATE TABLE users (
    id         NUMBER       NOT NULL,
    username   VARCHAR2(64) NOT NULL,
    email      VARCHAR2(255) NOT NULL,
    age        NUMBER(3),
    balance    NUMBER(10,2) DEFAULT 0.00,
    bio        CLOB,
    created_at TIMESTAMP    DEFAULT SYSTIMESTAMP NOT NULL,
    CONSTRAINT pk_users PRIMARY KEY (id),
    CONSTRAINT uk_username UNIQUE (username)
);

-- Oracle mode: sequence for auto-increment
CREATE SEQUENCE seq_users START WITH 1 INCREMENT BY 1;
-- Use: INSERT INTO users (id, ...) VALUES (seq_users.NEXTVAL, ...);

-- Oracle mode: partition by range
CREATE TABLE events (
    id         NUMBER NOT NULL,
    event_date DATE NOT NULL,
    data       CLOB
) PARTITION BY RANGE(event_date) (
    PARTITION p2023 VALUES LESS THAN (TO_DATE('2024-01-01', 'YYYY-MM-DD')),
    PARTITION p2024 VALUES LESS THAN (TO_DATE('2025-01-01', 'YYYY-MM-DD'))
);

-- Limitations:
-- FULLTEXT index: supported in 4.0+ (MySQL mode)
-- SPATIAL index: supported in 4.0+ (MySQL mode)
-- Foreign keys: fully supported and enforced
-- CHECK constraints: supported in 4.0+ (MySQL mode) and Oracle mode
