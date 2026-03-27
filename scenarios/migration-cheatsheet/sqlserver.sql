-- SQL Server: 迁移速查表 (Migration Cheatsheet)
--
-- 参考资料:
--   [1] Microsoft Docs - SQL Server Migration Assistant
--       https://learn.microsoft.com/en-us/sql/ssma/
--   [2] Microsoft Docs - T-SQL Reference
--       https://learn.microsoft.com/en-us/sql/t-sql/language-reference

-- ============================================================
-- 一、从 MySQL 迁移到 SQL Server
-- ============================================================
-- 数据类型: TINYINT→TINYINT, INT→INT, TEXT→NVARCHAR(MAX),
--           DATETIME→DATETIME2, JSON→NVARCHAR(MAX), AUTO_INCREMENT→IDENTITY
-- 函数: IFNULL→ISNULL, NOW()→GETDATE(), CONCAT→CONCAT或+,
--        GROUP_CONCAT→STRING_AGG(2017+), LIMIT→TOP或OFFSET FETCH
-- 陷阱: 反引号→方括号, 双引号是标识符, 无ENUM/SET类型,
--        存储过程语法完全不同

-- ============================================================
-- 二、从 Oracle 迁移到 SQL Server
-- ============================================================
-- 数据类型: NUMBER→DECIMAL/INT, VARCHAR2→NVARCHAR, CLOB→NVARCHAR(MAX),
--           DATE→DATETIME2(Oracle DATE含时间), SEQUENCE→IDENTITY或SEQUENCE
-- 函数: NVL→ISNULL/COALESCE, SYSDATE→GETDATE(), DECODE→IIF/CASE,
--        TO_CHAR→FORMAT/CONVERT, ROWNUM→TOP/ROW_NUMBER,
--        || →CONCAT或+, CONNECT BY→WITH递归CTE, MINUS→EXCEPT
-- 陷阱: Oracle空串=NULL不同, 序列语法不同, 包→SCHEMA+函数,
--        PL/SQL→T-SQL完全重写

-- ============================================================
-- 三、从 PostgreSQL 迁移到 SQL Server
-- ============================================================
-- 数据类型: SERIAL→IDENTITY, BOOLEAN→BIT, TEXT→NVARCHAR(MAX),
--           BYTEA→VARBINARY(MAX), UUID→UNIQUEIDENTIFIER, JSONB→NVARCHAR(MAX)
-- 函数: ||→CONCAT或+, COALESCE→COALESCE, NOW()→GETDATE(),
--        STRING_AGG→STRING_AGG(2017+), regexp_replace→无原生(2025预览有)
-- 陷阱: PostgreSQL严格模式→SQL Server宽松, LATERAL→CROSS APPLY,
--        CREATE TEMP TABLE→#temp, PL/pgSQL→T-SQL

-- ============================================================
-- 四、自增/序列
-- ============================================================
CREATE TABLE t (id BIGINT IDENTITY(1,1) PRIMARY KEY);
-- SQL Server 2012+ 也支持 SEQUENCE:
CREATE SEQUENCE my_seq START WITH 1 INCREMENT BY 1;
SELECT NEXT VALUE FOR my_seq;

-- ============================================================
-- 五、日期/时间函数
-- ============================================================
SELECT GETDATE();                             -- 当前日期时间
SELECT SYSDATETIME();                         -- 高精度当前时间
SELECT CAST(GETDATE() AS DATE);               -- 当前日期
SELECT DATEADD(DAY, 1, GETDATE());            -- 加一天
SELECT DATEDIFF(DAY, '2024-01-01', '2024-12-31'); -- 日期差
SELECT FORMAT(GETDATE(), 'yyyy-MM-dd HH:mm:ss');  -- 格式化
SELECT CONVERT(VARCHAR(10), GETDATE(), 120);       -- 转换格式

-- ============================================================
-- 六、字符串函数
-- ============================================================
SELECT LEN(N'hello');                   -- 字符长度（不含尾随空格）
SELECT DATALENGTH(N'hello');            -- 字节长度
SELECT UPPER(N'hello');                 -- 大写
SELECT LOWER(N'HELLO');                 -- 小写
SELECT LTRIM(RTRIM(N'  hello  '));      -- 去空格
SELECT SUBSTRING(N'hello', 2, 3);      -- 子串 → 'ell'
SELECT REPLACE(N'hello', N'l', N'r');   -- 替换
SELECT CHARINDEX(N'lo', N'hello');      -- 位置 → 4
SELECT CONCAT(N'hello', N' world');     -- 连接
SELECT STRING_AGG(name, N', ') FROM users;  -- 聚合连接（2017+）
SELECT STRING_SPLIT(N'a,b,c', N',');    -- 分割（2016+）
