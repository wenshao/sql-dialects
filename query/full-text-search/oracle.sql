-- Oracle: 全文搜索（Oracle Text）
--
-- 参考资料:
--   [1] Oracle Text Reference
--       https://docs.oracle.com/en/database/oracle/oracle-database/23/ccref/
--   [2] Oracle SQL Language Reference
--       https://docs.oracle.com/en/database/oracle/oracle-database/23/sqlrf/

-- 创建全文索引
CREATE INDEX idx_ft_content ON articles (content) INDEXTYPE IS CTXSYS.CONTEXT;

-- 基本搜索
SELECT * FROM articles WHERE CONTAINS(content, 'database') > 0;

-- 运算符
SELECT * FROM articles WHERE CONTAINS(content, 'database AND performance') > 0;
SELECT * FROM articles WHERE CONTAINS(content, 'database OR mysql') > 0;
SELECT * FROM articles WHERE CONTAINS(content, 'database NOT mysql') > 0;
SELECT * FROM articles WHERE CONTAINS(content, 'database NEAR performance') > 0;

-- 短语搜索
SELECT * FROM articles WHERE CONTAINS(content, '{full text search}') > 0;

-- 通配符
SELECT * FROM articles WHERE CONTAINS(content, 'data%') > 0;     -- 后缀通配
SELECT * FROM articles WHERE CONTAINS(content, '%base') > 0;     -- 前缀通配

-- 模糊搜索
SELECT * FROM articles WHERE CONTAINS(content, 'FUZZY(database, 70, 5)') > 0;

-- 带相关度分数
SELECT title, SCORE(1) AS relevance
FROM articles
WHERE CONTAINS(content, 'database', 1) > 0
ORDER BY SCORE(1) DESC;

-- CATSEARCH（简化的搜索，用于 CTXCAT 索引）
CREATE INDEX idx_cat ON articles (title) INDEXTYPE IS CTXSYS.CTXCAT;
SELECT * FROM articles WHERE CATSEARCH(title, 'database', NULL) > 0;

-- 同步索引（全文索引不自动更新）
EXEC CTX_DDL.SYNC_INDEX('idx_ft_content');

-- 12c+: SDATA（结构化数据与全文搜索结合）
-- 12c+: 支持 JSON 搜索
-- 12c+: CONTEXT 索引支持近实时同步

-- 中文支持：CHINESE_LEXER（内置）
