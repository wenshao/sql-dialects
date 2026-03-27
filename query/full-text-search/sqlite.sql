-- SQLite: 全文搜索（FTS5 扩展）
--
-- 参考资料:
--   [1] SQLite Documentation - FTS5 Extension
--       https://www.sqlite.org/fts5.html

-- ============================================================
-- 1. FTS5 虚拟表
-- ============================================================

-- 创建全文搜索表
CREATE VIRTUAL TABLE docs USING fts5(title, body);

INSERT INTO docs (title, body) VALUES
    ('SQLite Guide', 'Learn SQLite database with examples'),
    ('SQL Tutorial', 'Comprehensive SQL reference for developers'),
    ('Python DB', 'Connect Python to SQLite and PostgreSQL');

-- ============================================================
-- 2. 全文搜索查询
-- ============================================================

-- MATCH 操作符
SELECT * FROM docs WHERE docs MATCH 'SQLite';
SELECT * FROM docs WHERE docs MATCH 'SQL AND tutorial';
SELECT * FROM docs WHERE docs MATCH 'SQL OR Python';
SELECT * FROM docs WHERE docs MATCH 'SQL NOT Python';

-- 列限定搜索
SELECT * FROM docs WHERE docs MATCH 'title:SQLite';
SELECT * FROM docs WHERE docs MATCH 'body:Python';

-- 前缀搜索
SELECT * FROM docs WHERE docs MATCH 'sql*';

-- 短语搜索（精确匹配词序）
SELECT * FROM docs WHERE docs MATCH '"SQL reference"';

-- 邻近搜索（NEAR）
SELECT * FROM docs WHERE docs MATCH 'NEAR(SQLite Python, 5)';

-- ============================================================
-- 3. 排名与高亮
-- ============================================================

-- BM25 排名
SELECT *, rank FROM docs WHERE docs MATCH 'SQL' ORDER BY rank;

-- 高亮
SELECT highlight(docs, 0, '<b>', '</b>') AS title,
       highlight(docs, 1, '<b>', '</b>') AS body
FROM docs WHERE docs MATCH 'SQL';

-- 片段（Snippet）
SELECT snippet(docs, 1, '<b>', '</b>', '...', 10) FROM docs WHERE docs MATCH 'SQL';

-- ============================================================
-- 4. FTS5 的设计特色（对引擎开发者）
-- ============================================================

-- FTS5 通过虚拟表机制实现，不是核心引擎的一部分:
-- (a) 虚拟表模块: SQLite 的虚拟表 API 允许插件式扩展
-- (b) 独立的倒排索引: 存储在 shadow tables 中（*_data, *_idx 等）
-- (c) 与普通表联合查询:
SELECT u.username, d.title
FROM users u
JOIN docs d ON d.body MATCH u.interest
WHERE u.status = 1;
-- 但: FTS5 表不支持 ALTER TABLE，不支持常规索引

-- 对比:
--   MySQL:      InnoDB FULLTEXT INDEX（集成到存储引擎）
--   PostgreSQL: GIN + tsvector（集成到核心索引系统，最灵活）
--   ClickHouse: tokenbf_v1/ngrambf_v1 跳过索引 + full_text 索引
--   BigQuery:   SEARCH INDEX + SEARCH() 函数

-- ============================================================
-- 5. 对比与引擎开发者启示
-- ============================================================
-- SQLite FTS5 的设计:
--   (1) 虚拟表模块 → 不增加核心引擎复杂度
--   (2) BM25 排名 → 开箱即用的相关性排序
--   (3) highlight/snippet → 搜索结果展示
--   (4) 与普通表 JOIN → 全文搜索 + 关系查询结合
--
-- 对引擎开发者的启示:
--   全文搜索通过虚拟表/插件机制实现是好的架构选择。
--   核心引擎保持简洁，全文搜索作为可选模块。
--   BM25 排名是全文搜索的基本要求（用户期望按相关性排序）。
