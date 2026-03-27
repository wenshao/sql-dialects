-- Materialize: 聚合函数

-- Materialize 兼容 PostgreSQL 聚合函数

-- 基本聚合
SELECT COUNT(*), COUNT(DISTINCT city), SUM(age),
       AVG(age), MIN(age), MAX(age)
FROM users;

-- GROUP BY
SELECT city, COUNT(*), AVG(age)
FROM users GROUP BY city;

-- HAVING
SELECT city, COUNT(*) AS cnt
FROM users GROUP BY city HAVING COUNT(*) > 10;

-- 字符串聚合
SELECT STRING_AGG(username, ', ' ORDER BY username) FROM users;

-- JSON 聚合
SELECT jsonb_agg(username) FROM users;
SELECT jsonb_object_agg(id, username) FROM users;

-- 数组聚合
SELECT ARRAY_AGG(username ORDER BY id) FROM users;

-- 统计函数
SELECT STDDEV(age), VARIANCE(age) FROM users;

-- BOOL_AND / BOOL_OR
SELECT BOOL_AND(active), BOOL_OR(verified) FROM users;

-- FILTER
SELECT COUNT(*) FILTER (WHERE age > 30) AS over_30,
       COUNT(*) FILTER (WHERE age <= 30) AS under_30
FROM users;

-- ============================================================
-- 物化视图中的聚合（增量维护）
-- ============================================================

CREATE MATERIALIZED VIEW city_stats AS
SELECT city, COUNT(*) AS cnt, AVG(age) AS avg_age
FROM users
GROUP BY city;

-- 聚合结果自动随源数据更新

-- 注意：兼容 PostgreSQL 的聚合函数
-- 注意：物化视图中的聚合会增量维护
-- 注意：支持 FILTER 子句
-- 注意：不支持 GROUPING SETS / ROLLUP / CUBE
