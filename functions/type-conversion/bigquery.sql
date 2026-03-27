-- BigQuery: Type Conversion
--
-- 参考资料:
--   [1] BigQuery SQL Reference - Conversion Functions
--       https://cloud.google.com/bigquery/docs/reference/standard-sql/conversion_functions
--   [2] BigQuery SQL Reference - SAFE_CAST
--       https://cloud.google.com/bigquery/docs/reference/standard-sql/conversion_functions#safe_casting

-- ============================================================
-- CAST
-- ============================================================
SELECT CAST(42 AS STRING);                      -- '42'
SELECT CAST('42' AS INT64);                     -- 42
SELECT CAST(3.14 AS INT64);                     -- 3
SELECT CAST('3.14' AS FLOAT64);                -- 3.14
SELECT CAST('3.14' AS NUMERIC);                -- 3.14
SELECT CAST('2024-01-15' AS DATE);              -- DATE
SELECT CAST('2024-01-15 10:30:00' AS TIMESTAMP); -- TIMESTAMP
SELECT CAST(TRUE AS INT64);                     -- 1
SELECT CAST('{"a":1}' AS JSON);                 -- JSON

-- ============================================================
-- SAFE_CAST (安全转换，失败返回 NULL)
-- ============================================================
SELECT SAFE_CAST('abc' AS INT64);               -- NULL (不报错)
SELECT SAFE_CAST('42' AS INT64);                -- 42
SELECT SAFE_CAST('2024-13-01' AS DATE);         -- NULL
SELECT SAFE_CAST('3.14' AS INT64);              -- NULL (不能将小数转为整数)

-- ============================================================
-- 格式化函数
-- ============================================================
SELECT FORMAT('%d', 42);                         -- '42'
SELECT FORMAT('%.2f', 3.14159);                  -- '3.14'
SELECT FORMAT('%s', DATE '2024-01-15');          -- '2024-01-15'

-- FORMAT_DATE / FORMAT_DATETIME / FORMAT_TIMESTAMP / FORMAT_TIME
SELECT FORMAT_DATE('%Y/%m/%d', DATE '2024-01-15');  -- '2024/01/15'
SELECT FORMAT_TIMESTAMP('%Y-%m-%d %H:%M:%S', TIMESTAMP '2024-01-15 10:30:00 UTC');
SELECT FORMAT_DATE('%A, %B %d, %Y', DATE '2024-01-15'); -- 'Monday, January 15, 2024'

-- PARSE_DATE / PARSE_DATETIME / PARSE_TIMESTAMP / PARSE_TIME
SELECT PARSE_DATE('%Y/%m/%d', '2024/01/15');     -- DATE
SELECT PARSE_TIMESTAMP('%Y-%m-%d %H:%M:%S', '2024-01-15 10:30:00');
SELECT PARSE_DATE('%b %d, %Y', 'Jan 15, 2024'); -- DATE

-- ============================================================
-- 隐式转换
-- ============================================================
-- BigQuery 隐式转换严格，大多需要显式 CAST
-- INT64 → FLOAT64 : 自动（在运算中）
-- INT64 → NUMERIC  : 自动
-- 其他: 需要显式 CAST

-- ============================================================
-- 常见转换模式
-- ============================================================
SELECT CAST(123.45 AS STRING);                  -- '123.45'
SELECT CAST('123.45' AS FLOAT64);              -- 123.45
SELECT CAST(DATE '2024-01-15' AS STRING);      -- '2024-01-15'
SELECT UNIX_SECONDS(TIMESTAMP '2024-01-15 00:00:00 UTC'); -- Unix 时间戳
SELECT TIMESTAMP_SECONDS(1705276800);           -- Unix → TIMESTAMP

-- 注意：BigQuery 使用 SAFE_CAST 而非 TRY_CAST
-- 注意：FORMAT_* / PARSE_* 用于日期格式化
-- 注意：隐式转换严格
-- 限制：无 CONVERT / :: / TO_NUMBER / TO_CHAR
