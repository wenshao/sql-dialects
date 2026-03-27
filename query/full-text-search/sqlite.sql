-- SQLite: 全文搜索（FTS 扩展）
--
-- 参考资料:
--   [1] SQLite Documentation - FTS5 Extension
--       https://www.sqlite.org/fts5.html
--   [2] SQLite Documentation - FTS3 and FTS4
--       https://www.sqlite.org/fts3.html

-- FTS5（3.9.0+，推荐）
CREATE VIRTUAL TABLE articles_fts USING fts5(title, content);

-- 插入数据
INSERT INTO articles_fts (title, content) VALUES ('SQLite FTS', 'Full text search in SQLite');

-- 基本搜索
SELECT * FROM articles_fts WHERE articles_fts MATCH 'database';

-- MATCH 语法
SELECT * FROM articles_fts WHERE articles_fts MATCH 'database AND performance';
SELECT * FROM articles_fts WHERE articles_fts MATCH 'database OR mysql';
SELECT * FROM articles_fts WHERE articles_fts MATCH 'database NOT mysql';
SELECT * FROM articles_fts WHERE articles_fts MATCH '"full text search"';  -- 短语

-- 指定列搜索
SELECT * FROM articles_fts WHERE articles_fts MATCH 'title:database';

-- 前缀搜索
SELECT * FROM articles_fts WHERE articles_fts MATCH 'data*';

-- 近邻搜索
SELECT * FROM articles_fts WHERE articles_fts MATCH 'NEAR(database performance, 5)';

-- 排名
SELECT *, rank FROM articles_fts WHERE articles_fts MATCH 'database' ORDER BY rank;

-- BM25 排名
SELECT *, bm25(articles_fts) AS score
FROM articles_fts WHERE articles_fts MATCH 'database'
ORDER BY score;

-- 高亮和摘要
SELECT highlight(articles_fts, 1, '<b>', '</b>') FROM articles_fts WHERE articles_fts MATCH 'database';
SELECT snippet(articles_fts, 1, '<b>', '</b>', '...', 64) FROM articles_fts WHERE articles_fts MATCH 'database';

-- 内容表关联（外部内容 FTS 表）
CREATE VIRTUAL TABLE articles_fts USING fts5(title, content, content='articles', content_rowid='id');

-- FTS3/FTS4（更旧的版本）
CREATE VIRTUAL TABLE articles_fts3 USING fts3(title, content);
CREATE VIRTUAL TABLE articles_fts4 USING fts4(title, content);
