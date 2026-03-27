-- Apache Hive: Type Conversion
--
-- 参考资料:
--   [1] Hive Language Manual - UDF
--       https://cwiki.apache.org/confluence/display/Hive/LanguageManual+UDF

SELECT CAST(42 AS STRING); SELECT CAST('42' AS INT); SELECT CAST('42' AS BIGINT);
SELECT CAST('3.14' AS DOUBLE); SELECT CAST('3.14' AS DECIMAL(10,2));
SELECT CAST('2024-01-15' AS DATE); SELECT CAST('2024-01-15 10:30:00' AS TIMESTAMP);

-- 格式化
SELECT DATE_FORMAT(CURRENT_DATE, 'yyyy-MM-dd');
SELECT TO_DATE('2024-01-15 10:30:00');           -- 提取日期部分
SELECT FROM_UNIXTIME(1705276800, 'yyyy-MM-dd HH:mm:ss');
SELECT UNIX_TIMESTAMP('2024-01-15', 'yyyy-MM-dd');

-- 隐式转换
SELECT '42' + 0;                                 -- 42 (隐式)
SELECT CONCAT('val: ', 42);                      -- 隐式转字符串

-- 注意：Hive 使用 Java SimpleDateFormat 日期模式
-- 注意：隐式转换宽松
-- 限制：无 TRY_CAST (使用 Spark 3.x+), ::, CONVERT, TO_NUMBER, TO_CHAR
