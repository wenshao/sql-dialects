-- StarRocks: 累计求和
--
-- 参考资料:
--   [1] StarRocks Documentation - Window Functions

SELECT txn_id, amount, txn_date,
    SUM(amount) OVER (ORDER BY txn_date) AS running_total
FROM transactions;

SELECT txn_id, account_id, amount,
    SUM(amount) OVER (PARTITION BY account_id ORDER BY txn_date) AS acct_total
FROM transactions;

SELECT txn_id, amount,
    AVG(amount) OVER (ORDER BY txn_date ROWS BETWEEN 6 PRECEDING AND CURRENT ROW) AS ma7
FROM transactions;

-- Pipeline 引擎优化窗口函数的分区并行度。
-- 与 Doris 语法完全相同(同源)。
