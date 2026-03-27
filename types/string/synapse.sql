-- Azure Synapse: 字符串类型
--
-- 参考资料:
--   [1] Synapse SQL Features
--       https://learn.microsoft.com/en-us/azure/synapse-analytics/sql/overview-features
--   [2] Synapse T-SQL Differences
--       https://learn.microsoft.com/en-us/azure/synapse-analytics/sql/overview-features

-- CHAR(n): 定长，最大 8000 字节
-- VARCHAR(n): 变长，最大 8000 字节
-- VARCHAR(MAX): 变长，最大 2GB（行存储）/ 8000 字节（列存储）
-- NCHAR(n): 定长 Unicode，最大 4000 字符
-- NVARCHAR(n): 变长 Unicode，最大 4000 字符
-- NVARCHAR(MAX): 变长 Unicode，最大 2GB（行存储）/ 4000 字符（列存储）

CREATE TABLE examples (
    code       CHAR(10),                     -- 定长，尾部填充空格
    name       VARCHAR(255),                 -- 变长，非 Unicode
    content    VARCHAR(MAX),                 -- 最大变长
    uni_name   NVARCHAR(255),               -- 变长 Unicode（推荐）
    uni_content NVARCHAR(MAX)               -- 最大变长 Unicode
);

-- CHAR vs VARCHAR: CHAR 尾部填充空格到固定长度
-- VARCHAR vs NVARCHAR: NVARCHAR 支持 Unicode（每字符 2 字节）
-- 推荐使用 NVARCHAR 存储国际化文本

-- 列存储索引限制
-- 使用 CLUSTERED COLUMNSTORE INDEX 时：
-- VARCHAR(MAX) / NVARCHAR(MAX) 实际存储上限为 8000 / 4000
-- 超过限制的数据会被截断

-- BINARY 类型
-- BINARY(n): 定长二进制，最大 8000 字节
-- VARBINARY(n): 变长二进制，最大 8000 字节
-- VARBINARY(MAX): 最大 2GB

CREATE TABLE binary_data (
    hash_val   BINARY(32),                   -- 定长二进制（如 SHA-256）
    data       VARBINARY(MAX)               -- 变长二进制
);

-- 字符串字面量
SELECT 'hello world';                        -- VARCHAR
SELECT N'你好世界';                           -- NVARCHAR（N 前缀表示 Unicode）
SELECT 'it''s escaped';                      -- 单引号转义

-- 排序规则
SELECT * FROM users WHERE name COLLATE Latin1_General_CI_AS = 'alice';
-- CI = Case Insensitive, CS = Case Sensitive
-- AS = Accent Sensitive, AI = Accent Insensitive

CREATE TABLE t (
    name NVARCHAR(100) COLLATE Latin1_General_CI_AS
);

-- 注意：NVARCHAR 推荐用于存储国际化文本
-- 注意：列存储表中 MAX 类型有存储上限（8000/4000）
-- 注意：Synapse 专用池不支持 TEXT / NTEXT（已弃用类型）
-- 注意：排序规则影响字符串比较和排序行为
-- 注意：N 前缀对 NVARCHAR 字面量很重要
-- 注意：Serverless 池的字符串类型行为与 SQL Server 一致
