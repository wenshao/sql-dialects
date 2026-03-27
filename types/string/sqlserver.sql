-- SQL Server: 字符串类型
--
-- 参考资料:
--   [1] SQL Server T-SQL - char/varchar/nchar/nvarchar
--       https://learn.microsoft.com/en-us/sql/t-sql/data-types/char-and-varchar-transact-sql

-- ============================================================
-- 1. 双轨字符串类型系统: VARCHAR vs NVARCHAR
-- ============================================================

-- VARCHAR(n):     非 Unicode, 最大 8000 字节, 1 字节/字符（ASCII/ANSI）
-- NVARCHAR(n):    Unicode UTF-16, 最大 4000 字符, 2 字节/字符
-- VARCHAR(MAX):   非 Unicode, 最大 2GB
-- NVARCHAR(MAX):  Unicode, 最大 2GB
-- CHAR(n):        定长非 Unicode, 最大 8000 字节
-- NCHAR(n):       定长 Unicode, 最大 4000 字符

CREATE TABLE examples (
    code    CHAR(10),          -- 定长 ASCII（固定产品编码等）
    name    NVARCHAR(255),     -- 变长 Unicode（推荐默认选择）
    content NVARCHAR(MAX)      -- 大文本
);

-- 设计分析（对引擎开发者）:
--   SQL Server 的双轨设计是历史遗留——VARCHAR 使用代码页编码，
--   NVARCHAR 使用 UTF-16。这迫使开发者在每个列上决定是否需要 Unicode。
--
--   字符串字面量也需要 N 前缀:
SELECT 'ASCII string';       -- VARCHAR
SELECT N'Unicode 字符串';     -- NVARCHAR（没有 N 前缀会丢失非 ASCII 字符）
--
-- 横向对比:
--   PostgreSQL: TEXT/VARCHAR 就是 UTF-8（无需区分 Unicode/非 Unicode）
--   MySQL:      通过字符集控制（utf8mb4 统一 Unicode）
--   Oracle:     VARCHAR2 + AL32UTF8 数据库字符集
--
--   SQL Server 2019+: UTF-8 排序规则——允许 VARCHAR 存储 UTF-8
--   这是一个重大改进，终于可以在 VARCHAR 中安全存储中文等 Unicode 字符:
CREATE TABLE t (
    name VARCHAR(100) COLLATE Latin1_General_100_CI_AS_SC_UTF8
);
--   UTF-8 VARCHAR 比 NVARCHAR 节省 ASCII 字符的存储空间（1 字节 vs 2 字节）
--
-- 对引擎开发者的启示:
--   现代引擎应从第一天就使用 UTF-8 作为唯一的字符串编码。
--   双轨类型系统（VARCHAR/NVARCHAR）是 SQL Server 最大的历史包袱之一。
--   新引擎不应该重复这个错误——统一使用 UTF-8 的 STRING/TEXT 类型。

-- ============================================================
-- 2. 排序规则（Collation）: SQL Server 独特的层级设计
-- ============================================================

-- SQL Server 的排序规则是 4 级层次: Server → Database → Column → Expression
CREATE TABLE t (
    name NVARCHAR(100) COLLATE Latin1_General_CI_AS  -- 列级排序规则
);

-- 排序规则后缀含义:
-- CI = Case Insensitive（大小写不敏感）
-- CS = Case Sensitive
-- AI = Accent Insensitive（重音不敏感）
-- AS = Accent Sensitive
-- KS = Kana Sensitive（日文假名敏感）
-- WS = Width Sensitive（全角/半角敏感）
-- SC = Supplementary Characters（补充字符支持）
-- UTF8 = UTF-8 编码

-- 排序规则影响:
--   (1) 字符串比较: 'abc' = 'ABC'（CI 下为 TRUE，CS 下为 FALSE）
--   (2) 索引排序: 决定 B-tree 索引中数据的排列顺序
--   (3) UNIQUE 约束: CI 下 'Alice' 和 'alice' 被视为重复

-- 跨排序规则比较（会导致错误或性能问题）:
-- SELECT * FROM t1 JOIN t2 ON t1.name = t2.name  -- 如果排序规则不同，报错
-- 解决: ... ON t1.name COLLATE Latin1_General_CI_AS = t2.name

-- 对引擎开发者的启示:
--   排序规则是数据库引擎中最复杂的子系统之一。
--   建议使用 ICU 库（PostgreSQL 的做法）而非自行实现排序规则。
--   至少支持 CI/CS（大小写敏感性）和 AI/AS（重音敏感性）两个维度。

-- ============================================================
-- 3. VARCHAR(n) 中 n 的含义
-- ============================================================

-- SQL Server: VARCHAR(n) 的 n 是字节数（不是字符数！）
-- NVARCHAR(n) 的 n 是字符数

-- 这意味着:
--   VARCHAR(100) 最多存 100 个 ASCII 字符，但中文可能只能存 33 个（UTF-8, 3字节/字符）
--   NVARCHAR(100) 最多存 100 个任意字符

-- 横向对比:
--   PostgreSQL: VARCHAR(n) 的 n 是字符数
--   MySQL:      VARCHAR(n) 的 n 是字符数
--   Oracle:     VARCHAR2(n) 默认是字节数！VARCHAR2(n CHAR) 才是字符数

-- ============================================================
-- 4. TEXT / NTEXT / IMAGE: 已废弃类型
-- ============================================================

-- 这些类型在 SQL Server 2005 就已标记为废弃:
-- TEXT      → VARCHAR(MAX)
-- NTEXT     → NVARCHAR(MAX)
-- IMAGE     → VARBINARY(MAX)
-- 不能用于集合操作、变量赋值、大部分字符串函数

-- ============================================================
-- 5. 二进制数据类型
-- ============================================================

-- BINARY(n):      定长, 最大 8000 字节
-- VARBINARY(n):   变长, 最大 8000 字节
-- VARBINARY(MAX): 变长, 最大 2GB
-- 用于存储哈希值、加密数据、文件内容

SELECT HASHBYTES('SHA2_256', N'hello');  -- 返回 VARBINARY

-- ============================================================
-- 6. NULL vs 空字符串
-- ============================================================

-- SQL Server 正确区分 NULL 和 ''（与 SQL 标准一致）
-- Oracle 的 '' = NULL 行为不适用于 SQL Server
SELECT IIF('' IS NULL, 'null', 'not null');  -- 'not null'
SELECT IIF('' = '', 'equal', 'not equal');   -- 'equal'

-- 但 SQL Server 有一个 ANSI_PADDING 设置影响尾部空格:
-- SET ANSI_PADDING OFF 时，VARCHAR 列会裁剪尾部空格（已废弃行为）

-- ============================================================
-- 7. 字符串类型选择指南
-- ============================================================

-- 多语言内容:     NVARCHAR(n)（推荐默认选择）
-- 仅 ASCII 内容:  VARCHAR(n)（节省空间）
-- 大文本:         NVARCHAR(MAX)
-- 固定长度编码:    CHAR(n)（如国家代码 'US'）
-- 二进制数据:     VARBINARY(n) 或 VARBINARY(MAX)
-- 2019+ 新项目:   VARCHAR + UTF-8 排序规则（最佳空间效率）
