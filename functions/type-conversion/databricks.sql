-- Databricks: Type Conversion
--
-- 参考资料:
--   [1] Databricks SQL Reference - CAST / TRY_CAST
--       https://docs.databricks.com/en/sql/language-manual/functions/cast.html

SELECT CAST(42 AS STRING); SELECT CAST('42' AS INT); SELECT CAST('3.14' AS DOUBLE);
SELECT CAST('2024-01-15' AS DATE); SELECT CAST('2024-01-15 10:30:00' AS TIMESTAMP);

-- TRY_CAST (安全转换)
SELECT TRY_CAST('abc' AS INT);                  -- NULL
SELECT TRY_CAST('42' AS INT);                   -- 42
SELECT TRY_CAST('bad-date' AS DATE);            -- NULL

-- 格式化
SELECT DATE_FORMAT(CURRENT_DATE(), 'yyyy-MM-dd');
SELECT TO_DATE('2024/01/15', 'yyyy/MM/dd');
SELECT TO_TIMESTAMP('2024-01-15 10:30:00', 'yyyy-MM-dd HH:mm:ss');
SELECT FROM_UNIXTIME(1705276800);                -- Unix → 字符串
SELECT UNIX_TIMESTAMP('2024-01-15', 'yyyy-MM-dd'); -- → Unix

-- :: 运算符                                     -- Databricks SQL
SELECT 42::STRING; SELECT '42'::INT;

-- 注意：Databricks 支持 CAST, TRY_CAST, :: 运算符
-- 注意：日期函数使用 Java SimpleDateFormat 模式
