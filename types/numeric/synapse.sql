-- Azure Synapse: 数值类型
--
-- 参考资料:
--   [1] Synapse SQL Features
--       https://learn.microsoft.com/en-us/azure/synapse-analytics/sql/overview-features
--   [2] Synapse T-SQL Differences
--       https://learn.microsoft.com/en-us/azure/synapse-analytics/sql/overview-features

-- TINYINT: 1 字节，0 ~ 255
-- SMALLINT: 2 字节，-32768 ~ 32767
-- INT / INTEGER: 4 字节，-2^31 ~ 2^31-1
-- BIGINT: 8 字节，-2^63 ~ 2^63-1

CREATE TABLE examples (
    tiny_val   TINYINT,                      -- 1 字节
    small_val  SMALLINT,                     -- 2 字节
    int_val    INT,                          -- 4 字节
    big_val    BIGINT                        -- 8 字节
);

-- 定点数
-- DECIMAL(p, s) / NUMERIC(p, s): 最大精度 38
-- MONEY: 8 字节，-922337203685477.5808 ~ 922337203685477.5807
-- SMALLMONEY: 4 字节，-214748.3648 ~ 214748.3647
CREATE TABLE prices (
    price      DECIMAL(10, 2),               -- 10 位总精度，2 位小数
    rate       NUMERIC(5, 4),
    amount     MONEY,                        -- 货币类型（4 位小数）
    small_amt  SMALLMONEY
);

-- 浮点数
-- REAL / FLOAT(24): 4 字节单精度
-- FLOAT / FLOAT(53): 8 字节双精度
CREATE TABLE measurements (
    value      REAL,                         -- 4 字节
    result     FLOAT                         -- 8 字节
);
-- FLOAT(n): n 1~24 → 单精度，n 25~53 → 双精度

-- BIT: 0 或 1
CREATE TABLE flags (
    is_active  BIT DEFAULT 1,
    is_deleted BIT DEFAULT 0
);

-- 自增
CREATE TABLE t (
    id BIGINT IDENTITY(1, 1) NOT NULL        -- 起始值 1，步长 1
);

-- 类型转换
SELECT CAST('123' AS INT);
SELECT CAST('123.45' AS DECIMAL(10, 2));
SELECT CONVERT(INT, '123');                  -- T-SQL 风格
SELECT TRY_CAST('abc' AS INT);              -- 安全转换，失败返回 NULL
SELECT TRY_CONVERT(INT, 'abc');             -- 安全转换

-- 数值函数
SELECT ABS(-5);                              -- 5
SELECT CEILING(3.2);                         -- 4
SELECT FLOOR(3.8);                           -- 3
SELECT ROUND(3.567, 2);                      -- 3.57
SELECT ROUND(3.567, 2, 1);                   -- 3.56（截断模式）
SELECT POWER(2, 10);                         -- 1024
SELECT SQRT(144);                            -- 12
SELECT SIGN(-5);                             -- -1

-- APPROX_COUNT_DISTINCT（近似计数，Synapse 支持）
SELECT APPROX_COUNT_DISTINCT(user_id) FROM events;

-- 注意：TINYINT 只支持 0~255（无符号）
-- 注意：BIT 类型用于布尔值（不是 BOOLEAN）
-- 注意：MONEY 类型固定 4 位小数，不推荐用于精确计算
-- 注意：IDENTITY 列在 CTAS 中不保证原始值
-- 注意：没有 BOOLEAN 类型（用 BIT 代替）
-- 注意：DECIMAL 最大精度 38 位
-- 注意：TRY_CAST / TRY_CONVERT 是安全转换（不报错）
