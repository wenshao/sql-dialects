-- ClickHouse: JSON 类型
--
-- 参考资料:
--   [1] ClickHouse - JSON Data Type
--       https://clickhouse.com/docs/en/sql-reference/data-types/json
--   [2] ClickHouse - JSON Functions
--       https://clickhouse.com/docs/en/sql-reference/functions/json-functions

-- JSON: 半结构化数据类型（24.1+ 实验性，25.3+ 正式）
-- 之前使用 String + JSON 函数，或 Nested/Tuple/Map 类型
-- Object('json'): 旧版 JSON 类型（22.3+，已废弃，被 JSON 类型取代）

-- JSON 类型（25.3+）
CREATE TABLE events (
    id   UInt64,
    data JSON                              -- 原生 JSON 类型
) ENGINE = MergeTree() ORDER BY id;

-- 使用 String 存储 JSON（传统方式）
CREATE TABLE events_legacy (
    id   UInt64,
    data String                            -- 存储 JSON 字符串
) ENGINE = MergeTree() ORDER BY id;

-- 从 String 提取 JSON 字段
SELECT JSONExtractString(data, 'name') FROM events_legacy;   -- 提取字符串
SELECT JSONExtractInt(data, 'age') FROM events_legacy;       -- 提取整数
SELECT JSONExtractFloat(data, 'score') FROM events_legacy;   -- 提取浮点
SELECT JSONExtractBool(data, 'active') FROM events_legacy;   -- 提取布尔
SELECT JSONExtract(data, 'age', 'Int32') FROM events_legacy; -- 指定类型
SELECT JSONExtractRaw(data, 'tags') FROM events_legacy;      -- 提取原始 JSON

-- 嵌套路径
SELECT JSONExtractString(data, 'address', 'city') FROM events_legacy;
SELECT JSONExtractArrayRaw(data, 'tags') FROM events_legacy;

-- 查询条件
SELECT * FROM events_legacy WHERE JSONExtractString(data, 'name') = 'alice';

-- JSON 路径
SELECT JSON_VALUE(data, '$.name') FROM events_legacy;
SELECT JSON_QUERY(data, '$.tags') FROM events_legacy;
SELECT JSON_EXISTS(data, '$.name') FROM events_legacy;

-- Tuple（结构体，替代 JSON 的推荐方案之一）
CREATE TABLE users (
    name    String,
    address Tuple(street String, city String, zip String)
) ENGINE = MergeTree() ORDER BY name;
SELECT address.city FROM users;

-- Map（键值对，21.1+）
CREATE TABLE configs (
    id     UInt64,
    props  Map(String, String)
) ENGINE = MergeTree() ORDER BY id;
SELECT props['key1'] FROM configs;
SELECT mapKeys(props) FROM configs;
SELECT mapValues(props) FROM configs;

-- Nested（嵌套表）
CREATE TABLE orders (
    id    UInt64,
    items Nested(
        name String,
        qty  UInt32,
        price Float64
    )
) ENGINE = MergeTree() ORDER BY id;
-- items.name, items.qty, items.price 是平行数组

-- Array（数组）
CREATE TABLE t (
    tags Array(String)
) ENGINE = MergeTree() ORDER BY tags;
SELECT arrayJoin(tags) AS tag FROM t;     -- 展开数组
SELECT has(tags, 'vip') FROM t;           -- 包含检查
SELECT length(tags) FROM t;

-- 注意：JSON 类型在 25.x 之前为实验性功能
-- 注意：传统方式用 String + JSONExtract* 函数系列
-- 注意：Map/Tuple/Nested/Array 是 ClickHouse 推荐的结构化数据方式
-- 注意：JSONExtract* 函数每次调用都要解析，大规模使用时考虑物化列
