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

-- 注意：Spanner 使用 SAFE_CAST（同 BigQuery）
-- 注意：FORMAT_*/PARSE_* 用于日期格式化
-- 限制：无 CONVERT, ::, TRY_CAST, TO_NUMBER, TO_CHAR
