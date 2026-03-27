-- MaxCompute: 全文搜索
--
-- 参考资料:
--   [1] MaxCompute - String Functions
--       https://help.aliyun.com/zh/maxcompute/user-guide/string-functions
--   [2] MaxCompute SQL Overview
--       https://help.aliyun.com/zh/maxcompute/user-guide/sql-overview

-- 注意：MaxCompute 没有内置全文搜索引擎
-- 需要使用字符串函数和正则表达式模拟

-- LIKE 模糊搜索
SELECT * FROM articles
WHERE content LIKE '%database%';

-- INSTR（查找子字符串位置）
SELECT * FROM articles
WHERE INSTR(LOWER(content), 'database') > 0;

-- REGEXP（正则表达式搜索）
SELECT * FROM articles
WHERE content RLIKE '(?i)database.*performance';

-- REGEXP_EXTRACT（提取匹配的内容）
SELECT title,
    REGEXP_EXTRACT(content, '(database\\w*)', 1) AS matched
FROM articles
WHERE content RLIKE '(?i)database';

-- REGEXP_COUNT（统计匹配次数）
SELECT title,
    REGEXP_COUNT(content, '(?i)database') AS keyword_count
FROM articles
WHERE content RLIKE '(?i)database'
ORDER BY keyword_count DESC;

-- 多关键词搜索
SELECT * FROM articles
WHERE content RLIKE '(?i)(database|performance|optimization)';

-- 必须同时包含多个关键词
SELECT * FROM articles
WHERE content LIKE '%database%' AND content LIKE '%performance%';

-- 简单相关度计算
SELECT title,
    (LENGTH(content) - LENGTH(REPLACE(LOWER(content), 'database', ''))) / LENGTH('database') AS keyword_count
FROM articles
WHERE content LIKE '%database%'
ORDER BY keyword_count DESC;

-- 注意：MaxCompute 不支持全文搜索索引
-- 注意：所有字符串搜索都需要全表扫描
-- 注意：大数据量下 LIKE '%keyword%' 性能较差
-- 注意：如需全文搜索建议将数据导出到 Elasticsearch 或 OpenSearch
