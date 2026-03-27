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

-- 更多数值转换
SELECT CAST('100' AS BIGINT);                        -- 100
SELECT CAST(3.14 AS INT);                            -- 3 (截断)
SELECT CAST(3.14 AS DECIMAL(10,1));                  -- 3.1
SELECT CAST(TRUE AS INT);                            -- 1
SELECT CAST(0 AS BOOLEAN);                           -- false

-- TRY_CAST 详细示例 (1.17+)
SELECT TRY_CAST('hello' AS INT);                     -- NULL
SELECT TRY_CAST('2024-99-99' AS DATE);               -- NULL
SELECT TRY_CAST('3.14' AS DECIMAL(10,2));            -- 3.14
SELECT TRY_CAST('' AS INT);                          -- NULL

-- 日期/时间格式化
SELECT DATE_FORMAT(CURRENT_TIMESTAMP, 'yyyy-MM-dd HH:mm:ss');
SELECT DATE_FORMAT(CURRENT_TIMESTAMP, 'yyyy年MM月dd日');
SELECT DATE_FORMAT(CURRENT_TIMESTAMP, 'dd/MM/yyyy');
SELECT TO_DATE('2024-01-15');
SELECT TO_TIMESTAMP('2024-01-15 10:30:00');
SELECT FROM_UNIXTIME(1705276800, 'yyyy-MM-dd HH:mm:ss');
SELECT UNIX_TIMESTAMP(CAST('2024-01-15 00:00:00' AS TIMESTAMP));

-- 日期部分提取
SELECT YEAR(CURRENT_DATE);                           -- 2024
SELECT MONTH(CURRENT_DATE);                          -- 1
SELECT DAYOFMONTH(CURRENT_DATE);                     -- 15
SELECT HOUR(CURRENT_TIMESTAMP);                      -- 10

-- 区间转换
SELECT CAST('5' AS INTERVAL DAY);
SELECT CAST('2' AS INTERVAL HOUR);

-- 布尔转换
SELECT CAST('true' AS BOOLEAN);                      -- true
SELECT CAST(1 AS BOOLEAN);                           -- true

-- 复合类型转换
-- SELECT CAST(ARRAY[1, 2, 3] AS ARRAY<STRING>);
-- SELECT CAST(MAP['k1', 'v1'] AS MAP<STRING, STRING>);
-- SELECT CAST(ROW(1, 'abc') AS ROW<f1 INT, f2 STRING>);

-- 流处理中的类型转换
-- CREATE TABLE typed_sink AS
-- SELECT
--   TRY_CAST(raw_id AS BIGINT) AS id,
--   TRY_CAST(raw_amount AS DECIMAL(10,2)) AS amount,
--   TO_TIMESTAMP(event_time, 'yyyy-MM-dd HH:mm:ss') AS ts
-- FROM raw_source;

-- 注意：Flink SQL 支持 CAST 和 TRY_CAST (1.17+)
-- 注意：日期函数使用 Java SimpleDateFormat 模式 (yyyy, MM, dd, HH, mm, ss)
-- 注意：TRY_CAST 是流处理中的最佳实践（避免脏数据中断管道）
-- 限制：无 CONVERT, ::, TO_NUMBER, TO_CHAR
