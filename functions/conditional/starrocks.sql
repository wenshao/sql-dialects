-- StarRocks: 条件函数
--
-- 参考资料:
--   [1] StarRocks - Condition Functions
--       https://docs.starrocks.io/docs/sql-reference/sql-functions/condition-functions/
--   [2] StarRocks SQL Functions
--       https://docs.starrocks.io/docs/sql-reference/sql-functions/

-- CASE WHEN
SELECT username,
    CASE
        WHEN age < 18 THEN 'minor'
        WHEN age < 65 THEN 'adult'
        ELSE 'senior'
    END AS category
FROM users;

-- 简单 CASE
SELECT username,
    CASE status
        WHEN 0 THEN 'inactive'
        WHEN 1 THEN 'active'
        WHEN 2 THEN 'deleted'
        ELSE 'unknown'
    END AS status_name
FROM users;

-- COALESCE
SELECT COALESCE(phone, email, 'unknown') FROM users;

-- NULLIF
SELECT NULLIF(age, 0) FROM users;

-- IF（三元条件函数，MySQL 兼容）
SELECT IF(age >= 18, 'adult', 'minor') FROM users;
SELECT IF(amount > 0, amount, 0) FROM orders;

-- IFNULL（MySQL 兼容）
SELECT IFNULL(phone, 'no phone') FROM users;

-- NVL（Oracle 兼容）
SELECT NVL(phone, 'no phone') FROM users;

-- GREATEST / LEAST
SELECT GREATEST(1, 3, 2);                                -- 3
SELECT LEAST(1, 3, 2);                                   -- 1

-- 类型转换
SELECT CAST('123' AS INT);
SELECT CAST(123 AS VARCHAR);
SELECT CAST('2024-01-15' AS DATE);
SELECT CAST('2024-01-15 10:30:00' AS DATETIME);
SELECT CAST('true' AS BOOLEAN);

-- 注意：没有 TRY_CAST / SAFE_CAST
-- 转换失败会报错

-- IS 判断
SELECT * FROM users WHERE phone IS NULL;
SELECT * FROM users WHERE phone IS NOT NULL;

-- IN
SELECT * FROM users WHERE city IN ('Beijing', 'Shanghai');
SELECT * FROM users WHERE city NOT IN ('Beijing', 'Shanghai');

-- BETWEEN
SELECT * FROM orders WHERE amount BETWEEN 100 AND 1000;

-- NULL 安全比较（<=>）
SELECT * FROM users WHERE phone <=> NULL;                 -- 等同 IS NULL
SELECT * FROM users WHERE phone <=> 'unknown';            -- NULL 安全等于

-- BITMAP 条件函数
SELECT BITMAP_CONTAINS(user_bitmap, 12345) FROM agg_table;  -- 位图包含判断
SELECT BITMAP_HAS_ANY(bitmap1, bitmap2) FROM t;             -- 位图交集判断

-- 注意：与 MySQL 条件函数高度兼容
-- 注意：IF/IFNULL 是 MySQL 风格
-- 注意：NVL 是 Oracle 风格
-- 注意：<=> 是 NULL 安全等于运算符（MySQL 兼容）
-- 注意：没有 DECODE 函数
-- 注意：没有 :: 转换语法
