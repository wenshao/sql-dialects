-- Spark SQL: 聚合函数 (Aggregate Functions)
--
-- 参考资料:
--   [1] Spark SQL - Built-in Aggregate Functions
--       https://spark.apache.org/docs/latest/sql-ref-functions-builtin.html#aggregate-functions

-- ============================================================
-- 1. 基本聚合
-- ============================================================
SELECT COUNT(*) FROM users;
SELECT COUNT(DISTINCT city) FROM users;
SELECT SUM(amount) FROM orders;
SELECT AVG(amount) FROM orders;
SELECT MIN(amount), MAX(amount) FROM orders;

-- GROUP BY + HAVING
SELECT city, COUNT(*) AS cnt, AVG(age) AS avg_age
FROM users
GROUP BY city
HAVING COUNT(*) > 10;

-- ============================================================
-- 2. GROUPING SETS / ROLLUP / CUBE: 多维聚合
-- ============================================================

-- GROUPING SETS: 自定义分组组合
SELECT city, status, COUNT(*)
FROM users
GROUP BY GROUPING SETS ((city), (status), ());

-- ROLLUP: 层次化聚合（从细到粗）
SELECT city, status, COUNT(*)
FROM users
GROUP BY ROLLUP (city, status);

-- CUBE: 所有组合的聚合
SELECT city, status, COUNT(*)
FROM users
GROUP BY CUBE (city, status);

-- GROUPING() / GROUPING_ID(): 区分真实 NULL 和聚合产生的 NULL
SELECT city, GROUPING(city) AS is_total, COUNT(*)
FROM users
GROUP BY ROLLUP (city);

SELECT city, status, GROUPING_ID(city, status), COUNT(*)
FROM users
GROUP BY CUBE (city, status);

-- 设计分析:
--   Spark 的 GROUPING SETS 继承自 Hive，语义与 SQL 标准一致。
--   内部实现: Catalyst 将 ROLLUP/CUBE 展开为 GROUPING SETS，再通过 Expand 操作符
--   将每行复制为多行（每个分组组合一行），然后做标准 GROUP BY。
--   对比 MySQL: 8.0+ 支持 ROLLUP，不支持 CUBE 和 GROUPING SETS。
--   对比 PostgreSQL: 9.5+ 完整支持 GROUPING SETS/ROLLUP/CUBE。

-- ============================================================
-- 3. 集合聚合: Spark 的特色能力
-- ============================================================

-- COLLECT_LIST: 将列值聚合为数组（保留重复，保留顺序）
SELECT COLLECT_LIST(username) FROM users;

-- COLLECT_SET: 将列值聚合为集合（去重）
SELECT COLLECT_SET(city) FROM users;

-- 排序后聚合
SELECT SORT_ARRAY(COLLECT_LIST(username)) FROM users;

-- 字符串拼接聚合（替代 STRING_AGG / GROUP_CONCAT）
SELECT CONCAT_WS(', ', COLLECT_LIST(username)) FROM users;
SELECT CONCAT_WS(', ', SORT_ARRAY(COLLECT_LIST(username))) FROM users;

-- Map 聚合
SELECT MAP_FROM_ENTRIES(COLLECT_LIST(STRUCT(username, age))) FROM users;

-- ARRAY_AGG（Spark 3.3+，SQL 标准语法）
SELECT department, ARRAY_AGG(name) FROM employees GROUP BY department;

-- 设计分析:
--   COLLECT_LIST/COLLECT_SET 是 Spark 最独特的聚合函数——在传统数据库中没有直接等价物。
--   它们将关系数据聚合为复合类型（Array），实现了 SQL 和半结构化数据的桥梁。
--   注意: COLLECT_LIST 会将整个分组的数据收集到 Driver 端，大分组可能 OOM。
--
-- 对比:
--   MySQL:      GROUP_CONCAT(col SEPARATOR ',')
--   PostgreSQL: ARRAY_AGG(col), STRING_AGG(col, ',')
--   BigQuery:   ARRAY_AGG(col), STRING_AGG(col, ',')
--   ClickHouse: groupArray(col), groupUniqArray(col)

-- ============================================================
-- 4. 近似聚合: 大数据场景的性能优化
-- ============================================================

SELECT APPROX_COUNT_DISTINCT(city) FROM users;           -- HyperLogLog
SELECT PERCENTILE_APPROX(age, 0.5) FROM users;           -- 近似中位数
SELECT PERCENTILE_APPROX(age, ARRAY(0.25, 0.5, 0.75)) FROM users;  -- 多分位数

-- 精确百分位数
SELECT PERCENTILE(age, 0.5) FROM users;

-- 设计分析:
--   APPROX_COUNT_DISTINCT 使用 HyperLogLog 算法（精度 ~2%，内存 O(1)）
--   在亿级数据上，精确 COUNT DISTINCT 需要全量去重（O(n) 内存），
--   而 APPROX_COUNT_DISTINCT 只需 ~16KB 内存——性能差异可达 100 倍。
--   BigQuery 默认的 COUNT(DISTINCT col) 就是近似的（APPROX_COUNT_DISTINCT 的语义）。

-- ============================================================
-- 5. 统计函数
-- ============================================================
SELECT STDDEV(amount), STDDEV_POP(amount), STDDEV_SAMP(amount) FROM orders;
SELECT VARIANCE(amount), VAR_POP(amount), VAR_SAMP(amount) FROM orders;
SELECT CORR(x, y), COVAR_SAMP(x, y), COVAR_POP(x, y) FROM data;
SELECT REGR_SLOPE(y, x), REGR_INTERCEPT(y, x), REGR_R2(y, x) FROM data; -- 3.3+
SELECT KURTOSIS(age), SKEWNESS(age) FROM users;

-- ============================================================
-- 6. 条件聚合
-- ============================================================

-- IF / CASE 方式（全版本）
SELECT
    COUNT(*) AS total,
    COUNT(IF(age < 30, 1, NULL)) AS young,
    SUM(CASE WHEN status = 'completed' THEN amount ELSE 0 END) AS completed_total,
    COUNT_IF(age >= 30) AS senior                        -- Spark 3.0+
FROM users;

-- FILTER 子句（Spark 3.2+, SQL 标准语法）
SELECT
    COUNT(*) AS total,
    COUNT(*) FILTER (WHERE age < 30) AS young
FROM users;

-- 对比:
--   PostgreSQL: FILTER (WHERE ...) 从 9.4 开始支持——Spark 参照了这一标准语法
--   MySQL:      不支持 FILTER，只能用 IF/CASE
--   BigQuery:   COUNTIF() 函数 + 标准 FILTER 子句

-- ============================================================
-- 7. 布尔与位聚合
-- ============================================================
SELECT BOOL_AND(active), BOOL_OR(active) FROM users;     -- 3.0+
SELECT EVERY(active), SOME(active), ANY(active) FROM users; -- SQL 标准别名
SELECT BIT_AND(flags), BIT_OR(flags), BIT_XOR(flags) FROM settings; -- 3.0+

-- ============================================================
-- 8. FIRST / LAST / MIN_BY / MAX_BY
-- ============================================================
SELECT city, FIRST(username) FROM users GROUP BY city;    -- 非确定性
SELECT city, FIRST(username, true) FROM users GROUP BY city; -- 忽略 NULL
SELECT city, LAST(username) FROM users GROUP BY city;

-- MIN_BY / MAX_BY（Spark 3.3+）
SELECT MIN_BY(username, age) FROM users;                  -- 最年轻用户的 username
SELECT MAX_BY(username, age) FROM users;                  -- 最年长用户的 username

-- 对比:
--   PostgreSQL 13+: 也增加了 MIN_BY / MAX_BY（受 ClickHouse 启发的提案）
--   ClickHouse:     argMin(col, val) / argMax(col, val)

-- ============================================================
-- 9. 版本演进
-- ============================================================
-- Spark 2.0: 基本聚合, COLLECT_LIST/SET, GROUPING SETS
-- Spark 3.0: BOOL_AND/OR, BIT_AND/OR/XOR, COUNT_IF
-- Spark 3.2: FILTER 子句
-- Spark 3.3: MIN_BY/MAX_BY, REGR_SLOPE/INTERCEPT/R2, ARRAY_AGG
-- Spark 3.4: try_avg, try_sum
--
-- 限制:
--   FIRST/LAST 在 GROUP BY 中是非确定性的（无法指定 ORDER BY）
--   无 GROUP BY ALL（必须列出所有非聚合列）
--   COLLECT_LIST/COLLECT_SET 在大分组上可能 OOM
--   无 HISTOGRAM 聚合函数
--   FILTER 子句在窗口函数上不可用
