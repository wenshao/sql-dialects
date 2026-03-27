-- BigQuery: 类型转换
--
-- 参考资料:
--   [1] BigQuery SQL Reference - Conversion Functions
--       https://cloud.google.com/bigquery/docs/reference/standard-sql/conversion_functions

-- ============================================================
-- 1. CAST: 标准类型转换
-- ============================================================

SELECT CAST(42 AS STRING);              -- '42'
SELECT CAST('3.14' AS FLOAT64);         -- 3.14
SELECT CAST('2024-01-15' AS DATE);
SELECT CAST('2024-01-15 10:30:00' AS TIMESTAMP);
SELECT CAST(42 AS NUMERIC);
SELECT CAST(TRUE AS INT64);             -- 1

-- ============================================================
-- 2. SAFE_CAST: 安全转换（BigQuery 的设计亮点）
-- ============================================================

-- SAFE_CAST: 转换失败返回 NULL 而非报错
SELECT SAFE_CAST('not_a_number' AS INT64);     -- NULL
SELECT SAFE_CAST('invalid' AS DATE);           -- NULL
SELECT SAFE_CAST('3.14' AS INT64);             -- NULL（精度丢失不允许）

-- SAFE 前缀也可用于其他函数:
SELECT SAFE.PARSE_JSON('invalid json');         -- NULL
SELECT SAFE.PARSE_TIMESTAMP('%Y-%m-%d', 'bad'); -- NULL

-- 设计分析:
--   SAFE_CAST 与 ClickHouse 的 toOrNull 设计理念相同:
--   分析查询不应因一行脏数据而失败。
--   BigQuery 用 SAFE 前缀（更通用），ClickHouse 用 OrNull 后缀。
--   两种设计都是 OLAP 引擎的最佳实践。

-- ============================================================
-- 3. 特殊转换函数
-- ============================================================

-- 日期时间转换
SELECT PARSE_DATE('%Y-%m-%d', '2024-01-15');
SELECT PARSE_TIMESTAMP('%Y-%m-%d %H:%M:%S', '2024-01-15 10:30:00');
SELECT FORMAT_DATE('%B %d, %Y', DATE '2024-01-15');  -- 'January 15, 2024'
SELECT FORMAT_TIMESTAMP('%Y-%m-%dT%H:%M:%S', CURRENT_TIMESTAMP());

-- 数值格式化
SELECT FORMAT('%d items at $%.2f', 5, 9.99);  -- '5 items at $9.99'

-- 十六进制
SELECT TO_HEX(255);                    -- 'ff'
SELECT FROM_HEX('ff');                 -- b'\xff'

-- Base64
SELECT TO_BASE64(b'\xDE\xAD');
SELECT FROM_BASE64('3q0=');

-- JSON 转换
SELECT TO_JSON(STRUCT('alice' AS name, 25 AS age));
SELECT STRING(JSON '{"name": "alice"}');

-- ============================================================
-- 4. 隐式转换规则
-- ============================================================

-- BigQuery 的隐式转换较严格:
-- INT64 + FLOAT64 → FLOAT64（数值拓宽）
-- INT64 + NUMERIC → NUMERIC（数值拓宽）
-- STRING + INT64 → 报错!（不自动转换）
-- BOOL + INT64 → 报错!（不自动转换）
--
-- 需要显式 CAST 的场景:
-- WHERE int_col = '42'  → 报错! 需要 CAST('42' AS INT64)
-- 这比 MySQL 严格（MySQL 会隐式将 '42' 转为 42）

-- ============================================================
-- 5. COERCION（强制转换规则）
-- ============================================================

-- BigQuery 的类型强制转换遵循"超类型"规则:
-- INT64 和 FLOAT64 → 超类型是 FLOAT64
-- DATE 和 TIMESTAMP → 超类型是 TIMESTAMP
-- 用于 UNION ALL、CASE WHEN、IF 等需要统一类型的场景:
SELECT IF(TRUE, 1, 2.0);  -- FLOAT64（INT64 和 FLOAT64 的超类型）

-- ============================================================
-- 6. 对比与引擎开发者启示
-- ============================================================
-- BigQuery 类型转换的设计:
--   (1) CAST + SAFE_CAST → 标准 + 安全双轨
--   (2) PARSE_* / FORMAT_* → 日期时间的解析和格式化
--   (3) 严格隐式转换 → 减少意外行为
--   (4) SAFE 前缀通用 → 不仅限于 CAST
--
-- 对引擎开发者的启示:
--   SAFE 前缀是比 OrNull 后缀更通用的设计:
--   任何可能失败的函数都可以加 SAFE 前缀。
--   PARSE_DATE/FORMAT_DATE 比 CAST + strftime 更直观。
--   分析引擎应该选择严格隐式转换（减少 surprise behavior）。
