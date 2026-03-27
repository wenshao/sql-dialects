-- Oracle: 全文搜索（Oracle Text）
--
-- 参考资料:
--   [1] Oracle Text Reference
--       https://docs.oracle.com/en/database/oracle/oracle-database/23/ccref/
--   [2] Oracle Text Application Developer's Guide
--       https://docs.oracle.com/en/database/oracle/oracle-database/23/ccapp/

-- ============================================================
-- 1. Oracle Text 索引类型
-- ============================================================

-- CONTEXT 索引（最常用，全文搜索）
CREATE INDEX idx_ft_content ON articles (content) INDEXTYPE IS CTXSYS.CONTEXT;

-- CTXCAT 索引（结构化 + 全文混合搜索）
CREATE INDEX idx_cat ON articles (title) INDEXTYPE IS CTXSYS.CTXCAT;

-- CTXRULE 索引（文档分类）
-- CREATE INDEX idx_rule ON rules (query) INDEXTYPE IS CTXSYS.CTXRULE;

-- ============================================================
-- 2. 基本搜索语法
-- ============================================================

-- CONTAINS（CONTEXT 索引）
SELECT * FROM articles WHERE CONTAINS(content, 'database') > 0;

-- 布尔运算符
SELECT * FROM articles WHERE CONTAINS(content, 'database AND performance') > 0;
SELECT * FROM articles WHERE CONTAINS(content, 'database OR mysql') > 0;
SELECT * FROM articles WHERE CONTAINS(content, 'database NOT mysql') > 0;

-- 短语搜索
SELECT * FROM articles WHERE CONTAINS(content, '{full text search}') > 0;

-- 通配符
SELECT * FROM articles WHERE CONTAINS(content, 'data%') > 0;
SELECT * FROM articles WHERE CONTAINS(content, '%base') > 0;

-- 邻近搜索（NEAR）
SELECT * FROM articles WHERE CONTAINS(content, 'database NEAR performance') > 0;

-- 模糊搜索
SELECT * FROM articles WHERE CONTAINS(content, 'FUZZY(database, 70, 5)') > 0;

-- ============================================================
-- 3. 相关度评分
-- ============================================================

-- SCORE() 函数返回相关度分数（1-100）
SELECT title, SCORE(1) AS relevance
FROM articles
WHERE CONTAINS(content, 'database', 1) > 0
ORDER BY SCORE(1) DESC;

-- ============================================================
-- 4. 设计分析（对引擎开发者）
-- ============================================================

-- 4.1 Oracle Text 的架构特点:
--   - 独立的索引类型系统（INDEXTYPE IS ...），不是内建在 B-tree 中
--   - 异步索引更新（DML 后索引不自动同步，需要手动 SYNC）
--   - 丰富的文本处理管线: 数据源 → 过滤器 → 分词器 → 索引
--
-- 索引同步:
EXEC CTX_DDL.SYNC_INDEX('idx_ft_content');

-- 4.2 与其他数据库全文搜索对比:
--   Oracle Text:   最完善但最复杂（索引类型、Lexer、过滤器可定制）
--                  异步更新是特色也是缺点
--   PostgreSQL:    tsvector + GIN 索引（内建，自动同步，最易用）
--                  ts_rank() 评分，to_tsvector() 分词
--   MySQL:         FULLTEXT INDEX（InnoDB 5.6+，BOOLEAN MODE/NL MODE）
--                  MATCH ... AGAINST ... 语法，自动同步
--   SQL Server:    Full-Text Index（类似 Oracle，异步更新）
--   Elasticsearch: 专业搜索引擎（倒排索引，实时，分布式）
--
-- 对引擎开发者的启示:
--   全文搜索至少需要: 倒排索引 + 分词器 + 布尔查询 + 相关度评分。
--   同步更新 vs 异步更新是关键设计决策:
--     同步: 一致性好但影响写入性能（PostgreSQL/MySQL 方案）
--     异步: 写入性能好但有延迟（Oracle/SQL Server 方案）

-- ============================================================
-- 5. '' = NULL 对全文搜索的影响
-- ============================================================

-- CONTAINS 对 NULL 列返回 0（不匹配）
-- 由于 '' = NULL，空字符串列也不会被全文索引覆盖
-- 这与 PostgreSQL（空字符串可以被 tsvector 处理）不同

-- ============================================================
-- 6. 中文支持
-- ============================================================

-- Oracle Text 内置中文分词器:
-- CHINESE_LEXER（基于词典的中文分词）
-- CHINESE_VGRAM_LEXER（N-gram 中文分词，不需要词典）

BEGIN
    CTX_DDL.CREATE_PREFERENCE('chinese_lex', 'CHINESE_LEXER');
END;
/

CREATE INDEX idx_cn ON articles (content)
    INDEXTYPE IS CTXSYS.CONTEXT
    PARAMETERS ('LEXER chinese_lex');

-- ============================================================
-- 7. 12c+ 增强: 近实时搜索索引
-- ============================================================

-- CONTEXT 索引支持近实时同步（减少手动 SYNC 需要）
-- 21c+: JSON 搜索索引
CREATE SEARCH INDEX idx_json_search ON events (data) FOR JSON;

-- ============================================================
-- 8. 对引擎开发者的总结
-- ============================================================
-- 1. Oracle Text 是最完善的数据库内建全文搜索，但异步更新是主要缺点。
-- 2. CONTAINS + SCORE 的组合提供了搜索 + 排序的完整方案。
-- 3. PostgreSQL 的 tsvector + GIN 方案更简单实用，适合大多数场景。
-- 4. 如果引擎面向的是搜索密集场景，应考虑集成 Elasticsearch 而非自建。
-- 5. 中文分词是 CJK 市场的必备功能，至少需要 N-gram 分词支持。
