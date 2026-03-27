-- Oracle: 累计/滚动合计（Running Total）
--
-- 参考资料:
--   [1] Oracle Documentation - Analytic Functions
--       https://docs.oracle.com/en/database/oracle/oracle-database/19/sqlrf/Analytic-Functions.html
--   [2] Oracle Documentation - Window Frame Clause
--       https://docs.oracle.com/en/database/oracle/oracle-database/19/sqlrf/Analytic-Functions.html

-- ============================================================
-- 示例数据上下文
-- ============================================================
-- 假设表结构:
--   transactions(txn_id NUMBER, account_id NUMBER, amount NUMBER(10,2), txn_date DATE, category VARCHAR2(50))

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

-- 最近 30 天移动总和（RANGE 帧）
SELECT txn_id, amount, txn_date,
       SUM(amount) OVER (
           ORDER BY txn_date
           RANGE BETWEEN INTERVAL '30' DAY PRECEDING AND CURRENT ROW
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
-- 7. MODEL 子句（Oracle 独有的行级计算）
-- ============================================================

SELECT txn_id, amount, txn_date, running_total
FROM transactions
MODEL
    DIMENSION BY (ROW_NUMBER() OVER (ORDER BY txn_date) AS rn)
    MEASURES (txn_id, amount, txn_date, 0 AS running_total)
    RULES (
        running_total[rn] = NVL(running_total[cv()-1], 0) + amount[cv()]
    )
ORDER BY rn;

-- ============================================================
-- 8. 无窗口函数的替代方案
-- ============================================================

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

-- Oracle 的分析函数是最早支持窗口函数的数据库之一（8i 开始）
-- ROWS 帧比 RANGE 帧性能更好
-- MODEL 子句功能强大但性能不如窗口函数
-- Oracle 支持 RANGE + INTERVAL 帧
