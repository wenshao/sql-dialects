-- Snowflake: 累计/滚动合计（Running Total）
--
-- 参考资料:
--   [1] Snowflake Documentation - Window Functions
--       https://docs.snowflake.com/en/sql-reference/functions-analytic
--   [2] Snowflake Documentation - Window Frame Syntax
--       https://docs.snowflake.com/en/sql-reference/functions-analytic#window-frame-syntax

-- ============================================================
-- 示例数据上下文
-- ============================================================
-- 假设表结构:
--   transactions(txn_id NUMBER, account_id NUMBER, amount NUMBER(10,2), txn_date DATE, category VARCHAR)

-- ============================================================
-- 1. 累计求和
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
-- 8. QUALIFY 配合累计计算
-- ============================================================

-- 找出累计总额超过 10000 的第一条记录
SELECT txn_id, amount, txn_date, running_total
FROM (
    SELECT txn_id, amount, txn_date,
           SUM(amount) OVER (ORDER BY txn_date) AS running_total
    FROM transactions
)
QUALIFY ROW_NUMBER() OVER (ORDER BY txn_date) =
    (SELECT MIN(rn) FROM (
        SELECT ROW_NUMBER() OVER (ORDER BY txn_date) AS rn,
               SUM(amount) OVER (ORDER BY txn_date) AS rt
        FROM transactions
    ) WHERE rt >= 10000);

-- ============================================================
-- 9. 性能考量
-- ============================================================

-- Snowflake 自动并行执行窗口函数
-- 无需手动创建索引
-- 聚集键可优化排序：ALTER TABLE transactions CLUSTER BY (txn_date);
-- Snowflake 支持 ROWS 帧，RANGE 帧支持有限
