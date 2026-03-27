-- Google Cloud Spanner: Type Conversion
--
-- 参考资料:
--   [1] Cloud Spanner SQL Reference - Conversion Functions
--       https://cloud.google.com/spanner/docs/reference/standard-sql/conversion_functions

SELECT CAST(42 AS STRING); SELECT CAST('42' AS INT64);
SELECT CAST('3.14' AS FLOAT64); SELECT CAST('3.14' AS NUMERIC);
SELECT CAST('2024-01-15' AS DATE); SELECT CAST('2024-01-15T10:30:00Z' AS TIMESTAMP);
SELECT CAST(TRUE AS INT64);

-- SAFE_CAST (安全转换)
SELECT SAFE_CAST('abc' AS INT64);               -- NULL
SELECT SAFE_CAST('42' AS INT64);                -- 42

-- 格式化
SELECT FORMAT_DATE('%Y-%m-%d', DATE '2024-01-15');
SELECT FORMAT_TIMESTAMP('%Y-%m-%d %H:%M:%S', TIMESTAMP '2024-01-15 10:30:00 UTC');
SELECT PARSE_DATE('%Y-%m-%d', '2024-01-15');
SELECT PARSE_TIMESTAMP('%Y-%m-%dT%H:%M:%SZ', '2024-01-15T10:30:00Z');

-- Unix 时间戳
SELECT UNIX_SECONDS(TIMESTAMP '2024-01-15 00:00:00 UTC');
SELECT TIMESTAMP_SECONDS(1705276800);

-- 更多数值转換
SELECT CAST(3.14 AS INT64);                          -- 3 (截断)
SELECT CAST('100' AS INT64);                         -- 100
SELECT CAST(3.14 AS NUMERIC);                        -- 3.14
SELECT CAST(TRUE AS INT64);                          -- 1
SELECT CAST(0 AS BOOL);                              -- false

-- SAFE_CAST 详细示例
SELECT SAFE_CAST('hello' AS INT64);                  -- NULL
SELECT SAFE_CAST('2024-99-99' AS DATE);              -- NULL
SELECT SAFE_CAST('' AS INT64);                       -- NULL
SELECT SAFE_CAST('3.14' AS NUMERIC);                 -- 3.14
SELECT SAFE_CAST(999999999999999999 AS INT64);       -- 溢出返回 NULL

-- 日期/時間格式化
SELECT FORMAT_DATE('%Y-%m-%d', CURRENT_DATE());
SELECT FORMAT_DATE('%d/%m/%Y', CURRENT_DATE());
SELECT FORMAT_DATE('%A, %B %d, %Y', CURRENT_DATE());
SELECT FORMAT_TIMESTAMP('%Y-%m-%d %H:%M:%S', CURRENT_TIMESTAMP());
SELECT FORMAT_TIMESTAMP('%Y-%m-%dT%H:%M:%SZ', CURRENT_TIMESTAMP());
SELECT PARSE_DATE('%d/%m/%Y', '15/01/2024');
SELECT PARSE_TIMESTAMP('%Y-%m-%dT%H:%M:%SZ', '2024-01-15T10:30:00Z');

-- 日期部分提取
SELECT EXTRACT(YEAR FROM CURRENT_DATE());
SELECT EXTRACT(MONTH FROM CURRENT_DATE());
SELECT EXTRACT(DAY FROM CURRENT_DATE());
SELECT EXTRACT(HOUR FROM CURRENT_TIMESTAMP());

-- 区間転換
SELECT DATE_ADD(CURRENT_DATE(), INTERVAL 1 DAY);
SELECT DATE_SUB(CURRENT_DATE(), INTERVAL 30 DAY);
SELECT TIMESTAMP_ADD(CURRENT_TIMESTAMP(), INTERVAL 2 HOUR);

-- 字符串 ↔ バイト
SELECT CAST('hello' AS BYTES);
SELECT CAST(b'hello' AS STRING);

-- JSON 転換
SELECT CAST('{"a":1}' AS JSON);
SELECT JSON_VALUE('{"a":1}', '$.a');

-- 隐式転換
-- Spanner 隐式転換非常严格
-- 几乎所有类型转换必须显式 CAST/SAFE_CAST

-- 注意：Spanner 使用 SAFE_CAST（同 BigQuery）
-- 注意：FORMAT_*/PARSE_* 用于日期格式化
-- 注意：日期格式使用 strftime 格式码 (%Y, %m, %d, %H, %M, %S)
-- 限制：无 CONVERT, ::, TRY_CAST, TO_NUMBER, TO_CHAR
