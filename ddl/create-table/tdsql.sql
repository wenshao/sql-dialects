-- TDSQL: CREATE TABLE
-- TDSQL is Tencent Cloud's distributed database, MySQL compatible.
-- Supports distributed DDL with shardkey, broadcast tables, and strong consistency.
--
-- 参考资料:
--   [1] TDSQL-C MySQL Documentation
--       https://cloud.tencent.com/document/product/1003
--   [2] TDSQL MySQL Documentation
--       https://cloud.tencent.com/document/product/557

-- 基本建表（MySQL 兼容语法）
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

-- 分布式表：指定 shardkey（分片键）
-- shardkey 是 TDSQL 的核心概念，决定数据分布
CREATE TABLE orders (
    id         BIGINT       NOT NULL AUTO_INCREMENT,
    user_id    BIGINT       NOT NULL,
    amount     DECIMAL(10,2),
    created_at DATETIME     NOT NULL DEFAULT CURRENT_TIMESTAMP,
    PRIMARY KEY (id),
    KEY idx_user_id (user_id)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 shardkey=user_id;

-- 广播表（broadcast）：全量复制到所有节点
-- 适合数据量小、变更少、JOIN 频繁的字典表
CREATE TABLE regions (
    id   INT NOT NULL AUTO_INCREMENT,
    name VARCHAR(64) NOT NULL,
    PRIMARY KEY (id)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 shardkey=noshardkey_allset;

-- 单片表（noshard）：数据只存储在第一个分片
-- 不指定 shardkey 即为单片表（或用 TDSQL 控制台指定）
CREATE TABLE config (
    key_name VARCHAR(64) NOT NULL,
    value    TEXT,
    PRIMARY KEY (key_name)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

-- 分片键 + 二级分区（两级分区）
-- 先按 shardkey 分片到不同节点，再在节点内按 Range 分区
CREATE TABLE logs (
    id         BIGINT NOT NULL AUTO_INCREMENT,
    user_id    BIGINT NOT NULL,
    log_date   DATE   NOT NULL,
    message    TEXT,
    PRIMARY KEY (id, log_date),
    KEY idx_user (user_id)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 shardkey=user_id
PARTITION BY RANGE(YEAR(log_date)) (
    PARTITION p2023 VALUES LESS THAN (2024),
    PARTITION p2024 VALUES LESS THAN (2025),
    PARTITION p2025 VALUES LESS THAN (2026),
    PARTITION pmax  VALUES LESS THAN MAXVALUE
);

-- Hash 分区（节点内）
CREATE TABLE session_data (
    id         BIGINT       NOT NULL AUTO_INCREMENT,
    session_id VARCHAR(128) NOT NULL,
    user_id    BIGINT       NOT NULL,
    data       TEXT,
    PRIMARY KEY (id),
    KEY idx_session (session_id)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 shardkey=user_id;

-- 复合 shardkey（多列作为分片键）
CREATE TABLE order_items (
    id         BIGINT NOT NULL AUTO_INCREMENT,
    order_id   BIGINT NOT NULL,
    product_id BIGINT NOT NULL,
    quantity   INT    NOT NULL,
    PRIMARY KEY (id),
    KEY idx_order (order_id)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 shardkey=order_id;

-- 临时表
CREATE TEMPORARY TABLE temp_result (id BIGINT, val INT);

-- 注意事项：
-- shardkey 必须是主键或唯一索引的一部分
-- 唯一索引必须包含 shardkey 列
-- 广播表的写入会同步到所有节点
-- 不支持外键约束
-- 不支持 FULLTEXT 索引
-- 不支持 SPATIAL 索引
-- AUTO_INCREMENT 在分布式环境下全局唯一但不连续
-- 跨分片查询可能涉及分布式执行计划
