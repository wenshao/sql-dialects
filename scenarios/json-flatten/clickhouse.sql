-- ClickHouse: JSON 展平为关系行 (JSON Flatten)
--
-- 参考资料:
--   [1] ClickHouse - JSON Functions
--       https://clickhouse.com/docs/en/sql-reference/functions/json-functions
--   [2] ClickHouse - arrayJoin
--       https://clickhouse.com/docs/en/sql-reference/functions/array-join

-- ============================================================
-- 1. JSON 字段提取
-- ============================================================

-- 假设 events 表有一个 payload String 列存储 JSON:
-- {"user": "alice", "actions": [{"type": "click", "target": "btn1"}, {"type": "view", "target": "page1"}]}

-- 提取标量字段
SELECT JSONExtractString(payload, 'user') AS user_name FROM events;
SELECT JSONExtractInt(payload, 'count') AS count_val FROM events;

-- 提取嵌套字段
SELECT JSONExtractString(payload, 'address', 'city') AS city FROM events;

-- ============================================================
-- 2. JSON 数组展平（arrayJoin + JSONExtractArrayRaw）
-- ============================================================

-- 将 JSON 数组展平为多行:
SELECT
    JSONExtractString(payload, 'user') AS user_name,
    JSONExtractString(action, 'type') AS action_type,
    JSONExtractString(action, 'target') AS target
FROM events
ARRAY JOIN JSONExtractArrayRaw(payload, 'actions') AS action;

-- ARRAY JOIN 是 ClickHouse 独有的语法:
-- 它将数组列展开为多行（类似 UNNEST / LATERAL JOIN）

-- ============================================================
-- 3. 使用 Tuple 和 Array 代替 JSON（推荐模式）
-- ============================================================

-- ClickHouse 推荐用原生 Array/Tuple 类型代替 JSON:
CREATE TABLE events_native (
    user_name String,
    actions   Array(Tuple(type String, target String))
) ENGINE = MergeTree() ORDER BY user_name;

-- 展平 Array(Tuple):
SELECT user_name, action.1 AS type, action.2 AS target
FROM events_native
ARRAY JOIN actions AS action;

-- 设计分析:
--   原生 Array/Tuple 比 JSON 字符串更高效:
--   (a) 列式存储: Array 的每个子字段独立存储和压缩
--   (b) 无需解析: JSON 需要每次查询解析，Array/Tuple 直接读取
--   (c) 类型安全: Tuple 的字段有明确类型，JSON 是弱类型
--   性能差异: 原生类型比 JSON 函数快 5-50 倍

-- ============================================================
-- 4. JSON 对象展平为键值对
-- ============================================================

-- 使用 JSONExtractKeysAndValues:
SELECT
    key, value
FROM events
ARRAY JOIN
    JSONExtractKeysAndValues(payload, 'String') AS (key, value);

-- 使用 JSONEachRow 格式（在 INSERT/SELECT 中）
-- SELECT * FROM url('http://api/data', JSONEachRow);

-- ============================================================
-- 5. 对比与引擎开发者启示
-- ============================================================
-- ClickHouse JSON 展平的核心:
--   (1) ARRAY JOIN → 数组展开为行（独有语法，最简洁）
--   (2) JSONExtract* 函数族 → 类型安全的 JSON 提取
--   (3) Array/Tuple 原生类型 → 比 JSON 更高效
--   (4) JSONExtractKeysAndValues → 对象展平为键值对
--
-- 对引擎开发者的启示:
--   列存引擎应该优先支持原生嵌套类型（Array/Tuple/Map），
--   JSON 字符串作为兼容方案。
--   ARRAY JOIN 是比 UNNEST + CROSS JOIN 更简洁的语法设计。
