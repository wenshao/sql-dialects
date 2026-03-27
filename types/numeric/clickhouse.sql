-- ClickHouse: 数值类型
--
-- 参考资料:
--   [1] ClickHouse - Numeric Data Types
--       https://clickhouse.com/docs/en/sql-reference/data-types/int-uint
--   [2] ClickHouse - Decimal
--       https://clickhouse.com/docs/en/sql-reference/data-types/decimal

-- 有符号整数
-- Int8:   1 字节，-128 ~ 127
-- Int16:  2 字节，-32768 ~ 32767
-- Int32:  4 字节，-2^31 ~ 2^31-1
-- Int64:  8 字节，-2^63 ~ 2^63-1
-- Int128: 16 字节（21.6+）
-- Int256: 32 字节（21.6+）

-- 无符号整数
-- UInt8:   1 字节，0 ~ 255
-- UInt16:  2 字节，0 ~ 65535
-- UInt32:  4 字节，0 ~ 2^32-1
-- UInt64:  8 字节，0 ~ 2^64-1
-- UInt128: 16 字节（21.6+）
-- UInt256: 32 字节（21.6+）

CREATE TABLE examples (
    tiny_val   Int8,
    int_val    Int32,
    big_val    Int64,
    pos_val    UInt32,                     -- 无符号
    huge_val   Int128                      -- 超大整数（21.6+）
) ENGINE = MergeTree() ORDER BY int_val;

-- 浮点数
-- Float32: 4 字节，单精度
-- Float64: 8 字节，双精度
CREATE TABLE measurements (
    value      Float64
) ENGINE = MergeTree() ORDER BY value;

-- 定点数
-- Decimal(P, S) / Decimal32(S) / Decimal64(S) / Decimal128(S) / Decimal256(S)
-- Decimal32: P 1~9
-- Decimal64: P 10~18
-- Decimal128: P 19~38
-- Decimal256: P 39~76（21.6+）
CREATE TABLE prices (
    price      Decimal(10, 2),            -- 自动选择 Decimal32
    precise    Decimal128(18)             -- 高精度
) ENGINE = MergeTree() ORDER BY price;

-- 布尔（21.12+）
-- Bool: UInt8 的别名，0 = false, 1 = true
CREATE TABLE t (
    active Bool DEFAULT true
) ENGINE = MergeTree() ORDER BY active;

-- Nullable 包装器
-- ClickHouse 列默认不允许 NULL，需显式声明
CREATE TABLE t (
    val    Int32,                          -- 不允许 NULL
    opt    Nullable(Int32)                 -- 允许 NULL
) ENGINE = MergeTree() ORDER BY val;

-- 类型转换
SELECT toInt32('123');
SELECT toFloat64('3.14');
SELECT toInt32OrNull('abc');              -- 安全转换，失败返回 NULL
SELECT toInt32OrZero('abc');              -- 安全转换，失败返回 0
SELECT CAST('123' AS Int64);

-- 注意：UInt* 是 ClickHouse 特有的无符号类型
-- 注意：Int128/Int256 支持超大整数运算
-- 注意：Nullable 会影响查询性能，非必要不使用
-- 注意：没有自增类型
