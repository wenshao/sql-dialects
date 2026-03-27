-- Redshift: 全文搜索
--
-- 参考资料:
--   [1] Redshift SQL Reference
--       https://docs.aws.amazon.com/redshift/latest/dg/cm_chap_SQLCommandRef.html
--   [2] Redshift SQL Functions
--       https://docs.aws.amazon.com/redshift/latest/dg/c_SQL_functions.html
--   [3] Redshift Data Types
--       https://docs.aws.amazon.com/redshift/latest/dg/c_Supported_data_types.html

-- Redshift 没有内置全文搜索引擎
-- 使用 LIKE / ILIKE / 正则表达式进行文本搜索

-- ============================================================
-- LIKE / ILIKE（基本文本搜索）
-- ============================================================

-- LIKE（大小写敏感）
SELECT * FROM articles WHERE content LIKE '%database%';
SELECT * FROM articles WHERE content LIKE 'database%';     -- 前缀匹配
SELECT * FROM articles WHERE content LIKE '%database';     -- 后缀匹配

-- ILIKE（大小写不敏感，Redshift 扩展）
SELECT * FROM articles WHERE content ILIKE '%database%';

-- 通配符：% 任意字符序列，_ 单个字符
SELECT * FROM articles WHERE title LIKE 'SQL_____';        -- 8 字符以 SQL 开头

-- ============================================================
-- 正则表达式
-- ============================================================

-- POSIX 正则匹配（~ 大小写敏感，~* 不敏感）
SELECT * FROM articles WHERE content ~ 'data(base|warehouse)';
SELECT * FROM articles WHERE content ~* 'data(base|warehouse)';  -- 不区分大小写

-- SIMILAR TO（SQL 标准正则）
SELECT * FROM articles WHERE content SIMILAR TO '%data(base|warehouse)%';

-- REGEXP_SUBSTR（提取匹配）
SELECT REGEXP_SUBSTR(content, '[A-Z][a-z]+') AS first_word FROM articles;

-- REGEXP_REPLACE（替换）
SELECT REGEXP_REPLACE(content, '[0-9]+', '#') FROM articles;

-- REGEXP_COUNT（计数）
SELECT REGEXP_COUNT(content, 'database') AS match_count FROM articles;

-- REGEXP_INSTR（查找位置）
SELECT REGEXP_INSTR(content, 'database') AS position FROM articles;

-- ============================================================
-- 模拟全文搜索（使用字符串函数）
-- ============================================================

-- 多关键词搜索
SELECT * FROM articles
WHERE content ILIKE '%database%'
  AND content ILIKE '%performance%';

-- 多关键词（任一匹配）
SELECT * FROM articles
WHERE content ILIKE '%database%'
   OR content ILIKE '%performance%';

-- 简单排名（按匹配数量）
SELECT title, relevance FROM (
    SELECT title,
        (CASE WHEN content ILIKE '%database%' THEN 1 ELSE 0 END +
         CASE WHEN content ILIKE '%performance%' THEN 1 ELSE 0 END +
         CASE WHEN content ILIKE '%optimization%' THEN 1 ELSE 0 END) AS relevance
    FROM articles
) t
WHERE relevance > 0
ORDER BY relevance DESC;

-- ============================================================
-- 外部全文搜索方案
-- ============================================================

-- 方案一：使用 Amazon OpenSearch（Elasticsearch）
-- 将数据同步到 OpenSearch，在 OpenSearch 中搜索
-- 使用 Redshift 联邦查询（Federated Query）连接 OpenSearch

-- 方案二：使用 Redshift Spectrum + AWS Glue
-- 在 Glue 中预处理全文索引
-- 通过 Spectrum 外部表查询

-- 注意：Redshift 没有原生全文搜索（无 tsvector / tsquery / FULLTEXT INDEX）
-- 注意：LIKE / ILIKE 在大表上性能较差（全表扫描）
-- 注意：正则表达式匹配比 LIKE 更灵活但也更慢
-- 注意：SORTKEY 不能加速 LIKE '%keyword%' 查询
-- 注意：建议将全文搜索需求卸载到 Amazon OpenSearch 等专用搜索引擎
