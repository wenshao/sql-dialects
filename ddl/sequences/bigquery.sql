-- BigQuery: Sequences & Auto-Increment
--
-- 参考资料:
--   [1] BigQuery SQL Reference - Data Definition Language
--       https://cloud.google.com/bigquery/docs/reference/standard-sql/data-definition-language
--   [2] BigQuery Documentation - Generating Unique IDs
--       https://cloud.google.com/bigquery/docs/reference/standard-sql/functions-and-operators#generate_uuid
--   [3] BigQuery Documentation - Row-level Data
--       https://cloud.google.com/bigquery/docs/reference/standard-sql/functions-and-operators#row_number

-- ============================================
-- BigQuery 没有 SEQUENCE 和 AUTO_INCREMENT
-- 以下是替代方案
-- ============================================

-- 方法 1：使用 GENERATE_UUID() 生成唯一标识符
CREATE TABLE users (
    id         STRING NOT NULL DEFAULT GENERATE_UUID(),
    username   STRING NOT NULL,
    email      STRING NOT NULL,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP()
);

INSERT INTO users (username, email)
VALUES ('alice', 'alice@example.com');
-- id 会自动生成类似 '7f1b7e42-3a1c-4b5d-8f2e-9c0d1e2f3a4b' 的 UUID

-- 方法 2：使用 ROW_NUMBER() 在查询时生成序号
SELECT
    ROW_NUMBER() OVER (ORDER BY created_at) AS row_id,
    username,
    email
FROM users;

-- 方法 3：使用 FARM_FINGERPRINT 生成确定性哈希 ID
INSERT INTO users (id, username, email)
SELECT
    CAST(FARM_FINGERPRINT(CONCAT(username, email)) AS STRING),
    username,
    email
FROM staging_users;

-- 方法 4：CTAS + ROW_NUMBER 为存量数据生成自增 ID
CREATE TABLE users_with_id AS
SELECT
    ROW_NUMBER() OVER (ORDER BY created_at) AS id,
    username,
    email,
    created_at
FROM users;

-- 方法 5：使用 JavaScript UDF 生成自增 ID（不推荐，性能差）
-- CREATE TEMP FUNCTION next_id() RETURNS INT64
-- LANGUAGE js AS "return Date.now();";

-- ============================================
-- UUID 生成
-- ============================================
-- GENERATE_UUID() 返回 RFC 4122 v4 UUID 字符串
SELECT GENERATE_UUID();
-- 结果示例：'7f1b7e42-3a1c-4b5d-8f2e-9c0d1e2f3a4b'

-- ============================================
-- 序列 vs 自增 权衡
-- ============================================
-- BigQuery 是列式存储分析引擎，设计理念不同于 OLTP：
-- 1. 无需主键自增（没有 B-tree 索引，插入顺序无关紧要）
-- 2. UUID 足以满足唯一标识需求
-- 3. 如需严格递增 ID，建议在应用层或 ETL 管道中生成
-- 4. ROW_NUMBER() 仅在查询时有效，不能作为持久化自增字段

-- 限制：
-- BigQuery 不支持 CREATE SEQUENCE
-- BigQuery 不支持 AUTO_INCREMENT / IDENTITY / SERIAL
-- BigQuery 不支持 GENERATED ALWAYS AS IDENTITY
-- DEFAULT GENERATE_UUID() 是最接近的自动生成方案
