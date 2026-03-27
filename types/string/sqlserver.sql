-- SQL Server: 字符串类型
--
-- 参考资料:
--   [1] SQL Server T-SQL - char and varchar
--       https://learn.microsoft.com/en-us/sql/t-sql/data-types/char-and-varchar-transact-sql
--   [2] SQL Server T-SQL - nchar and nvarchar
--       https://learn.microsoft.com/en-us/sql/t-sql/data-types/nchar-and-nvarchar-transact-sql

-- CHAR(n): 定长，最大 8000 字节
-- VARCHAR(n): 变长，最大 8000 字节
-- VARCHAR(MAX): 变长，最大 2GB
-- NCHAR(n): 定长 Unicode，最大 4000 字符
-- NVARCHAR(n): 变长 Unicode，最大 4000 字符
-- NVARCHAR(MAX): 变长 Unicode，最大 2GB
-- TEXT / NTEXT: 已废弃，用 VARCHAR(MAX) / NVARCHAR(MAX) 代替

CREATE TABLE examples (
    code    CHAR(10),                 -- 定长 ASCII
    name    NVARCHAR(255),            -- 变长 Unicode（推荐）
    content NVARCHAR(MAX)             -- 大文本
);

-- CHAR/VARCHAR: 非 Unicode，每字符 1 字节
-- NCHAR/NVARCHAR: Unicode，每字符 2 字节（UTF-16）
-- 推荐总是使用 N 前缀类型以支持多语言

-- 字符串字面量
SELECT 'ASCII string';                -- ASCII
SELECT N'Unicode 字符串';              -- Unicode（N 前缀）

-- 排序规则
CREATE TABLE t (
    name NVARCHAR(100) COLLATE Latin1_General_CI_AS  -- 大小写不敏感，重音敏感
);

-- 常用排序规则后缀:
-- CI: Case Insensitive
-- CS: Case Sensitive
-- AI: Accent Insensitive
-- AS: Accent Sensitive
-- BIN2: 二进制比较

-- 2019+: UTF-8 排序规则（允许 VARCHAR 存储 UTF-8）
CREATE TABLE t (name VARCHAR(100) COLLATE Latin1_General_100_CI_AS_SC_UTF8);

-- 二进制数据
-- BINARY(n): 定长，最大 8000 字节
-- VARBINARY(n): 变长，最大 8000 字节
-- VARBINARY(MAX): 变长，最大 2GB
-- IMAGE: 已废弃

-- 注意：SQL Server 区分 NULL 和 ''（空字符串不等于 NULL）
