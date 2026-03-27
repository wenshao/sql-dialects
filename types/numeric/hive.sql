-- Hive: 数值类型
--
-- 参考资料:
--   [1] Apache Hive - Data Types
--       https://cwiki.apache.org/confluence/display/Hive/LanguageManual+Types
--   [2] Apache Hive - Math Functions
--       https://cwiki.apache.org/confluence/display/Hive/LanguageManual+UDF#LanguageManualUDF-MathematicalFunctions

-- 整数
-- TINYINT:  1 字节，-128 ~ 127
-- SMALLINT: 2 字节，-32768 ~ 32767
-- INT:      4 字节，-2^31 ~ 2^31-1
-- BIGINT:   8 字节，-2^63 ~ 2^63-1

CREATE TABLE examples (
    tiny_val   TINYINT,
    small_val  SMALLINT,
    int_val    INT,
    big_val    BIGINT
);

-- 整数字面量后缀
SELECT 100Y;                              -- TINYINT
SELECT 100S;                              -- SMALLINT
SELECT 100;                               -- INT
SELECT 100L;                              -- BIGINT

-- 浮点数
-- FLOAT:  4 字节，单精度
-- DOUBLE: 8 字节，双精度（DOUBLE PRECISION 是别名）

-- 定点数
-- DECIMAL(p, s): p 最大 38，s 最大 38（0.11+）
-- DECIMAL: 默认 DECIMAL(10, 0)
CREATE TABLE prices (
    price      DECIMAL(10, 2),            -- 精确到分
    value      DOUBLE                     -- 浮点数
);

-- 注意：DECIMAL 在 0.11 引入，0.13 进行了重大改进
-- 早期 Hive 建议用 DOUBLE 替代

-- 布尔
-- BOOLEAN: TRUE / FALSE
CREATE TABLE t (active BOOLEAN DEFAULT TRUE);

-- 类型转换
SELECT CAST('123' AS INT);
SELECT CAST(123 AS DOUBLE);

-- 隐式类型转换规则
-- TINYINT -> SMALLINT -> INT -> BIGINT -> FLOAT -> DOUBLE
-- STRING 可以隐式转换为 DOUBLE
-- BOOLEAN 不能隐式转换为任何其他类型

-- 注意：没有 UNSIGNED 类型
-- 注意：没有自增类型
-- 注意：没有 BIT 类型
-- 注意：数值精度受 SerDe 和文件格式影响
