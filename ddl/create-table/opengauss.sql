-- openGauss/GaussDB: CREATE TABLE
-- openGauss is Huawei's open-source database based on PostgreSQL.
-- GaussDB is the commercial version with additional enterprise features.
--
-- 参考资料:
--   [1] openGauss SQL Reference
--       https://docs.opengauss.org/zh/docs/latest/docs/SQLReference/SQL-reference.html
--   [2] GaussDB Documentation
--       https://support.huaweicloud.com/gaussdb/index.html

-- 基本建表（PostgreSQL 兼容语法）
CREATE TABLE users (
    id         BIGSERIAL     PRIMARY KEY,
    username   VARCHAR(64)   NOT NULL UNIQUE,
    email      VARCHAR(255)  NOT NULL UNIQUE,
    age        INTEGER,
    balance    NUMERIC(10,2) DEFAULT 0.00,
    bio        TEXT,
    created_at TIMESTAMP     NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP     NOT NULL DEFAULT CURRENT_TIMESTAMP
);

-- openGauss 没有 ON UPDATE CURRENT_TIMESTAMP，需要用触发器实现
CREATE OR REPLACE FUNCTION update_updated_at()
RETURNS TRIGGER AS $$
BEGIN
    NEW.updated_at = CURRENT_TIMESTAMP;
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER trg_users_updated_at
    BEFORE UPDATE ON users
    FOR EACH ROW
    EXECUTE PROCEDURE update_updated_at();

-- 行存储表（默认，适合 OLTP）
CREATE TABLE orders (
    id         BIGSERIAL PRIMARY KEY,
    user_id    BIGINT    NOT NULL,
    amount     NUMERIC(10,2),
    created_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP
) WITH (ORIENTATION = ROW);

-- 列存储表（适合 OLAP 分析查询）
CREATE TABLE analytics_events (
    event_id   BIGINT NOT NULL,
    event_type VARCHAR(32),
    event_data TEXT,
    created_at TIMESTAMP NOT NULL
) WITH (ORIENTATION = COLUMN)
DISTRIBUTE BY HASH(event_id);

-- MOT 内存优化表（Memory-Optimized Table）
-- 高性能事务处理，数据存储在内存中
CREATE FOREIGN TABLE hot_data (
    id   BIGINT NOT NULL,
    data VARCHAR(256),
    PRIMARY KEY (id)
) SERVER mot_server;

-- 分布式表（GaussDB 分布式版本）
-- DISTRIBUTE BY HASH: 按哈希分布到多个 DN
CREATE TABLE big_table (
    id   BIGINT NOT NULL,
    name VARCHAR(64),
    PRIMARY KEY (id)
) DISTRIBUTE BY HASH(id);

-- DISTRIBUTE BY REPLICATION: 全量复制到每个 DN（类似广播表）
CREATE TABLE dict_table (
    code VARCHAR(10) NOT NULL,
    name VARCHAR(64),
    PRIMARY KEY (code)
) DISTRIBUTE BY REPLICATION;

-- 分区表 - Range 分区
CREATE TABLE logs (
    id         BIGSERIAL,
    log_date   DATE NOT NULL,
    message    TEXT
) PARTITION BY RANGE(log_date) (
    PARTITION p2023 VALUES LESS THAN ('2024-01-01'),
    PARTITION p2024 VALUES LESS THAN ('2025-01-01'),
    PARTITION p2025 VALUES LESS THAN ('2026-01-01'),
    PARTITION pmax  VALUES LESS THAN (MAXVALUE)
);

-- List 分区
CREATE TABLE regional_data (
    id     BIGINT NOT NULL,
    region VARCHAR(32) NOT NULL,
    data   TEXT
) PARTITION BY LIST(region) (
    PARTITION p_east   VALUES ('shanghai', 'hangzhou', 'nanjing'),
    PARTITION p_north  VALUES ('beijing', 'tianjin'),
    PARTITION p_south  VALUES ('guangzhou', 'shenzhen')
);

-- Hash 分区
CREATE TABLE session_data (
    session_id VARCHAR(128) NOT NULL,
    data       TEXT,
    PRIMARY KEY (session_id)
) PARTITION BY HASH(session_id) (
    PARTITION p0,
    PARTITION p1,
    PARTITION p2,
    PARTITION p3
);

-- 临时表
CREATE TEMPORARY TABLE temp_result (id BIGINT, val INTEGER);

-- 全局临时表
CREATE GLOBAL TEMPORARY TABLE temp_session (
    id  BIGINT,
    val INTEGER
) ON COMMIT DELETE ROWS;

-- 压缩表
CREATE TABLE compressed_data (
    id   BIGINT NOT NULL,
    data TEXT
) WITH (ORIENTATION = COLUMN, COMPRESSION = HIGH);

-- 注意事项：
-- 基于 PostgreSQL，兼容大部分 PG 语法
-- 列存储表不支持主键和唯一约束
-- MOT 表有一些限制（不支持列存储、不支持分区等）
-- GaussDB 商业版支持更多 AI4DB 特性（自动索引推荐、慢 SQL 诊断等）
-- EXECUTE PROCEDURE 替代 EXECUTE FUNCTION（与 PG 的差异）
