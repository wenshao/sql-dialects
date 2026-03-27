-- TDSQL: Type Conversion
--
-- 参考资料:
--   [1] TDSQL Documentation
--       https://cloud.tencent.com/document/product/557

-- MySQL 兼容
SELECT CAST(42 AS CHAR); SELECT CAST('42' AS SIGNED);
SELECT CAST('3.14' AS DECIMAL(10,2)); SELECT CAST('2024-01-15' AS DATE);
SELECT CONVERT(42, CHAR); SELECT CONVERT('42', SIGNED);
SELECT CONVERT('hello' USING utf8mb4);
SELECT DATE_FORMAT(NOW(), '%Y-%m-%d'); SELECT STR_TO_DATE('2024-01-15', '%Y-%m-%d');

-- 注意：TDSQL 兼容 MySQL 类型转换语法
