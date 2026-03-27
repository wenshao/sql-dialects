-- MariaDB: 表分区策略
--
-- 参考资料:
--   [1] MariaDB Documentation - Partitioning
--       https://mariadb.com/kb/en/partitioning/
--   [2] MariaDB Documentation - Partition Maintenance
--       https://mariadb.com/kb/en/partition-maintenance/

-- ============================================================
-- RANGE 分区
-- ============================================================

CREATE TABLE orders (
    id BIGINT AUTO_INCREMENT,
    user_id BIGINT, amount DECIMAL(10,2), order_date DATE,
    PRIMARY KEY (id, order_date)
) PARTITION BY RANGE (YEAR(order_date)) (
    PARTITION p2023 VALUES LESS THAN (2024),
    PARTITION p2024 VALUES LESS THAN (2025),
    PARTITION p2025 VALUES LESS THAN (2026),
    PARTITION pmax  VALUES LESS THAN MAXVALUE
);

-- RANGE COLUMNS
CREATE TABLE logs (
    id BIGINT AUTO_INCREMENT, log_date DATE, message TEXT,
    PRIMARY KEY (id, log_date)
) PARTITION BY RANGE COLUMNS(log_date) (
    PARTITION p202401 VALUES LESS THAN ('2024-02-01'),
    PARTITION p202402 VALUES LESS THAN ('2024-03-01'),
    PARTITION pmax    VALUES LESS THAN (MAXVALUE)
);

-- ============================================================
-- LIST 分区
-- ============================================================

CREATE TABLE users_region (
    id BIGINT AUTO_INCREMENT, username VARCHAR(100), region VARCHAR(20),
    PRIMARY KEY (id, region)
) PARTITION BY LIST COLUMNS(region) (
    PARTITION p_east  VALUES IN ('Shanghai', 'Hangzhou'),
    PARTITION p_north VALUES IN ('Beijing', 'Tianjin'),
    PARTITION p_other VALUES IN (DEFAULT)  -- MariaDB 10.2+ DEFAULT
);

-- ============================================================
-- HASH 分区
-- ============================================================

CREATE TABLE sessions (
    id BIGINT AUTO_INCREMENT, user_id BIGINT, data TEXT,
    PRIMARY KEY (id, user_id)
) PARTITION BY HASH(user_id) PARTITIONS 8;

-- ============================================================
-- SYSTEM_TIME 分区（MariaDB 10.3.4+，系统版本表）
-- ============================================================

CREATE TABLE versioned_users (
    id BIGINT PRIMARY KEY,
    username VARCHAR(100),
    start_time TIMESTAMP(6) GENERATED ALWAYS AS ROW START,
    end_time   TIMESTAMP(6) GENERATED ALWAYS AS ROW END,
    PERIOD FOR SYSTEM_TIME (start_time, end_time)
) WITH SYSTEM VERSIONING
  PARTITION BY SYSTEM_TIME (
    PARTITION p_history HISTORY,
    PARTITION p_current CURRENT
);

-- ============================================================
-- 分区管理
-- ============================================================

ALTER TABLE orders ADD PARTITION (PARTITION p2026 VALUES LESS THAN (2027));
ALTER TABLE orders DROP PARTITION p2023;
ALTER TABLE orders TRUNCATE PARTITION p2023;
ALTER TABLE orders REORGANIZE PARTITION pmax INTO (
    PARTITION p2026 VALUES LESS THAN (2027),
    PARTITION pmax  VALUES LESS THAN MAXVALUE
);
ALTER TABLE orders EXCHANGE PARTITION p2024 WITH TABLE orders_2024;

-- 注意：MariaDB 分区语法与 MySQL 类似
-- 注意：10.2+ LIST 分区支持 DEFAULT
-- 注意：SYSTEM_TIME 分区是 MariaDB 特有的时态表分区
-- 注意：分区键必须包含在唯一索引中
