-- ClickHouse: Sequences & Auto-Increment
--
-- 参考资料:
--   [1] ClickHouse Documentation - CREATE TABLE
--       https://clickhouse.com/docs/en/sql-reference/statements/create/table
--   [2] ClickHouse Documentation - Functions for Generating UUIDs
--       https://clickhouse.com/docs/en/sql-reference/functions/uuid-functions
--   [3] ClickHouse Documentation - Data Types
--       https://clickhouse.com/docs/en/sql-reference/data-types

-- ============================================
-- ClickHouse 没有 SEQUENCE 和 AUTO_INCREMENT
-- 以下是替代方案
-- ============================================

-- 方法 1：使用 UUID 类型和 generateUUIDv4()
CREATE TABLE users (
    id         UUID DEFAULT generateUUIDv4(),
    username   String,
    email      String,
    created_at DateTime DEFAULT now()
) ENGINE = MergeTree()
ORDER BY id;

INSERT INTO users (username, email)
VALUES ('alice', 'alice@example.com');
-- id 自动生成 UUID

-- 方法 2：使用 rowNumberInAllBlocks()（查询时生成）
SELECT
    rowNumberInAllBlocks() AS row_id,
    username,
    email
FROM users;

-- 方法 3：使用 materialize(now64()) 或时间戳作为排序键
CREATE TABLE events (
    id         UInt64 DEFAULT toUnixTimestamp64Nano(now64(9)),
    event_type String,
    data       String
) ENGINE = MergeTree()
ORDER BY id;

-- 方法 4：使用外部序列服务（如 ZooKeeper、Redis、etcd）
-- ClickHouse 可通过字典或 JDBC 从外部获取序列值
-- CREATE DICTIONARY seq_dict (...) SOURCE(HTTP(...)) ...

-- 方法 5：使用 cityHash64 生成确定性 ID
INSERT INTO users (id, username, email)
SELECT
    generateUUIDv4(),
    username,
    email
FROM staging_users;

-- ============================================
-- UUID 生成
-- ============================================
SELECT generateUUIDv4();
-- 结果示例：'7f1b7e42-3a1c-4b5d-8f2e-9c0d1e2f3a4b'

-- UUIDv7（ClickHouse 24.1+，时间有序的 UUID）
SELECT generateUUIDv7();

-- UUID 转换
SELECT toUUID('7f1b7e42-3a1c-4b5d-8f2e-9c0d1e2f3a4b');

-- ============================================
-- 序列 vs 自增 权衡
-- ============================================
-- ClickHouse 是列式 OLAP 引擎，设计理念：
-- 1. 数据通常批量插入，不需要行级自增
-- 2. 排序键（ORDER BY）决定数据物理布局，不需要自增主键
-- 3. UUID 或业务键更适合作为标识符
-- 4. 如需严格递增 ID，在数据管道上游生成
-- 5. ReplacingMergeTree 可以用版本号去重，但不自增

-- 限制：
-- ClickHouse 不支持 CREATE SEQUENCE
-- ClickHouse 不支持 AUTO_INCREMENT / IDENTITY / SERIAL
-- ClickHouse 不支持 GENERATED ALWAYS AS IDENTITY
-- UUID DEFAULT generateUUIDv4() 是最常用的自动唯一标识方案
