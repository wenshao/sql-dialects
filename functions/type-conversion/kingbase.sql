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

-- 注意：KingbaseES 同时支持 PostgreSQL 和 Oracle 类型转换语法
-- 注意：支持 CAST, ::, TO_CHAR, TO_NUMBER, TO_DATE
