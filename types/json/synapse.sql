-- Azure Synapse: JSON 类型
--
-- 参考资料:
--   [1] Synapse SQL Features
--       https://learn.microsoft.com/en-us/azure/synapse-analytics/sql/overview-features
--   [2] Synapse T-SQL Differences
--       https://learn.microsoft.com/en-us/azure/synapse-analytics/sql/overview-features

-- Synapse 没有原生 JSON 列类型
-- 使用 NVARCHAR(MAX) 存储 JSON 数据，用 JSON 函数查询

CREATE TABLE events (
    id   BIGINT IDENTITY(1, 1),
    data NVARCHAR(MAX)                       -- 存储 JSON 字符串
);

-- 插入 JSON
INSERT INTO events (data) VALUES ('{"name": "alice", "age": 25, "tags": ["vip"]}');
INSERT INTO events (data) VALUES ('{"name": "bob", "age": 30}');

-- ============================================================
-- JSON 查询函数
-- ============================================================

-- JSON_VALUE（提取标量值，返回 NVARCHAR）
SELECT JSON_VALUE(data, '$.name') FROM events;              -- 'alice'
SELECT JSON_VALUE(data, '$.age') FROM events;               -- '25'（字符串）

-- JSON_QUERY（提取对象或数组，返回 JSON 字符串）
SELECT JSON_QUERY(data, '$.tags') FROM events;              -- '["vip"]'

-- 嵌套路径
SELECT JSON_VALUE(data, '$.address.city') FROM events;

-- 数组下标
SELECT JSON_VALUE(data, '$.tags[0]') FROM events;           -- 'vip'

-- ============================================================
-- JSON 验证和判断
-- ============================================================

-- ISJSON（验证是否为有效 JSON）
SELECT * FROM events WHERE ISJSON(data) = 1;

-- JSON_VALUE 类型转换
SELECT CAST(JSON_VALUE(data, '$.age') AS INT) AS age FROM events;

-- ============================================================
-- JSON_MODIFY（修改 JSON）
-- ============================================================

-- 修改/添加属性
UPDATE events
SET data = JSON_MODIFY(data, '$.name', 'alice_updated')
WHERE JSON_VALUE(data, '$.name') = 'alice';

-- 添加新属性
UPDATE events
SET data = JSON_MODIFY(data, '$.email', 'alice@example.com')
WHERE JSON_VALUE(data, '$.name') = 'alice';

-- 删除属性（设为 NULL）
UPDATE events
SET data = JSON_MODIFY(data, '$.phone', NULL)
WHERE JSON_VALUE(data, '$.name') = 'alice';

-- 追加数组元素
UPDATE events
SET data = JSON_MODIFY(data, 'append $.tags', 'premium')
WHERE JSON_VALUE(data, '$.name') = 'alice';

-- ============================================================
-- OPENJSON（展开 JSON 为行集）
-- ============================================================

-- 展开 JSON 对象
SELECT id, j.[key], j.[value]
FROM events
CROSS APPLY OPENJSON(data) j;

-- 展开 JSON 数组
SELECT id, tag.value AS tag
FROM events
CROSS APPLY OPENJSON(data, '$.tags') tag;

-- 带 Schema 的 OPENJSON
SELECT id, j.name, j.age
FROM events
CROSS APPLY OPENJSON(data) WITH (
    name NVARCHAR(64) '$.name',
    age  INT '$.age',
    tags NVARCHAR(MAX) '$.tags' AS JSON
) j;

-- ============================================================
-- JSON 构造
-- ============================================================

-- FOR JSON（查询结果转 JSON）
SELECT id, username AS name, age
FROM users
FOR JSON PATH;                               -- [{"id":1,"name":"alice","age":25}]

SELECT id, username AS name, age
FROM users
FOR JSON AUTO;                               -- 自动嵌套

-- ============================================================
-- 条件查询
-- ============================================================

SELECT * FROM events
WHERE JSON_VALUE(data, '$.name') = 'alice';

SELECT * FROM events
WHERE CAST(JSON_VALUE(data, '$.age') AS INT) > 25;

-- ============================================================
-- Serverless 池的 JSON 处理
-- ============================================================

-- 从 Parquet 文件读取嵌套 JSON
SELECT data.*
FROM OPENROWSET(
    BULK 'https://account.dfs.core.windows.net/container/*.parquet',
    FORMAT = 'PARQUET'
) WITH (
    data NVARCHAR(MAX)
) AS raw
CROSS APPLY OPENJSON(raw.data) WITH (
    name NVARCHAR(64),
    age INT
) data;

-- 注意：Synapse 没有原生 JSON 列类型，使用 NVARCHAR(MAX) 存储
-- 注意：列存储表中 NVARCHAR(MAX) 上限为 4000 字符
-- 注意：JSON_VALUE 返回标量值（最大 4000 NVARCHAR 字符）
-- 注意：JSON_QUERY 返回 JSON 对象/数组
-- 注意：OPENJSON 是展开 JSON 的强大工具
-- 注意：ISJSON 用于验证 JSON 格式
-- 注意：Serverless 池支持完整的 JSON 函数
