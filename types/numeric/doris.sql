-- Apache Doris: 数值类型
--
-- 参考资料:
--   [1] Doris SQL Manual
--       https://doris.apache.org/docs/sql-manual/sql-statements/
--   [2] Doris Data Types
--       https://doris.apache.org/docs/sql-manual/data-types/
--   [3] Doris Functions
--       https://doris.apache.org/docs/sql-manual/sql-functions/

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
    huge_val   LARGEINT                   -- 128 位整数（Doris 特有）
)
DUPLICATE KEY(int_val)
DISTRIBUTED BY HASH(int_val);

-- 注意：LARGEINT 是 Doris/StarRocks 特有类型（128 位）
-- 注意：不支持 UNSIGNED

-- 浮点数
-- FLOAT:  4 字节，单精度
-- DOUBLE: 8 字节，双精度

-- 定点数
-- DECIMAL(P, S): P 最大 38，S 最大 P
-- DECIMALV3: 更高精度（1.2+，默认启用）
CREATE TABLE prices (
    price      DECIMAL(10, 2),            -- 精确到分
    value      DOUBLE                     -- 浮点数
)
DUPLICATE KEY(price)
DISTRIBUTED BY HASH(price);

-- 布尔
-- BOOLEAN: TRUE / FALSE / NULL
CREATE TABLE t (
    active BOOLEAN DEFAULT TRUE
)
DUPLICATE KEY(active)
DISTRIBUTED BY HASH(active);

-- 特殊聚合类型
-- BITMAP: 位图（用于精确去重聚合，如 COUNT DISTINCT 加速）
-- HLL: HyperLogLog（用于近似去重聚合）
-- QUANTILE_STATE: 分位数计算
CREATE TABLE agg_table (
    dt         DATE,
    user_id    BITMAP BITMAP_UNION,       -- 位图聚合
    uv         HLL HLL_UNION,            -- HLL 聚合
    percentile QUANTILE_STATE QUANTILE_UNION
)
AGGREGATE KEY(dt)
DISTRIBUTED BY HASH(dt);

-- BITMAP 相关函数
SELECT BITMAP_COUNT(BITMAP_UNION(user_id)) AS uv FROM agg_table;
SELECT HLL_UNION_AGG(uv) FROM agg_table;

-- 类型转换
SELECT CAST('123' AS INT);
SELECT CAST(123 AS VARCHAR);
SELECT CAST(1.5 AS INT);                 -- 截断为 1

-- 注意：BITMAP/HLL/QUANTILE_STATE 只能用于聚合模型
-- 注意：2.1+ 支持 AUTO_INCREMENT（仅 Unique Key 的 Merge-on-Write 模型）
-- 注意：没有 BIT 类型
-- 注意：DECIMAL 精度最高 38 位
