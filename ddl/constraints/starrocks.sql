-- StarRocks: 约束
--
-- 参考资料:
--   [1] StarRocks - CREATE TABLE
--       https://docs.starrocks.io/docs/sql-reference/sql-statements/table_bucket_part_index/CREATE_TABLE/
--   [2] StarRocks - Data Types
--       https://docs.starrocks.io/docs/sql-reference/data-types/

-- StarRocks 有有限的约束支持

-- ============================================================
-- NOT NULL
-- ============================================================

CREATE TABLE users (
    id       BIGINT NOT NULL,
    username VARCHAR(64) NOT NULL,
    email    VARCHAR(255)          -- 默认允许 NULL
)
DUPLICATE KEY(id)
DISTRIBUTED BY HASH(id) BUCKETS 16;

-- Key 列必须是 NOT NULL
-- Value 列可以为 NULL

-- ============================================================
-- PRIMARY KEY（Primary Key 模型，3.0+）
-- ============================================================

-- Primary Key 模型强制唯一（通过覆盖实现）
CREATE TABLE users (
    id       BIGINT NOT NULL,
    username VARCHAR(64),
    email    VARCHAR(255)
)
PRIMARY KEY(id)
DISTRIBUTED BY HASH(id) BUCKETS 16;

-- 注意：PRIMARY KEY 模型下插入相同 Key 的数据会覆盖旧数据

-- ============================================================
-- UNIQUE KEY（唯一模型，通过覆盖实现去重）
-- ============================================================

CREATE TABLE users (
    id       BIGINT NOT NULL,
    username VARCHAR(64),
    email    VARCHAR(255)
)
UNIQUE KEY(id)
DISTRIBUTED BY HASH(id) BUCKETS 16;

-- UNIQUE KEY 在后台合并时保留最新行

-- ============================================================
-- AGGREGATE KEY（聚合模型的隐式约束）
-- ============================================================

-- Key 列定义聚合维度，Value 列必须指定聚合方式
CREATE TABLE daily_stats (
    date    DATE NOT NULL,
    user_id BIGINT NOT NULL,
    clicks  BIGINT SUM DEFAULT '0',
    revenue DECIMAL(10,2) SUM DEFAULT '0'
)
AGGREGATE KEY(date, user_id)
DISTRIBUTED BY HASH(user_id) BUCKETS 16;

-- 聚合方式：SUM, MIN, MAX, REPLACE, REPLACE_IF_NOT_NULL, HLL_UNION, BITMAP_UNION

-- ============================================================
-- DEFAULT
-- ============================================================

CREATE TABLE users (
    id         BIGINT NOT NULL,
    status     INT DEFAULT '1',
    created_at DATETIME DEFAULT CURRENT_TIMESTAMP
)
DUPLICATE KEY(id)
DISTRIBUTED BY HASH(id) BUCKETS 16;

-- ============================================================
-- 不支持的约束
-- ============================================================

-- UNIQUE 约束（传统 SQL 意义的）: 不支持
-- FOREIGN KEY: 不支持
-- CHECK: 不支持
-- EXCLUDE: 不支持

-- ============================================================
-- 数据完整性替代方案
-- ============================================================

-- 1. 使用 Primary Key 模型保证主键唯一性
-- 2. 在应用层或 ETL 中验证数据
-- 3. 使用 INSERT INTO ... SELECT 做数据清洗

-- 通过 Primary Key 模型去重
INSERT INTO users VALUES (1, 'alice', 'alice@example.com');
INSERT INTO users VALUES (1, 'alice_new', 'alice_new@example.com');
-- id=1 的旧数据被新数据覆盖

-- 注意：Key 列必须定义在表定义的最前面
-- 注意：Key 列不能被 ALTER TABLE 修改
-- 注意：PRIMARY KEY 和 UNIQUE KEY 通过覆盖实现唯一性
-- 注意：AGGREGATE KEY 模型的 Value 列必须有聚合类型
