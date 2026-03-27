-- Apache Flink SQL: Type Conversion
--
-- 参考资料:
--   [1] Flink Documentation - Type Conversion Functions
--       https://nightlies.apache.org/flink/flink-docs-stable/docs/dev/table/functions/systemfunctions/

SELECT CAST(42 AS VARCHAR); SELECT CAST('42' AS INT); SELECT CAST('42' AS BIGINT);
SELECT CAST('3.14' AS DOUBLE); SELECT CAST('3.14' AS DECIMAL(10,2));
SELECT CAST('2024-01-15' AS DATE); SELECT CAST('2024-01-15 10:30:00' AS TIMESTAMP);

-- TRY_CAST                                      -- 1.17+
SELECT TRY_CAST('abc' AS INT);                   -- NULL
SELECT TRY_CAST('42' AS INT);                    -- 42

-- 日期/时间转换
SELECT DATE_FORMAT(CURRENT_TIMESTAMP, 'yyyy-MM-dd HH:mm:ss');
SELECT TO_DATE('2024-01-15'); SELECT TO_TIMESTAMP('2024-01-15 10:30:00');
SELECT FROM_UNIXTIME(1705276800);

-- 注意：Flink SQL 支持 CAST 和 TRY_CAST (1.17+)
-- 注意：日期函数使用 Java SimpleDateFormat 模式
-- 限制：无 CONVERT, ::
