-- Spark SQL: 累计/滚动合计 (Running Total)
--
-- 参考资料:
--   [1] Spark SQL - Window Functions
--       https://spark.apache.org/docs/latest/sql-ref-syntax-qry-select-window.html

-- ============================================================
-- 1. 累计求和
-- ============================================================

-- 默认帧: RANGE BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW
SELECT txn_id, account_id, amount, txn_date,
       SUM(amount) OVER (ORDER BY txn_date) AS running_total
FROM transactions;

-- 显式帧（推荐，语义更清晰）
SELECT txn_id, account_id, amount, txn_date,
       SUM(amount) OVER (
           ORDER BY txn_date
           ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW
       ) AS running_total
FROM transactions;

-- ROWS vs RANGE 的重要区别:
--   ROWS:  基于物理行位置，相同 txn_date 的行按出现顺序累加
--   RANGE: 基于逻辑值范围，相同 txn_date 的行一起累加（可能产生不同结果!）
--   当 ORDER BY 列有重复值时，ROWS 和 RANGE 的结果不同
--   推荐: 总是使用 ROWS 明确指定帧（避免 RANGE 的歧义行为）

-- ============================================================
-- 2. 分组累计
-- ============================================================
SELECT txn_id, account_id, amount, txn_date,
       SUM(amount) OVER (
           PARTITION BY account_id
           ORDER BY txn_date
       ) AS running_total_per_account
FROM transactions;

-- PARTITION BY account_id 使 Shuffle 按 account_id 分区
-- 每个账户的累计在各自的 Executor 上独立计算——可以并行

-- ============================================================
-- 3. 累计平均与计数
-- ============================================================
SELECT txn_id, amount, txn_date,
       ROUND(AVG(amount) OVER (ORDER BY txn_date), 2) AS running_avg,
       COUNT(*) OVER (ORDER BY txn_date ROWS UNBOUNDED PRECEDING) AS running_count
FROM transactions;

-- ============================================================
-- 4. 滑动窗口（Moving Average）
-- ============================================================
SELECT txn_id, amount, txn_date,
       AVG(amount) OVER (
           ORDER BY txn_date
           ROWS BETWEEN 6 PRECEDING AND CURRENT ROW
       ) AS moving_avg_7,
       SUM(amount) OVER (
           ORDER BY txn_date
           ROWS BETWEEN 29 PRECEDING AND CURRENT ROW
       ) AS moving_sum_30
FROM transactions;

-- 7 日移动平均: 包含当前行在内的最近 7 行
-- 30 日移动求和: 包含当前行在内的最近 30 行

-- ============================================================
-- 5. 条件重置累计
-- ============================================================

-- 场景: 遇到负数金额时重置累计
WITH groups AS (
    SELECT txn_id, amount, txn_date,
           SUM(CASE WHEN amount < 0 THEN 1 ELSE 0 END) OVER (
               ORDER BY txn_date
               ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW
           ) AS grp
    FROM transactions
)
SELECT txn_id, amount, txn_date,
       SUM(amount) OVER (PARTITION BY grp ORDER BY txn_date) AS running_total_reset
FROM groups;

-- 原理: 用条件累计 COUNT 创建分组标识，然后在每组内独立累计

-- ============================================================
-- 6. 百分比累计
-- ============================================================
SELECT txn_id, amount, txn_date,
       SUM(amount) OVER (ORDER BY txn_date) AS running_total,
       ROUND(SUM(amount) OVER (ORDER BY txn_date)
           / SUM(amount) OVER () * 100, 2) AS running_pct
FROM transactions;

-- ============================================================
-- 7. 性能考量
-- ============================================================

-- 无 PARTITION BY 的窗口函数:
--   所有数据 Shuffle 到单个分区执行——这是性能瓶颈!
--   在大数据集上应尽量使用 PARTITION BY 将计算分布到多个 Executor
--
-- 有 PARTITION BY 的窗口函数:
--   Shuffle 按分区键分布，每个分区独立计算——可以并行

-- ============================================================
-- 8. 版本演进
-- ============================================================
-- Spark 1.4: 基本窗口函数累计
-- Spark 3.0: 命名窗口, GROUPS 帧模式
-- Spark 3.2: 窗口函数性能优化
--
-- 限制:
--   RANGE 帧不支持 INTERVAL（只支持数值范围）
--   无 PARTITION BY 时单分区执行（大数据集性能差）
--   条件重置累计需要两步查询（无内建语法）
