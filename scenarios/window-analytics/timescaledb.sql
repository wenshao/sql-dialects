-- TimescaleDB: 窗口函数实战分析
--
-- 参考资料:
--   [1] TimescaleDB Documentation - Hyperfunctions (Window)
--       https://docs.timescale.com/api/latest/hyperfunctions/
--   [2] PostgreSQL Documentation - Window Functions
--       https://www.postgresql.org/docs/current/tutorial-window.html

-- TimescaleDB 继承 PostgreSQL 所有窗口函数，并添加时序特有函数
-- 假设表结构（hypertable）:
--   daily_sales(sale_date TIMESTAMPTZ, product_id INT, region VARCHAR,
--               amount NUMERIC(10,2), quantity INT)
--   SELECT create_hypertable('daily_sales', 'sale_date');

-- ============================================================
-- 1. 移动平均
-- ============================================================

-- 标准窗口函数（同 PostgreSQL）
SELECT sale_date, amount,
       ROUND(AVG(amount) OVER (
           ORDER BY sale_date ROWS BETWEEN 2 PRECEDING AND CURRENT ROW
       ), 2) AS ma_3d,
       ROUND(AVG(amount) OVER (
           ORDER BY sale_date
           RANGE BETWEEN INTERVAL '6 days' PRECEDING AND CURRENT ROW
       ), 2) AS ma_7d
FROM daily_sales;

-- TimescaleDB 特有: time_bucket 分组后移动平均
SELECT time_bucket('1 day', sale_date) AS day,
       SUM(amount) AS daily_total,
       AVG(SUM(amount)) OVER (
           ORDER BY time_bucket('1 day', sale_date)
           ROWS BETWEEN 6 PRECEDING AND CURRENT ROW
       ) AS ma_7d
FROM daily_sales
GROUP BY day;

-- ============================================================
-- 2. 同比/环比
-- ============================================================

WITH monthly AS (
    SELECT time_bucket('1 month', sale_date) AS sale_month,
           SUM(amount) AS total_amount
    FROM daily_sales
    GROUP BY sale_month
)
SELECT sale_month, total_amount,
       LAG(total_amount) OVER (ORDER BY sale_month) AS prev_month,
       ROUND((total_amount - LAG(total_amount) OVER (ORDER BY sale_month))
           / NULLIF(LAG(total_amount) OVER (ORDER BY sale_month), 0) * 100, 2) AS mom_pct,
       LAG(total_amount, 12) OVER (ORDER BY sale_month) AS prev_year,
       ROUND((total_amount - LAG(total_amount, 12) OVER (ORDER BY sale_month))
           / NULLIF(LAG(total_amount, 12) OVER (ORDER BY sale_month), 0) * 100, 2) AS yoy_pct
FROM monthly;

-- ============================================================
-- 3. 占比
-- ============================================================

SELECT product_id,
       SUM(amount) AS product_total,
       ROUND(SUM(amount) / SUM(SUM(amount)) OVER () * 100, 2) AS pct_of_total
FROM daily_sales
GROUP BY product_id;

-- ============================================================
-- 4. 百分位数 / 中位数
-- ============================================================

-- 标准 PostgreSQL 方式
SELECT time_bucket('1 month', sale_date) AS month,
       PERCENTILE_CONT(0.5) WITHIN GROUP (ORDER BY amount) AS median_amount,
       PERCENTILE_CONT(0.90) WITHIN GROUP (ORDER BY amount) AS p90_amount,
       PERCENTILE_CONT(0.99) WITHIN GROUP (ORDER BY amount) AS p99_amount
FROM daily_sales
GROUP BY month;

-- TimescaleDB Toolkit 近似百分位（大数据集推荐）
-- SELECT time_bucket('1 day', sale_date) AS day,
--        approx_percentile(0.5, percentile_agg(amount)) AS approx_median,
--        approx_percentile(0.99, percentile_agg(amount)) AS approx_p99
-- FROM daily_sales
-- GROUP BY day;

-- ============================================================
-- 5. 会话化
-- ============================================================

WITH event_gaps AS (
    SELECT user_id, event_time, event_type,
           CASE
               WHEN event_time - LAG(event_time) OVER (
                   PARTITION BY user_id ORDER BY event_time) > INTERVAL '30 minutes'
               OR LAG(event_time) OVER (PARTITION BY user_id ORDER BY event_time) IS NULL
               THEN 1 ELSE 0
           END AS is_new_session
    FROM user_events
),
sessions AS (
    SELECT *, SUM(is_new_session) OVER (
        PARTITION BY user_id ORDER BY event_time
    ) AS session_num
    FROM event_gaps
)
SELECT user_id, session_num,
       MIN(event_time) AS session_start,
       MAX(event_time) AS session_end,
       EXTRACT(EPOCH FROM MAX(event_time) - MIN(event_time))::INT AS duration_sec,
       COUNT(*) AS event_count,
       ARRAY_AGG(event_type ORDER BY event_time) AS event_path
FROM sessions
GROUP BY user_id, session_num;

-- ============================================================
-- 6. FIRST_VALUE / LAST_VALUE
-- ============================================================

SELECT sale_date, product_id, amount,
       FIRST_VALUE(amount) OVER (
           PARTITION BY product_id ORDER BY sale_date
       ) AS first_amount,
       LAST_VALUE(amount) OVER (
           PARTITION BY product_id ORDER BY sale_date
           ROWS BETWEEN UNBOUNDED PRECEDING AND UNBOUNDED FOLLOWING
       ) AS last_amount
FROM daily_sales;

-- TimescaleDB Toolkit: first/last 函数
-- SELECT product_id,
--        first(amount, sale_date) AS first_amount,
--        last(amount, sale_date) AS last_amount
-- FROM daily_sales GROUP BY product_id;

-- ============================================================
-- 7. LEAD / LAG
-- ============================================================

SELECT sale_date, amount,
       LAG(amount) OVER w AS prev_day,
       LEAD(amount) OVER w AS next_day,
       amount - LAG(amount) OVER w AS daily_change,
       ROUND((amount - LAG(amount) OVER w)
           / NULLIF(LAG(amount) OVER w, 0) * 100, 2) AS change_pct
FROM daily_sales
WINDOW w AS (ORDER BY sale_date);

-- ============================================================
-- 8. 累计分布
-- ============================================================

SELECT sale_date, amount,
       RANK() OVER w AS amount_rank,
       PERCENT_RANK() OVER w AS pct_rank,
       CUME_DIST() OVER w AS cum_dist,
       NTILE(4) OVER w AS quartile
FROM daily_sales
WINDOW w AS (ORDER BY amount);

-- TimescaleDB 继承 PostgreSQL 所有窗口函数
-- time_bucket 是 TimescaleDB 的核心函数
-- Toolkit 扩展提供 percentile_agg, first, last 等时序分析函数
-- Hypertable 自动分区优化大规模时序数据上的窗口查询
