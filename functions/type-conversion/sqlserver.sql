-- SQL Server: 类型转换（CAST / CONVERT / TRY_CAST）
--
-- 参考资料:
--   [1] SQL Server T-SQL - CAST and CONVERT
--       https://learn.microsoft.com/en-us/sql/t-sql/functions/cast-and-convert-transact-sql
--   [2] SQL Server T-SQL - Data Type Conversion
--       https://learn.microsoft.com/en-us/sql/t-sql/data-types/data-type-conversion-database-engine

-- ============================================================
-- 1. CAST（SQL 标准语法）
-- ============================================================

SELECT CAST(42 AS VARCHAR(10));                 -- '42'
SELECT CAST('42' AS INT);                       -- 42
SELECT CAST(3.14 AS INT);                       -- 3（截断）
SELECT CAST('2024-01-15' AS DATE);              -- 2024-01-15
SELECT CAST(1 AS BIT);                          -- 1（TRUE）
SELECT CAST('hello' AS VARBINARY(100));         -- 0x68656C6C6F

-- ============================================================
-- 2. CONVERT: SQL Server 独有的样式码系统
-- ============================================================

-- CONVERT(target_type, expression [, style])
SELECT CONVERT(VARCHAR(10), 42);                -- '42'
SELECT CONVERT(INT, '42');                      -- 42

-- 日期格式化样式码（SQL Server 独有核心功能）
SELECT CONVERT(VARCHAR(20), GETDATE(), 120);    -- 'yyyy-mm-dd hh:mi:ss'
SELECT CONVERT(VARCHAR(10), GETDATE(), 101);    -- 'mm/dd/yyyy' (美式)
SELECT CONVERT(VARCHAR(10), GETDATE(), 103);    -- 'dd/mm/yyyy' (英式)
SELECT CONVERT(VARCHAR(10), GETDATE(), 104);    -- 'dd.mm.yyyy' (德式)
SELECT CONVERT(VARCHAR(10), GETDATE(), 111);    -- 'yyyy/mm/dd' (日式)
SELECT CONVERT(VARCHAR(10), GETDATE(), 112);    -- 'yyyymmdd' (ISO 紧凑)
SELECT CONVERT(VARCHAR(30), GETDATE(), 126);    -- ISO 8601

-- 设计分析（对引擎开发者）:
--   CONVERT 的样式码是 SQL Server 最独特的设计决策之一。
--   数字编码（101, 103, 120 等）毫无语义，完全依赖记忆和文档查阅。
--
-- 横向对比:
--   PostgreSQL: TO_CHAR(date, 'YYYY-MM-DD HH24:MI:SS')（格式字符串，直观）
--   Oracle:     TO_CHAR(date, 'YYYY-MM-DD HH24:MI:SS')（同 PostgreSQL）
--   MySQL:      DATE_FORMAT(date, '%Y-%m-%d %H:%i:%s')（类似但用 % 前缀）
--   SQL Server: CONVERT(VARCHAR, date, 120) 或 FORMAT(date, 'yyyy-MM-dd')
--
-- 对引擎开发者的启示:
--   格式化应使用格式字符串而非数字编码。SQL Server 2012 引入 FORMAT 函数
--   正是为了解决这个问题，但 FORMAT 基于 CLR 导致性能很差。
--   理想方案: 原生实现格式字符串解析（PostgreSQL 的 TO_CHAR 就是原生实现）。

-- ============================================================
-- 3. TRY_CAST / TRY_CONVERT: 安全转换（2012+）
-- ============================================================

SELECT TRY_CAST('abc' AS INT);              -- NULL（不报错）
SELECT TRY_CAST('42' AS INT);               -- 42
SELECT TRY_CAST('2024-13-01' AS DATE);      -- NULL（无效日期）

SELECT TRY_CONVERT(INT, 'abc');             -- NULL
SELECT TRY_CONVERT(DATE, '2024-01-15');     -- 2024-01-15

-- 设计分析:
--   TRY_ 系列是 SQL Server 对 ETL 场景的重要贡献。
--   转换失败返回 NULL 而非抛错，允许查询继续处理其余行。
--   典型 ETL 模式:
--   SELECT TRY_CAST(raw_age AS INT) AS age,
--          TRY_CAST(raw_date AS DATE) AS birth_date
--   FROM staging_table
--   WHERE TRY_CAST(raw_age AS INT) IS NOT NULL;
--
--   PostgreSQL 至今没有原生 TRY_CAST——这是一个被忽视的需求。

-- ============================================================
-- 4. TRY_PARSE / PARSE: 文化敏感转换（2012+）
-- ============================================================

SELECT TRY_PARSE('$1,234.56' AS MONEY USING 'en-US');          -- 1234.56
SELECT TRY_PARSE('1.234,56' AS DECIMAL(10,2) USING 'de-DE');   -- 1234.56
SELECT TRY_PARSE('15 January 2024' AS DATE USING 'en-US');     -- 2024-01-15

-- PARSE/TRY_PARSE 基于 .NET CLR，性能较差，但解决了多语言环境下的解析问题。

-- ============================================================
-- 5. FORMAT: 格式化输出（2012+, CLR 实现）
-- ============================================================

SELECT FORMAT(1234567.89, 'N2');                 -- '1,234,567.89'
SELECT FORMAT(1234567.89, 'N2', 'de-de');        -- '1.234.567,89'（德国格式）
SELECT FORMAT(GETDATE(), 'yyyy-MM-dd');          -- '2024-01-15'
SELECT FORMAT(GETDATE(), 'dddd, MMMM dd, yyyy');-- 'Monday, January 15, 2024'
SELECT FORMAT(0.5, 'P');                         -- '50.00 %'

-- 性能警告: FORMAT 使用 .NET CLR，比 CONVERT 慢 10-50 倍。
-- 大数据集避免使用 FORMAT，在应用层格式化。

-- ============================================================
-- 6. 隐式转换规则（对引擎开发者）
-- ============================================================

-- SQL Server 有详细的隐式转换优先级矩阵:
SELECT 1 + '2';                           -- 3（字符串隐式转数字）
SELECT CONCAT(1, 2);                      -- '12'（数字隐式转字符串）
-- 类型优先级: INT < BIGINT < DECIMAL < FLOAT（低→高自动转换）

-- 隐式转换的性能陷阱:
--   WHERE varchar_column = 42  → varchar_column 被隐式转为 INT
--   这导致索引无法使用！（每行都要转换才能比较）
--   正确: WHERE varchar_column = '42'（类型匹配，走索引）
--
-- 对引擎开发者的启示:
--   隐式转换的两个问题:
--   (1) 索引失效（SARGABILITY 丢失）
--   (2) 意外行为（'2024-01-15' + 1 → 报错，因为字符串不能加数字）
--   建议: 在查询优化器中检测隐式转换并发出警告，而非静默执行。

-- ============================================================
-- 7. Unicode 转换
-- ============================================================

SELECT CAST('hello' AS NVARCHAR(100));     -- VARCHAR → NVARCHAR
SELECT UNICODE(N'A');                      -- 65（Unicode 码点）
SELECT NCHAR(65);                          -- N'A'（码点 → 字符）

-- 2019+: UTF-8 排序规则（允许 VARCHAR 存储 UTF-8）
-- 这是 SQL Server 的重大变化: 之前 VARCHAR = 非 Unicode，NVARCHAR = UTF-16
-- 2019+ VARCHAR 可以用 UTF-8 排序规则，存储空间比 NVARCHAR(UTF-16) 小很多
-- CREATE TABLE t (name VARCHAR(100) COLLATE Latin1_General_100_CI_AS_SC_UTF8);

-- ============================================================
-- 8. 常见转换模式
-- ============================================================

-- 字符串 ↔ 数字
SELECT CAST('123.45' AS DECIMAL(10,2));
SELECT STR(123.45, 10, 2);                -- '    123.45'（旧式，右对齐填充空格）

-- 字符串 ↔ 日期
SELECT CAST('2024-01-15' AS DATE);
SELECT CONVERT(VARCHAR(10), GETDATE(), 120);

-- JSON 转换（2016+）
SELECT JSON_VALUE('{"name":"test"}', '$.name');  -- 'test'

-- 版本说明:
-- 2005+ : CAST, CONVERT
-- 2012+ : TRY_CAST, TRY_CONVERT, TRY_PARSE, FORMAT, PARSE
-- 2016+ : JSON_VALUE, JSON_QUERY
-- 2019+ : UTF-8 VARCHAR 排序规则
-- 限制: 无 :: 运算符, 无 TO_NUMBER/TO_CHAR/TO_DATE
