-- Hive: 全文搜索
--
-- 参考资料:
--   [1] Apache Hive Language Manual - UDF
--       https://cwiki.apache.org/confluence/display/Hive/LanguageManual+UDF
--   [2] Apache Hive Language Manual - SELECT
--       https://cwiki.apache.org/confluence/display/Hive/LanguageManual+Select

-- 注意：Hive 没有内置全文搜索引擎
-- 需要使用字符串函数和正则表达式模拟

-- LIKE 模糊搜索
SELECT * FROM articles
WHERE content LIKE '%database%';

-- RLIKE / REGEXP（正则表达式搜索）
SELECT * FROM articles
WHERE content RLIKE '(?i)database.*performance';

SELECT * FROM articles
WHERE content REGEXP '(?i)database';

-- INSTR（查找子字符串位置）
SELECT * FROM articles
WHERE INSTR(LOWER(content), 'database') > 0;

-- LOCATE（查找子字符串位置）
SELECT * FROM articles
WHERE LOCATE('database', LOWER(content)) > 0;

-- REGEXP_EXTRACT（提取匹配的内容）
SELECT title,
    REGEXP_EXTRACT(content, '(database\\w*)', 1) AS matched
FROM articles
WHERE content RLIKE '(?i)database';

-- 多关键词搜索（OR）
SELECT * FROM articles
WHERE content RLIKE '(?i)(database|performance|optimization)';

-- 多关键词搜索（AND）
SELECT * FROM articles
WHERE content LIKE '%database%' AND content LIKE '%performance%';

-- 简单相关度排序
SELECT title,
    (LENGTH(content) - LENGTH(REGEXP_REPLACE(LOWER(content), 'database', ''))) / LENGTH('database') AS keyword_count
FROM articles
WHERE content RLIKE '(?i)database'
ORDER BY keyword_count DESC;

-- 自定义 UDF 实现全文搜索
-- 可以编写 Hive UDF 集成 Lucene 等搜索引擎库

-- 注意：Hive 不支持全文搜索索引
-- 注意：所有字符串搜索都需要全表扫描或全分区扫描
-- 注意：建议对搜索列做分区或分桶以缩小扫描范围
-- 注意：如需全文搜索建议使用 Elasticsearch + Hive 联合方案
