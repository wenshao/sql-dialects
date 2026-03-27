-- TDSQL: 全文搜索
-- TDSQL distributed MySQL-compatible syntax.
-- Note: Full-text search support is limited in TDSQL distributed mode.
--
-- 参考资料:
--   [1] TDSQL-C MySQL Documentation
--       https://cloud.tencent.com/document/product/1003
--   [2] TDSQL MySQL Documentation
--       https://cloud.tencent.com/document/product/557

-- 创建全文索引（部分版本支持）
CREATE FULLTEXT INDEX idx_ft_bio ON users (bio);
CREATE FULLTEXT INDEX idx_ft_multi ON articles (title, content);

-- 自然语言模式
SELECT * FROM articles
WHERE MATCH(title, content) AGAINST('database performance');

-- 带相关度分数
SELECT title, MATCH(title, content) AGAINST('database performance') AS score
FROM articles
WHERE MATCH(title, content) AGAINST('database performance')
ORDER BY score DESC;

-- 布尔模式
SELECT * FROM articles
WHERE MATCH(title, content) AGAINST('+database -mysql' IN BOOLEAN MODE);

-- 短语搜索
SELECT * FROM articles
WHERE MATCH(title, content) AGAINST('"full text search"' IN BOOLEAN MODE);

-- 替代方案：使用 LIKE 进行模糊搜索
SELECT * FROM articles WHERE content LIKE '%database%';

-- 替代方案：使用 REGEXP 正则搜索
SELECT * FROM articles WHERE content REGEXP 'database|performance';

-- 注意事项：
-- 全文索引在分布式模式下支持有限
-- 全文索引只在各分片内独立生效
-- 建议使用外部搜索引擎（如 Elasticsearch）处理全文搜索
-- LIKE '%keyword%' 无法使用索引，性能差
