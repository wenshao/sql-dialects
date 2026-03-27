-- Apache Impala: 全文搜索
--
-- 参考资料:
--   [1] Impala SQL Reference
--       https://impala.apache.org/docs/build/html/topics/impala_langref.html
--   [2] Impala Built-in Functions
--       https://impala.apache.org/docs/build/html/topics/impala_functions.html

-- Impala 没有原生的全文搜索功能
-- 但可以使用字符串函数和正则表达式实现基本搜索

-- ============================================================
-- LIKE（模糊匹配）
-- ============================================================

SELECT * FROM articles WHERE content LIKE '%database%';
SELECT * FROM articles WHERE content LIKE '%database%' OR content LIKE '%performance%';

-- 大小写不敏感
SELECT * FROM articles WHERE LOWER(content) LIKE '%database%';

-- 多关键词（AND）
SELECT * FROM articles
WHERE LOWER(content) LIKE '%database%'
  AND LOWER(content) LIKE '%performance%';

-- 多关键词（OR）
SELECT * FROM articles
WHERE LOWER(content) LIKE '%database%'
   OR LOWER(content) LIKE '%performance%';

-- ============================================================
-- RLIKE / REGEXP（正则表达式）
-- ============================================================

-- 基本正则搜索
SELECT * FROM articles WHERE content RLIKE 'database|performance';

-- 大小写不敏感正则
SELECT * FROM articles WHERE content RLIKE '(?i)database';

-- 词边界（近似）
SELECT * FROM articles WHERE content RLIKE '\\bdatabase\\b';

-- 复杂正则
SELECT * FROM articles
WHERE content RLIKE '(?i)(full.text.search|fulltext)';

-- ============================================================
-- INSTR（精确查找）
-- ============================================================

SELECT * FROM articles WHERE INSTR(LOWER(content), 'database') > 0;

-- 统计关键词出现次数
SELECT title,
    (LENGTH(content) - LENGTH(REPLACE(LOWER(content), 'database', ''))) / 8 AS match_count
FROM articles
WHERE LOWER(content) LIKE '%database%'
ORDER BY match_count DESC;

-- ============================================================
-- 外部全文搜索方案
-- ============================================================

-- 方案一：将数据导入 Elasticsearch，通过 Elasticsearch 搜索
-- 方案二：使用 Apache Solr 索引数据
-- 方案三：在 Hive 中使用 UDF 调用外部搜索引擎

-- ============================================================
-- 搜索结果优化
-- ============================================================

-- 使用 CASE 实现简单的相关度评分
SELECT title, content,
    CASE WHEN LOWER(title) LIKE '%database%' THEN 10 ELSE 0 END +
    CASE WHEN LOWER(content) LIKE '%database%' THEN 5 ELSE 0 END +
    CASE WHEN LOWER(title) LIKE '%performance%' THEN 10 ELSE 0 END +
    CASE WHEN LOWER(content) LIKE '%performance%' THEN 5 ELSE 0 END AS score
FROM articles
WHERE LOWER(title) LIKE '%database%'
   OR LOWER(content) LIKE '%database%'
   OR LOWER(title) LIKE '%performance%'
   OR LOWER(content) LIKE '%performance%'
ORDER BY score DESC;

-- 注意：Impala 没有原生全文搜索功能
-- 注意：LIKE 和 REGEXP 是全表扫描，性能较低
-- 注意：生产环境推荐使用 Elasticsearch/Solr 等外部搜索引擎
-- 注意：大数据场景下字符串搜索开销很大
