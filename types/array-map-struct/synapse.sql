-- Azure Synapse Analytics: 复合/复杂类型 (Array, Map, Struct)
--
-- 参考资料:
--   [1] Azure Synapse Documentation - JSON Functions
--       https://learn.microsoft.com/en-us/azure/synapse-analytics/sql/query-json-files
--   [2] Microsoft Docs - OPENJSON
--       https://learn.microsoft.com/en-us/sql/t-sql/functions/openjson-transact-sql
--   [3] Azure Synapse Documentation - Serverless SQL Pool
--       https://learn.microsoft.com/en-us/azure/synapse-analytics/sql/on-demand-workspace-overview

-- ============================================================
-- Synapse 没有原生 ARRAY / MAP / STRUCT 类型
-- 使用 JSON (NVARCHAR) 作为替代
-- ============================================================

-- ============================================================
-- Dedicated SQL Pool（与 SQL Server 类似）
-- ============================================================

CREATE TABLE users (
    id       BIGINT NOT NULL,
    name     NVARCHAR(100) NOT NULL,
    tags     NVARCHAR(MAX),                    -- 存储 JSON 数组
    metadata NVARCHAR(MAX)                     -- 存储 JSON 对象
)
WITH (DISTRIBUTION = HASH(id), CLUSTERED COLUMNSTORE INDEX);

INSERT INTO users VALUES (1, 'Alice', '["admin","dev"]', '{"city":"NYC"}');

-- JSON 函数
SELECT JSON_VALUE(tags, '$[0]') FROM users;
SELECT JSON_VALUE(metadata, '$.city') FROM users;
SELECT ISJSON(tags) FROM users;

-- OPENJSON 展开
SELECT u.name, j.value AS tag
FROM users u
CROSS APPLY OPENJSON(u.tags) j;

-- OPENJSON 强类型展开
SELECT u.name, j.tag
FROM users u
CROSS APPLY OPENJSON(u.tags) WITH (tag NVARCHAR(50) '$') j;

-- JSON_MODIFY
UPDATE users SET metadata = JSON_MODIFY(metadata, '$.zip', '10001') WHERE id = 1;

-- FOR JSON PATH（结果转 JSON）
SELECT name, id FROM users FOR JSON PATH;

-- STRING_AGG（聚合为分隔字符串）
SELECT department, STRING_AGG(name, ', ') AS members
FROM employees GROUP BY department;

-- ============================================================
-- Serverless SQL Pool（查询外部数据）
-- ============================================================

-- Serverless 可以直接查询 Parquet/JSON/CSV 文件中的嵌套数据
SELECT
    result.tags,
    result.metadata.city
FROM OPENROWSET(
    BULK 'https://storage.blob.core.windows.net/data/*.parquet',
    FORMAT = 'PARQUET'
) AS result;

-- ============================================================
-- 注意事项
-- ============================================================

-- 1. Dedicated SQL Pool 使用 NVARCHAR(MAX) 存储 JSON
-- 2. 支持 OPENJSON / JSON_VALUE / JSON_QUERY
-- 3. Serverless SQL Pool 可以查询嵌套 Parquet/JSON 数据
-- 4. 不支持 SQL Server 2022 的 JSON_ARRAY/JSON_OBJECT
-- 5. 参见 sqlserver.sql 获取更多 JSON 函数
