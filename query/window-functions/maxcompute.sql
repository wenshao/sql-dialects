-- MaxCompute (ODPS): 窗口函数
--
-- 参考资料:
--   [1] MaxCompute SQL - Window Functions
--       https://help.aliyun.com/zh/maxcompute/user-guide/window-functions
--   [2] MaxCompute Built-in Functions
--       https://help.aliyun.com/zh/maxcompute/user-guide/built-in-functions-overview

-- ============================================================
-- 1. 排名函数
-- ============================================================

SELECT username, age,
    ROW_NUMBER() OVER (ORDER BY age) AS rn,          -- 1,2,3,4（无并列）
    RANK()       OVER (ORDER BY age) AS rnk,         -- 1,2,2,4（有并列，跳号）
    DENSE_RANK() OVER (ORDER BY age) AS dense_rnk    -- 1,2,2,3（有并列，不跳号）
FROM users;

-- 分区排名（最常用的模式: 分组取 Top-N）
SELECT username, city, age,
    ROW_NUMBER() OVER (PARTITION BY city ORDER BY age DESC) AS city_rank
FROM users;

-- NTILE: 等频分桶
SELECT username, age,
    NTILE(4) OVER (ORDER BY age) AS quartile         -- 分为 4 组
FROM users;

-- PERCENT_RANK / CUME_DIST
SELECT username, age,
    PERCENT_RANK() OVER (ORDER BY age) AS pct_rank,  -- (rank-1) / (total-1)
    CUME_DIST()    OVER (ORDER BY age) AS cume_dist   -- count(<=current) / total
FROM users;

-- ============================================================
-- 2. 聚合窗口函数
-- ============================================================

SELECT username, age,
    SUM(age)   OVER () AS total_age,
    AVG(age)   OVER () AS avg_age,
    COUNT(*)   OVER () AS total_count,
    MIN(age)   OVER (PARTITION BY city) AS city_min,
    MAX(age)   OVER (PARTITION BY city) AS city_max
FROM users;

-- ============================================================
-- 3. 偏移函数
-- ============================================================

SELECT username, age,
    LAG(age, 1)  OVER (ORDER BY id) AS prev_age,     -- 上一行
    LEAD(age, 1) OVER (ORDER BY id) AS next_age,     -- 下一行
    LAG(age, 1, 0) OVER (ORDER BY id) AS prev_or_0,  -- 带默认值
    FIRST_VALUE(username) OVER (
        PARTITION BY city ORDER BY age
    ) AS youngest_in_city,
    LAST_VALUE(username) OVER (
        PARTITION BY city ORDER BY age
        ROWS BETWEEN UNBOUNDED PRECEDING AND UNBOUNDED FOLLOWING
    ) AS oldest_in_city
FROM users;

-- NTH_VALUE（2.0+）
SELECT username, age,
    NTH_VALUE(username, 2) OVER (
        PARTITION BY city ORDER BY age
        ROWS BETWEEN UNBOUNDED PRECEDING AND UNBOUNDED FOLLOWING
    ) AS second_youngest
FROM users;

-- 设计注意: LAST_VALUE 陷阱
--   默认帧是 ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW
--   所以 LAST_VALUE 默认只看到"当前行"→ 总是返回当前行的值
--   必须显式指定: ROWS BETWEEN UNBOUNDED PRECEDING AND UNBOUNDED FOLLOWING

-- ============================================================
-- 4. 帧子句（Frame Clause）
-- ============================================================

-- ROWS 帧: 按物理行偏移
SELECT username, age,
    SUM(age) OVER (ORDER BY id
        ROWS BETWEEN 2 PRECEDING AND CURRENT ROW) AS rolling_sum_3,
    AVG(age) OVER (ORDER BY id
        ROWS BETWEEN 1 PRECEDING AND 1 FOLLOWING) AS moving_avg_3
FROM users;

-- RANGE 帧: 按值范围（部分版本支持）
-- SELECT username, age,
--     SUM(age) OVER (ORDER BY age
--         RANGE BETWEEN 5 PRECEDING AND 5 FOLLOWING) AS age_range_sum
-- FROM users;

-- 帧简写:
--   ROWS UNBOUNDED PRECEDING = ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW
--   ROWS n PRECEDING = ROWS BETWEEN n PRECEDING AND CURRENT ROW

-- 设计分析: MaxCompute 窗口帧的限制
--   支持: ROWS 帧（物理行偏移）
--   部分支持: RANGE 帧（按值范围，版本相关）
--   不支持: GROUPS 帧（按分组偏移，SQL:2011 标准）
--   对比:
--     PostgreSQL: ROWS/RANGE/GROUPS 全支持
--     MySQL 8.0:  ROWS/RANGE 支持
--     BigQuery:   ROWS/RANGE 支持
--     Snowflake:  ROWS 支持，RANGE 部分支持
--     Hive:       ROWS/RANGE 支持（MaxCompute 继承）

-- ============================================================
-- 5. 窗口函数去重 —— MaxCompute 最常用的模式
-- ============================================================

-- ROW_NUMBER 去重（保留每组最新的一行）
SELECT * FROM (
    SELECT *, ROW_NUMBER() OVER (
        PARTITION BY email ORDER BY created_at DESC
    ) AS rn
    FROM users
) t WHERE rn = 1;

-- 为什么这是 MaxCompute 最常用的模式?
--   普通表不支持 UNIQUE 约束 → 数据可能有重复
--   普通表不支持 DELETE → 不能直接删除重复行
--   ROW_NUMBER + INSERT OVERWRITE = 去重并持久化结果
INSERT OVERWRITE TABLE users_clean
SELECT id, username, email, age FROM (
    SELECT *, ROW_NUMBER() OVER (PARTITION BY email ORDER BY created_at DESC) AS rn
    FROM users
) t WHERE rn = 1;

-- ============================================================
-- 6. 不支持的窗口函数特性
-- ============================================================

-- 不支持 QUALIFY（BigQuery/Snowflake 独有的窗口过滤语法）
-- BigQuery: SELECT ... FROM ... QUALIFY ROW_NUMBER() OVER (...) = 1
-- MaxCompute: 需要子查询包装（见上面的去重模式）

-- 不支持命名窗口（WINDOW 子句）
-- 标准 SQL: SELECT ..., SUM(x) OVER w FROM t WINDOW w AS (ORDER BY id)
-- MaxCompute: 需要重复写 OVER 子句

-- 不支持 FILTER 子句
-- 标准 SQL: COUNT(*) FILTER (WHERE status = 'active') OVER ()
-- MaxCompute: 用 CASE WHEN 替代
SELECT SUM(CASE WHEN status = 'active' THEN 1 ELSE 0 END) OVER () AS active_count
FROM users;

-- 不支持 IGNORE NULLS
-- 标准 SQL: FIRST_VALUE(col IGNORE NULLS) OVER (ORDER BY id)
-- MaxCompute: 需要额外逻辑处理 NULL（见 scenarios/date-series-fill）

-- ============================================================
-- 7. 分布式执行机制
-- ============================================================

-- MaxCompute 窗口函数的伏羲调度:
--   PARTITION BY: 数据按 PARTITION BY 列做 Hash Shuffle 到不同 Reducer
--   ORDER BY: 每个 Reducer 内部排序
--   窗口计算: 在排序后的数据上流式计算（内存效率高）
--
--   无 PARTITION BY 的窗口: 所有数据发送到一个 Reducer → 性能瓶颈
--   例: SUM(age) OVER (ORDER BY id) 需要全局排序 → 单节点处理
--   最佳实践: 尽量使用 PARTITION BY 分散负载

-- DISTRIBUTE BY / SORT BY: MaxCompute/Hive 特有的分发排序语法
--   等价于窗口函数中的 PARTITION BY / ORDER BY
--   直接控制 Shuffle 和排序行为（更底层的操作）

-- ============================================================
-- 8. 横向对比: 窗口函数能力
-- ============================================================

-- 基本窗口函数:
--   MaxCompute: 完整支持（ROW_NUMBER/RANK/DENSE_RANK/NTILE 等）
--   Hive: 完整支持（MaxCompute 继承）
--   所有现代引擎均完整支持

-- QUALIFY:
--   MaxCompute: 不支持    | BigQuery: 支持  | Snowflake: 支持
--   PostgreSQL: 不支持    | Databricks: 支持

-- 命名窗口（WINDOW 子句）:
--   MaxCompute: 不支持    | PostgreSQL: 支持 | MySQL 8.0: 支持
--   BigQuery:   不支持    | Snowflake: 不支持

-- GROUPS 帧:
--   MaxCompute: 不支持    | PostgreSQL: 支持
--   其他大多数引擎: 不支持

-- ============================================================
-- 9. 对引擎开发者的启示
-- ============================================================

-- 1. 窗口函数是 OLAP 引擎的核心 — 必须完整支持
-- 2. QUALIFY 语法极大简化了窗口过滤，值得加入（BigQuery/Snowflake 已验证）
-- 3. 无 PARTITION BY 的窗口导致单节点瓶颈 — 应该有 WARNING 提示
-- 4. ROWS 帧比 RANGE 帧更常用且实现更简单 — 优先支持
-- 5. 窗口函数去重（ROW_NUMBER + WHERE rn=1）是用户最频繁的模式
-- 6. HBO 可以利用窗口函数的 PARTITION BY 优化 Shuffle 策略
