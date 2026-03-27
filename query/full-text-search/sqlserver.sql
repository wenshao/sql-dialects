-- SQL Server: 全文搜索 (Full-Text Search)
--
-- 参考资料:
--   [1] SQL Server - Full-Text Search
--       https://learn.microsoft.com/en-us/sql/relational-databases/search/full-text-search
--   [2] SQL Server T-SQL - CONTAINS / FREETEXT
--       https://learn.microsoft.com/en-us/sql/t-sql/queries/contains-transact-sql

-- ============================================================
-- 1. 全文索引创建
-- ============================================================

-- 创建全文目录（逻辑容器）
CREATE FULLTEXT CATALOG ft_catalog AS DEFAULT;

-- 创建全文索引（必须有唯一索引作为键）
CREATE FULLTEXT INDEX ON articles (title, content)
    KEY INDEX pk_articles ON ft_catalog;

-- 设计分析（对引擎开发者）:
--   SQL Server 的全文搜索是独立的子系统（Full-Text Engine, iFTS），
--   不是存储引擎的一部分。它使用倒排索引（Inverted Index），
--   但管理方式与常规索引完全不同:
--   (1) 异步更新（默认自动跟踪变更，但有延迟）
--   (2) 需要专门的全文目录和唯一键索引
--   (3) 不参与常规查询优化器的成本估算
--
-- 横向对比:
--   PostgreSQL: tsvector/tsquery 类型 + GIN 索引（与常规索引统一管理）
--   MySQL:      InnoDB 5.6+ 支持全文索引（FULLTEXT INDEX，语法更简洁）
--   Oracle:     Oracle Text（独立组件，功能最丰富）
--   Elasticsearch: 专用全文搜索引擎（功能远超任何关系数据库）
--
-- 对引擎开发者的启示:
--   PostgreSQL 的做法最优雅——将全文搜索集成到类型系统中（tsvector 类型），
--   使用标准的 GIN 索引，不需要额外的目录管理。
--   SQL Server 的独立子系统增加了管理复杂度但提供了更高的搜索质量。

-- ============================================================
-- 2. CONTAINS: 精确匹配搜索
-- ============================================================

SELECT * FROM articles WHERE CONTAINS(content, 'database');
SELECT * FROM articles WHERE CONTAINS(content, 'database AND performance');
SELECT * FROM articles WHERE CONTAINS(content, 'database OR mysql');
SELECT * FROM articles WHERE CONTAINS(content, 'database AND NOT mysql');
SELECT * FROM articles WHERE CONTAINS(content, 'database NEAR performance');

-- 短语搜索
SELECT * FROM articles WHERE CONTAINS(content, '"full text search"');

-- 前缀搜索
SELECT * FROM articles WHERE CONTAINS(content, '"data*"');

-- 加权搜索
SELECT * FROM articles WHERE CONTAINS(content,
    'ISABOUT(database WEIGHT(0.8), performance WEIGHT(0.2))');

-- ============================================================
-- 3. FREETEXT: 语义搜索（自动词干提取和同义词）
-- ============================================================

SELECT * FROM articles WHERE FREETEXT(content, 'database performance tuning');
-- FREETEXT 自动处理: 词干提取（running→run）、同义词、停用词过滤

-- ============================================================
-- 4. CONTAINSTABLE / FREETEXTTABLE: 返回排名
-- ============================================================

-- CONTAINSTABLE 返回 KEY 和 RANK 列（可用于排序）
SELECT a.title, ft.RANK
FROM articles a
JOIN CONTAINSTABLE(articles, content, 'database') ft ON a.id = ft.[KEY]
ORDER BY ft.RANK DESC;

-- FREETEXTTABLE
SELECT a.title, ft.RANK
FROM articles a
JOIN FREETEXTTABLE(articles, content, 'database performance') ft ON a.id = ft.[KEY]
ORDER BY ft.RANK DESC;

-- 设计分析:
--   TABLE 函数返回表值结果（用 JOIN 而非 WHERE），这是 SQL Server 独有的设计。
--   PostgreSQL 使用 ts_rank() 函数计算排名（更灵活但需要手动组合）。
--   SQL Server 的 RANK 是内置的——更简单但不可定制。

-- ============================================================
-- 5. 搜索多列
-- ============================================================

SELECT * FROM articles WHERE CONTAINS((title, content), 'database');

-- ============================================================
-- 6. 语义搜索（2012+, 需要安装语义数据库）
-- ============================================================

-- SEMANTICKEYPHRASETABLE: 提取文档的关键短语
-- SEMANTICSIMILARITYTABLE: 查找与指定文档相似的文档
-- SEMANTICSIMILARITYDETAILSTABLE: 返回两个文档的共同关键短语
-- 这是 SQL Server 独有的能力——其他关系数据库没有内置的语义搜索

-- ============================================================
-- 7. 中文支持
-- ============================================================

-- SQL Server 内置中文断字器（Chinese Word Breaker）
-- 配置语言列表:
SELECT * FROM sys.fulltext_languages ORDER BY name;

-- 指定语言的全文索引:
CREATE FULLTEXT INDEX ON articles (
    title LANGUAGE 2052,    -- 简体中文
    content LANGUAGE 2052
) KEY INDEX pk_articles ON ft_catalog;

-- 对引擎开发者的启示:
--   中文/日文/韩文的分词是全文搜索的核心挑战。
--   SQL Server 内置分词器质量一般，生产环境通常需要 Elasticsearch。
--   如果引擎要支持中文全文搜索，建议集成 jieba/IK 等成熟分词库。
