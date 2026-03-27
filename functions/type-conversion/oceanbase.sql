-- OceanBase: Type Conversion
--
-- 参考资料:
--   [1] OceanBase Documentation
--       https://www.oceanbase.com/docs/common-oceanbase-database-cn

-- MySQL 模式
SELECT CAST(42 AS CHAR); SELECT CAST('42' AS SIGNED); SELECT CAST('3.14' AS DECIMAL(10,2));
SELECT CONVERT(42, CHAR); SELECT CONVERT('42', SIGNED);
SELECT DATE_FORMAT(NOW(), '%Y-%m-%d'); SELECT STR_TO_DATE('2024-01-15', '%Y-%m-%d');

-- Oracle 模式
-- SELECT CAST(42 AS VARCHAR2(10)) FROM DUAL;
-- SELECT TO_CHAR(SYSDATE, 'YYYY-MM-DD') FROM DUAL;
-- SELECT TO_NUMBER('123.45') FROM DUAL;
-- SELECT TO_DATE('2024-01-15', 'YYYY-MM-DD') FROM DUAL;

-- 注意：OceanBase 支持 MySQL 和 Oracle 两种模式
