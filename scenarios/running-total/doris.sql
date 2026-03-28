-- Apache Doris: 累计求和
--
-- 参考资料:
--   [1] Doris Documentation - Window Functions

SELECT txn_id, amount, txn_date,
    SUM(amount) OVER (ORDER BY txn_date) AS running_total
FROM transactions;

SELECT txn_id, amount, txn_date,
    SUM(amount) OVER (ORDER BY txn_date
        ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW) AS running_total
FROM transactions;

-- 分组累计
SELECT txn_id, account_id, amount,
    SUM(amount) OVER (PARTITION BY account_id ORDER BY txn_date) AS acct_total
FROM transactions;

-- 滑动窗口
SELECT txn_id, amount,
    AVG(amount) OVER (ORDER BY txn_date ROWS BETWEEN 6 PRECEDING AND CURRENT ROW) AS ma7
FROM transactions;

-- 累计平均/计数
SELECT txn_id, ROUND(AVG(amount) OVER (ORDER BY txn_date), 2) AS running_avg,
    COUNT(*) OVER (ORDER BY txn_date ROWS UNBOUNDED PRECEDING) AS running_count
FROM transactions;

-- MPP 架构自动并行执行窗口函数。
