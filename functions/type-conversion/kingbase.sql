-- KingbaseES: Type Conversion
--
-- 参考资料:
--   [1] KingbaseES SQL 参考手册
--       https://help.kingbase.com.cn/

-- PostgreSQL 兼容
SELECT CAST(42 AS TEXT); SELECT 42::TEXT; SELECT '42'::INTEGER;
SELECT to_char(123456.789, '999,999.99'); SELECT to_char(now(), 'YYYY-MM-DD');
SELECT to_number('123.45', '999.99'); SELECT to_date('2024-01-15', 'YYYY-MM-DD');

-- Oracle 兼容
SELECT TO_CHAR(SYSDATE, 'YYYY-MM-DD') FROM DUAL;
SELECT TO_NUMBER('123.45') FROM DUAL;
SELECT TO_DATE('2024-01-15', 'YYYY-MM-DD') FROM DUAL;

-- 更多数值转换
SELECT CAST(3.14 AS INTEGER);                        -- 3 (截断)
SELECT '100'::BIGINT;                                -- 100
SELECT CAST(3.14 AS NUMERIC(10,1));                  -- 3.1

-- 布尔转换 (PostgreSQL 模式)
SELECT CAST(1 AS BOOLEAN);                           -- true
SELECT 'yes'::BOOLEAN;                               -- true
SELECT TRUE::INTEGER;                                -- 1

-- 日期/时间格式化 (PostgreSQL 模式)
SELECT to_char(now(), 'YYYY-MM-DD HH24:MI:SS');
SELECT to_char(now(), 'Day, DD Month YYYY');
SELECT to_timestamp('2024-01-15 10:30:00', 'YYYY-MM-DD HH24:MI:SS');
SELECT to_timestamp(1705276800);                     -- Unix → TIMESTAMP
SELECT EXTRACT(EPOCH FROM now());                    -- TIMESTAMP → Unix

-- 日期/时间格式化 (Oracle 模式)
SELECT TO_CHAR(SYSDATE, 'YYYY-MM-DD HH24:MI:SS') FROM DUAL;
SELECT TO_CHAR(SYSDATE, 'Day, DD Month YYYY') FROM DUAL;
SELECT TO_TIMESTAMP('2024-01-15 10:30:00', 'YYYY-MM-DD HH24:MI:SS') FROM DUAL;

-- 数值格式化
SELECT to_char(1234567.89, 'FM9,999,999.00');        -- '1,234,567.89'
SELECT TO_NUMBER('$1,234.56', 'L9,999.99');
SELECT TO_CHAR(-1234.5, '9,999.00MI') FROM DUAL;    -- Oracle 模式

-- JSON 转换 (PostgreSQL 模式)
SELECT '{"name":"test"}'::JSONB;
SELECT CAST('["a","b"]' AS JSONB);

-- 隐式转换规则
SELECT 1 + 1.5;                                     -- NUMERIC
-- PG模式: 严格
-- Oracle模式: VARCHAR2 + NUMBER 时可隐式转换

-- 错误处理（无 TRY_CAST）
-- 可使用 PL/pgSQL 或 PL/SQL 封装安全转换函数

-- 注意：KingbaseES 同时支持 PostgreSQL 和 Oracle 类型转换语法
-- 注意：支持 CAST, ::, TO_CHAR, TO_NUMBER, TO_DATE
-- 注意：兼容模式在初始化时选择，影响转换行为
-- 注意：Oracle 模式下使用 FROM DUAL
