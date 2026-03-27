-- Trino: 全文搜索
--
-- 参考资料:
--   [1] Trino - String Functions
--       https://trino.io/docs/current/functions/string.html
--   [2] Trino - Regular Expression Functions
--       https://trino.io/docs/current/functions/regexp.html

-- 注意：Trino 自身没有全文搜索引擎
-- 搜索能力取决于底层连接器

-- LIKE 模糊搜索
SELECT * FROM articles
WHERE content LIKE '%database%';

-- 正则表达式搜索（regexp_like）
SELECT * FROM articles
WHERE regexp_like(content, '(?i)database.*performance');

-- STRPOS（查找子字符串位置）
SELECT * FROM articles
WHERE STRPOS(LOWER(content), 'database') > 0;

-- POSITION
SELECT * FROM articles
WHERE POSITION('database' IN LOWER(content)) > 0;

-- 多关键词搜索（OR）
SELECT * FROM articles
WHERE regexp_like(content, '(?i)(database|performance|optimization)');

-- 多关键词搜索（AND）
SELECT * FROM articles
WHERE STRPOS(LOWER(content), 'database') > 0
  AND STRPOS(LOWER(content), 'performance') > 0;

-- 简单相关度排序
SELECT title,
    regexp_count(content, '(?i)database') AS keyword_count
FROM articles
WHERE regexp_like(content, '(?i)database')
ORDER BY keyword_count DESC;

-- Elasticsearch 连接器（透传全文搜索到 Elasticsearch）
-- 使用 Elasticsearch catalog 时可以利用 ES 的全文搜索能力
-- SELECT * FROM elasticsearch.default.articles
-- WHERE content LIKE '%database%';
-- Elasticsearch 连接器会将 LIKE 翻译为 ES 查询

-- JMX / Hive / MySQL 等连接器
-- 搜索能力取决于底层存储引擎

-- 注意：Trino 自身不提供全文搜索索引
-- 注意：LIKE / REGEXP 搜索需要全表扫描
-- 注意：通过 Elasticsearch 连接器可利用 ES 全文搜索能力
-- 注意：通过 MySQL/PostgreSQL 连接器可利用对应数据库的全文搜索
