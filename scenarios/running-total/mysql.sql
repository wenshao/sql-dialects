-- MySQL: 累计/滚动合计（Running Total）
--
-- 参考资料:
--   [1] MySQL 8.0 Reference Manual - Window Functions
--       https://dev.mysql.com/doc/refman/8.0/en/window-functions.html
--   [2] MySQL 8.0 Reference Manual - Window Function Frame
--       https://dev.mysql.com/doc/refman/8.0/en/window-functions-frames.html

-- ============================================================
-- 示例数据上下文
-- ============================================================
-- 假设表结构:
--   transactions(txn_id INT AUTO_INCREMENT, account_id INT, amount DECIMAL(10,2), txn_date DATE, category VARCHAR(50))

-- ============================================================
-- 1. 累计求和（MySQL 8.0+）
-- ============================================================

SELECT txn_id, account_id, amount, txn_date,
       SUM(amount) OVER (ORDER BY txn_date) AS running_total
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

-- RANGE 帧（按值范围）
SELECT txn_id, amount, txn_date,
       SUM(amount) OVER (
           ORDER BY txn_date
           RANGE BETWEEN INTERVAL 30 DAY PRECEDING AND CURRENT ROW
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
-- 7. MySQL 5.7 替代方案（无窗口函数）
-- ============================================================

-- 用户变量方式（MySQL 5.7，不推荐在 8.0 使用）
SELECT txn_id, amount, txn_date,
       @running := @running + amount AS running_total
FROM transactions, (SELECT @running := 0) r
ORDER BY txn_date;

-- 自连接方式
SELECT t1.txn_id, t1.amount, t1.txn_date,
       SUM(t2.amount) AS running_total
FROM transactions t1
JOIN transactions t2 ON t2.txn_date <= t1.txn_date
GROUP BY t1.txn_id, t1.amount, t1.txn_date
ORDER BY t1.txn_date;

-- ============================================================
-- 8. 性能考量
-- ============================================================

CREATE INDEX idx_transactions_date ON transactions (txn_date);
CREATE INDEX idx_transactions_account_date ON transactions (account_id, txn_date);

-- 窗口函数需要 MySQL 8.0+
-- 用户变量方式在 MySQL 8.0 中行为不可靠，不推荐
-- RANGE + INTERVAL 在 MySQL 8.0 中支持
-- 注意：MySQL 不支持 RANGE BETWEEN INTERVAL 的某些复杂形式
