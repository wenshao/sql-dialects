-- Materialize: 条件函数

-- Materialize 兼容 PostgreSQL 条件函数

-- CASE WHEN
SELECT username,
    CASE WHEN age < 18 THEN 'minor' WHEN age < 65 THEN 'adult' ELSE 'senior' END
FROM users;

-- 简单 CASE
SELECT username,
    CASE status WHEN 0 THEN 'inactive' WHEN 1 THEN 'active' ELSE 'unknown' END
FROM users;

-- COALESCE
SELECT COALESCE(phone, email, 'unknown') FROM users;

-- NULLIF
SELECT NULLIF(age, 0) FROM users;

-- GREATEST / LEAST
SELECT GREATEST(score1, score2, score3) FROM results;
SELECT LEAST(score1, score2, score3) FROM results;

-- 类型转换
SELECT CAST('123' AS INTEGER);
SELECT '123'::INT;
SELECT CAST(age AS TEXT) FROM users;

-- 条件聚合
SELECT COUNT(*) FILTER (WHERE age > 30) AS over_30
FROM users;

-- BOOL 表达式
SELECT username, age > 18 AS is_adult FROM users;

-- 注意：兼容 PostgreSQL 的条件函数
-- 注意：支持 FILTER 子句
-- 注意：支持 :: 类型转换
