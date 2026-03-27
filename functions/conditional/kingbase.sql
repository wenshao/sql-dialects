-- KingbaseES (人大金仓): 条件函数
-- PostgreSQL compatible syntax.
--
-- 参考资料:
--   [1] KingbaseES SQL Reference
--       https://help.kingbase.com.cn/v8/index.html
--   [2] KingbaseES Documentation
--       https://help.kingbase.com.cn/v8/index.html

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

-- GREATEST / LEAST
SELECT GREATEST(1, 3, 2);                               -- 3
SELECT LEAST(1, 3, 2);                                  -- 1

-- 类型转换
SELECT CAST('123' AS INTEGER);
SELECT '123'::INTEGER;
SELECT '2024-01-15'::DATE;
SELECT CAST('true' AS BOOLEAN);

-- DISTINCT FROM（NULL 安全比较）
SELECT * FROM users WHERE phone IS DISTINCT FROM 'unknown';
SELECT * FROM users WHERE phone IS NOT DISTINCT FROM NULL;

-- 布尔条件表达式
SELECT username, (age >= 18) AS is_adult FROM users;

-- Oracle 兼容模式下的函数
-- NVL(phone, 'N/A')
-- NVL2(phone, phone, 'N/A')
-- DECODE(status, 0, 'inactive', 1, 'active', 'unknown')

-- 注意事项：
-- 条件函数与 PostgreSQL 完全兼容
-- Oracle 兼容模式下支持 NVL、NVL2、DECODE
-- :: 类型转换语法可用
