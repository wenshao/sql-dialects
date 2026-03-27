-- Apache Hive: 分页 (Pagination)
--
-- 参考资料:
--   [1] Apache Hive Language Manual - SELECT
--       https://cwiki.apache.org/confluence/display/Hive/LanguageManual+Select
--   [2] Apache Hive - Sort/Distribute/Cluster By
--       https://cwiki.apache.org/confluence/display/Hive/LanguageManual+SortBy
--   [3] Apache Hive Window Functions
--       https://cwiki.apache.org/confluence/display/Hive/LanguageManual+WindowingAndAnalytics

-- ============================================================
-- 1. LIMIT（所有版本）
-- ============================================================

-- 仅取前 N 行
SELECT * FROM users ORDER BY id LIMIT 10;

-- 注意: ORDER BY + LIMIT 可以利用 Top-K 优化
-- Hive 优化器会将全局排序（单个 Reducer）优化为 Top-K 算子
-- 只需维护一个大小为 K 的堆，避免全量排序

-- ============================================================
-- 2. LIMIT / OFFSET（Hive 2.0+）
-- ============================================================

-- 基本分页: 跳过前 20 行，取 10 行
SELECT * FROM users ORDER BY id LIMIT 10 OFFSET 20;

-- Hive 2.0 之前不支持 OFFSET 的替代方案:
--   方案一: 使用窗口函数 ROW_NUMBER（见第 4 节）
--   方案二: 使用子查询 + LIMIT 嵌套
--     SELECT * FROM (
--         SELECT * FROM users ORDER BY id LIMIT 30
--     ) t ORDER BY id DESC LIMIT 10;  -- 取后 10 行（需要反转）

-- ============================================================
-- 3. ORDER BY vs SORT BY vs DISTRIBUTE BY（Hive 特有）
-- ============================================================

-- ORDER BY（全局排序，所有数据汇聚到一个 Reducer）
SELECT * FROM users ORDER BY id LIMIT 10;
-- 问题: 大数据量下，单个 Reducer 是严重瓶颈
-- 建议: 始终配合 LIMIT 使用（触发 Top-K 优化）

-- SORT BY（局部排序，每个 Reducer 内部分别排序）
SELECT * FROM users SORT BY id LIMIT 10;
-- SORT BY + LIMIT: 每个 Reducer 取前 N，最终合并取全局前 N
-- 比 ORDER BY + LIMIT 高效: 利用多 Reducer 并行

-- DISTRIBUTE BY + SORT BY（分区内排序）
SELECT * FROM users DISTRIBUTE BY city SORT BY age DESC LIMIT 10;
-- 先按 city 分发到不同 Reducer，每个 Reducer 内按 age 排序
-- 等价于: MapReduce 的分区 + 排序

-- CLUSTER BY（等价于 DISTRIBUTE BY + SORT BY，但只能升序）
SELECT * FROM users CLUSTER BY id;
-- 注意: CLUSTER BY 不支持 ASC/DESC，只能升序

-- ============================================================
-- 4. 窗口函数辅助分页（Hive 0.11+）
-- ============================================================

-- ROW_NUMBER 分页
SELECT * FROM (
    SELECT *, ROW_NUMBER() OVER (ORDER BY id) AS rn
    FROM users
) t
WHERE t.rn BETWEEN 21 AND 30;

-- 分组后 Top-N
SELECT * FROM (
    SELECT *, ROW_NUMBER() OVER (PARTITION BY city ORDER BY age DESC) AS rn
    FROM users
) t WHERE rn <= 3;

-- RANK / DENSE_RANK 分页（包含并列排名）
SELECT * FROM (
    SELECT *, RANK() OVER (ORDER BY score DESC) AS rnk
    FROM users
) t WHERE rnk <= 10;
-- RANK:       并列排名后跳号（1, 2, 2, 4, 5...）
-- DENSE_RANK: 并列排名不跳号（1, 2, 2, 3, 4...）

-- ============================================================
-- 5. 键集分页（Keyset Pagination）
-- ============================================================

-- 第一页
SELECT * FROM users ORDER BY id LIMIT 10;

-- 后续页（已知上一页最后一条 id = 100）
SELECT * FROM users WHERE id > 100 ORDER BY id LIMIT 10;

-- 多列排序的键集分页（展开为 OR 条件）
SELECT * FROM users
WHERE created_at > '2025-01-01'
   OR (created_at = '2025-01-01' AND id > 100)
ORDER BY created_at, id
LIMIT 10;

-- ============================================================
-- 6. Hive 不支持的语法
-- ============================================================

-- 以下语法在 Hive 中不支持:
--   FETCH FIRST ... ROWS ONLY    -- 不支持 SQL 标准 FETCH 语法
--   TOP N                        -- 不支持 TOP 关键字
--   LIMIT offset, count          -- 不支持 MySQL 风格的简写
--   DECLARE CURSOR               -- 不支持服务端游标

-- ============================================================
-- 7. Hive 特有说明: 大数据场景下的分页
-- ============================================================

-- Hive 是离线批处理引擎，分页有特殊考量:
--
-- ORDER BY 的单 Reducer 问题:
--   ORDER BY 需要全局排序，所有数据发送到一个 Reducer
--   数据量 TB 级时，单个 Reducer 可能运行数小时
--   解决方案: SORT BY + LIMIT（利用多 Reducer 并行取 Top-K）
--
-- 分页性能建议:
--   小结果集（分区过滤后 < 100 万行）: LIMIT / OFFSET 可用
--   中等结果集（100 万 ~ 1 亿行）: 使用 SORT BY + LIMIT
--   大结果集（> 1 亿行）: 避免分页，改用分区过滤或数据导出
--
-- Tez/Spark 执行引擎的影响:
--   Tez:  减少中间落盘，ORDER BY + LIMIT 性能优于 MapReduce
--   Spark: 内存计算，排序速度更快，但大数据量仍需注意 OOM

-- ============================================================
-- 8. 版本演进
-- ============================================================
-- Hive 0.x:   LIMIT（仅取前 N 行，无 OFFSET）
-- Hive 0.11:  窗口函数（ROW_NUMBER, RANK, DENSE_RANK）
-- Hive 2.0:   LIMIT + OFFSET 支持
-- Hive 3.0:   Materialized View 可用于加速分页查询

-- ============================================================
-- 9. 横向对比: 分页语法差异
-- ============================================================

-- 语法对比:
--   Hive:        LIMIT n OFFSET m（不支持 FETCH FIRST）
--   Spark SQL:   LIMIT n OFFSET m（类似 Hive，部分版本支持 FETCH FIRST）
--   Presto/Trino: LIMIT n OFFSET m + FETCH FIRST（SQL 标准）
--   Impala:      LIMIT n OFFSET m（不支持 FETCH FIRST）
--
-- 大数据引擎分页对比:
--   Hive:   离线批处理，ORDER BY 单 Reducer 瓶颈，SORT BY 可并行
--   Spark:  内存计算，排序性能优于 Hive
--   Impala: MPP 架构，交互式分页性能好
--   Trino:  MPP 架构，交互式分页性能好
