-- StarRocks: 全文搜索
--
-- 参考资料:
--   [1] StarRocks - String Functions
--       https://docs.starrocks.io/docs/sql-reference/sql-functions/string-functions/
--   [2] StarRocks SQL Functions
--       https://docs.starrocks.io/docs/sql-reference/sql-functions/

-- LIKE 模糊搜索
SELECT * FROM articles
WHERE content LIKE '%database%';

-- 正则表达式搜索
SELECT * FROM articles
WHERE content REGEXP '(?i)database.*performance';

-- INSTR（查找子字符串位置）
SELECT * FROM articles
WHERE INSTR(LOWER(content), 'database') > 0;

-- LOCATE（查找子字符串位置）
SELECT * FROM articles
WHERE LOCATE('database', LOWER(content)) > 0;

-- 多关键词搜索（OR）
SELECT * FROM articles
WHERE content REGEXP '(?i)(database|performance|optimization)';

-- 多关键词搜索（AND）
SELECT * FROM articles
WHERE content LIKE '%database%' AND content LIKE '%performance%';

-- 简单相关度排序
SELECT title,
    (LENGTH(content) - LENGTH(REPLACE(LOWER(content), 'database', ''))) / LENGTH('database') AS keyword_count
FROM articles
WHERE content LIKE '%database%'
ORDER BY keyword_count DESC;

-- GIN 索引加速（3.3+，倒排索引）
-- CREATE INDEX idx_content ON articles (content) USING GIN;
-- 创建索引后可加速 LIKE、MATCH 等搜索

-- 注意：StarRocks 原生不支持全文搜索引擎（如 tsvector/tsquery）
-- 注意：StarRocks 3.3+ 引入 GIN（倒排）索引，可加速字符串匹配
-- 注意：所有字符串搜索默认需要全表扫描
-- 注意：如需高性能全文搜索，建议集成 Elasticsearch
