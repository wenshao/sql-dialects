-- Apache Impala: 数值类型
--
-- 参考资料:
--   [1] Impala SQL Reference
--       https://impala.apache.org/docs/build/html/topics/impala_langref.html
--   [2] Impala Built-in Functions
--       https://impala.apache.org/docs/build/html/topics/impala_functions.html

-- 整数
-- TINYINT:   1 字节，-128 ~ 127
-- SMALLINT:  2 字节，-32768 ~ 32767
-- INT:       4 字节，-2^31 ~ 2^31-1
-- BIGINT:    8 字节，-2^63 ~ 2^63-1

CREATE TABLE examples (
    tiny_val   TINYINT,
    small_val  SMALLINT,
    int_val    INT,
    big_val    BIGINT
)
STORED AS PARQUET;

-- 浮点数
-- FLOAT:  4 字节，单精度
-- DOUBLE: 8 字节，双精度

-- 定点数
-- DECIMAL(P, S): P 最大 38，S 最大 38
CREATE TABLE prices (
    price      DECIMAL(10, 2),            -- 精确到分
    value      DOUBLE,                    -- 浮点数
    rate       FLOAT                      -- 单精度
)
STORED AS PARQUET;

-- 布尔
-- BOOLEAN: TRUE / FALSE / NULL
CREATE TABLE t (
    active BOOLEAN
)
STORED AS PARQUET;

-- Kudu 表数值类型
CREATE TABLE kudu_numbers (
    id         BIGINT,
    quantity   INT,
    price      DECIMAL(18, 4),
    PRIMARY KEY (id)
)
STORED AS KUDU;

-- 类型转换
SELECT CAST('123' AS INT);
SELECT CAST(123 AS STRING);
SELECT CAST(1.5 AS INT);                 -- 截断为 1
SELECT CAST('1.5' AS DECIMAL(10,2));

-- 数学运算
SELECT 5 / 2;                            -- 整数除法 = 2
SELECT 5.0 / 2;                          -- 浮点除法 = 2.5
SELECT 5 % 2;                            -- 取模 = 1
SELECT POW(2, 10);                       -- 幂运算 = 1024
SELECT SQRT(144);                        -- 平方根 = 12

-- 数值函数
SELECT ABS(-5);                          -- 5
SELECT CEIL(1.3);                        -- 2
SELECT FLOOR(1.7);                       -- 1
SELECT ROUND(1.567, 2);                  -- 1.57
SELECT TRUNCATE(1.567, 2);              -- 1.56
SELECT MOD(10, 3);                       -- 1

-- 注意：Impala 数值类型与 Hive 兼容
-- 注意：没有 UNSIGNED 类型
-- 注意：没有自增类型
-- 注意：没有 SERIAL 类型
-- 注意：DECIMAL 精度最高 38 位
-- 注意：整数除法返回整数（需要 CAST 为浮点类型）
