-- ClickHouse: 约束
--
-- 参考资料:
--   [1] ClickHouse SQL Reference - CREATE TABLE
--       https://clickhouse.com/docs/en/sql-reference/statements/create/table
--   [2] ClickHouse - ALTER CONSTRAINT
--       https://clickhouse.com/docs/en/sql-reference/statements/alter/constraint

-- ClickHouse 的约束模型与传统数据库不同
-- 主键不保证唯一性，没有外键

-- ============================================================
-- PRIMARY KEY（不保证唯一性！）
-- ============================================================

-- PRIMARY KEY 定义稀疏索引，不强制唯一
CREATE TABLE users (
    id         UInt64,
    username   String,
    email      String
)
ENGINE = MergeTree()
ORDER BY id;                                 -- ORDER BY 默认就是 PRIMARY KEY

-- 显式指定 PRIMARY KEY（可以与 ORDER BY 不同）
CREATE TABLE orders (
    id         UInt64,
    user_id    UInt64,
    order_date Date
)
ENGINE = MergeTree()
ORDER BY (user_id, order_date)
PRIMARY KEY user_id;                         -- 主键是排序键的前缀

-- 注意：主键不保证唯一，可以插入重复值！
-- 使用 ReplacingMergeTree 实现去重（后台异步合并）

-- ============================================================
-- NOT NULL（默认行为）
-- ============================================================

-- ClickHouse 默认所有列都是 NOT NULL
CREATE TABLE users (
    id       UInt64,                         -- 不能为 NULL
    username String,                         -- 不能为 NULL
    email    Nullable(String),               -- 可以为 NULL（需要显式声明）
    age      Nullable(UInt8)                 -- 可以为 NULL
)
ENGINE = MergeTree()
ORDER BY id;

-- Nullable 类型有额外的存储和性能开销

-- ============================================================
-- DEFAULT
-- ============================================================

CREATE TABLE users (
    id         UInt64,
    status     UInt8 DEFAULT 1,
    created_at DateTime DEFAULT now(),
    name       String DEFAULT 'unknown'
)
ENGINE = MergeTree()
ORDER BY id;

-- MATERIALIZED（计算后存储，不能手动插入）
CREATE TABLE events (
    timestamp DateTime,
    date      Date MATERIALIZED toDate(timestamp),
    hour      UInt8 MATERIALIZED toHour(timestamp)
)
ENGINE = MergeTree()
ORDER BY timestamp;

-- ALIAS（查询时计算，不存储）
CREATE TABLE users (
    first_name String,
    last_name  String,
    full_name  String ALIAS concat(first_name, ' ', last_name)
)
ENGINE = MergeTree()
ORDER BY first_name;

-- ============================================================
-- CHECK 约束（19.14+）
-- ============================================================

CREATE TABLE users (
    id   UInt64,
    age  UInt8,
    CONSTRAINT chk_age CHECK age > 0 AND age < 200
)
ENGINE = MergeTree()
ORDER BY id;

-- 添加约束
ALTER TABLE users ADD CONSTRAINT chk_status CHECK status IN (0, 1);

-- 删除约束
ALTER TABLE users DROP CONSTRAINT chk_status;

-- ============================================================
-- 不支持的约束
-- ============================================================

-- UNIQUE: 不支持（ReplacingMergeTree 提供最终一致的去重）
-- FOREIGN KEY: 不支持
-- EXCLUDE: 不支持

-- ============================================================
-- 去重替代方案（ReplacingMergeTree）
-- ============================================================

CREATE TABLE users (
    id         UInt64,
    username   String,
    updated_at DateTime
)
ENGINE = ReplacingMergeTree(updated_at)
ORDER BY id;

-- 查询时用 FINAL 获取去重后的结果
SELECT * FROM users FINAL WHERE id = 1;

-- 注意：ClickHouse 默认列不可为 NULL（与其他数据库相反）
-- 注意：PRIMARY KEY 不保证唯一性
-- 注意：CHECK 约束在 19.14+ 版本引入
-- 注意：去重通过 ReplacingMergeTree + FINAL 实现
-- 注意：MATERIALIZED 列不能手动插入值
