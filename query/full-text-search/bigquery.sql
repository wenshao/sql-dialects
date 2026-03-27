-- BigQuery: 全文搜索
--
-- 参考资料:
--   [1] BigQuery SQL Reference - SEARCH Function
--       https://cloud.google.com/bigquery/docs/reference/standard-sql/search-function
--   [2] BigQuery SQL Reference - Search Index
--       https://cloud.google.com/bigquery/docs/reference/standard-sql/search-index

-- BigQuery 支持 Search Index + SEARCH 函数进行全文搜索
-- 也可以使用字符串函数和正则表达式进行模糊匹配

-- LIKE 模糊搜索
SELECT * FROM articles
WHERE content LIKE '%database%';

-- CONTAINS_SUBSTR（包含子字符串，大小写不敏感）
SELECT * FROM articles
WHERE CONTAINS_SUBSTR(content, 'database performance');

-- REGEXP_CONTAINS（正则表达式搜索）
SELECT * FROM articles
WHERE REGEXP_CONTAINS(content, r'(?i)database\s+performance');

-- REGEXP_CONTAINS 多关键词（OR）
SELECT * FROM articles
WHERE REGEXP_CONTAINS(content, r'(?i)(database|performance|optimization)');

-- STRPOS（查找子字符串位置，>0 表示包含）
SELECT * FROM articles
WHERE STRPOS(LOWER(content), 'database') > 0;

-- 简单相关度排序（基于关键词出现次数）
SELECT title,
    (LENGTH(content) - LENGTH(REPLACE(LOWER(content), 'database', ''))) / LENGTH('database') AS keyword_count
FROM articles
WHERE CONTAINS_SUBSTR(content, 'database')
ORDER BY keyword_count DESC;

-- SEARCH 函数（BigQuery Search Index，预览功能）
-- 需要先创建搜索索引
-- CREATE SEARCH INDEX idx_search ON articles (content);
SELECT * FROM articles
WHERE SEARCH(content, 'database performance');

-- SEARCH 函数 + 分析器
SELECT * FROM articles
WHERE SEARCH(content, 'database AND performance', analyzer => 'LOG_ANALYZER');

-- 注意：BigQuery Search Index + SEARCH 函数提供原生全文搜索能力
-- 注意：CONTAINS_SUBSTR 会扫描全表，大表性能较差
-- 注意：创建 Search Index 后 SEARCH 函数会利用索引加速查询
