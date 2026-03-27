-- TiDB: Type Conversion
--
-- 参考资料:
--   [1] TiDB Documentation - CAST
--       https://docs.pingcap.com/tidb/stable/cast-functions-and-operators

-- MySQL 兼容
SELECT CAST(42 AS CHAR); SELECT CAST('42' AS SIGNED); SELECT CAST('42' AS UNSIGNED);
SELECT CAST('3.14' AS DECIMAL(10,2)); SELECT CAST('3.14' AS DOUBLE);
SELECT CAST('2024-01-15' AS DATE); SELECT CAST('2024-01-15 10:30:00' AS DATETIME);

SELECT CONVERT(42, CHAR); SELECT CONVERT('42', SIGNED);
SELECT CONVERT('hello' USING utf8mb4);

SELECT DATE_FORMAT(NOW(), '%Y-%m-%d %H:%i:%s');
SELECT STR_TO_DATE('2024-01-15', '%Y-%m-%d');

-- 隐式转换 (MySQL 兼容)
SELECT '42' + 0; SELECT CONCAT('val: ', 42);

-- 注意：TiDB 兼容 MySQL 类型转换
-- 限制：无 TRY_CAST, ::, TO_NUMBER, TO_CHAR
