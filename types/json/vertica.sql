-- Vertica: JSON 类型
--
-- 参考资料:
--   [1] Vertica SQL Reference
--       https://www.vertica.com/docs/latest/HTML/Content/Authoring/SQLReferenceManual/SQLReferenceManual.htm
--   [2] Vertica Functions
--       https://www.vertica.com/docs/latest/HTML/Content/Authoring/SQLReferenceManual/Functions/Functions.htm

-- Vertica 通过 Flex 表和 JSON 函数处理 JSON 数据

-- ============================================================
-- Flex 表（半结构化数据存储）
-- ============================================================

-- Flex 表不需要预定义 Schema
CREATE FLEX TABLE events_flex ();

-- 加载 JSON 数据
COPY events_flex FROM '/data/events.json' PARSER fjsonparser();

-- 查询 Flex 表（使用 MapToString 查看所有键值）
SELECT MapToString(__raw__) FROM events_flex LIMIT 5;

-- 提取字段
SELECT events_flex.name::VARCHAR AS name,
       events_flex.age::INT AS age
FROM events_flex;

-- 计算键定义
SELECT COMPUTE_FLEXTABLE_KEYS('events_flex');
SELECT * FROM events_flex_keys;

-- 从 Flex 表创建物化列
ALTER TABLE events_flex ADD COLUMN name VARCHAR(64)
    DEFAULT events_flex.name::VARCHAR(64);
ALTER TABLE events_flex ADD COLUMN age INT
    DEFAULT events_flex.age::INT;

-- ============================================================
-- 常规表中的 JSON（VARCHAR/LONG VARCHAR 列）
-- ============================================================

CREATE TABLE events (
    id   INT NOT NULL,
    data LONG VARCHAR                      -- JSON 以字符串存储
);

INSERT INTO events VALUES
    (1, '{"name": "alice", "age": 25, "tags": ["vip", "new"]}'),
    (2, '{"name": "bob", "age": 30, "address": {"city": "Beijing"}}');

-- ============================================================
-- JSON 提取函数
-- ============================================================

-- MAPJSONEXTRACTOR
SELECT MAPJSONEXTRACTOR(data) OVER () FROM events;

-- JSON_EXTRACT_PATH_TEXT（提取为文本）
-- 注意：Vertica 中通常使用 Flex 表方式访问 JSON

-- ============================================================
-- JSON 解析（通过 Flex Table 函数）
-- ============================================================

-- 使用 fjsonparser 解析 JSON 列
SELECT id, MapLookup(__raw__, 'name') AS name
FROM (
    SELECT id, MAPJSONEXTRACTOR(data USING PARAMETERS flatten_maps=false) OVER (PARTITION BEST) AS (__raw__)
    FROM events
) t;

-- ============================================================
-- Flex 表 vs 常规表
-- ============================================================

-- 将 Flex 表物化为常规表
CREATE TABLE events_regular AS
SELECT events_flex.name::VARCHAR(64) AS name,
       events_flex.age::INT AS age,
       events_flex.city::VARCHAR(64) AS city
FROM events_flex;

-- ============================================================
-- 外部 JSON 数据
-- ============================================================

-- COPY 从 JSON 文件
COPY events_flex FROM '/data/events.json'
    PARSER fjsonparser(flatten_maps=false, flatten_arrays=false);

-- COPY 从 S3
COPY events_flex FROM 's3://bucket/events/*.json'
    PARSER fjsonparser();

-- 注意：Vertica 没有原生 JSON 类型
-- 注意：Flex 表是处理 JSON 的推荐方式
-- 注意：fjsonparser 是 Vertica 内置的 JSON 解析器
-- 注意：生产环境建议将 JSON 数据物化为常规列
-- 注意：Flex 表可以自动推断 Schema（COMPUTE_FLEXTABLE_KEYS）
