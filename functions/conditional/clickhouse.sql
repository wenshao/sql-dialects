-- ClickHouse: 条件函数
--
-- 参考资料:
--   [1] ClickHouse - Conditional Functions
--       https://clickhouse.com/docs/en/sql-reference/functions/conditional-functions
--   [2] ClickHouse SQL Reference - Functions
--       https://clickhouse.com/docs/en/sql-reference/functions

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

-- if 函数（三元条件，ClickHouse 推荐）
SELECT if(age >= 18, 'adult', 'minor') FROM users;
SELECT if(amount > 0, amount, 0) FROM orders;

-- multiIf（多条件，替代 CASE WHEN）
SELECT multiIf(
    age < 18, 'minor',
    age < 65, 'adult',
    'senior'
) AS category FROM users;

-- COALESCE
SELECT coalesce(phone, email, 'unknown') FROM users;

-- NULLIF
SELECT nullIf(age, 0) FROM users;                         -- 注意：驼峰命名

-- ifNull / nullIf
SELECT ifNull(phone, 'no phone') FROM users;              -- NULL 替换
SELECT nullIf(age, 0) FROM users;                         -- 等于 0 时返回 NULL

-- assumeNotNull（去除 Nullable 包装）
SELECT assumeNotNull(nullable_col) FROM t;                -- 假设非 NULL
SELECT toNullable(123);                                   -- 添加 Nullable 包装

-- greatest / least
SELECT greatest(1, 3, 2);                                 -- 3
SELECT least(1, 3, 2);                                    -- 1

-- 类型转换
SELECT CAST('123' AS Int32);
SELECT toInt32('123');                                    -- ClickHouse 风格
SELECT toFloat64('3.14');
SELECT toString(123);
SELECT toDate('2024-01-15');
SELECT toDateTime('2024-01-15 10:30:00');

-- 安全转换（OrNull / OrZero / OrDefault 后缀）
SELECT toInt32OrNull('abc');                               -- NULL
SELECT toInt32OrZero('abc');                               -- 0
SELECT toInt32OrDefault('abc', -1);                        -- -1
SELECT toDateOrNull('invalid');                            -- NULL
SELECT toDateOrZero('invalid');                            -- 1970-01-01
SELECT toFloat64OrNull('abc');                             -- NULL

-- 类型判断
SELECT toTypeName(123);                                   -- 'Int32'
SELECT toTypeName('hello');                               -- 'String'
SELECT toTypeName(now());                                 -- 'DateTime'

-- IS 判断
SELECT * FROM users WHERE phone IS NULL;
SELECT * FROM users WHERE phone IS NOT NULL;
SELECT isNull(phone) FROM users;                          -- 函数形式
SELECT isNotNull(phone) FROM users;                       -- 函数形式

-- IN
SELECT * FROM users WHERE city IN ('Beijing', 'Shanghai');
SELECT * FROM users WHERE city GLOBAL IN (SELECT city FROM other);  -- 分布式 IN

-- BETWEEN
SELECT * FROM orders WHERE amount BETWEEN 100 AND 1000;

-- 三元运算符
SELECT age >= 18 ? 'adult' : 'minor' FROM users;          -- C 风格三元运算符

-- 注意：函数名驼峰命名（if, multiIf, ifNull, nullIf 等）
-- 注意：OrNull / OrZero / OrDefault 后缀是安全转换的核心模式
-- 注意：支持 C 风格三元运算符 ? :
-- 注意：GLOBAL IN 用于分布式查询场景
-- 注意：Nullable 类型需要显式声明，影响条件函数行为
