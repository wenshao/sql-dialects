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

-- 更多数值转换
SELECT CAST('100' AS INT);                           -- 100
SELECT CAST(3.14 AS INT);                            -- 3 (截断)
SELECT CAST(3.14 AS DECIMAL(10,1));                  -- 3.1
SELECT CAST(3.14 AS FLOAT);                          -- 3.14
SELECT CAST(TRUE AS INT);                            -- 1
SELECT CAST(0 AS BOOLEAN);                           -- false
SELECT CAST('' AS INT);                              -- NULL

-- 日期/时间格式化
SELECT DATE_FORMAT(CURRENT_DATE, 'yyyy-MM-dd');
SELECT DATE_FORMAT(CURRENT_DATE, 'dd/MM/yyyy');
SELECT DATE_FORMAT(CURRENT_TIMESTAMP, 'yyyy年MM月dd日 HH:mm:ss');
SELECT FROM_UNIXTIME(1705276800, 'yyyy-MM-dd HH:mm:ss');
SELECT FROM_UNIXTIME(1705276800, 'yyyyMMdd');
SELECT UNIX_TIMESTAMP('2024-01-15 10:30:00', 'yyyy-MM-dd HH:mm:ss');
SELECT TO_DATE('2024-01-15 10:30:00');               -- 提取日期部分

-- 日期部分提取
SELECT YEAR(CURRENT_DATE);                           -- 2024
SELECT MONTH(CURRENT_DATE);                          -- 1
SELECT DAY(CURRENT_DATE);                            -- 15
SELECT HOUR(CURRENT_TIMESTAMP);                      -- 10

-- 数值格式化 (无内置函数，需手动拼接)
SELECT CONCAT(CAST(CAST(1234567.89 AS DECIMAL(12,2)) AS STRING));

-- 复合类型转换
SELECT CAST(ARRAY(1, 2, 3) AS ARRAY<STRING>);
-- SELECT CAST(MAP('k1', 'v1') AS MAP<STRING, STRING>);

-- JSON 转换
SELECT GET_JSON_OBJECT('{"a":1}', '$.a');

-- 隐式转换详细规则
SELECT '42' + 0;                                     -- 42 (STRING → DOUBLE → 加法)
SELECT CONCAT('val: ', 42);                          -- 隐式转 STRING
SELECT 1 + 1.5;                                     -- DOUBLE
SELECT TRUE + 1;                                    -- 2 (BOOLEAN → INT)

-- 错误处理（无 TRY_CAST）
-- CAST 失败返回 NULL（Hive 行为较宽松）
-- 例如 CAST('abc' AS INT) → NULL（不报错）

-- 注意：Hive 使用 Java SimpleDateFormat 日期模式 (yyyy, MM, dd, HH, mm, ss)
-- 注意：隐式转换宽松
-- 注意：CAST 失败通常返回 NULL 而非报错
-- 限制：无 TRY_CAST (使用 Spark 3.x+), ::, CONVERT, TO_NUMBER, TO_CHAR
