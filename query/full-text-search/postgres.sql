-- PostgreSQL: 全文搜索（8.3+ 内置）
--
-- 参考资料:
--   [1] PostgreSQL Documentation - Full Text Search
--       https://www.postgresql.org/docs/current/textsearch.html
--   [2] PostgreSQL Documentation - Text Search Functions
--       https://www.postgresql.org/docs/current/functions-textsearch.html
--   [3] PostgreSQL Documentation - GIN Indexes
--       https://www.postgresql.org/docs/current/gin.html

-- 基本搜索：tsvector + tsquery
SELECT * FROM articles
WHERE to_tsvector('english', content) @@ to_tsquery('english', 'database & performance');

-- 运算符
-- &: AND
-- |: OR
-- !: NOT
-- <->: 相邻（短语搜索，9.6+）
SELECT * FROM articles
WHERE to_tsvector('english', content) @@ to_tsquery('english', 'full <-> text <-> search');

-- 带排名
SELECT title,
    ts_rank(to_tsvector('english', content), to_tsquery('english', 'database')) AS rank
FROM articles
WHERE to_tsvector('english', content) @@ to_tsquery('english', 'database')
ORDER BY rank DESC;

-- ts_rank_cd（覆盖密度排名，考虑匹配词的距离）
SELECT title,
    ts_rank_cd(to_tsvector('english', content), to_tsquery('english', 'database & performance')) AS rank
FROM articles
WHERE to_tsvector('english', content) @@ to_tsquery('english', 'database & performance')
ORDER BY rank DESC;

-- GIN 索引加速
CREATE INDEX idx_ft ON articles USING gin (to_tsvector('english', content));

-- 存储 tsvector 列（避免每次计算）
-- 注意：to_tsvector 是 STABLE 函数，不能用于 GENERATED ALWAYS AS 生成列
-- 需要用触发器维护
ALTER TABLE articles ADD COLUMN search_vector tsvector;
CREATE INDEX idx_search ON articles USING gin (search_vector);

CREATE OR REPLACE FUNCTION articles_search_vector_update() RETURNS TRIGGER AS $$
BEGIN
    NEW.search_vector = to_tsvector('english', coalesce(NEW.title,'') || ' ' || coalesce(NEW.content,''));
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER trg_articles_search_vector
    BEFORE INSERT OR UPDATE ON articles
    FOR EACH ROW
    EXECUTE FUNCTION articles_search_vector_update();

-- plainto_tsquery（自动处理空格为 AND）
SELECT * FROM articles
WHERE to_tsvector('english', content) @@ plainto_tsquery('english', 'database performance');

-- phraseto_tsquery（9.6+，短语查询）
SELECT * FROM articles
WHERE to_tsvector('english', content) @@ phraseto_tsquery('english', 'full text search');

-- websearch_to_tsquery（11+，支持搜索引擎语法）
SELECT * FROM articles
WHERE to_tsvector('english', content) @@ websearch_to_tsquery('english', '"full text" -mysql');

-- 高亮显示
SELECT ts_headline('english', content, to_tsquery('english', 'database'),
    'StartSel=<b>, StopSel=</b>, MaxFragments=3')
FROM articles
WHERE to_tsvector('english', content) @@ to_tsquery('english', 'database');

-- 中文支持：需要安装 zhparser 或 pg_jieba 扩展
