-- MariaDB: 累计/滚动合计（Running Total）
--
-- 参考资料:
--   [1] MariaDB Documentation - Window Functions
--       https://mariadb.com/kb/en/window-functions/

-- ============================================================
-- 示例数据上下文
-- ============================================================
-- 假设表结构:
--   transactions(order_id INT AUTO_INCREMENT, account_id INT, amount DECIMAL(10,2), txn_date DATE)

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

-- 最近 7 行移动平均
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
-- 7. MariaDB 10.1 及以下替代方案（无窗口函数）
-- ============================================================

-- 关联子查询
SELECT t1.txn_id, t1.amount, t1.txn_date,
       (SELECT SUM(t2.amount)
        FROM transactions t2
        WHERE t2.txn_date <= t1.txn_date) AS running_total
FROM transactions t1
ORDER BY t1.txn_date;

-- ============================================================
-- 8. 性能考量
-- ============================================================

-- 窗口函数从 MariaDB 10.2 开始支持
-- CTE 从 MariaDB 10.2 开始支持
CREATE INDEX idx_transactions_date ON transactions (txn_date);
CREATE INDEX idx_transactions_account_date ON transactions (account_id, txn_date);
