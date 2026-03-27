-- ClickHouse: Sequences & Auto-Increment
--
-- 参考资料:
--   [1] ClickHouse Documentation - UUID Functions
--       https://clickhouse.com/docs/en/sql-reference/functions/uuid-functions
--   [2] ClickHouse Documentation - Data Types (UUID)
--       https://clickhouse.com/docs/en/sql-reference/data-types/uuid
--   [3] ClickHouse Documentation - generateUUIDv7
--       https://clickhouse.com/docs/en/sql-reference/functions/uuid-functions#generateuuidv7

-- ============================================================
-- 1. 为什么 ClickHouse 不支持 SEQUENCE / AUTO_INCREMENT
-- ============================================================

-- ClickHouse 没有 SEQUENCE 对象，也没有 AUTO_INCREMENT 列属性。
-- 这是 OLAP 引擎的刻意设计选择:
--
-- (a) 批量写入模式:
--     ClickHouse 的写入是批量的（推荐每批 10K-100K 行）。
--     AUTO_INCREMENT 为逐行插入设计，与批量写入模式矛盾。
--     为每批中的每一行分配全局自增 ID 需要锁或协调，开销巨大。
--
-- (b) 分布式环境:
--     ClickHouse 集群中多个节点同时写入。
--     全局自增序列需要分布式协调（如 ZooKeeper），增加延迟和复杂性。
--     即使 MySQL 的 AUTO_INCREMENT 在主从复制中也有 ID 冲突风险。
--
-- (c) 主键不需要唯一:
--     ClickHouse 的 PRIMARY KEY 只是稀疏索引，不保证唯一性。
--     既然主键不唯一，就不需要自增来保证唯一性。
--
-- (d) 排序键 > 主键:
--     ClickHouse 的数据按 ORDER BY 排序存储。
--     自增 ID 对分析查询没有意义（不会 WHERE id = X）。
--     业务维度列（user_id, event_time）更适合作为排序键。

-- ============================================================
-- 2. UUID: 推荐的唯一标识方案
-- ============================================================

-- UUIDv4（随机 UUID）
CREATE TABLE users (
    id         UUID DEFAULT generateUUIDv4(),
    username   String,
    email      String,
    created_at DateTime DEFAULT now()
)
ENGINE = MergeTree()
ORDER BY id;

INSERT INTO users (username, email) VALUES ('alice', 'alice@e.com');
-- id 自动生成: 如 '7f1b7e42-3a1c-4b5d-8f2e-9c0d1e2f3a4b'

-- UUIDv7（24.1+，时间有序 UUID）
CREATE TABLE events (
    id         UUID DEFAULT generateUUIDv7(),
    event_type String,
    payload    String
)
ENGINE = MergeTree()
ORDER BY id;           -- UUIDv7 按时间排序，适合作为排序键

-- UUIDv7 的设计优势:
--   高 48 位 = Unix 毫秒时间戳 → 自然有序
--   低 80 位 = 随机值 → 同一毫秒内不冲突
--   → 兼具时间有序性和全局唯一性
--   → 非常适合 ClickHouse 的 ORDER BY（数据按时间排列）
--
-- 对比:
--   UUIDv4: 完全随机，作为 ORDER BY 键效率低（数据分散）
--   UUIDv7: 时间有序，作为 ORDER BY 键效率高（数据按时间聚集）

-- UUID 工具函数
SELECT generateUUIDv4();
SELECT generateUUIDv7();
SELECT toUUID('7f1b7e42-3a1c-4b5d-8f2e-9c0d1e2f3a4b');
SELECT UUIDStringToNum(generateUUIDv4());     -- UUID → FixedString(16)
SELECT UUIDNumToString(UUIDStringToNum(id)) FROM users;

-- ============================================================
-- 3. 其他唯一标识替代方案
-- ============================================================

-- 方法 1: 纳秒时间戳（简单但有碰撞风险）
CREATE TABLE events (
    id         UInt64 DEFAULT toUnixTimestamp64Nano(now64(9)),
    event_type String
)
ENGINE = MergeTree()
ORDER BY id;

-- 方法 2: cityHash64 生成确定性 ID（基于业务字段哈希）
INSERT INTO users (id, username, email)
SELECT
    cityHash64(concat(username, email, toString(now()))),
    username, email
FROM staging;

-- 方法 3: rowNumberInAllBlocks()（查询时生成，非持久化）
SELECT rowNumberInAllBlocks() AS row_num, * FROM users;
-- 注意: 这不是持久化的 ID，每次查询重新计算

-- 方法 4: 外部序列服务
-- 对于必须使用全局自增 ID 的场景（如需要与 MySQL 兼容）:
-- (a) ZooKeeper 路径: 创建顺序节点获取递增 ID
-- (b) Redis INCR: 原子自增计数器
-- (c) Snowflake ID: 应用层生成（时间戳+机器ID+序列号）
-- 这些方案都在 ClickHouse 外部实现，通过 INSERT 传入 ID 值

-- ============================================================
-- 4. 版本号 vs 自增 ID（ReplacingMergeTree 场景）
-- ============================================================

-- ReplacingMergeTree 需要版本号来决定保留哪行（不是自增 ID）
CREATE TABLE users_rmt (
    id       UInt64,
    username String,
    version  UInt64            -- 版本号，merge 时保留最大值
)
ENGINE = ReplacingMergeTree(version)
ORDER BY id;

-- 版本号通常用时间戳:
INSERT INTO users_rmt VALUES (1, 'alice', toUnixTimestamp(now()));
-- 后续更新:
INSERT INTO users_rmt VALUES (1, 'alice_updated', toUnixTimestamp(now()));
-- merge 后只保留 version 最大的行

-- ============================================================
-- 5. 对比与引擎开发者启示
-- ============================================================
-- ClickHouse 不支持自增的根因:
--   OLAP 批量写入 + 分布式 + 主键不唯一 → 自增没有用武之地
--
-- 替代方案的选择:
--   UUID v4: 最简单，完全随机，适合不需要排序的场景
--   UUID v7: 时间有序，适合作为 ORDER BY 键（推荐）
--   时间戳:  简单但有碰撞风险，适合低并发
--   哈希 ID: 确定性，适合幂等写入（相同输入相同 ID）
--   外部序列: 最后手段，增加架构复杂度
--
-- 对引擎开发者的启示:
--   (1) OLAP 引擎不需要自增 ID（批量写入不适合逐行分配）
--   (2) UUIDv7 是最佳折中: 唯一 + 有序 + 无协调
--   (3) 如果必须兼容 MySQL 的 AUTO_INCREMENT，
--       考虑段分配（每个节点预分配 ID 范围），如 TiDB 的做法
