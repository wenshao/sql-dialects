-- KingbaseES (人大金仓): 全文搜索
-- PostgreSQL compatible tsvector/tsquery approach.
--
-- 参考资料:
--   [1] KingbaseES SQL Reference
--       https://help.kingbase.com.cn/v8/index.html
--   [2] KingbaseES Documentation
--       https://help.kingbase.com.cn/v8/index.html

-- 基本搜索：tsvector + tsquery
SELECT * FROM articles
WHERE to_tsvector('english', content) @@ to_tsquery('english', 'database & performance');

-- 运算符
-- &: AND
-- |: OR
-- !: NOT
-- <->: 相邻
SELECT * FROM articles
WHERE to_tsvector('english', content) @@ to_tsquery('english', 'full <-> text <-> search');

-- 带排名
SELECT title,
    ts_rank(to_tsvector('english', content), to_tsquery('english', 'database')) AS rank
FROM articles
WHERE to_tsvector('english', content) @@ to_tsquery('english', 'database')
ORDER BY rank DESC;

-- ts_rank_cd（覆盖密度排名）
SELECT title,
    ts_rank_cd(to_tsvector('english', content), to_tsquery('english', 'database & performance')) AS rank
FROM articles
WHERE to_tsvector('english', content) @@ to_tsquery('english', 'database & performance')
ORDER BY rank DESC;

-- GIN 索引加速
CREATE INDEX idx_ft ON articles USING gin (to_tsvector('english', content));

-- 存储 tsvector 列
ALTER TABLE articles ADD COLUMN search_vector tsvector
    GENERATED ALWAYS AS (to_tsvector('english', coalesce(title,'') || ' ' || coalesce(content,''))) STORED;
CREATE INDEX idx_search ON articles USING gin (search_vector);

-- plainto_tsquery
SELECT * FROM articles
WHERE to_tsvector('english', content) @@ plainto_tsquery('english', 'database performance');

-- 高亮显示
SELECT ts_headline('english', content, to_tsquery('english', 'database'),
    'StartSel=<b>, StopSel=</b>, MaxFragments=3')
FROM articles
WHERE to_tsvector('english', content) @@ to_tsquery('english', 'database');

-- 注意事项：
-- 全文搜索语法与 PostgreSQL 完全兼容
-- 使用 GIN 索引加速
-- 中文支持需要安装分词扩展
