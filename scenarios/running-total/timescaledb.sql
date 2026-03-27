-- TimescaleDB: 累计/滚动合计（Running Total）
--
-- 参考资料:
--   [1] TimescaleDB Documentation
--       https://docs.timescale.com/

-- ============================================================
-- 示例数据上下文
-- ============================================================
-- 假设表结构:
--   transactions(txn_id SERIAL, account_id INT, amount NUMERIC(10,2), txn_date TIMESTAMPTZ)

-- ============================================================
-- 1. 累计求和
-- ============================================================

SELECT txn_id, account_id, amount, txn_date,
       SUM(amount) OVER (ORDER BY txn_date) AS running_total
FROM transactions;

SELECT txn_id, account_id, amount, txn_date,
       SUM(amount) OVER (
           ORDER BY txn_date
           ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW
       ) AS running_total
FROM transactions;

-- ============================================================
-- 2. 累计平均值
-- ============================================================

SELECT txn_id, amount, txn_date,
       ROUND(AVG(amount) OVER (ORDER BY txn_date), 2) AS running_avg
FROM transactions;

-- ============================================================
-- 3. 累计计数
-- ============================================================

SELECT txn_id, amount, txn_date,
       COUNT(*) OVER (ORDER BY txn_date ROWS UNBOUNDED PRECEDING) AS running_count
FROM transactions;

-- ============================================================
-- 4. 分组累计
-- ============================================================

SELECT txn_id, account_id, amount, txn_date,
       SUM(amount) OVER (
           PARTITION BY account_id
           ORDER BY txn_date
       ) AS running_total_per_account
FROM transactions;

-- ============================================================
-- 5. 滑动窗口
-- ============================================================

SELECT txn_id, amount, txn_date,
       AVG(amount) OVER (
           ORDER BY txn_date
           ROWS BETWEEN 6 PRECEDING AND CURRENT ROW
       ) AS moving_avg_7
FROM transactions;

-- ============================================================
-- 6. 条件重置累计
-- ============================================================

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

-- ============================================================
-- 7. TimescaleDB 特色：时间桶累计
-- ============================================================

-- 按小时分桶的累计
SELECT time_bucket('1 hour', txn_date) AS bucket,
       SUM(amount) AS bucket_total,
       SUM(SUM(amount)) OVER (ORDER BY time_bucket('1 hour', txn_date)) AS running_total
FROM transactions
GROUP BY bucket
ORDER BY bucket;

-- 连续聚合 + 累计
CREATE MATERIALIZED VIEW hourly_totals
WITH (timescaledb.continuous) AS
SELECT time_bucket('1 hour', txn_date) AS bucket,
       account_id,
       SUM(amount) AS total
FROM transactions
GROUP BY bucket, account_id;

-- ============================================================
-- 8. 性能考量
-- ============================================================

-- TimescaleDB 完全兼容 PostgreSQL
-- 超表按时间分区，时间范围查询自动修剪
-- 连续聚合自动维护
CREATE INDEX idx_transactions_date ON transactions (txn_date);
