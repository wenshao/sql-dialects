-- MaxCompute (ODPS): 数值类型
--
-- 参考资料:
--   [1] MaxCompute SQL - Data Types
--       https://help.aliyun.com/zh/maxcompute/user-guide/data-types-1
--   [2] MaxCompute - Mathematical Functions
--       https://help.aliyun.com/zh/maxcompute/user-guide/mathematical-functions

-- 整数
-- TINYINT:  1 字节，-128 ~ 127（2.0+）
-- SMALLINT: 2 字节，-32768 ~ 32767（2.0+）
-- INT:      4 字节，-2^31 ~ 2^31-1（2.0+）
-- BIGINT:   8 字节，-2^63 ~ 2^63-1（1.0 起就有）

CREATE TABLE examples (
    tiny_val   TINYINT,                   -- 2.0+
    small_val  SMALLINT,                  -- 2.0+
    int_val    INT,                       -- 2.0+
    big_val    BIGINT                     -- 1.0+ 唯一整数类型
);

-- 注意：1.0 版本只有 BIGINT 类型
-- 2.0 新数据类型需要开启：set odps.sql.type.system.odps2 = true;

-- 浮点数
-- FLOAT:  4 字节，单精度（2.0+）
-- DOUBLE: 8 字节，双精度

-- 定点数
-- DECIMAL: 精度 54，小数位 18（1.0）
-- DECIMAL(p, s): p 最大 36，s 最大 18（2.0+）
CREATE TABLE prices (
    price      DECIMAL(10, 2),            -- 精确到分
    value      DOUBLE                     -- 浮点数
);

-- 布尔
-- BOOLEAN: TRUE / FALSE / NULL（2.0+）
CREATE TABLE t (active BOOLEAN DEFAULT TRUE);

-- 注意：1.0 版本没有 BOOLEAN，通常用 BIGINT 的 0/1 代替

-- 类型转换
SELECT CAST('123' AS BIGINT);
SELECT CAST(123 AS DOUBLE);

-- 注意：没有 UNSIGNED 类型
-- 注意：没有自增类型（分布式环境不支持）
-- 注意：没有 BIT 类型
-- 注意：数值溢出行为取决于设置
