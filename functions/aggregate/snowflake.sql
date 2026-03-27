-- Snowflake: 聚合函数
--
-- 参考资料:
--   [1] Snowflake SQL Reference - Aggregate Functions
--       https://docs.snowflake.com/en/sql-reference/functions-aggregation
--   [2] Snowflake SQL Reference - SELECT
--       https://docs.snowflake.com/en/sql-reference/sql/select

-- 基本聚合
SELECT COUNT(*) FROM users;
SELECT COUNT(DISTINCT city) FROM users;
SELECT SUM(amount) FROM orders;
SELECT AVG(amount) FROM orders;
SELECT MIN(amount) FROM orders;
SELECT MAX(amount) FROM orders;

-- GROUP BY
SELECT city, COUNT(*) AS cnt, AVG(age) AS avg_age
FROM users
GROUP BY city;

-- HAVING
SELECT city, COUNT(*) AS cnt
FROM users
GROUP BY city
HAVING COUNT(*) > 10;

-- GROUP BY ALL（自动推断分组列）
SELECT city, status, COUNT(*)
FROM users
GROUP BY ALL;

-- GROUPING SETS / ROLLUP / CUBE
SELECT city, status, COUNT(*)
FROM users
GROUP BY GROUPING SETS ((city), (status), ());

SELECT city, status, COUNT(*)
FROM users
GROUP BY ROLLUP (city, status);

SELECT city, status, COUNT(*)
FROM users
GROUP BY CUBE (city, status);

SELECT city, GROUPING(city) AS is_total, COUNT(*)
FROM users
GROUP BY ROLLUP (city);

-- 字符串聚合
SELECT LISTAGG(username, ', ') WITHIN GROUP (ORDER BY username) FROM users;
SELECT LISTAGG(DISTINCT city, ', ') FROM users;
SELECT ARRAY_TO_STRING(ARRAY_AGG(username), ', ') FROM users;

-- 数组聚合
SELECT ARRAY_AGG(username) WITHIN GROUP (ORDER BY username) FROM users;
SELECT ARRAY_AGG(DISTINCT city) FROM users;
SELECT ARRAY_UNIQUE_AGG(city) FROM users;                -- 去重数组聚合

-- VARIANT 聚合
SELECT OBJECT_AGG(key, value) FROM t;                    -- 构造 OBJECT

-- 统计函数
SELECT STDDEV(amount) FROM orders;                       -- 样本标准差
SELECT STDDEV_POP(amount) FROM orders;                   -- 总体标准差
SELECT STDDEV_SAMP(amount) FROM orders;                  -- 样本标准差
SELECT VARIANCE(amount) FROM orders;                     -- 样本方差
SELECT VAR_POP(amount) FROM orders;                      -- 总体方差
SELECT CORR(x, y) FROM data;                             -- 相关系数
SELECT COVAR_SAMP(x, y) FROM data;                       -- 样本协方差
SELECT COVAR_POP(x, y) FROM data;                        -- 总体协方差
SELECT REGR_SLOPE(y, x) FROM data;                       -- 线性回归斜率
SELECT KURTOSIS(amount) FROM orders;                     -- 峰度
SELECT SKEW(amount) FROM orders;                         -- 偏度

-- 近似聚合
SELECT APPROX_COUNT_DISTINCT(user_id) FROM events;       -- HyperLogLog 近似去重
SELECT APPROX_PERCENTILE(amount, 0.5) FROM orders;       -- 近似中位数
SELECT APPROX_TOP_K(city, 10) FROM users;                -- 近似 TOP K

-- 位聚合
SELECT BITAND_AGG(flags) FROM settings;
SELECT BITOR_AGG(flags) FROM settings;
SELECT BITXOR_AGG(flags) FROM settings;

-- 布尔聚合
SELECT BOOLAND_AGG(active) FROM users;                   -- 所有为 TRUE
SELECT BOOLOR_AGG(active) FROM users;                    -- 任一为 TRUE

-- 其他
SELECT ANY_VALUE(name) FROM users;                       -- 任意值
SELECT MEDIAN(amount) FROM orders;                       -- 中位数（精确）
SELECT MODE(city) FROM users;                            -- 众数
SELECT HASH_AGG(*) FROM users;                           -- 整表哈希

-- 条件聚合（使用 IFF / CASE）
SELECT
    COUNT(*) AS total,
    COUNT(IFF(age < 30, 1, NULL)) AS young,
    SUM(IFF(status = 'active', amount, 0)) AS active_amount
FROM users;

-- 注意：LISTAGG 是标准字符串聚合函数（SQL:2011）
-- 注意：MEDIAN / MODE 是 Snowflake 便捷函数
-- 注意：GROUP BY ALL 自动推断非聚合列
-- 注意：没有 FILTER 子句
