-- DB2: Type Conversion
--
-- 参考资料:
--   [1] IBM DB2 Documentation - CAST
--       https://www.ibm.com/docs/en/db2/11.5?topic=expressions-cast-specification

SELECT CAST(42 AS VARCHAR(10)); SELECT CAST('42' AS INTEGER);
SELECT CAST('3.14' AS DECIMAL(10,2)); SELECT CAST('2024-01-15' AS DATE);

-- 专用转换函数
SELECT CHAR(42);                                 -- '42' (整数→字符)
SELECT CHAR(CURRENT_DATE, ISO);                  -- 'YYYY-MM-DD' (ISO 格式)
SELECT CHAR(CURRENT_TIMESTAMP, ISO);
SELECT INTEGER('42');                            -- 42
SELECT DECIMAL('3.14', 10, 2);                   -- 3.14
SELECT DATE('2024-01-15');                       -- DATE
SELECT TIMESTAMP('2024-01-15 10:30:00');         -- TIMESTAMP
SELECT VARCHAR_FORMAT(CURRENT_TIMESTAMP, 'YYYY-MM-DD HH24:MI:SS');
SELECT TO_DATE('2024-01-15', 'YYYY-MM-DD');      -- 11.1+
SELECT TO_CHAR(CURRENT_DATE, 'YYYY-MM-DD');      -- 11.1+
SELECT TO_NUMBER('123.45');                       -- 11.1+

-- 隐式转换
SELECT 1 + CAST('2' AS INTEGER);                 -- DB2 隐式转换严格

-- 注意：DB2 有专用类型转换函数 (CHAR, INTEGER, DECIMAL, DATE 等)
-- 注意：DB2 11.1+ 支持 TO_CHAR / TO_DATE / TO_NUMBER (Oracle 兼容)
-- 限制：无 TRY_CAST / :: / CONVERT (SQL Server 风格)
