-- BigQuery: Math Functions
--
-- 参考资料:
--   [1] BigQuery SQL Reference - Mathematical Functions
--       https://cloud.google.com/bigquery/docs/reference/standard-sql/mathematical_functions

-- ============================================================
-- 基本数学函数
-- ============================================================
SELECT ABS(-42);                          -- 42
SELECT CEIL(4.3);                         -- 5            (CEILING 同义)
SELECT CEILING(4.3);                      -- 5
SELECT FLOOR(4.7);                        -- 4
SELECT ROUND(3.14159, 2);                 -- 3.14
SELECT ROUND(3.14159);                    -- 3
SELECT TRUNC(3.14159, 2);                 -- 3.14
SELECT TRUNC(3.14159);                    -- 3

-- ============================================================
-- 取模运算
-- ============================================================
SELECT MOD(17, 5);                        -- 2

-- ============================================================
-- 幂、根、指数、对数
-- ============================================================
SELECT POWER(2, 10);                      -- 1024         (POW 同义)
SELECT POW(2, 10);                        -- 1024
SELECT SQRT(144);                         -- 12.0
SELECT EXP(1);                            -- 2.718...
SELECT LN(2.718281828);                   -- ≈ 1.0
SELECT LOG(100);                          -- 2.0          (以 e 为底)
SELECT LOG(2, 1024);                      -- 10           (自定义底数)
SELECT LOG10(1000);                       -- 3.0

SELECT SIGN(-42);                         -- -1
SELECT IEEE_DIVIDE(10, 3);               -- 3.333...     (安全除法，不报错)
SELECT SAFE_DIVIDE(10, 0);               -- NULL          (安全除法)

-- ============================================================
-- 随机数
-- ============================================================
SELECT RAND();                            -- 0.0 到 1.0

-- ============================================================
-- 三角函数
-- ============================================================
SELECT SIN(0);                            -- 0
SELECT COS(0);                            -- 1
SELECT TAN(0);                            -- 0
SELECT ASIN(1);                           -- π/2
SELECT ACOS(1);                           -- 0
SELECT ATAN(1);                           -- π/4
SELECT ATAN2(1, 1);                       -- π/4
SELECT SINH(1); SELECT COSH(1); SELECT TANH(1);

-- GREATEST / LEAST
SELECT GREATEST(1, 5, 3);                -- 5
SELECT LEAST(1, 5, 3);                   -- 1

-- 位运算
SELECT 5 & 3;                             -- 1
SELECT 5 | 3;                             -- 7
SELECT 5 ^ 3;                             -- 6
SELECT ~5;                                -- -6
SELECT 1 << 4;                            -- 16
SELECT 16 >> 2;                           -- 4
SELECT BIT_COUNT(7);                      -- 3

-- 其他
SELECT IS_NAN(CAST('NaN' AS FLOAT64));   -- TRUE
SELECT IS_INF(1.0/0.0);                  -- TRUE
SELECT SAFE_NEGATE(-42);                  -- 42
SELECT RANGE_BUCKET(35, [0, 10, 20, 30, 40]); -- 4

-- 注意：BigQuery LOG(x) 以 e 为底
-- 注意：SAFE_DIVIDE, SAFE_NEGATE 等安全函数不报错，返回 NULL
-- 注意：IEEE_DIVIDE 遵循 IEEE 754（除以零返回 Inf）
-- 限制：无 PI() 函数（使用 ACOS(-1)）
