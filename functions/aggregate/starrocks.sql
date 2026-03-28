-- StarRocks: 聚合函数
--
-- 参考资料:
--   [1] StarRocks Documentation - Aggregate Functions
--       https://docs.starrocks.io/docs/sql-reference/sql-functions/

-- ============================================================
-- 1. 基本聚合 (与 Doris 完全兼容)
-- ============================================================
SELECT COUNT(*), COUNT(email), COUNT(DISTINCT city) FROM users;
SELECT SUM(amount), AVG(amount), MIN(amount), MAX(amount) FROM orders;

SELECT city, COUNT(*) AS cnt, AVG(age) AS avg_age
FROM users GROUP BY city HAVING cnt > 10;

-- ============================================================
-- 2. 多维聚合
-- ============================================================
SELECT city, status, COUNT(*)
FROM users GROUP BY GROUPING SETS ((city), (status), (city, status), ());

SELECT city, status, COUNT(*)
FROM users GROUP BY ROLLUP (city, status);

SELECT city, status, COUNT(*)
FROM users GROUP BY CUBE (city, status);

-- ============================================================
-- 3. 字符串聚合
-- ============================================================
SELECT GROUP_CONCAT(username ORDER BY username SEPARATOR ', ') FROM users;

-- ============================================================
-- 4. 近似聚合与精确去重
-- ============================================================
SELECT APPROX_COUNT_DISTINCT(user_id) FROM orders;
SELECT NDV(user_id) FROM orders;

-- BITMAP 精确去重
SELECT BITMAP_UNION_COUNT(TO_BITMAP(user_id)) FROM orders;

-- HLL 近似去重
SELECT HLL_UNION_AGG(HLL_HASH(user_id)) FROM orders;

-- ============================================================
-- 5. 百分位数
-- ============================================================
SELECT PERCENTILE_APPROX(amount, 0.5) FROM orders;
SELECT PERCENTILE_APPROX(amount, 0.95) FROM orders;

-- ============================================================
-- 6. 收集为数组
-- ============================================================
SELECT ARRAY_AGG(username) FROM users GROUP BY city;

-- ============================================================
-- 7. StarRocks vs Doris 聚合差异
-- ============================================================
-- 核心函数完全相同(同源)。
--
-- 差异:
--   StarRocks: ARRAY_AGG (更标准)
--   Doris:     COLLECT_LIST / COLLECT_SET (Hive 风格)
--
--   StarRocks: QUANTILE_STATE 不支持(用 PERCENTILE_APPROX)
--   Doris:     QUANTILE_STATE 聚合类型(Aggregate Key 模型)
--
-- 对引擎开发者的启示:
--   聚合函数的向量化实现是 OLAP 引擎性能的关键:
--     Batch Aggregation: 一次处理一个向量(1024 行)而非逐行
--     SIMD 加速: SUM/COUNT 可用 AVX2/AVX512 指令
--     Two-Phase Aggregation: 先本地聚合(Partial)，再全局聚合(Final)
