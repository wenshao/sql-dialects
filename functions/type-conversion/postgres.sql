-- PostgreSQL: Type Conversion
--
-- 参考资料:
--   [1] PostgreSQL Documentation - Type Conversion
--       https://www.postgresql.org/docs/current/typeconv.html
--   [2] PostgreSQL Documentation - CAST
--       https://www.postgresql.org/docs/current/sql-expressions.html#SQL-SYNTAX-TYPE-CASTS
--   [3] PostgreSQL Documentation - Formatting Functions
--       https://www.postgresql.org/docs/current/functions-formatting.html

-- ============================================================
-- CAST (标准 SQL 语法)
-- ============================================================
SELECT CAST(42 AS TEXT);                        -- '42'
SELECT CAST('42' AS INTEGER);                   -- 42
SELECT CAST(3.14 AS INTEGER);                   -- 3
SELECT CAST('2024-01-15' AS DATE);              -- 2024-01-15
SELECT CAST('2024-01-15 10:30:00' AS TIMESTAMP); -- TIMESTAMP
SELECT CAST('true' AS BOOLEAN);                 -- TRUE
SELECT CAST('{1,2,3}' AS INTEGER[]);            -- ARRAY[1,2,3]
SELECT CAST('{"a":1}' AS JSON);                 -- JSON

-- ============================================================
-- :: 运算符 (PostgreSQL 类型转换快捷语法)
-- ============================================================
SELECT 42::TEXT;                                -- '42'
SELECT '42'::INTEGER;                           -- 42
SELECT '42'::INT;                               -- 42
SELECT 3.14::INT;                               -- 3
SELECT '2024-01-15'::DATE;                      -- DATE
SELECT '2024-01-15 10:30:00'::TIMESTAMP;        -- TIMESTAMP
SELECT 'true'::BOOLEAN;                         -- TRUE
SELECT '192.168.1.1'::INET;                     -- INET
SELECT '{"a":1}'::JSONB;                        -- JSONB
SELECT 'a0eebc99-9c0b-4ef8-bb6d-6bb9bd380a11'::UUID; -- UUID

-- ============================================================
-- 格式化函数 (TO_CHAR, TO_NUMBER, TO_DATE, TO_TIMESTAMP)
-- ============================================================
-- TO_CHAR: 数值/日期 → 格式化字符串
SELECT TO_CHAR(123456.789, '999,999.99');        -- ' 123,456.79'
SELECT TO_CHAR(NOW(), 'YYYY-MM-DD HH24:MI:SS'); -- '2024-01-15 10:30:00'
SELECT TO_CHAR(NOW(), 'Day, DD Month YYYY');     -- 'Monday  , 15 January  2024'
SELECT TO_CHAR(1234, '0000');                    -- '1234'
SELECT TO_CHAR(0.5, '99.99%');                   -- '  .50%' (注意不自动乘100)

-- TO_NUMBER: 字符串 → 数值
SELECT TO_NUMBER('123,456.78', '999,999.99');    -- 123456.78
SELECT TO_NUMBER('$1,234.56', 'L9,999.99');      -- 1234.56

-- TO_DATE: 字符串 → DATE
SELECT TO_DATE('2024-01-15', 'YYYY-MM-DD');      -- 2024-01-15
SELECT TO_DATE('15/01/2024', 'DD/MM/YYYY');      -- 2024-01-15
SELECT TO_DATE('Jan 15, 2024', 'Mon DD, YYYY');  -- 2024-01-15

-- TO_TIMESTAMP: 字符串 → TIMESTAMP
SELECT TO_TIMESTAMP('2024-01-15 10:30:00', 'YYYY-MM-DD HH24:MI:SS');
SELECT TO_TIMESTAMP(1705312200);                  -- Unix 时间戳 → TIMESTAMP

-- ============================================================
-- 常见转换模式
-- ============================================================
-- 字符串 ↔ 数字
SELECT '42'::NUMERIC;                           -- 42
SELECT 42::TEXT;                                -- '42'
SELECT TO_CHAR(42, 'FM999');                     -- '42' (FM 去前导空格)

-- 字符串 ↔ 日期
SELECT '2024-01-15'::DATE;
SELECT CURRENT_DATE::TEXT;

-- 数字 ↔ 布尔
SELECT 0::BOOLEAN;                              -- FALSE
SELECT 1::BOOLEAN;                              -- TRUE
SELECT TRUE::INTEGER;                           -- 1

-- JSON 转换
SELECT '{"name":"test"}'::JSONB;
SELECT '{"name":"test"}'::JSONB->>'name';       -- 'test' (TEXT)
SELECT ROW_TO_JSON(ROW(1, 'test'));              -- JSON

-- ============================================================
-- 隐式转换规则
-- ============================================================
-- PostgreSQL 隐式转换相对严格：
-- 数值间: 自动提升 (INT → BIGINT → NUMERIC → FLOAT)
-- 字符串到数值: 不隐式转换（需显式 CAST）
-- 字符串到日期: 不隐式转换
-- CHAR/VARCHAR/TEXT 间: 自动转换
SELECT 1 + 1.5;                                 -- 2.5 (INT → NUMERIC)
SELECT 'hello' || 42;                           -- 错误！需 42::TEXT
SELECT 'hello' || 42::TEXT;                      -- 'hello42'

-- ============================================================
-- 创建自定义类型转换                                   -- 高级
-- ============================================================
-- CREATE CAST (source_type AS target_type)
--     WITH FUNCTION function_name(source_type)
--     AS IMPLICIT;

-- 版本说明：
--   PostgreSQL 全版本 : CAST, :: 运算符
--   PostgreSQL 全版本 : TO_CHAR, TO_NUMBER, TO_DATE, TO_TIMESTAMP
-- 注意：:: 是 PostgreSQL 特有语法，不可移植
-- 注意：PostgreSQL 隐式转换比 MySQL 严格
-- 注意：TO_CHAR 格式化模式区分大小写
-- 注意：FM 修饰符去除前导空格和尾部零
-- 限制：无 TRY_CAST（错误时抛异常）
-- 限制：无 CONVERT 函数（SQL Server 风格）
