-- H2: 全文搜索
--
-- 参考资料:
--   [1] H2 SQL Reference - Commands
--       https://h2database.com/html/commands.html
--   [2] H2 - Data Types
--       https://h2database.com/html/datatypes.html
--   [3] H2 - Functions
--       https://h2database.com/html/functions.html

-- H2 内置全文搜索引擎和 Lucene 集成

-- ============================================================
-- 内置全文搜索（FullText）
-- ============================================================

-- 初始化全文搜索
CREATE ALIAS IF NOT EXISTS FT_INIT FOR 'org.h2.fulltext.FullText.init';
CALL FT_INIT();

-- 在表的列上创建全文索引
CALL FT_CREATE_INDEX('PUBLIC', 'ARTICLES', 'TITLE,CONTENT');

-- 全文搜索
SELECT * FROM FT_SEARCH('database performance', 10, 0);
-- 参数：搜索词, 限制行数, 偏移量

-- 按数据搜索
SELECT T.* FROM FT_SEARCH_DATA('database', 0, 0) FT, ARTICLES T
WHERE FT.TABLE = 'ARTICLES' AND T.ID = FT.KEYS[1];

-- 删除全文索引
CALL FT_DROP_INDEX('PUBLIC', 'ARTICLES');

-- 重建全文索引
CALL FT_REINDEX();

-- ============================================================
-- Lucene 全文搜索（更强大）
-- ============================================================

-- 初始化 Lucene 引擎
CREATE ALIAS IF NOT EXISTS FTL_INIT FOR 'org.h2.fulltext.FullTextLucene.init';
CALL FTL_INIT();

-- 创建 Lucene 全文索引
CALL FTL_CREATE_INDEX('PUBLIC', 'ARTICLES', 'TITLE,CONTENT');

-- Lucene 搜索
SELECT * FROM FTL_SEARCH('database AND performance', 10, 0);

-- Lucene 布尔搜索
SELECT * FROM FTL_SEARCH('database OR optimization', 10, 0);
SELECT * FROM FTL_SEARCH('"database performance"', 10, 0);    -- 短语搜索
SELECT * FROM FTL_SEARCH('database NOT slow', 10, 0);

-- 删除 Lucene 索引
CALL FTL_DROP_INDEX('PUBLIC', 'ARTICLES');

-- ============================================================
-- LIKE 模糊搜索
-- ============================================================

SELECT * FROM articles WHERE content LIKE '%database%';
SELECT * FROM articles WHERE LOWER(content) LIKE '%database%';

-- ============================================================
-- 正则表达式
-- ============================================================

SELECT * FROM articles WHERE content REGEXP 'database\s+performance';
SELECT * FROM articles WHERE REGEXP_LIKE(content, 'database|optimization', 'i');

-- ============================================================
-- REGEXP_REPLACE / REGEXP_SUBSTR
-- ============================================================

SELECT REGEXP_REPLACE(content, '(?i)database', '<b>DATABASE</b>') AS highlighted
FROM articles WHERE content LIKE '%database%';

-- 注意：H2 内置两种全文搜索引擎
-- 注意：内置 FullText 简单但功能有限
-- 注意：Lucene 引擎功能更强（需要 Lucene 库）
-- 注意：全文索引通过 CALL 存储过程管理
-- 注意：也支持标准 LIKE 和正则表达式
