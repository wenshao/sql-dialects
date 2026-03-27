-- SQLite: 条件函数
--
-- 参考资料:
--   [1] SQLite Documentation - CASE Expression
--       https://www.sqlite.org/lang_expr.html#case
--   [2] SQLite Documentation - Core Functions
--       https://www.sqlite.org/lang_corefunc.html

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
        ELSE 'unknown'
    END AS status_name
FROM users;

-- COALESCE
SELECT COALESCE(phone, email, 'unknown') FROM users;

-- NULLIF
SELECT NULLIF(age, 0) FROM users;

-- IIF（3.32.0+，类似 IF）
SELECT username, IIF(age >= 18, 'adult', 'minor') AS category FROM users;

-- IFNULL（两参数 NULL 替换，等同于两参数的 COALESCE）
SELECT IFNULL(phone, 'N/A') FROM users;

-- MAX / MIN 也可以用于两个值比较（非聚合用法）
SELECT MAX(0, age) FROM users;                           -- 保证非负
SELECT MIN(100, age) FROM users;                         -- 最大 100

-- 类型转换
SELECT CAST('123' AS INTEGER);
SELECT CAST('2024-01-15' AS TEXT);
-- 注意：SQLite 的 CAST 受限于 5 种存储类型

-- typeof（返回存储类型）
SELECT typeof(123);                                      -- 'integer'
SELECT typeof(1.5);                                      -- 'real'
SELECT typeof('hello');                                  -- 'text'
SELECT typeof(NULL);                                     -- 'null'
SELECT typeof(X'0102');                                  -- 'blob'

-- 注意：没有 GREATEST / LEAST 函数
-- 注意：没有 IF() 函数（用 IIF 或 CASE 代替）
