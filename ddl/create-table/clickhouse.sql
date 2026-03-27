-- ClickHouse: CREATE TABLE
--
-- 参考资料:
--   [1] ClickHouse SQL Reference - CREATE TABLE
--       https://clickhouse.com/docs/en/sql-reference/statements/create/table
--   [2] ClickHouse - Data Types
--       https://clickhouse.com/docs/en/sql-reference/data-types
--   [3] ClickHouse - Table Engines
--       https://clickhouse.com/docs/en/engines/table-engines

-- 基本建表（必须指定引擎！）
CREATE TABLE users (
    id         UInt64,
    username   String,
    email      String,
    age        Nullable(UInt8),             -- ClickHouse 默认列不能为 NULL
    balance    Decimal(10,2),
    bio        Nullable(String),
    tags       Array(String),               -- 原生数组
    created_at DateTime DEFAULT now(),
    updated_at DateTime DEFAULT now()
)
ENGINE = MergeTree()
ORDER BY id;                                -- MergeTree 必须指定排序键

-- MergeTree 系列引擎（最常用）
CREATE TABLE orders (
    id         UInt64,
    user_id    UInt64,
    amount     Decimal(10,2),
    order_date Date
)
ENGINE = MergeTree()
PARTITION BY toYYYYMM(order_date)           -- 按月分区
ORDER BY (user_id, order_date)              -- 排序键（决定数据布局和查询性能）
PRIMARY KEY user_id                          -- 主键（默认等于 ORDER BY）
SETTINGS index_granularity = 8192;

-- ReplacingMergeTree（去重，按排序键合并最新行）
CREATE TABLE users (
    id         UInt64,
    username   String,
    email      String,
    updated_at DateTime
)
ENGINE = ReplacingMergeTree(updated_at)     -- 用 updated_at 判断保留哪行
ORDER BY id;

-- AggregatingMergeTree（预聚合）
CREATE TABLE stats (
    date       Date,
    user_id    UInt64,
    click_count AggregateFunction(sum, UInt64),
    uniq_pages  AggregateFunction(uniq, String)
)
ENGINE = AggregatingMergeTree()
PARTITION BY toYYYYMM(date)
ORDER BY (date, user_id);

-- CollapsingMergeTree（折叠，用 sign 列标记插入/删除）
CREATE TABLE events (
    id       UInt64,
    user_id  UInt64,
    event    String,
    sign     Int8                            -- 1: 插入, -1: 取消
)
ENGINE = CollapsingMergeTree(sign)
ORDER BY (user_id, id);

-- SummingMergeTree（合并时自动求和）
CREATE TABLE daily_stats (
    date       Date,
    user_id    UInt64,
    clicks     UInt64,
    revenue    Decimal(10,2)
)
ENGINE = SummingMergeTree()
PARTITION BY toYYYYMM(date)
ORDER BY (date, user_id);

-- 分布式表（多节点）
CREATE TABLE orders_dist AS orders
ENGINE = Distributed(cluster_name, default, orders, rand());

-- TTL（数据过期自动删除或移动）
CREATE TABLE logs (
    timestamp DateTime,
    level     String,
    message   String
)
ENGINE = MergeTree()
ORDER BY timestamp
TTL timestamp + INTERVAL 30 DAY;            -- 30 天后删除

-- 物化视图
CREATE MATERIALIZED VIEW daily_summary
ENGINE = SummingMergeTree()
ORDER BY (date, user_id) AS
SELECT toDate(order_date) AS date, user_id, sum(amount) AS total
FROM orders GROUP BY date, user_id;

-- 数据类型：
-- UInt8/16/32/64/128/256, Int8/16/32/64/128/256: 整数
-- Float32/64: 浮点
-- Decimal(P,S) / Decimal32/64/128/256: 定点
-- String: 变长字符串（无限制）
-- FixedString(N): 定长
-- Date / Date32: 日期
-- DateTime / DateTime64: 时间戳
-- UUID: UUID
-- Array(T) / Tuple(T1,T2,...) / Map(K,V): 复合类型
-- Nullable(T): 可空包装
-- Enum8/16: 枚举
-- LowCardinality(T): 字典编码（优化低基数列）
-- IPv4 / IPv6: IP 地址

-- 注意：默认列不可为 NULL（需要显式 Nullable）
-- 注意：没有 UPDATE/DELETE，使用 ALTER TABLE ... UPDATE/DELETE（异步后台执行）
-- 注意：MergeTree 的"合并"是后台异步的，查询可能暂时看到重复数据
