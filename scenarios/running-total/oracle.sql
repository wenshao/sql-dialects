-- Oracle: 累计/滚动合计 (Running Total)
--
-- 参考资料:
--   [1] Oracle SQL Language Reference - Analytic Functions
--       https://docs.oracle.com/en/database/oracle/oracle-database/23/sqlrf/Analytic-Functions.html

-- ============================================================
-- 1. 基本累计求和（Oracle 8i+ 首创窗口函数）
-- ============================================================

SELECT txn_id, account_id, amount, txn_date,
       SUM(amount) OVER (ORDER BY txn_date) AS running_total
FROM transactions;

-- 显式帧子句
SELECT txn_id, amount, txn_date,
       SUM(amount) OVER (
           ORDER BY txn_date
           ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW
       ) AS running_total
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
-- 3. 累计平均和计数
-- ============================================================

SELECT txn_id, amount, txn_date,
       ROUND(AVG(amount) OVER (ORDER BY txn_date), 2) AS running_avg,
       COUNT(*) OVER (ORDER BY txn_date ROWS UNBOUNDED PRECEDING) AS running_count
FROM transactions;

-- ============================================================
-- 4. 滑动窗口
-- ============================================================

-- 最近 7 行移动平均
SELECT txn_id, amount, txn_date,
       AVG(amount) OVER (
           ORDER BY txn_date ROWS BETWEEN 6 PRECEDING AND CURRENT ROW
       ) AS moving_avg_7
FROM transactions;

-- 最近 30 天移动总和（RANGE + INTERVAL，Oracle 独有能力）
SELECT txn_id, amount, txn_date,
       SUM(amount) OVER (
           ORDER BY txn_date
           RANGE BETWEEN INTERVAL '30' DAY PRECEDING AND CURRENT ROW
       ) AS moving_sum_30d
FROM transactions;

-- 设计分析: ROWS vs RANGE + INTERVAL
--   ROWS BETWEEN 6 PRECEDING: 按物理行数（前 6 行）
--   RANGE BETWEEN INTERVAL '30' DAY: 按值范围（前 30 天内的所有行）
--   RANGE + INTERVAL 是 Oracle 的独特支持:
--     PostgreSQL: 也支持 RANGE + INTERVAL
--     MySQL:      RANGE 只支持数值，不支持 INTERVAL
--     SQL Server: RANGE 只支持 UNBOUNDED/CURRENT ROW

-- ============================================================
-- 5. 条件重置累计
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
-- 6. MODEL 子句（Oracle 10g+ 独有的行级计算）
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

-- MODEL 子句直接引用前一行的值（类似 Excel 的 A2 = A1 + B2），
-- 但语法复杂，性能不如窗口函数，实际使用率低。

-- ============================================================
-- 7. 无窗口函数的替代方案（关联子查询）
-- ============================================================

SELECT t1.txn_id, t1.amount, t1.txn_date,
       (SELECT SUM(t2.amount)
        FROM transactions t2
        WHERE t2.txn_date <= t1.txn_date) AS running_total
FROM transactions t1 ORDER BY t1.txn_date;

-- 性能极差（O(n^2)），仅作为理解窗口函数价值的对比

-- ============================================================
-- 8. 性能考量
-- ============================================================

CREATE INDEX idx_txn_date ON transactions (txn_date);
CREATE INDEX idx_txn_account_date ON transactions (account_id, txn_date);

-- Oracle 分析函数从 8i 开始支持（1999年，业界最早）
-- ROWS 帧比 RANGE 帧性能更好（ROWS 不需要值比较）
-- Oracle 支持 RANGE + INTERVAL（其他数据库有限或不支持）

-- ============================================================
-- 9. 对引擎开发者的总结
-- ============================================================
-- 1. 累计求和是窗口函数最基本的应用，Oracle 8i 首创此能力。
-- 2. RANGE + INTERVAL 帧使时间序列分析更自然（按日期范围而非行数）。
-- 3. MODEL 子句可以实现任意行间引用，但语法复杂，窗口函数是更好的选择。
-- 4. 条件重置累计需要"分组标记+分组累计"的两步模式。
-- 5. 窗口函数将 O(n^2) 关联子查询优化为 O(n)，性能差距可达 100 倍以上。
