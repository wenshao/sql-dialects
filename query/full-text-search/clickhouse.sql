-- ClickHouse: 全文搜索
--
-- 参考资料:
--   [1] ClickHouse - Full-Text Indexes
--       https://clickhouse.com/docs/en/sql-reference/statements/alter/skipping-index
--   [2] ClickHouse - String Search Functions
--       https://clickhouse.com/docs/en/sql-reference/functions/string-search-functions

-- LIKE 模糊搜索
SELECT * FROM articles
WHERE content LIKE '%database%';

-- ILIKE（大小写不敏感）
SELECT * FROM articles
WHERE content ILIKE '%database%';

-- hasToken / hasTokenCaseInsensitive（基于 token 的搜索，利用 tokenbf_v1 索引）
SELECT * FROM articles
WHERE hasToken(content, 'database');

SELECT * FROM articles
WHERE hasTokenCaseInsensitive(content, 'database');

-- multiSearchAny（多关键词搜索，任一匹配）
SELECT * FROM articles
WHERE multiSearchAnyCaseInsensitive(content, ['database', 'performance', 'optimization']);

-- multiSearchAll（所有关键词都匹配）
-- 无内置函数，需组合使用
SELECT * FROM articles
WHERE hasToken(content, 'database') AND hasToken(content, 'performance');

-- multiSearchFirstIndex（返回第一个匹配的关键词索引）
SELECT title,
    multiSearchFirstIndexCaseInsensitive(content, ['database', 'performance']) AS first_match
FROM articles
WHERE multiSearchAnyCaseInsensitive(content, ['database', 'performance']);

-- countSubstrings（统计子字符串出现次数）
SELECT title,
    countSubstringsCaseInsensitive(content, 'database') AS keyword_count
FROM articles
WHERE content ILIKE '%database%'
ORDER BY keyword_count DESC;

-- MATCH（正则表达式搜索）
SELECT * FROM articles
WHERE match(content, '(?i)database.*performance');

-- ngramSearch / ngramDistance（基于 n-gram 的模糊搜索，支持相似度计算）
SELECT title,
    ngramSearchCaseInsensitive(content, 'database') AS similarity
FROM articles
WHERE ngramSearchCaseInsensitive(content, 'database') > 0.3
ORDER BY similarity DESC;

-- 全文搜索索引（tokenbf_v1 / ngrambf_v1）
-- CREATE TABLE articles (
--     id UInt64,
--     title String,
--     content String,
--     INDEX idx_content content TYPE tokenbf_v1(10240, 3, 0) GRANULARITY 4,
--     INDEX idx_ngram  content TYPE ngrambf_v1(4, 10240, 3, 0) GRANULARITY 4
-- ) ENGINE = MergeTree() ORDER BY id;

-- 全文搜索索引（inverted，23.1+）
-- CREATE TABLE articles (
--     id UInt64,
--     content String,
--     INDEX idx_inv content TYPE full_text(0) GRANULARITY 1
-- ) ENGINE = MergeTree() ORDER BY id;

-- 注意：ClickHouse 的 tokenbf_v1 索引支持 hasToken 高效搜索
-- 注意：ngrambf_v1 索引支持 LIKE 和 ngram 搜索
-- 注意：23.1+ 支持 inverted（全文）索引，大幅提升全文搜索性能
-- 注意：ClickHouse 不支持 tsvector/tsquery 等传统全文搜索语法
