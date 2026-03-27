-- SQL Server: 全文搜索
--
-- 参考资料:
--   [1] SQL Server - Full-Text Search
--       https://learn.microsoft.com/en-us/sql/relational-databases/search/full-text-search
--   [2] SQL Server T-SQL - CONTAINS
--       https://learn.microsoft.com/en-us/sql/t-sql/queries/contains-transact-sql
--   [3] SQL Server T-SQL - FREETEXT
--       https://learn.microsoft.com/en-us/sql/t-sql/queries/freetext-transact-sql

-- 创建全文目录和索引
CREATE FULLTEXT CATALOG ft_catalog AS DEFAULT;
CREATE FULLTEXT INDEX ON articles (title, content)
    KEY INDEX pk_articles ON ft_catalog;

-- CONTAINS（精确匹配）
SELECT * FROM articles WHERE CONTAINS(content, 'database');

-- 运算符
SELECT * FROM articles WHERE CONTAINS(content, 'database AND performance');
SELECT * FROM articles WHERE CONTAINS(content, 'database OR mysql');
SELECT * FROM articles WHERE CONTAINS(content, 'database AND NOT mysql');
SELECT * FROM articles WHERE CONTAINS(content, 'database NEAR performance');

-- 短语搜索
SELECT * FROM articles WHERE CONTAINS(content, '"full text search"');

-- 前缀搜索
SELECT * FROM articles WHERE CONTAINS(content, '"data*"');

-- 加权搜索
SELECT * FROM articles WHERE CONTAINS(content, 'ISABOUT(database WEIGHT(0.8), performance WEIGHT(0.2))');

-- FREETEXT（语义搜索，自动词干提取和同义词）
SELECT * FROM articles WHERE FREETEXT(content, 'database performance tuning');

-- CONTAINSTABLE（返回排名）
SELECT a.title, ft.RANK
FROM articles a
JOIN CONTAINSTABLE(articles, content, 'database') ft ON a.id = ft.[KEY]
ORDER BY ft.RANK DESC;

-- FREETEXTTABLE
SELECT a.title, ft.RANK
FROM articles a
JOIN FREETEXTTABLE(articles, content, 'database performance') ft ON a.id = ft.[KEY]
ORDER BY ft.RANK DESC;

-- 搜索多列
SELECT * FROM articles WHERE CONTAINS((title, content), 'database');

-- 2012+: 语义搜索（需要安装语义数据库）
-- SEMANTICKEYPHRASETABLE: 提取关键短语
-- SEMANTICSIMILARITYTABLE: 查找相似文档

-- 中文支持：安装中文断字符（Chinese Word Breaker）
