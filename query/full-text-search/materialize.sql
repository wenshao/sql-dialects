-- Materialize: 全文搜索
--
-- 参考资料:
--   [1] Materialize SQL Reference
--       https://materialize.com/docs/sql/
--   [2] Materialize SQL Functions
--       https://materialize.com/docs/sql/functions/

-- Materialize 支持基本的字符串匹配
-- 不支持 PostgreSQL 的 tsvector/tsquery 全文搜索

-- ============================================================
-- LIKE 模糊搜索
-- ============================================================

SELECT * FROM articles WHERE content LIKE '%database%';
SELECT * FROM articles WHERE content LIKE 'Data%';
SELECT * FROM articles WHERE content LIKE '%_base%';

-- ILIKE（大小写不敏感）
SELECT * FROM articles WHERE content ILIKE '%database%';

-- ============================================================
-- 正则表达式
-- ============================================================

-- ~ 正则匹配（大小写敏感）
SELECT * FROM articles WHERE content ~ 'database\s+performance';

-- ~* 正则匹配（大小写不敏感）
SELECT * FROM articles WHERE content ~* 'database\s+performance';

-- !~ 不匹配
SELECT * FROM articles WHERE content !~ 'error';

-- ============================================================
-- 字符串函数辅助搜索
-- ============================================================

-- POSITION
SELECT * FROM articles WHERE POSITION('database' IN LOWER(content)) > 0;

-- LENGTH 过滤
SELECT * FROM articles WHERE LENGTH(content) > 100;

-- 简单相关度排序（基于关键词出现位置）
SELECT title,
    POSITION('database' IN LOWER(content)) AS first_pos
FROM articles
WHERE content ILIKE '%database%'
ORDER BY first_pos;

-- ============================================================
-- 物化视图中的搜索
-- ============================================================

-- 创建过滤的物化视图
CREATE MATERIALIZED VIEW db_articles AS
SELECT * FROM articles WHERE content ILIKE '%database%';

-- 实时搜索结果（增量更新）
SELECT * FROM db_articles ORDER BY created_at DESC;

-- 多关键词搜索
CREATE MATERIALIZED VIEW tech_articles AS
SELECT * FROM articles
WHERE content ~* '(database|performance|optimization)';

-- ============================================================
-- 不支持的全文搜索功能
-- ============================================================

-- 不支持 tsvector / tsquery
-- 不支持 GIN 全文索引
-- 不支持 ts_rank / ts_rank_cd
-- 不支持 ts_headline
-- 不支持分词器

-- 注意：Materialize 不支持 PostgreSQL 的全文搜索系统
-- 注意：仅支持 LIKE、ILIKE 和正则表达式
-- 注意：可以通过物化视图实现实时搜索过滤
-- 注意：高级全文搜索建议使用外部搜索引擎
