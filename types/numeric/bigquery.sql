-- BigQuery: 数值类型
--
-- 参考资料:
--   [1] BigQuery SQL Reference - Data Types (Numeric)
--       https://cloud.google.com/bigquery/docs/reference/standard-sql/data-types#numeric_types
--   [2] BigQuery SQL Reference - Mathematical Functions
--       https://cloud.google.com/bigquery/docs/reference/standard-sql/mathematical_functions

-- 整数
-- INT64: 8 字节，-2^63 ~ 2^63-1（唯一整数类型）

CREATE TABLE examples (
    id         INT64,                     -- 唯一整数类型
    amount     INT64                      -- 没有 TINYINT/SMALLINT/INT 区分
);

-- 注意：INT64 是唯一的整数类型
-- INT / INTEGER / SMALLINT / TINYINT / BYTEINT 均为 INT64 的别名

-- 浮点数
-- FLOAT64: 8 字节，IEEE 754 双精度（唯一浮点类型）
CREATE TABLE measurements (
    value      FLOAT64                    -- 没有 FLOAT / REAL 区分
);

-- 注意：FLOAT64 的别名：FLOAT

-- 定点数（精确）
-- NUMERIC / DECIMAL: 16 字节，精度 38，小数位 9
-- BIGNUMERIC / BIGDECIMAL: 32 字节，精度 76，小数位 38（2020+）
CREATE TABLE prices (
    price      NUMERIC,                   -- 精度 38，小数位 9
    precise    BIGNUMERIC                 -- 精度 76，小数位 38
);

-- NUMERIC(P) / NUMERIC(P, S) 参数化形式
SELECT CAST(1.23 AS NUMERIC(10, 2));

-- 布尔
-- BOOL: TRUE / FALSE / NULL
CREATE TABLE t (active BOOL DEFAULT TRUE);

-- 类型转换
SELECT CAST('123' AS INT64);
SELECT SAFE_CAST('abc' AS INT64);         -- 安全转换，失败返回 NULL

-- 特殊数值
SELECT IEEE_DIVIDE(0, 0);                 -- NaN
SELECT IEEE_DIVIDE(1, 0);                 -- Infinity

-- 数学函数
SELECT ABS(-5);
SELECT MOD(10, 3);
SELECT ROUND(3.14159, 2);                 -- 3.14
SELECT TRUNC(3.14159, 2);                 -- 3.14
SELECT CEIL(3.14);                        -- 4
SELECT FLOOR(3.14);                       -- 3

-- 注意：没有 UNSIGNED 类型
-- 注意：没有自增类型（使用 GENERATE_UUID() 或 ROW_NUMBER()）
-- 注意：没有 MONEY 类型
-- 注意：所有数值运算溢出会报错（不会静默截断）
