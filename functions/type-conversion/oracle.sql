-- Oracle: Type Conversion
--
-- 参考资料:
--   [1] Oracle SQL Reference - Conversion Functions
--       https://docs.oracle.com/en/database/oracle/oracle-database/23/sqlrf/Conversion-Functions.html
--   [2] Oracle SQL Reference - CAST
--       https://docs.oracle.com/en/database/oracle/oracle-database/23/sqlrf/CAST.html
--   [3] Oracle SQL Reference - Format Models
--       https://docs.oracle.com/en/database/oracle/oracle-database/23/sqlrf/Format-Models.html

-- ============================================================
-- CAST
-- ============================================================
SELECT CAST(42 AS VARCHAR2(10)) FROM DUAL;       -- '42'
SELECT CAST('42' AS NUMBER) FROM DUAL;           -- 42
SELECT CAST(3.14 AS NUMBER(10,0)) FROM DUAL;    -- 3
SELECT CAST('2024-01-15' AS DATE) FROM DUAL;     -- DATE
SELECT CAST(SYSDATE AS TIMESTAMP) FROM DUAL;     -- TIMESTAMP

-- ============================================================
-- TO_CHAR (数值/日期 → 字符串)
-- ============================================================
-- 数值格式化
SELECT TO_CHAR(123456.789, '999,999.99') FROM DUAL;     -- ' 123,456.79'
SELECT TO_CHAR(123456.789, 'FM999,999.99') FROM DUAL;   -- '123,456.79' (FM 去空格)
SELECT TO_CHAR(0.5, '990.00') FROM DUAL;                 -- '  0.50'
SELECT TO_CHAR(42, '0000') FROM DUAL;                    -- '0042'
SELECT TO_CHAR(1234.5, '$9,999.99') FROM DUAL;          -- ' $1,234.50'

-- 日期格式化
SELECT TO_CHAR(SYSDATE, 'YYYY-MM-DD HH24:MI:SS') FROM DUAL;
SELECT TO_CHAR(SYSDATE, 'Day, DD Month YYYY') FROM DUAL;
SELECT TO_CHAR(SYSDATE, 'DY') FROM DUAL;                 -- 'MON'
SELECT TO_CHAR(SYSDATE, 'Q') FROM DUAL;                  -- 季度
SELECT TO_CHAR(SYSDATE, 'WW') FROM DUAL;                 -- 年中的周
SELECT TO_CHAR(SYSDATE, 'YYYY"年"MM"月"DD"日"') FROM DUAL;

-- ============================================================
-- TO_NUMBER (字符串 → 数值)
-- ============================================================
SELECT TO_NUMBER('123.45') FROM DUAL;                     -- 123.45
SELECT TO_NUMBER('123,456.78', '999,999.99') FROM DUAL;  -- 123456.78
SELECT TO_NUMBER('$1,234.56', '$9,999.99') FROM DUAL;    -- 1234.56
SELECT TO_NUMBER('FF', 'XX') FROM DUAL;                   -- 255 (十六进制)

-- ============================================================
-- TO_DATE (字符串 → DATE)
-- ============================================================
SELECT TO_DATE('2024-01-15', 'YYYY-MM-DD') FROM DUAL;
SELECT TO_DATE('15/01/2024', 'DD/MM/YYYY') FROM DUAL;
SELECT TO_DATE('Jan 15, 2024', 'Mon DD, YYYY') FROM DUAL;
SELECT TO_DATE('20240115', 'YYYYMMDD') FROM DUAL;

-- ============================================================
-- TO_TIMESTAMP (字符串 → TIMESTAMP)
-- ============================================================
SELECT TO_TIMESTAMP('2024-01-15 10:30:00.123', 'YYYY-MM-DD HH24:MI:SS.FF3') FROM DUAL;

-- ============================================================
-- TO_TIMESTAMP_TZ (字符串 → TIMESTAMP WITH TIME ZONE)
-- ============================================================
SELECT TO_TIMESTAMP_TZ('2024-01-15 10:30:00 +08:00', 'YYYY-MM-DD HH24:MI:SS TZH:TZM') FROM DUAL;

-- ============================================================
-- TO_CLOB / TO_NCHAR / TO_NCLOB
-- ============================================================
SELECT TO_CLOB('hello') FROM DUAL;
SELECT TO_NCHAR(42) FROM DUAL;

-- ============================================================
-- 隐式转换规则
-- ============================================================
-- Oracle 隐式转换较宽松:
-- VARCHAR2 → NUMBER : 在算术运算中自动转换
-- VARCHAR2 → DATE   : 使用 NLS_DATE_FORMAT 自动转换
-- NUMBER → VARCHAR2  : 在字符串拼接中自动转换
SELECT '42' + 0 FROM DUAL;                       -- 42 (隐式转换)
SELECT 'Value: ' || 42 FROM DUAL;                -- 'Value: 42' (隐式转换)

-- ============================================================
-- 常见转换模式
-- ============================================================
-- 字符串 ↔ 数字
SELECT TO_NUMBER('123.45') FROM DUAL;
SELECT TO_CHAR(123.45, 'FM999.99') FROM DUAL;

-- 字符串 ↔ 日期
SELECT TO_DATE('2024-01-15', 'YYYY-MM-DD') FROM DUAL;
SELECT TO_CHAR(SYSDATE, 'YYYY-MM-DD') FROM DUAL;

-- Unix 时间戳
SELECT (CAST(SYSDATE AS DATE) - TO_DATE('1970-01-01','YYYY-MM-DD')) * 86400 FROM DUAL; -- 秒数

-- RAW / HEXTORAW
SELECT RAWTOHEX('hello') FROM DUAL;              -- '68656C6C6F'
SELECT UTL_RAW.CAST_TO_VARCHAR2(HEXTORAW('68656C6C6F')) FROM DUAL; -- 'hello'

-- ============================================================
-- VALIDATE_CONVERSION (安全检查是否可转换)             -- 12c R2+
-- ============================================================
SELECT VALIDATE_CONVERSION('42' AS NUMBER) FROM DUAL;     -- 1 (可转换)
SELECT VALIDATE_CONVERSION('abc' AS NUMBER) FROM DUAL;    -- 0 (不可转换)
SELECT VALIDATE_CONVERSION('2024-13-01' AS DATE, 'YYYY-MM-DD') FROM DUAL; -- 0

-- ============================================================
-- CAST ... DEFAULT ... ON CONVERSION ERROR             -- 12c R2+
-- ============================================================
SELECT CAST('abc' AS NUMBER DEFAULT 0 ON CONVERSION ERROR) FROM DUAL; -- 0
SELECT CAST('bad-date' AS DATE DEFAULT DATE '2000-01-01' ON CONVERSION ERROR) FROM DUAL;

-- 版本说明：
--   Oracle 全版本  : CAST, TO_CHAR, TO_NUMBER, TO_DATE, TO_TIMESTAMP
--   Oracle 12c R2+ : VALIDATE_CONVERSION, DEFAULT ON CONVERSION ERROR
-- 注意：Oracle TO_CHAR 格式模式非常丰富
-- 注意：FM 修饰符去除前导空格
-- 注意：NLS_DATE_FORMAT 影响隐式日期转换
-- 注意：Oracle 12c R2+ 的 DEFAULT ON CONVERSION ERROR 替代了 TRY_CAST
-- 限制：无 TRY_CAST 关键字（使用 DEFAULT ON CONVERSION ERROR）
-- 限制：无 CONVERT 函数（SQL Server 风格）
-- 限制：无 :: 运算符
