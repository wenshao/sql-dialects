-- StarRocks: 约束
--
-- 参考资料:
--   [1] StarRocks - Table Design
--       https://docs.starrocks.io/docs/table_design/table_types/

-- ============================================================
-- 1. 约束模型: 与 Doris 同源但 PRIMARY KEY 语法独立
-- ============================================================
-- StarRocks 同样不支持 UNIQUE/FOREIGN KEY/CHECK 等传统约束。
-- 核心差异: StarRocks 有独立的 PRIMARY KEY 语法(1.19+)。
--
-- 对比 Doris:
--   Doris:     UNIQUE KEY + PROPERTIES("enable_unique_key_merge_on_write")
--   StarRocks: PRIMARY KEY — 独立语法，语义更清晰
--
-- 设计分析:
--   StarRocks 的 PRIMARY KEY 模型的唯一性保证机制:
--     写入时通过内存中的 HashIndex 定位旧行 → 标记删除 → 插入新行
--     保证实时唯一(不是后台异步合并)
--     代价: 主键索引常驻内存，百亿行约需 160GB 内存
--
-- 对比:
--   ClickHouse: ReplacingMergeTree 异步去重(不保证实时唯一)
--   MySQL:      PRIMARY KEY 原生约束 + 行级锁
--   BigQuery:   PRIMARY KEY 信息性(不强制执行)

-- ============================================================
-- 2. NOT NULL
-- ============================================================
CREATE TABLE users (
    id       BIGINT       NOT NULL,
    username VARCHAR(64)  NOT NULL,
    email    VARCHAR(255)
)
DUPLICATE KEY(id)
DISTRIBUTED BY HASH(id) BUCKETS 16;

-- Key 列必须 NOT NULL。Value 列默认允许 NULL。
-- NOT NULL 是唯一强制执行的约束(本地检查，无分布式代价)。

-- ============================================================
-- 3. PRIMARY KEY 模型 (StarRocks 独有语法)
-- ============================================================
CREATE TABLE users_pk (
    id       BIGINT       NOT NULL,
    username VARCHAR(64),
    email    VARCHAR(255)
)
PRIMARY KEY(id)
DISTRIBUTED BY HASH(id) BUCKETS 16;

-- 与 Doris UNIQUE KEY + MoW 的功能等价，但语法更清晰。
-- PRIMARY KEY 列不能被修改/删除(与 MySQL PRIMARY KEY 约束一致)。
-- 插入相同 Key 的行会覆盖旧行(不报错——与 MySQL 不同)。

-- ============================================================
-- 4. UNIQUE KEY 模型 (Merge-on-Read)
-- ============================================================
CREATE TABLE users_unique (
    id       BIGINT       NOT NULL,
    username VARCHAR(64),
    email    VARCHAR(255)
)
UNIQUE KEY(id)
DISTRIBUTED BY HASH(id) BUCKETS 16;

-- Unique Key = Merge-on-Read，后台 Compaction 时合并。
-- 读性能不如 Primary Key，但写入更快(无需实时查重)。

-- ============================================================
-- 5. AGGREGATE KEY 模型: 隐式约束
-- ============================================================
CREATE TABLE daily_stats (
    date    DATE         NOT NULL,
    user_id BIGINT       NOT NULL,
    clicks  BIGINT       SUM DEFAULT '0',
    revenue DECIMAL(10,2) SUM DEFAULT '0'
)
AGGREGATE KEY(date, user_id)
DISTRIBUTED BY HASH(user_id) BUCKETS 16;

-- Value 列必须指定聚合方式——这是"模式级约束"。

-- ============================================================
-- 6. DEFAULT 值
-- ============================================================
CREATE TABLE users_def (
    id         BIGINT       NOT NULL,
    status     INT          DEFAULT '1',
    created_at DATETIME     DEFAULT CURRENT_TIMESTAMP
)
DUPLICATE KEY(id)
DISTRIBUTED BY HASH(id) BUCKETS 16;

-- ============================================================
-- 7. 不支持的约束
-- ============================================================
-- UNIQUE (SQL 标准):   不支持。用 Unique Key / Primary Key 模型替代
-- FOREIGN KEY:         不支持
-- CHECK:               不支持
-- EXCLUDE:             不支持

-- ============================================================
-- 8. 数据完整性替代方案
-- ============================================================
INSERT INTO users_pk VALUES (1, 'alice', 'alice@example.com');
INSERT INTO users_pk VALUES (1, 'alice_new', 'new@example.com');
-- id=1 的旧行被新行覆盖(不报错)

-- ============================================================
-- 9. StarRocks vs Doris 约束对比
-- ============================================================
-- PRIMARY KEY 语法:
--   StarRocks: PRIMARY KEY(id) — 独立语法
--   Doris:     UNIQUE KEY(id) + PROPERTIES — 复用语法
--
-- 唯一性保证:
--   StarRocks Primary Key: 实时唯一(HashIndex 内存索引)
--   Doris Unique Key MoW:  实时唯一(类似实现)
--   StarRocks Unique Key:  最终一致(Compaction 后)
--   Doris Unique Key MoR:  最终一致(Compaction 后)
--
-- 内存代价:
--   StarRocks Primary Key: 约 16 字节/主键
--   10 亿行 → 约 16GB 内存用于主键索引
--
-- 对引擎开发者的启示:
--   StarRocks 的 PRIMARY KEY 设计展示了一个重要 trade-off:
--     实时唯一性(用户体验好) vs 内存消耗(运维代价高)。
--   Doris 通过 PROPERTIES 开关让用户自己选择(灵活但不直观)。
--   StarRocks 通过独立模型让选择更清晰(直观但不灵活)。
--
-- 约束的分布式挑战:
--   单节点 UNIQUE: 本地 Hash 检查 → O(1)
--   分布式 UNIQUE: 需要路由到正确节点 → 依赖 DISTRIBUTED BY HASH
--     如果 UNIQUE 列 != 分桶列，则需要全局协调 → 不支持
--   所以: PRIMARY KEY 列必须包含分桶列(与 MySQL 分区表限制类似)。
