-- Apache Spark SQL: Type Conversion
--
-- 参考资料:
--   [1] Spark SQL Reference - CAST
--       https://spark.apache.org/docs/latest/api/sql/index.html

SELECT CAST(42 AS STRING); SELECT CAST('42' AS INT); SELECT CAST('3.14' AS DOUBLE);
SELECT CAST('3.14' AS DECIMAL(10,2));
SELECT CAST('2024-01-15' AS DATE); SELECT CAST('2024-01-15 10:30:00' AS TIMESTAMP);

-- TRY_CAST                                      -- 3.4+
SELECT TRY_CAST('abc' AS INT);                   -- NULL
SELECT TRY_CAST('42' AS INT);                    -- 42

-- :: 运算符                                      -- 3.4+
SELECT 42::STRING; SELECT '42'::INT;

-- 格式化
SELECT DATE_FORMAT(CURRENT_DATE(), 'yyyy-MM-dd');
SELECT TO_DATE('2024/01/15', 'yyyy/MM/dd');
SELECT TO_TIMESTAMP('2024-01-15 10:30:00', 'yyyy-MM-dd HH:mm:ss');
SELECT FROM_UNIXTIME(1705276800, 'yyyy-MM-dd HH:mm:ss');
SELECT UNIX_TIMESTAMP('2024-01-15', 'yyyy-MM-dd');

-- 隐式转换 (Spark 较宽松)
SELECT '42' + 0; SELECT CONCAT('val: ', 42);

-- 注意：Spark 3.4+ 支持 TRY_CAST 和 ::
-- 注意：日期模式使用 Java SimpleDateFormat/DateTimeFormatter
-- 限制：TO_NUMBER 支持有限
