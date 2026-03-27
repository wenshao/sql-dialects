-- SQL 标准: 全文搜索演进
--
-- 参考资料:
--   [1] ISO/IEC 9075 SQL Standard
--       https://www.iso.org/standard/76583.html
--   [2] Modern SQL - by Markus Winand
--       https://modern-sql.com/
--   [3] SQL Standardization History (Wikipedia)
--       https://en.wikipedia.org/wiki/SQL#Standardization_history

-- ========== SQL-92 (SQL2) ==========
-- 仅支持基本字符串匹配

-- LIKE 模糊搜索（SQL-92 标准）
SELECT * FROM articles
WHERE content LIKE '%database%';

-- LIKE 通配符：
-- %: 匹配任意数量字符
-- _: 匹配单个字符
-- ESCAPE: 转义通配符
SELECT * FROM articles
WHERE content LIKE '%100\%%' ESCAPE '\';

-- ========== SQL:1999 (SQL3) ==========
-- 引入 SIMILAR TO（正则表达式风格的模式匹配）

-- SIMILAR TO（SQL:1999 标准正则模式匹配）
SELECT * FROM articles
WHERE content SIMILAR TO '%(database|performance)%';
-- SIMILAR TO 支持的特殊字符：
-- |: 或
-- *: 重复零次或多次
-- +: 重复一次或多次
-- ?: 可选（零次或一次）
-- {n}: 重复 n 次
-- []: 字符类
-- (): 分组

-- ========== SQL:2003 ==========
-- 无全文搜索相关新增

-- ========== SQL:2008 ==========
-- 无全文搜索相关新增

-- ========== SQL:2016 ==========
-- JSON 路径查询可用于搜索 JSON 文档中的文本
SELECT * FROM articles
WHERE JSON_EXISTS(metadata, '$.tags[*] ? (@ == "database")');

-- ========== SQL 标准与全文搜索的关系 ==========
-- SQL 标准始终没有定义完整的全文搜索功能
-- 各数据库的全文搜索实现都是私有扩展：
--   PostgreSQL: tsvector / tsquery / @@
--   MySQL: MATCH ... AGAINST
--   Oracle: CONTAINS / CTXSYS
--   SQL Server: CONTAINS / FREETEXT
--   SQLite: FTS5 虚拟表

-- 标准只提供了基础模式匹配：
-- LIKE（SQL-92）: 简单通配符匹配
-- SIMILAR TO（SQL:1999）: 正则风格模式匹配

-- 标准没有定义的全文搜索特性：
-- 全文索引
-- 分词（Tokenization）
-- 词干提取（Stemming）
-- 停用词（Stop Words）
-- 相关度排序（Relevance Ranking）
-- 短语搜索（Phrase Search）
-- 布尔搜索（Boolean Search）
-- 模糊搜索（Fuzzy Search）
-- 搜索结果高亮（Highlighting）
