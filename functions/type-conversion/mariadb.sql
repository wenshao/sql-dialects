-- MariaDB: Type Conversion
--
-- 参考资料:
--   [1] MariaDB Knowledge Base - CAST and CONVERT
--       https://mariadb.com/kb/en/cast/
--   [2] MariaDB Knowledge Base - CONVERT
--       https://mariadb.com/kb/en/convert/

SELECT CAST(42 AS CHAR); SELECT CAST('42' AS SIGNED); SELECT CAST('42' AS UNSIGNED);
SELECT CAST('3.14' AS DECIMAL(10,2)); SELECT CAST('3.14' AS DOUBLE);
SELECT CAST('2024-01-15' AS DATE); SELECT CAST('2024-01-15 10:30:00' AS DATETIME);

-- CONVERT
SELECT CONVERT(42, CHAR); SELECT CONVERT('42', SIGNED);
SELECT CONVERT('hello' USING utf8mb4);          -- 字符集转换

-- 格式化
SELECT FORMAT(1234567.89, 2);                   -- '1,234,567.89'
SELECT DATE_FORMAT(NOW(), '%Y-%m-%d %H:%i:%s');
SELECT STR_TO_DATE('15/01/2024', '%d/%m/%Y');

-- 隐式转换 (与 MySQL 一致，宽松)
SELECT '42' + 0; SELECT CONCAT('val: ', 42);

-- 注意：与 MySQL 类型转换高度兼容
-- 限制：无 TRY_CAST, ::, TO_NUMBER, TO_CHAR
