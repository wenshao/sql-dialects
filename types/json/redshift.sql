-- Redshift: JSON 类型
--
-- 参考资料:
--   [1] Redshift SQL Reference
--       https://docs.aws.amazon.com/redshift/latest/dg/cm_chap_SQLCommandRef.html
--   [2] Redshift SQL Functions
--       https://docs.aws.amazon.com/redshift/latest/dg/c_SQL_functions.html
--   [3] Redshift Data Types
--       https://docs.aws.amazon.com/redshift/latest/dg/c_Supported_data_types.html

-- SUPER: 半结构化数据类型（2020+，推荐）
-- 支持 JSON 对象、数组、标量值
-- 之前用 VARCHAR 存储 JSON 并用 JSON 函数解析

CREATE TABLE events (
    id   BIGINT IDENTITY(1, 1),
    data SUPER                               -- 半结构化数据
);

-- 插入 JSON
INSERT INTO events (data) VALUES (JSON_PARSE('{"name": "alice", "age": 25, "tags": ["vip"]}'));
INSERT INTO events (data) VALUES (JSON_PARSE('{"name": "bob", "age": 30}'));

-- 从 S3 加载 JSON 数据
COPY events (data)
FROM 's3://my-bucket/data/events.json'
IAM_ROLE 'arn:aws:iam::123456789012:role/MyRole'
FORMAT AS JSON 'auto';

-- ============================================================
-- SUPER 类型访问
-- ============================================================

-- 点号访问
SELECT data.name FROM events;                -- 返回 SUPER 类型
SELECT data.name::VARCHAR FROM events;       -- 转为 VARCHAR

-- 数组下标
SELECT data.tags[0]::VARCHAR FROM events;

-- 嵌套访问
SELECT data.address.city::VARCHAR FROM events;

-- ============================================================
-- JSON 提取函数（VARCHAR JSON 方式，旧方式）
-- ============================================================

-- JSON_EXTRACT_PATH_TEXT（从 VARCHAR JSON 提取文本）
SELECT JSON_EXTRACT_PATH_TEXT('{"name": "alice", "age": 25}', 'name');  -- 'alice'

-- 嵌套路径
SELECT JSON_EXTRACT_PATH_TEXT(json_col, 'address', 'city') FROM events;

-- JSON_EXTRACT_ARRAY_ELEMENT_TEXT（提取数组元素）
SELECT JSON_EXTRACT_ARRAY_ELEMENT_TEXT('["a", "b", "c"]', 0);  -- 'a'

-- ============================================================
-- SUPER 类型函数
-- ============================================================

-- 类型检查
SELECT IS_VARCHAR(data.name) FROM events;    -- true/false
SELECT IS_INTEGER(data.age) FROM events;
SELECT IS_ARRAY(data.tags) FROM events;
SELECT IS_OBJECT(data) FROM events;
SELECT JSON_TYPEOF(data.name) FROM events;   -- 'string'

-- 数组操作
SELECT JSON_ARRAY_LENGTH(data.tags) FROM events;
SELECT data.tags[0]::VARCHAR FROM events;

-- 对象键
SELECT JSON_KEYS(data) FROM events;

-- SUPER 序列化
SELECT JSON_SERIALIZE(data) FROM events;     -- SUPER → VARCHAR JSON 字符串

-- ============================================================
-- PartiQL 查询（SUPER 类型的高级查询）
-- ============================================================

-- 直接在 SUPER 列上使用 SQL 条件
SELECT data.name::VARCHAR
FROM events
WHERE data.age::INT > 25;

-- 展开数组（UNNEST）
SELECT e.id, tag::VARCHAR
FROM events e, e.data.tags AS tag;

-- 嵌套展开
SELECT e.id, item.name::VARCHAR, item.price::DECIMAL(10,2)
FROM events e, e.data.items AS item;

-- ============================================================
-- JSON 构造
-- ============================================================

SELECT JSON_PARSE('{"key": "value"}');       -- VARCHAR → SUPER
SELECT JSON_PARSE(JSON_SERIALIZE(data))
FROM events;                                 -- 往返转换

-- ============================================================
-- 从查询结果生成 JSON
-- ============================================================

-- JSON_ARRAY / JSON_OBJECT（Redshift 不支持这些构造函数）
-- 使用 LISTAGG + 字符串拼接生成 JSON

-- 注意：SUPER 是推荐的 JSON 存储类型（2020+）
-- 注意：SUPER 支持无 Schema 的半结构化数据
-- 注意：点号访问 SUPER 列返回 SUPER 类型，需要 :: 转换
-- 注意：PartiQL 允许像查询关系数据一样查询 SUPER
-- 注意：SUPER 列最大 16 MB
-- 注意：旧代码可能用 VARCHAR + JSON_EXTRACT_PATH_TEXT
-- 注意：COPY 可以直接将 JSON 文件加载为 SUPER 列
