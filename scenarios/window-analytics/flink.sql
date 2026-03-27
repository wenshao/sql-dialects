-- Flink SQL: 窗口函数实战分析
--
-- 参考资料:
--   [1] Apache Flink Documentation - Over Aggregation
--       https://nightlies.apache.org/flink/flink-docs-stable/docs/dev/table/sql/queries/over-agg/
--   [2] Apache Flink Documentation - Window Functions
--       https://nightlies.apache.org/flink/flink-docs-stable/docs/dev/table/sql/queries/window-agg/

-- ============================================================
-- Flink SQL 窗口函数特殊之处：
-- - 流处理场景下 OVER 窗口必须有 ORDER BY 时间属性
-- - 支持处理时间（proctime）和事件时间（rowtime）
-- - RANGE 帧基于时间间隔
-- ============================================================

-- 假设表结构（带时间属性）:
--   daily_sales(sale_date DATE, product_id INT, region STRING,
--               amount DECIMAL(10,2), quantity INT,
--               proc_time AS PROCTIME())
--   user_events(user_id BIGINT, event_time TIMESTAMP(3),
--               event_type STRING, page STRING,
--               WATERMARK FOR event_time AS event_time - INTERVAL '5' SECOND)

-- ============================================================
-- 1. 移动平均（OVER 窗口）
-- ============================================================

-- 基于行数的移动平均
SELECT sale_date, amount,
       AVG(amount) OVER (
           ORDER BY proc_time
           ROWS BETWEEN 2 PRECEDING AND CURRENT ROW
       ) AS ma_3,
       AVG(amount) OVER (
           ORDER BY proc_time
           ROWS BETWEEN 6 PRECEDING AND CURRENT ROW
       ) AS ma_7
FROM daily_sales;

-- 基于时间范围的移动平均
SELECT sale_date, amount,
       AVG(amount) OVER (
           ORDER BY proc_time
           RANGE BETWEEN INTERVAL '7' DAY PRECEDING AND CURRENT ROW
       ) AS ma_7d
FROM daily_sales;

-- 分区移动平均
SELECT sale_date, product_id, amount,
       AVG(amount) OVER (
           PARTITION BY product_id
           ORDER BY proc_time
           ROWS BETWEEN 6 PRECEDING AND CURRENT ROW
       ) AS ma_7
FROM daily_sales;

-- ============================================================
-- 2. LEAD / LAG（Flink 不直接支持传统 LAG/LEAD）
-- ============================================================

-- Flink SQL 在 OVER 窗口中不支持 LAG/LEAD
-- 使用 LAST_VALUE + ROWS BETWEEN 模拟

-- 对于批处理模式（Flink 1.14+），可使用标准窗口函数
-- SELECT sale_date, amount,
--        LAG(amount) OVER (ORDER BY sale_date) AS prev_day
-- FROM daily_sales;

-- ============================================================
-- 3. 占比（批处理模式）
-- ============================================================

SELECT product_id,
       SUM(amount) AS product_total,
       SUM(amount) / SUM(SUM(amount)) OVER () * 100 AS pct_of_total
FROM daily_sales
GROUP BY product_id;

-- ============================================================
-- 4. 百分位数（使用 OVER 窗口）
-- ============================================================

-- Flink SQL 目前不支持 PERCENTILE_CONT / PERCENTILE_DISC
-- 使用 NTILE 近似
SELECT emp_id, salary,
       NTILE(4) OVER (ORDER BY salary) AS quartile
FROM employee_salaries;

-- ============================================================
-- 5. 累计聚合
-- ============================================================

SELECT sale_date, amount,
       SUM(amount) OVER (ORDER BY proc_time ROWS UNBOUNDED PRECEDING) AS running_total,
       COUNT(*) OVER (ORDER BY proc_time ROWS UNBOUNDED PRECEDING) AS running_count,
       AVG(amount) OVER (ORDER BY proc_time ROWS UNBOUNDED PRECEDING) AS running_avg
FROM daily_sales;

-- ============================================================
-- 6. 窗口 TVF（Table-Valued Function，Flink 1.13+）
-- ============================================================

-- 滚动窗口（TUMBLE）
SELECT window_start, window_end, product_id,
       SUM(amount) AS total_amount,
       COUNT(*) AS order_count
FROM TABLE(
    TUMBLE(TABLE daily_sales, DESCRIPTOR(proc_time), INTERVAL '1' DAY)
)
GROUP BY window_start, window_end, product_id;

-- 滑动窗口（HOP）
SELECT window_start, window_end,
       AVG(amount) AS avg_amount
FROM TABLE(
    HOP(TABLE daily_sales, DESCRIPTOR(proc_time), INTERVAL '1' HOUR, INTERVAL '1' DAY)
)
GROUP BY window_start, window_end;

-- 累积窗口（CUMULATE）
SELECT window_start, window_end,
       SUM(amount) AS cumulative_total
FROM TABLE(
    CUMULATE(TABLE daily_sales, DESCRIPTOR(proc_time),
             INTERVAL '1' HOUR, INTERVAL '1' DAY)
)
GROUP BY window_start, window_end;

-- ============================================================
-- 7. 排名
-- ============================================================

SELECT emp_id, salary,
       RANK() OVER (ORDER BY salary DESC) AS salary_rank,
       DENSE_RANK() OVER (ORDER BY salary DESC) AS dense_rank,
       ROW_NUMBER() OVER (ORDER BY salary DESC) AS row_num
FROM employee_salaries;

-- Flink SQL 窗口函数注意事项：
-- 流处理: OVER 窗口必须有时间属性的 ORDER BY
-- 批处理(1.14+): 支持更多标准窗口函数
-- 窗口 TVF 是 Flink 推荐的窗口处理方式（1.13+）
-- 不支持 PERCENTILE_CONT/DISC
-- LAG/LEAD 支持有限（取决于版本和模式）
