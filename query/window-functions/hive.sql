-- Hive: 窗口函数 (0.11+, 大数据窗口函数先驱)
--
-- 参考资料:
--   [1] Apache Hive - Windowing Functions
--       https://cwiki.apache.org/confluence/display/Hive/LanguageManual+WindowingAndAnalytics
--   [2] Apache Hive Language Manual - SELECT
--       https://cwiki.apache.org/confluence/display/Hive/LanguageManual+Select

-- ============================================================
-- 1. 排名函数
-- ============================================================
SELECT username, age,
    ROW_NUMBER() OVER (ORDER BY age) AS rn,
    RANK()       OVER (ORDER BY age) AS rnk,
    DENSE_RANK() OVER (ORDER BY age) AS dense_rnk
FROM users;

-- 分区内排名
SELECT username, city, age,
    ROW_NUMBER() OVER (PARTITION BY city ORDER BY age DESC) AS city_rank
FROM users;

-- ROW_NUMBER 去重（Hive 最常用的窗口函数模式）
SELECT * FROM (
    SELECT *, ROW_NUMBER() OVER (PARTITION BY city ORDER BY created_at DESC) AS rn
    FROM users
) t WHERE t.rn = 1;

-- 设计历史: Hive 是大数据引擎中最早支持窗口函数的之一 (0.11, 2013)
-- 这对整个大数据生态影响深远: Spark SQL、Impala、Presto 都跟进支持了窗口函数

-- ============================================================
-- 2. 聚合窗口函数
-- ============================================================
SELECT username, age,
    SUM(age)   OVER () AS total_age,
    AVG(age)   OVER () AS avg_age,
    COUNT(*)   OVER () AS total_count,
    MIN(age)   OVER (PARTITION BY city) AS city_min_age,
    MAX(age)   OVER (PARTITION BY city) AS city_max_age
FROM users;

-- ============================================================
-- 3. 偏移函数: LAG / LEAD / FIRST_VALUE / LAST_VALUE
-- ============================================================
SELECT username, age,
    LAG(age, 1)  OVER (ORDER BY id) AS prev_age,
    LEAD(age, 1) OVER (ORDER BY id) AS next_age,
    FIRST_VALUE(username) OVER (PARTITION BY city ORDER BY age) AS youngest,
    LAST_VALUE(username) OVER (PARTITION BY city ORDER BY age
        ROWS BETWEEN UNBOUNDED PRECEDING AND UNBOUNDED FOLLOWING) AS oldest
FROM users;

-- LAST_VALUE 的陷阱:
-- 默认窗口帧是 ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW
-- 这意味着 LAST_VALUE 默认返回当前行（不是分区的最后一行!）
-- 必须显式指定 ROWS BETWEEN UNBOUNDED PRECEDING AND UNBOUNDED FOLLOWING

-- NTH_VALUE (2.1+)
SELECT username, age,
    NTH_VALUE(username, 2) OVER (ORDER BY age) AS second_youngest
FROM users;

-- ============================================================
-- 4. 分布函数
-- ============================================================
SELECT username, age,
    NTILE(4)       OVER (ORDER BY age) AS quartile,
    PERCENT_RANK() OVER (ORDER BY age) AS pct_rank,
    CUME_DIST()    OVER (ORDER BY age) AS cume_dist
FROM users;

-- ============================================================
-- 5. 窗口帧 (Frame)
-- ============================================================
-- ROWS 帧（行级别）
SELECT username, age,
    SUM(age) OVER (ORDER BY id ROWS BETWEEN 2 PRECEDING AND CURRENT ROW) AS rolling_sum,
    AVG(age) OVER (ORDER BY id ROWS BETWEEN 1 PRECEDING AND 1 FOLLOWING) AS moving_avg
FROM users;

-- RANGE 帧（值范围，2.1+）
SELECT username, age,
    COUNT(*) OVER (ORDER BY age RANGE BETWEEN 5 PRECEDING AND 5 FOLLOWING) AS age_range_count
FROM users;

-- ROWS vs RANGE:
-- ROWS BETWEEN 2 PRECEDING → 前 2 行（精确行数）
-- RANGE BETWEEN 5 PRECEDING → 值在 [当前值-5, 当前值] 范围内的所有行

-- ============================================================
-- 6. 窗口函数在 Hive 的执行模型
-- ============================================================
-- PARTITION BY 的执行:
-- 1. 数据按 PARTITION BY 键 Shuffle（与 DISTRIBUTE BY 相同）
-- 2. 每个 Reducer 处理一个分区
-- 3. 分区内按 ORDER BY 排序后计算窗口函数
--
-- 性能要点:
-- 1. PARTITION BY 避免了全局排序（比 ORDER BY 独占单个 Reducer 高效）
-- 2. 多个窗口函数如果使用相同的 PARTITION BY + ORDER BY，可以共享排序
-- 3. 大分区可能导致 OOM（单个分区的所有数据必须在一个 Reducer 中）

-- ============================================================
-- 7. 已知限制
-- ============================================================
-- 1. 不支持命名窗口（WINDOW 子句）:
--    不能 WINDOW w AS (PARTITION BY city ORDER BY age) ... OVER w
-- 2. 不支持 GROUPS 帧模式: 只有 ROWS 和 RANGE
-- 3. 不支持 FILTER 子句: SUM(age) FILTER (WHERE active) 不可用
-- 4. 不支持 QUALIFY 子句: 需要用子查询包装后过滤
-- 5. 不支持 EXCLUDE 子句: ROWS BETWEEN ... EXCLUDE CURRENT ROW 不可用

-- ============================================================
-- 8. 跨引擎对比: 窗口函数能力
-- ============================================================
-- 引擎          窗口函数  ROWS  RANGE  GROUPS  命名窗口  QUALIFY  FILTER
-- MySQL(8.0+)   支持      支持  支持   不支持  支持      不支持   不支持
-- PostgreSQL    支持      支持  支持   支持    支持      不支持   支持(9.4+)
-- Hive(0.11+)   支持      支持  2.1+   不支持  不支持    不支持   不支持
-- Spark SQL     支持      支持  支持   不支持  不支持    不支持   不支持
-- BigQuery      支持      支持  支持   不支持  支持      QUALIFY  不支持
-- Trino         支持      支持  支持   不支持  不支持    不支持   不支持
-- ClickHouse    支持      支持  支持   不支持  不支持    不支持   不支持

-- ============================================================
-- 9. 对引擎开发者的启示
-- ============================================================
-- 1. 窗口函数是分析引擎的核心能力:
--    Hive 0.11 引入窗口函数后，大数据 SQL 的表达能力大幅提升
-- 2. LAST_VALUE 的默认帧是常见陷阱:
--    考虑让 LAST_VALUE 的默认帧为 UNBOUNDED FOLLOWING（更符合用户直觉）
-- 3. QUALIFY 应该被支持: 避免了窗口函数 + 子查询包装的冗长写法
-- 4. 命名窗口提升可读性: 多个窗口函数复用同一窗口定义时很有用
-- 5. 窗口函数的分布式执行: PARTITION BY 决定了 Shuffle，
--    优化器应该尽量合并使用相同 PARTITION BY 的窗口函数
