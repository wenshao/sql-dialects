-- KingbaseES (人大金仓): 类型转换函数 (Type Conversion Functions)
--
-- 参考资料:
--   [1] KingbaseES SQL Reference Manual
--       https://help.kingbase.com.cn/v8/index.html
--   [2] KingbaseES Documentation - Data Types
--       https://help.kingbase.com.cn/v8/developer/sql-reference/data-types/
--   [3] PostgreSQL Documentation - Type Conversion
--       https://www.postgresql.org/docs/current/typeconv.html
--
-- 说明: KingbaseES 同时支持 PostgreSQL 和 Oracle 类型转换语法。
--       兼容模式在数据库初始化时选择，影响转换函数行为。

-- ============================================================
-- 1. CAST: SQL 标准类型转换
-- ============================================================

-- 数值转换
SELECT CAST(42 AS TEXT);                              -- '42'
SELECT CAST('42' AS INTEGER);                         -- 42
SELECT CAST(3.14 AS INTEGER);                         -- 3（截断小数部分）
SELECT CAST('3.14' AS NUMERIC(10, 2));                -- 3.14
SELECT CAST(42 AS BIGINT);                            -- 42（bigint 类型）
SELECT CAST(3.14 AS NUMERIC(10, 1));                  -- 3.1

-- 字符串转换
SELECT CAST(12345 AS TEXT);                           -- '12345'
SELECT CAST(3.14 AS TEXT);                            -- '3.14'

-- 布尔转换
SELECT CAST(1 AS BOOLEAN);                            -- true
SELECT CAST(0 AS BOOLEAN);                            -- false
SELECT CAST('yes' AS BOOLEAN);                        -- true
SELECT CAST('no' AS BOOLEAN);                         -- false
SELECT TRUE::INTEGER;                                 -- 1
SELECT FALSE::INTEGER;                                -- 0

-- 日期转换
SELECT CAST('2024-01-15' AS DATE);                    -- 2024-01-15
SELECT CAST('2024-01-15 10:30:00' AS TIMESTAMP);      -- 2024-01-15 10:30:00

-- ============================================================
-- 2. :: 操作符: PostgreSQL 风格简写
-- ============================================================

SELECT '42'::INTEGER;                                 -- 42
SELECT '3.14'::DOUBLE PRECISION;                      -- 3.14
SELECT '2024-01-15'::DATE;                            -- 2024-01-15
SELECT 'hello world'::BYTEA;                          -- 二进制
SELECT 42::TEXT;                                      -- '42'
SELECT 'true'::BOOLEAN;                               -- true

-- :: 是 PostgreSQL 语法糖，等价于 CAST(... AS ...)
-- 优势: 代码更简洁（特别是在复杂表达式中）
-- 注意: :: 不是 SQL 标准，Oracle 模式下建议用 CAST

-- ============================================================
-- 3. TO_CHAR: 格式化输出 (数值/日期)
-- ============================================================

-- 数值格式化
SELECT TO_CHAR(123456.789, '999,999.99');             -- ' 123,456.79'
SELECT TO_CHAR(1234567.89, 'FM9,999,999.00');         -- '1,234,567.89'（FM 去空格）
SELECT TO_CHAR(42, '00009');                          -- '00042'（补零）

-- 日期格式化
SELECT TO_CHAR(NOW(), 'YYYY-MM-DD HH24:MI:SS');      -- '2024-01-15 10:30:00'
SELECT TO_CHAR(NOW(), 'YYYY-MM-DD');                  -- '2024-01-15'
SELECT TO_CHAR(NOW(), 'Day, DD Month YYYY');          -- 'Monday  , 15 January    2024'
SELECT TO_CHAR(NOW(), 'Mon DD, YYYY');                -- 'Jan 15, 2024'
SELECT TO_CHAR(NOW(), 'IW (IYYY)');                   -- ISO 周格式

-- 常用格式码:
--   数值: 9(数字位), 0(补零), ,(千分位), .(小数点), FM(去空格)
--   日期: YYYY/MM/DD, HH24/MI/SS, Day/Mon/Month

-- ============================================================
-- 4. TO_NUMBER / TO_DATE / TO_TIMESTAMP: 解析转换
-- ============================================================

-- TO_NUMBER: 字符串 → 数值
SELECT TO_NUMBER('123.45', '999.99');                 -- 123.45
SELECT TO_NUMBER('1,234.56', '9,999.99');             -- 1234.56

-- TO_DATE: 字符串 → 日期
SELECT TO_DATE('2024-01-15', 'YYYY-MM-DD');           -- 2024-01-15
SELECT TO_DATE('15/01/2024', 'DD/MM/YYYY');           -- 2024-01-15
SELECT TO_DATE('Jan 15, 2024', 'Mon DD, YYYY');       -- 2024-01-15

-- TO_TIMESTAMP: 字符串 → 时间戳
SELECT TO_TIMESTAMP('2024-01-15 10:30:00', 'YYYY-MM-DD HH24:MI:SS');
SELECT TO_TIMESTAMP(1705286400);                      -- Unix 时间戳 → TIMESTAMPTZ

-- ============================================================
-- 5. Oracle 兼容模式转换
-- ============================================================

-- Oracle 模式下的类型转换（FROM DUAL 语法）
SELECT TO_CHAR(SYSDATE, 'YYYY-MM-DD') FROM DUAL;             -- Oracle 日期格式化
SELECT TO_CHAR(SYSDATE, 'YYYY-MM-DD HH24:MI:SS') FROM DUAL;  -- 带时间
SELECT TO_CHAR(-1234.5, '9,999.00MI') FROM DUAL;              -- Oracle 数值格式化
SELECT TO_NUMBER('123.45') FROM DUAL;                          -- Oracle 数值解析
SELECT TO_DATE('2024-01-15', 'YYYY-MM-DD') FROM DUAL;         -- Oracle 日期解析
SELECT TO_TIMESTAMP('2024-01-15 10:30:00', 'YYYY-MM-DD HH24:MI:SS') FROM DUAL;

-- Oracle 模式独有: NVL (替代 COALESCE)
SELECT NVL(phone, 'N/A') FROM users;                 -- 等价于 COALESCE(phone, 'N/A')
SELECT NVL2(phone, phone, 'N/A') FROM users;         -- 非 NULL 返回第一个，NULL 返回第二个

-- ============================================================
-- 6. EPOCH 时间戳转换
-- ============================================================

SELECT EXTRACT(EPOCH FROM NOW());                     -- → Unix 时间戳（浮点秒）
SELECT EXTRACT(EPOCH FROM NOW())::INTEGER;            -- → 整数秒
SELECT TO_TIMESTAMP(1705286400);                      -- Unix → TIMESTAMPTZ

-- ============================================================
-- 7. JSON 类型转换
-- ============================================================

SELECT '{"name":"test"}'::JSONB;                      -- 字符串 → JSONB
SELECT CAST('["a","b"]' AS JSONB);                    -- 标准 CAST → JSONB
SELECT '{"a":1}'::JSON -> 'a';                        -- JSON 路径提取
SELECT '{"a":1}'::JSONB ->> 'a';                      -- JSONB 路径提取（文本结果）

-- ============================================================
-- 8. 隐式转换规则
-- ============================================================

-- PG 模式: 严格（大部分类型需要显式转换）
SELECT 1 + 1.5;                                      -- 2.5 (INTEGER + NUMERIC → NUMERIC)
-- SELECT '42' + 0;                                   -- 错误!（PG 模式不会自动将字符串转数值）

-- Oracle 模式: 较宽松（VARCHAR2 + NUMBER 可隐式转换）
-- Oracle 模式下部分隐式转换行为与 Oracle 一致

-- ============================================================
-- 9. 错误处理（安全转换）
-- ============================================================

-- KingbaseES 没有 TRY_CAST 函数
-- 可使用 PL/pgSQL 或 PL/SQL 封装安全转换函数:

-- 示例: 安全数值转换函数
-- CREATE OR REPLACE FUNCTION safe_to_number(text) RETURNS NUMERIC AS $$
-- BEGIN
--     RETURN CAST($1 AS NUMERIC);
-- EXCEPTION WHEN OTHERS THEN
--     RETURN NULL;
-- END;
-- $$ LANGUAGE plpgsql;

-- ============================================================
-- 10. 兼容模式差异总结
-- ============================================================

-- PostgreSQL 模式:
--   转换方式:  CAST, ::, TO_CHAR, TO_NUMBER, TO_DATE
--   DUAL 表:   不需要
--   NULL 函数: COALESCE, NULLIF
--   隐式转换:  严格
--
-- Oracle 模式:
--   转换方式:  CAST, TO_CHAR, TO_NUMBER, TO_DATE, NVL, NVL2
--   DUAL 表:   需要使用 FROM DUAL
--   NULL 函数: NVL, NVL2, COALESCE, NULLIF
--   隐式转换:  较宽松（VARCHAR2 ↔ NUMBER）

-- ============================================================
-- 11. 版本演进与注意事项
-- ============================================================
-- KingbaseES V8R2: PostgreSQL 兼容转换函数完备
-- KingbaseES V8R3: Oracle 兼容模式增强（NVL/NVL2/TO_CHAR 增强）
-- KingbaseES V8R6: JSONB 类型转换增强
--
-- 注意事项:
--   1. :: 操作符仅在 PG 模式下可用（Oracle 模式建议用 CAST）
--   2. 兼容模式在数据库初始化时选择，无法动态切换
--   3. TO_CHAR 格式码在 PG 模式和 Oracle 模式下有细微差异
--   4. 建议使用标准 SQL 的 CAST 以保持跨模式兼容
--   5. JSON 类型使用 PostgreSQL 语法（::JSONB）
