-- ClickHouse: Type Conversion
--
-- 参考资料:
--   [1] ClickHouse Documentation - Type Conversion Functions
--       https://clickhouse.com/docs/en/sql-reference/functions/type-conversion-functions

-- ============================================================
-- CAST
-- ============================================================
SELECT CAST(42 AS String);                      -- '42'
SELECT CAST('42' AS UInt64);                    -- 42
SELECT CAST('2024-01-15' AS Date);              -- Date
SELECT CAST(3.14 AS UInt32);                    -- 3

-- ============================================================
-- :: 运算符 (ClickHouse 支持)
-- ============================================================
SELECT 42::String;                              -- '42'
SELECT '42'::UInt64;                            -- 42

-- ============================================================
-- toType 系列函数
-- ============================================================
SELECT toString(42);                             -- '42'
SELECT toUInt64('42');                           -- 42
SELECT toFloat64('3.14');                        -- 3.14
SELECT toDate('2024-01-15');                     -- Date
SELECT toDateTime('2024-01-15 10:30:00');        -- DateTime
SELECT toDecimal128('3.14', 2);                 -- Decimal

-- ============================================================
-- 安全转换 (*OrZero, *OrNull, *OrDefault)
-- ============================================================
SELECT toUInt64OrZero('abc');                    -- 0
SELECT toUInt64OrNull('abc');                    -- NULL
SELECT toUInt64OrDefault('abc', 42);             -- 42
SELECT toFloat64OrZero('not_number');           -- 0.0
SELECT toDateOrNull('bad-date');                -- NULL
SELECT toDateOrZero('bad-date');                -- '1970-01-01'

-- ============================================================
-- 格式化
-- ============================================================
SELECT formatDateTime(now(), '%Y-%m-%d %H:%M:%S');
SELECT parseDateTimeBestEffort('Jan 15, 2024');  -- 自动解析
SELECT parseDateTime32BestEffort('2024-01-15 10:30:00');

-- 数值格式化
SELECT formatReadableSize(1073741824);           -- '1.00 GiB'
SELECT formatReadableQuantity(1234567);          -- '1.23 million'
SELECT formatReadableTimeDelta(3661);            -- '1 hour, 1 minute and 1 second'

-- 隐式转换
-- ClickHouse 隐式转换比较严格
SELECT 1 + toUInt64('2');                        -- 需要显式转换
SELECT concat('val: ', toString(42));            -- 需要显式转换

-- 注意：ClickHouse 有 toType / toTypeOrZero / toTypeOrNull / toTypeOrDefault 系列
-- 注意：支持 :: 运算符
-- 注意：parseDateTimeBestEffort 自动识别多种日期格式
-- 注意：formatReadable* 系列提供人类可读格式
-- 限制：无 TRY_CAST / SAFE_CAST
-- 限制：无 CONVERT (SQL Server 风格)
