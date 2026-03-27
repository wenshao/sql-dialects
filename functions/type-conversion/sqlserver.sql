-- SQL Server: Type Conversion
--
-- 参考资料:
--   [1] SQL Server T-SQL - CAST and CONVERT
--       https://learn.microsoft.com/en-us/sql/t-sql/functions/cast-and-convert-transact-sql
--   [2] SQL Server T-SQL - TRY_CAST / TRY_CONVERT
--       https://learn.microsoft.com/en-us/sql/t-sql/functions/try-cast-transact-sql
--   [3] SQL Server T-SQL - Data Type Conversion
--       https://learn.microsoft.com/en-us/sql/t-sql/data-types/data-type-conversion-database-engine

-- ============================================================
-- CAST
-- ============================================================
SELECT CAST(42 AS VARCHAR(10));                 -- '42'
SELECT CAST('42' AS INT);                       -- 42
SELECT CAST(3.14 AS INT);                       -- 3
SELECT CAST('3.14' AS DECIMAL(10,2));           -- 3.14
SELECT CAST('2024-01-15' AS DATE);              -- 2024-01-15
SELECT CAST('2024-01-15 10:30:00' AS DATETIME2); -- DATETIME2
SELECT CAST(1 AS BIT);                          -- 1 (TRUE)
SELECT CAST('hello' AS VARBINARY(100));         -- 0x68656C6C6F

-- ============================================================
-- CONVERT (SQL Server 特有，支持样式码)
-- ============================================================
-- CONVERT(target_type, expression [, style])
SELECT CONVERT(VARCHAR(10), 42);                 -- '42'
SELECT CONVERT(INT, '42');                       -- 42

-- 日期格式化（使用样式码）
SELECT CONVERT(VARCHAR(20), GETDATE(), 120);     -- '2024-01-15 10:30:00' (ODBC 标准)
SELECT CONVERT(VARCHAR(10), GETDATE(), 101);     -- '01/15/2024' (美式)
SELECT CONVERT(VARCHAR(10), GETDATE(), 103);     -- '15/01/2024' (英式)
SELECT CONVERT(VARCHAR(10), GETDATE(), 104);     -- '15.01.2024' (德式)
SELECT CONVERT(VARCHAR(10), GETDATE(), 111);     -- '2024/01/15' (日式)
SELECT CONVERT(VARCHAR(10), GETDATE(), 112);     -- '20240115'   (ISO)
SELECT CONVERT(VARCHAR(30), GETDATE(), 126);     -- '2024-01-15T10:30:00.000' (ISO 8601)

-- 常用样式码:
-- 100: mon dd yyyy hh:miAM/PM    101: mm/dd/yyyy
-- 103: dd/mm/yyyy                104: dd.mm.yyyy
-- 108: hh:mi:ss                  112: yyyymmdd
-- 120: yyyy-mm-dd hh:mi:ss       126: yyyy-mm-ddThh:mi:ss.mmm (ISO8601)

-- ============================================================
-- TRY_CAST / TRY_CONVERT (安全转换，失败返回 NULL)     -- 2012+
-- ============================================================
SELECT TRY_CAST('abc' AS INT);                  -- NULL (不报错)
SELECT TRY_CAST('42' AS INT);                   -- 42
SELECT TRY_CAST('2024-13-01' AS DATE);          -- NULL (无效日期)

SELECT TRY_CONVERT(INT, 'abc');                  -- NULL
SELECT TRY_CONVERT(DATE, '2024-01-15');         -- 2024-01-15
SELECT TRY_CONVERT(VARCHAR(10), GETDATE(), 120); -- 安全格式化

-- ============================================================
-- TRY_PARSE (字符串 → 数值/日期，支持区域设置)         -- 2012+
-- ============================================================
SELECT TRY_PARSE('$1,234.56' AS MONEY USING 'en-US');     -- 1234.56
SELECT TRY_PARSE('1.234,56' AS DECIMAL(10,2) USING 'de-DE'); -- 1234.56
SELECT TRY_PARSE('15 January 2024' AS DATE USING 'en-US'); -- 2024-01-15

-- ============================================================
-- FORMAT (格式化输出)                                  -- 2012+
-- ============================================================
SELECT FORMAT(1234567.89, 'N2');                 -- '1,234,567.89'
SELECT FORMAT(1234567.89, 'N2', 'de-de');       -- '1.234.567,89'
SELECT FORMAT(GETDATE(), 'yyyy-MM-dd');          -- '2024-01-15'
SELECT FORMAT(GETDATE(), 'dddd, MMMM dd, yyyy'); -- 'Monday, January 15, 2024'
SELECT FORMAT(0.5, 'P');                          -- '50.00 %'
SELECT FORMAT(1234, '0000');                      -- '1234'

-- ============================================================
-- 隐式转换规则
-- ============================================================
-- SQL Server 有详细的隐式转换矩阵:
-- INT → BIGINT → DECIMAL → FLOAT : 自动
-- VARCHAR → INT : 自动（在比较和运算中）
-- DATE → DATETIME : 自动
-- NVARCHAR → VARCHAR : 自动
SELECT 1 + '2';                                  -- 3 (字符串隐式转数字)
SELECT '2024-01-15' + 1;                         -- 错误！日期字符串不自动转
SELECT CAST('2024-01-15' AS DATE) + 1;           -- 2024-01-16

-- ============================================================
-- 常见转换模式
-- ============================================================
-- 字符串 ↔ 数字
SELECT CAST('123.45' AS DECIMAL(10,2));
SELECT CAST(123.45 AS VARCHAR(20));
SELECT STR(123.45, 10, 2);                      -- '    123.45' (旧式)

-- 字符串 ↔ 日期
SELECT CAST('2024-01-15' AS DATE);
SELECT CONVERT(VARCHAR(10), GETDATE(), 120);

-- Unicode 转换
SELECT CAST('hello' AS NVARCHAR(100));
SELECT UNICODE(N'A');                            -- 65
SELECT NCHAR(65);                                -- N'A'

-- ============================================================
-- JSON 转换                                          -- 2016+
-- ============================================================
SELECT CAST('{"a":1}' AS NVARCHAR(MAX));
-- JSON_VALUE 返回标量值
SELECT JSON_VALUE('{"name":"test"}', '$.name');  -- 'test'

-- 版本说明：
--   SQL Server 2005+ : CAST, CONVERT
--   SQL Server 2012+ : TRY_CAST, TRY_CONVERT, TRY_PARSE, FORMAT
--   SQL Server 2016+ : JSON 函数
-- 注意：CONVERT 的样式码是 SQL Server 特有功能
-- 注意：TRY_CAST / TRY_CONVERT 失败返回 NULL 而非报错
-- 注意：FORMAT 使用 .NET 格式化字符串
-- 注意：隐式转换可能导致索引无法使用（类型不匹配）
-- 限制：无 :: 运算符
-- 限制：无 TO_NUMBER / TO_CHAR / TO_DATE
