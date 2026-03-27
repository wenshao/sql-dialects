-- MariaDB: Math Functions
--
-- 参考资料:
--   [1] MariaDB Knowledge Base - Mathematical Functions
--       https://mariadb.com/kb/en/mathematical-functions/

-- ============================================================
-- 基本数学函数
-- ============================================================
SELECT ABS(-42);                          -- 42
SELECT CEIL(4.3);                         -- 5
SELECT CEILING(4.3);                      -- 5
SELECT FLOOR(4.7);                        -- 4
SELECT ROUND(3.14159, 2);                 -- 3.14
SELECT TRUNCATE(3.14159, 2);              -- 3.14

-- 取模
SELECT MOD(17, 5);                        -- 2
SELECT 17 % 5;                            -- 2
SELECT 17 MOD 5;                          -- 2

-- 幂、根、对数
SELECT POWER(2, 10);                      -- 1024
SELECT POW(2, 10);                        -- 1024
SELECT SQRT(144);                         -- 12
SELECT EXP(1);                            -- 2.718...
SELECT LN(EXP(1));                        -- 1.0
SELECT LOG(EXP(1));                       -- 1.0          (自然对数)
SELECT LOG(2, 1024);                      -- 10
SELECT LOG2(1024);                        -- 10
SELECT LOG10(1000);                       -- 3

SELECT SIGN(-42);                         -- -1
SELECT PI();                              -- 3.141593
SELECT RAND();                            -- 0.0 到 1.0
SELECT RAND(42);                          -- 可重复随机数

-- 三角函数
SELECT SIN(0); SELECT COS(0); SELECT TAN(0);
SELECT ASIN(1); SELECT ACOS(1); SELECT ATAN(1);
SELECT ATAN2(1, 1);
SELECT COT(1);                            -- 余切
SELECT DEGREES(PI());                     -- 180
SELECT RADIANS(180);                      -- π

-- GREATEST / LEAST
SELECT GREATEST(1, 5, 3);                -- 5
SELECT LEAST(1, 5, 3);                   -- 1

-- 位运算
SELECT 5 & 3; SELECT 5 | 3; SELECT 5 ^ 3; SELECT ~5;
SELECT 1 << 4; SELECT 16 >> 2;
SELECT BIT_COUNT(7);                      -- 3

-- 其他
SELECT CONV(255, 10, 16);                -- 'FF'
SELECT CRC32('hello');                    -- 907060870

-- 注意：与 MySQL 数学函数高度兼容
-- 注意：LOG(x) 以 e 为底
-- 注意：^ 是 XOR（幂用 POW/POWER）
