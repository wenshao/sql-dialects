-- StarRocks: 数值类型
--
-- 参考资料:
--   [1] StarRocks - Data Types
--       https://docs.starrocks.io/docs/sql-reference/data-types/
--   [2] StarRocks - Math Functions
--       https://docs.starrocks.io/docs/sql-reference/sql-functions/math-functions/

-- 整数
-- TINYINT:   1 字节，-128 ~ 127
-- SMALLINT:  2 字节，-32768 ~ 32767
-- INT:       4 字节，-2^31 ~ 2^31-1
-- BIGINT:    8 字节，-2^63 ~ 2^63-1
-- LARGEINT: 16 字节，-2^127 ~ 2^127-1

CREATE TABLE examples (
    tiny_val   TINYINT,
    small_val  SMALLINT,
    int_val    INT,
    big_val    BIGINT,
    huge_val   LARGEINT                   -- 128 位整数（StarRocks 特有）
)
DISTRIBUTED BY HASH(int_val);

-- 注意：LARGEINT 是 StarRocks/Doris 特有类型（128 位）
-- 注意：不支持 UNSIGNED

-- 浮点数
-- FLOAT:  4 字节，单精度
-- DOUBLE: 8 字节，双精度

-- 定点数
-- DECIMAL(P, S): P 最大 38，S 最大 P（2.x）
-- DECIMAL V3: P 最大 38，更高性能（3.0+）
CREATE TABLE prices (
    price      DECIMAL(10, 2),            -- 精确到分
    value      DOUBLE                     -- 浮点数
)
DISTRIBUTED BY HASH(price);

-- 布尔
-- BOOLEAN: TRUE / FALSE / NULL
CREATE TABLE t (
    active BOOLEAN DEFAULT TRUE
)
DISTRIBUTED BY HASH(active);

-- 特殊聚合类型
-- BITMAP: 位图（用于精确去重聚合，如 COUNT DISTINCT 加速）
-- HLL: HyperLogLog（用于近似去重聚合）
-- PERCENTILE: 百分位数（用于近似百分位计算）
CREATE TABLE agg_table (
    dt         DATE,
    user_id    BITMAP BITMAP_UNION,       -- 位图聚合
    uv         HLL HLL_UNION              -- HLL 聚合
)
AGGREGATE KEY(dt)
DISTRIBUTED BY HASH(dt);

-- 类型转换
SELECT CAST('123' AS INT);
SELECT CAST(123 AS VARCHAR);

-- 注意：BITMAP/HLL/PERCENTILE 只能用于聚合模型
-- 注意：没有自增类型
-- 注意：没有 BIT 类型
