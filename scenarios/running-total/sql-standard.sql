-- SQL Standard: 累计/滚动合计（Running Total）
--
-- 参考资料:
--   [1] ISO/IEC 9075 SQL Standard - Window Functions
--       https://www.iso.org/standard/76583.html
--   [2] SQL Standard - Window Frame Clause
--       https://modern-sql.com/feature/over

-- ============================================================
-- 示例数据上下文
-- ============================================================
-- 假设表结构:
--   transactions(txn_id INT, account_id INT, amount DECIMAL(10,2), txn_date DATE, category VARCHAR)

-- ============================================================
-- 1. 累计求和（SUM OVER）
-- ============================================================

-- 按日期排序的累计总额
SELECT txn_id, account_id, amount, txn_date,
       SUM(amount) OVER (
           ORDER BY txn_date
           ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW
       ) AS running_total
FROM transactions;

-- 简写形式（ROWS UNBOUNDED PRECEDING 是默认行为）
SELECT txn_id, account_id, amount, txn_date,
       SUM(amount) OVER (ORDER BY txn_date) AS running_total
FROM transactions;

-- ============================================================
-- 2. 累计平均值
-- ============================================================

SELECT txn_id, account_id, amount, txn_date,
       AVG(amount) OVER (
           ORDER BY txn_date
           ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW
       ) AS running_avg
FROM transactions;

-- ============================================================
-- 3. 累计计数
-- ============================================================

SELECT txn_id, account_id, amount, txn_date,
       COUNT(*) OVER (
           ORDER BY txn_date
           ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW
       ) AS running_count
FROM transactions;

-- ============================================================
-- 4. 分组累计（按账户分组的累计求和）
-- ============================================================

SELECT txn_id, account_id, amount, txn_date,
       SUM(amount) OVER (
           PARTITION BY account_id
           ORDER BY txn_date
           ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW
       ) AS running_total_per_account
FROM transactions;

-- 按类别分组的累计
SELECT txn_id, category, amount, txn_date,
       SUM(amount) OVER (
           PARTITION BY category
           ORDER BY txn_date
       ) AS running_total_per_category
FROM transactions;

-- ============================================================
-- 5. 滑动窗口聚合
-- ============================================================

-- 最近 7 行的移动平均
SELECT txn_id, amount, txn_date,
       AVG(amount) OVER (
           ORDER BY txn_date
           ROWS BETWEEN 6 PRECEDING AND CURRENT ROW
       ) AS moving_avg_7
FROM transactions;

-- 最近 30 天的移动总和（RANGE 窗口）
SELECT txn_id, amount, txn_date,
       SUM(amount) OVER (
           ORDER BY txn_date
           RANGE BETWEEN INTERVAL '30' DAY PRECEDING AND CURRENT ROW
       ) AS moving_sum_30d
FROM transactions;

-- ============================================================
-- 6. 累计最大/最小值
-- ============================================================

SELECT txn_id, amount, txn_date,
       MAX(amount) OVER (
           ORDER BY txn_date
           ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW
       ) AS running_max,
       MIN(amount) OVER (
           ORDER BY txn_date
           ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW
       ) AS running_min
FROM transactions;

-- ============================================================
-- 7. 条件重置累计（使用窗口函数模拟）
-- ============================================================

-- 每当 amount < 0 时重置累计（使用分组技巧）
WITH groups AS (
    SELECT txn_id, amount, txn_date,
           SUM(CASE WHEN amount < 0 THEN 1 ELSE 0 END) OVER (
               ORDER BY txn_date
               ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW
           ) AS grp
    FROM transactions
)
SELECT txn_id, amount, txn_date,
       SUM(amount) OVER (
           PARTITION BY grp
           ORDER BY txn_date
       ) AS running_total_reset
FROM groups;

-- ============================================================
-- 8. 无窗口函数的替代方案（自连接）
-- ============================================================

-- 自连接实现累计求和
SELECT t1.txn_id, t1.amount, t1.txn_date,
       SUM(t2.amount) AS running_total
FROM transactions t1
JOIN transactions t2
  ON t2.txn_date <= t1.txn_date
GROUP BY t1.txn_id, t1.amount, t1.txn_date
ORDER BY t1.txn_date;

-- 关联子查询实现累计求和
SELECT t1.txn_id, t1.amount, t1.txn_date,
       (SELECT SUM(t2.amount)
        FROM transactions t2
        WHERE t2.txn_date <= t1.txn_date) AS running_total
FROM transactions t1
ORDER BY t1.txn_date;

-- ============================================================
-- 9. 性能考量
-- ============================================================

-- 窗口函数的 ROWS 帧比 RANGE 帧更高效（精确行数 vs 值范围）
-- ROWS UNBOUNDED PRECEDING 是最常见的累计帧
-- 自连接/关联子查询是 O(n^2)，仅适合小数据集
-- 建议在 ORDER BY 列上建索引
