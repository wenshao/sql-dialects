-- Apache Impala: 条件函数
--
-- 参考资料:
--   [1] Impala SQL Reference
--       https://impala.apache.org/docs/build/html/topics/impala_langref.html
--   [2] Impala Built-in Functions
--       https://impala.apache.org/docs/build/html/topics/impala_functions.html

-- CASE WHEN（SQL 标准）
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

-- IF（Impala 原生支持）
SELECT username, IF(age >= 18, 'adult', 'minor') AS category FROM users;

-- 嵌套 IF
SELECT username,
    IF(age < 18, 'minor', IF(age < 65, 'adult', 'senior')) AS category
FROM users;

-- IFNULL（NULL 替换）
SELECT IFNULL(phone, 'N/A') FROM users;

-- COALESCE（返回第一个非 NULL 值）
SELECT COALESCE(phone, email, 'unknown') FROM users;

-- NULLIF（两值相等返回 NULL）
SELECT NULLIF(age, 0) FROM users;

-- NVL（等同于 IFNULL，Hive 兼容）
SELECT NVL(phone, 'N/A') FROM users;

-- NVL2
SELECT NVL2(phone, 'has phone', 'no phone') FROM users;

-- ISNULL（判断是否为 NULL，返回 BOOLEAN）
SELECT ISNULL(phone) FROM users;

-- ISNOTFALSE / ISNOTTRUE / ISTRUE / ISFALSE
SELECT username FROM users WHERE ISTRUE(active);
SELECT username FROM users WHERE ISFALSE(active);

-- 类型转换
SELECT CAST('123' AS INT);
SELECT CAST('2024-01-15' AS TIMESTAMP);
SELECT TYPEOF(123);                                      -- 返回类型名

-- GREATEST / LEAST
SELECT GREATEST(1, 3, 2);                               -- 3
SELECT LEAST(1, 3, 2);                                  -- 1

-- NULL 判断
SELECT username FROM users WHERE age IS NULL;
SELECT username FROM users WHERE age IS NOT NULL;

-- DECODE（Oracle 风格条件）
SELECT DECODE(status, 0, 'inactive', 1, 'active', 'unknown') FROM users;
-- 等价于 CASE status WHEN 0 THEN ... WHEN 1 THEN ... ELSE ... END

-- 注意：Impala 支持 IF / IFNULL / NVL / NVL2 / DECODE
-- 注意：TYPEOF 返回值的类型名（Impala 特有）
-- 注意：不支持 IS DISTINCT FROM
