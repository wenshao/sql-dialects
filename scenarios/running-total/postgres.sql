-- PostgreSQL: 累计/滚动合计（Running Total）
--
-- 参考资料:
--   [1] PostgreSQL Documentation - Window Functions
--       https://www.postgresql.org/docs/current/tutorial-window.html
--   [2] PostgreSQL Documentation - Window Function Calls
--       https://www.postgresql.org/docs/current/sql-expressions.html#SYNTAX-WINDOW-FUNCTIONS

-- ============================================================
-- 示例数据上下文
-- ============================================================
-- 假设表结构:
--   transactions(txn_id SERIAL, account_id INT, amount NUMERIC(10,2), txn_date DATE, category VARCHAR)

-- ============================================================
-- 1. 累计求和
-- ============================================================

SELECT txn_id, account_id, amount, txn_date,
       SUM(amount) OVER (ORDER BY txn_date) AS running_total
FROM transactions;

-- 显式指定帧
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
       AVG(amount) OVER (ORDER BY txn_date) AS running_avg,
       ROUND(AVG(amount) OVER (ORDER BY txn_date), 2) AS running_avg_rounded
FROM transactions;

-- ============================================================
-- 3. 累计计数
-- ============================================================

SELECT txn_id, amount, txn_date,
       COUNT(*) OVER (ORDER BY txn_date) AS running_count
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

-- 最近 7 行移动平均
SELECT txn_id, amount, txn_date,
       AVG(amount) OVER (
           ORDER BY txn_date
           ROWS BETWEEN 6 PRECEDING AND CURRENT ROW
       ) AS moving_avg_7
FROM transactions;

-- 最近 30 天移动总和（RANGE 帧）
SELECT txn_id, amount, txn_date,
       SUM(amount) OVER (
           ORDER BY txn_date
           RANGE BETWEEN INTERVAL '30 days' PRECEDING AND CURRENT ROW
       ) AS moving_sum_30d
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
-- 7. 累计百分比
-- ============================================================

SELECT txn_id, amount, txn_date,
       SUM(amount) OVER (ORDER BY txn_date) AS running_total,
       ROUND(
           SUM(amount) OVER (ORDER BY txn_date) * 100.0 /
           SUM(amount) OVER (), 2
       ) AS running_pct
FROM transactions;

-- ============================================================
-- 8. 无窗口函数的替代方案
-- ============================================================

-- 自连接
SELECT t1.txn_id, t1.amount, t1.txn_date,
       SUM(t2.amount) AS running_total
FROM transactions t1
JOIN transactions t2 ON t2.txn_date <= t1.txn_date
GROUP BY t1.txn_id, t1.amount, t1.txn_date
ORDER BY t1.txn_date;

-- 关联子查询
SELECT t1.txn_id, t1.amount, t1.txn_date,
       (SELECT SUM(t2.amount)
        FROM transactions t2
        WHERE t2.txn_date <= t1.txn_date) AS running_total
FROM transactions t1
ORDER BY t1.txn_date;

-- ============================================================
-- 9. 性能考量
-- ============================================================

CREATE INDEX idx_transactions_date ON transactions (txn_date);
CREATE INDEX idx_transactions_account_date ON transactions (account_id, txn_date);

-- PostgreSQL 窗口函数支持 ROWS 和 RANGE 帧
-- ROWS 帧性能优于 RANGE 帧
-- RANGE + INTERVAL 需要 PostgreSQL 支持日期运算
-- 大表建议使用分区表 + 索引
