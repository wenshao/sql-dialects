-- StarRocks: Type Conversion
--
-- 参考资料:
--   [1] StarRocks Documentation - CAST
--       https://docs.starrocks.io/docs/sql-reference/sql-functions/cast/

SELECT CAST(42 AS VARCHAR); SELECT CAST('42' AS INT);
SELECT CAST('3.14' AS DOUBLE); SELECT CAST('3.14' AS DECIMAL(10,2));
SELECT CAST('2024-01-15' AS DATE); SELECT CAST('2024-01-15 10:30:00' AS DATETIME);

SELECT DATE_FORMAT(NOW(), '%Y-%m-%d %H:%i:%s');
SELECT STR_TO_DATE('2024-01-15', '%Y-%m-%d');

-- 隐式转换 (MySQL 兼容)
SELECT '42' + 0;

-- 注意：StarRocks 兼容 MySQL 类型转换
-- 限制：无 TRY_CAST, ::, CONVERT, TO_NUMBER
