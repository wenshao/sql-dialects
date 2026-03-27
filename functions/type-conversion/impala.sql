-- Apache Impala: Type Conversion
--
-- 参考资料:
--   [1] Impala SQL Reference - Type Conversion
--       https://impala.apache.org/docs/build/html/topics/impala_conversion_functions.html

SELECT CAST(42 AS STRING); SELECT CAST('42' AS INT); SELECT CAST('3.14' AS DOUBLE);
SELECT CAST('2024-01-15' AS TIMESTAMP);

-- 格式化
SELECT FROM_TIMESTAMP(NOW(), 'yyyy-MM-dd HH:mm:ss');
SELECT TO_TIMESTAMP('2024-01-15 10:30:00', 'yyyy-MM-dd HH:mm:ss');
SELECT FROM_UNIXTIME(1705276800, 'yyyy-MM-dd');
SELECT UNIX_TIMESTAMP('2024-01-15 10:30:00');

-- 隐式转换
SELECT '42' + 0;                                 -- INT
SELECT CONCAT('val: ', CAST(42 AS STRING));

-- 注意：Impala CAST 目标类型直接用类型名
-- 注意：日期使用 Java SimpleDateFormat 模式
-- 限制：无 TRY_CAST, ::, CONVERT, TO_CHAR, TO_NUMBER
