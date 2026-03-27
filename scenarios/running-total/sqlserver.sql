-- SQL Server: 累计/滚动合计（Running Total）
--
-- 参考资料:
--   [1] Microsoft Docs - Window Functions
--       https://learn.microsoft.com/en-us/sql/t-sql/queries/select-over-clause-transact-sql
--   [2] Microsoft Docs - SUM with OVER
--       https://learn.microsoft.com/en-us/sql/t-sql/functions/sum-transact-sql

-- ============================================================
-- 示例数据上下文
-- ============================================================
-- 假设表结构:
--   transactions(txn_id INT IDENTITY, account_id INT, amount DECIMAL(10,2), txn_date DATE, category VARCHAR(50))

-- ============================================================
-- 1. 累计求和（SQL Server 2012+）
-- ============================================================

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
       AVG(amount) OVER (
           ORDER BY txn_date
           ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW
       ) AS running_avg
FROM transactions;

-- ============================================================
-- 3. 累计计数
-- ============================================================

SELECT txn_id, amount, txn_date,
       COUNT(*) OVER (
           ORDER BY txn_date
           ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW
       ) AS running_count
FROM transactions;

-- ============================================================
-- 4. 分组累计
-- ============================================================

SELECT txn_id, account_id, amount, txn_date,
       SUM(amount) OVER (
           PARTITION BY account_id
           ORDER BY txn_date
           ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW
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
       SUM(amount) OVER (PARTITION BY grp ORDER BY txn_date ROWS UNBOUNDED PRECEDING) AS running_total_reset
FROM groups;

-- ============================================================
-- 7. SQL Server 2008 及以下替代方案
-- ============================================================

-- CROSS APPLY + 子查询
SELECT t.txn_id, t.amount, t.txn_date, rt.running_total
FROM transactions t
CROSS APPLY (
    SELECT SUM(amount) AS running_total
    FROM transactions t2
    WHERE t2.txn_date <= t.txn_date
) rt
ORDER BY t.txn_date;

-- 递归 CTE
WITH ordered AS (
    SELECT txn_id, amount, txn_date,
           ROW_NUMBER() OVER (ORDER BY txn_date) AS rn
    FROM transactions
),
running AS (
    SELECT txn_id, amount, txn_date, rn, amount AS running_total
    FROM ordered WHERE rn = 1
    UNION ALL
    SELECT o.txn_id, o.amount, o.txn_date, o.rn,
           r.running_total + o.amount
    FROM ordered o
    JOIN running r ON o.rn = r.rn + 1
)
SELECT txn_id, amount, txn_date, running_total
FROM running
ORDER BY txn_date
OPTION (MAXRECURSION 0);

-- ============================================================
-- 8. 性能考量
-- ============================================================

CREATE INDEX idx_transactions_date ON transactions (txn_date);
CREATE INDEX idx_transactions_account_date ON transactions (account_id, txn_date);

-- SQL Server 2012+ ROWS 帧比 RANGE 帧性能好很多
-- SUM OVER (ORDER BY) 不指定帧时默认使用 RANGE（性能较差）
-- 建议显式指定 ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW
-- CROSS APPLY 方式在 SQL Server 2005/2008 中可用但 O(n^2)
-- 注意：SQL Server 不支持 RANGE + INTERVAL
