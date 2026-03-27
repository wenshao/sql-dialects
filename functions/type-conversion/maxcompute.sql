-- MaxCompute: Type Conversion
--
-- 参考资料:
--   [1] MaxCompute SQL Reference - Type Conversion
--       https://www.alibabacloud.com/help/en/maxcompute/user-guide/type-conversions

SELECT CAST(42 AS STRING); SELECT CAST('42' AS BIGINT); SELECT CAST('3.14' AS DOUBLE);
SELECT CAST('3.14' AS DECIMAL(10,2));

-- 日期转换
SELECT TO_DATE('2024-01-15', 'yyyy-MM-dd');
SELECT TO_CHAR(CURRENT_TIMESTAMP, 'yyyy-MM-dd HH:mm:ss');
SELECT FROM_UNIXTIME(1705276800);
SELECT UNIX_TIMESTAMP('2024-01-15 00:00:00');

-- 隐式转换
SELECT '42' + 0;

-- 注意：MaxCompute 类型转换与 Hive 类似
-- 注意：日期模式使用 Java SimpleDateFormat
-- 限制：无 TRY_CAST, ::, CONVERT
