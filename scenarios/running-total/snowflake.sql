-- Snowflake: 累计/滚动合计
--
-- 参考资料:
--   [1] Snowflake Documentation - Window Functions
--       https://docs.snowflake.com/en/sql-reference/functions-analytic

-- ============================================================
-- 1. 累计求和
-- ============================================================

SELECT txn_id, account_id, amount, txn_date,
       SUM(amount) OVER (ORDER BY txn_date) AS running_total
FROM transactions;

-- ============================================================
-- 2. 分组累计
-- ============================================================

SELECT txn_id, account_id, amount, txn_date,
       SUM(amount) OVER (
           PARTITION BY account_id ORDER BY txn_date
       ) AS running_total_per_account
FROM transactions;

-- ============================================================
-- 3. 累计平均与计数
-- ============================================================

SELECT txn_id, amount, txn_date,
       ROUND(AVG(amount) OVER (ORDER BY txn_date), 2) AS running_avg,
       COUNT(*) OVER (ORDER BY txn_date ROWS UNBOUNDED PRECEDING) AS running_count
FROM transactions;

-- ============================================================
-- 4. 滑动窗口
-- ============================================================

-- 7 日移动平均
SELECT txn_id, amount, txn_date,
       AVG(amount) OVER (
           ORDER BY txn_date ROWS BETWEEN 6 PRECEDING AND CURRENT ROW
       ) AS moving_avg_7
FROM transactions;

-- 3 日移动和
SELECT txn_id, amount, txn_date,
       SUM(amount) OVER (
           ORDER BY txn_date ROWS BETWEEN 2 PRECEDING AND CURRENT ROW
       ) AS rolling_sum_3
FROM transactions;

-- 对引擎开发者的启示:
--   Snowflake 支持 ROWS 和 RANGE 帧，不支持 GROUPS。
--   ROWS BETWEEN n PRECEDING 是 O(窗口大小) 实现，
--   对于大窗口可能需要优化（如前缀和或分段求和）。

-- ============================================================
-- 5. 累计百分比
-- ============================================================

SELECT txn_id, amount, txn_date,
       SUM(amount) OVER (ORDER BY txn_date) AS running_total,
       ROUND(
           SUM(amount) OVER (ORDER BY txn_date) * 100.0 /
           SUM(amount) OVER (), 2
       ) AS running_pct
FROM transactions;

-- ============================================================
-- 6. 条件重置累计
-- ============================================================

WITH groups AS (
    SELECT txn_id, amount, txn_date,
           SUM(CASE WHEN amount < 0 THEN 1 ELSE 0 END) OVER (
               ORDER BY txn_date ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW
           ) AS grp
    FROM transactions
)
SELECT txn_id, amount, txn_date,
       SUM(amount) OVER (PARTITION BY grp ORDER BY txn_date) AS running_total_reset
FROM groups;

-- ============================================================
-- 7. DIV0: 安全除法在累计计算中的应用
-- ============================================================

SELECT txn_date, amount,
       LAG(amount) OVER (ORDER BY txn_date) AS prev_amount,
       ROUND(DIV0(
           amount - LAG(amount) OVER (ORDER BY txn_date),
           LAG(amount) OVER (ORDER BY txn_date)
       ) * 100, 2) AS change_pct
FROM transactions;
-- DIV0: 除以零时返回 0（Snowflake 独有，避免除零错误）

-- ============================================================
-- 8. 性能考量
-- ============================================================
-- Snowflake 自动并行执行窗口函数
-- 聚簇键优化: ALTER TABLE transactions CLUSTER BY (txn_date);
-- 大 PARTITION BY 可能导致数据溢出 → 需要更大的 Warehouse
-- Snowflake 支持 ROWS 帧（精确行数），RANGE 帧支持有限

-- ============================================================
-- 横向对比: 累计计算
-- ============================================================
-- 能力          | Snowflake    | BigQuery  | PostgreSQL | MySQL 8.0
-- SUM OVER      | 支持         | 支持      | 支持       | 支持
-- 滑动窗口      | ROWS         | ROWS      | ROWS/RANGE | ROWS
-- GROUPS 帧     | 不支持       | 不支持    | 13+        | 不支持
-- DIV0 安全除法 | 原生         | IEEE_DIV  | NULLIF变通 | NULLIF变通
-- QUALIFY 过滤  | 支持         | 支持      | 不支持     | 不支持
