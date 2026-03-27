-- Snowflake: 全文搜索
--
-- 参考资料:
--   [1] Snowflake SQL Reference - LIKE / ILIKE
--       https://docs.snowflake.com/en/sql-reference/functions/like
--   [2] Snowflake SQL Reference - REGEXP
--       https://docs.snowflake.com/en/sql-reference/functions/rlike

-- 注意：Snowflake 没有内置全文搜索引擎
-- 需要使用字符串函数和正则表达式模拟

-- LIKE 模糊搜索
SELECT * FROM articles
WHERE content LIKE '%database%';

-- ILIKE（大小写不敏感）
SELECT * FROM articles
WHERE content ILIKE '%database%';

-- LIKE ANY / LIKE ALL（多模式匹配）
SELECT * FROM articles
WHERE content LIKE ANY ('%database%', '%performance%');

SELECT * FROM articles
WHERE content LIKE ALL ('%database%', '%performance%');

-- REGEXP / RLIKE（正则表达式搜索）
SELECT * FROM articles
WHERE content REGEXP '(?i)database.*performance';

-- REGEXP_LIKE
SELECT * FROM articles
WHERE REGEXP_LIKE(content, '(?i)database\\s+performance');

-- CONTAINS（子字符串匹配）
SELECT * FROM articles
WHERE CONTAINS(content, 'database');

-- POSITION / CHARINDEX（查找子字符串）
SELECT * FROM articles
WHERE POSITION('database' IN LOWER(content)) > 0;

-- 简单相关度排序（基于关键词出现次数）
SELECT title,
    REGEXP_COUNT(LOWER(content), 'database') AS keyword_count
FROM articles
WHERE CONTAINS(content, 'database')
ORDER BY keyword_count DESC;

-- COLLATE（指定排序规则进行搜索）
SELECT * FROM articles
WHERE content COLLATE 'en-ci' LIKE '%database%';

-- 注意：Snowflake 不支持原生全文搜索索引
-- 注意：Snowflake 的字符串搜索需要全表扫描
-- 注意：如需高性能全文搜索，建议集成外部搜索引擎（Elasticsearch 等）
-- 注意：Snowflake Search Optimization Service 可加速点查但非全文搜索
