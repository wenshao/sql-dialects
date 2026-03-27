-- BigQuery: 累计/滚动合计（Running Total）
--
-- 参考资料:
--   [1] BigQuery Documentation - Analytic Functions
--       https://cloud.google.com/bigquery/docs/reference/standard-sql/analytic-function-concepts
--   [2] BigQuery Documentation - Window Frame
--       https://cloud.google.com/bigquery/docs/reference/standard-sql/window-function-calls

-- ============================================================
-- 示例数据上下文
-- ============================================================
-- 假设表结构:
--   project.dataset.transactions(txn_id INT64, account_id INT64, amount NUMERIC, txn_date DATE, category STRING)

-- ============================================================
-- 1. 累计求和
-- ============================================================

SELECT txn_id, account_id, amount, txn_date,
       SUM(amount) OVER (ORDER BY txn_date) AS running_total
FROM `project.dataset.transactions`;

-- ============================================================
-- 2. 累计平均值
-- ============================================================

SELECT txn_id, amount, txn_date,
       ROUND(AVG(amount) OVER (ORDER BY txn_date), 2) AS running_avg
FROM `project.dataset.transactions`;

-- ============================================================
-- 3. 累计计数
-- ============================================================

SELECT txn_id, amount, txn_date,
       COUNT(*) OVER (ORDER BY txn_date ROWS UNBOUNDED PRECEDING) AS running_count
FROM `project.dataset.transactions`;

-- ============================================================
-- 4. 分组累计
-- ============================================================

SELECT txn_id, account_id, amount, txn_date,
       SUM(amount) OVER (
           PARTITION BY account_id
           ORDER BY txn_date
       ) AS running_total_per_account
FROM `project.dataset.transactions`;

-- ============================================================
-- 5. 滑动窗口
-- ============================================================

SELECT txn_id, amount, txn_date,
       AVG(amount) OVER (
           ORDER BY txn_date
           ROWS BETWEEN 6 PRECEDING AND CURRENT ROW
       ) AS moving_avg_7
FROM `project.dataset.transactions`;

-- RANGE 帧（BigQuery 支持有限的 RANGE）
SELECT txn_id, amount, txn_date,
       SUM(amount) OVER (
           ORDER BY UNIX_DATE(txn_date)
           RANGE BETWEEN 30 PRECEDING AND CURRENT ROW
       ) AS moving_sum_30d
FROM `project.dataset.transactions`;

-- ============================================================
-- 6. 条件重置累计
-- ============================================================

WITH groups AS (
    SELECT txn_id, amount, txn_date,
           SUM(CASE WHEN amount < 0 THEN 1 ELSE 0 END) OVER (
               ORDER BY txn_date
               ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW
           ) AS grp
    FROM `project.dataset.transactions`
)
SELECT txn_id, amount, txn_date,
       SUM(amount) OVER (PARTITION BY grp ORDER BY txn_date) AS running_total_reset
FROM groups;

-- ============================================================
-- 7. 累计百分比
-- ============================================================

SELECT txn_id, amount, txn_date,
       SUM(amount) OVER (ORDER BY txn_date) AS running_total,
       ROUND(
           SUM(amount) OVER (ORDER BY txn_date) * 100.0 /
           SUM(amount) OVER (), 2
       ) AS running_pct
FROM `project.dataset.transactions`;

-- ============================================================
-- 8. 性能考量
-- ============================================================

-- BigQuery 无需手动创建索引
-- 使用分区表减少扫描量
-- 窗口函数自动分布式并行执行
-- RANGE 帧在 BigQuery 中需要数值类型的 ORDER BY（用 UNIX_DATE 转换日期）
-- BigQuery 按扫描数据量计费
