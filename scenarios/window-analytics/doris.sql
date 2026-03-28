-- Apache Doris: 窗口函数实战
--
-- 参考资料:
--   [1] Doris Documentation - Window Functions

-- 移动平均
SELECT sale_date, amount,
    ROUND(AVG(amount) OVER (ORDER BY sale_date ROWS BETWEEN 2 PRECEDING AND CURRENT ROW), 2) AS ma3,
    ROUND(AVG(amount) OVER (ORDER BY sale_date ROWS BETWEEN 6 PRECEDING AND CURRENT ROW), 2) AS ma7
FROM daily_sales;

-- 环比
WITH monthly AS (
    SELECT DATE_FORMAT(sale_date, '%Y-%m-01') AS month, SUM(amount) AS total FROM daily_sales
    GROUP BY DATE_FORMAT(sale_date, '%Y-%m-01')
)
SELECT month, total,
    LAG(total) OVER (ORDER BY month) AS prev,
    ROUND((total - LAG(total) OVER (ORDER BY month)) / NULLIF(LAG(total) OVER (ORDER BY month), 0) * 100, 2) AS mom_pct
FROM monthly;

-- 占比
SELECT product_id, SUM(amount) AS total,
    ROUND(SUM(amount) / SUM(SUM(amount)) OVER () * 100, 2) AS pct
FROM daily_sales GROUP BY product_id;

-- 会话化
WITH gaps AS (
    SELECT user_id, event_time, event_type,
        CASE WHEN TIMESTAMPDIFF(MINUTE, LAG(event_time) OVER (PARTITION BY user_id ORDER BY event_time), event_time) > 30
             OR LAG(event_time) OVER (PARTITION BY user_id ORDER BY event_time) IS NULL THEN 1 ELSE 0 END AS new_session
    FROM user_events
),
sessions AS (SELECT *, SUM(new_session) OVER (PARTITION BY user_id ORDER BY event_time) AS session_num FROM gaps)
SELECT user_id, session_num, MIN(event_time) AS start, MAX(event_time) AS end, COUNT(*) AS events
FROM sessions GROUP BY user_id, session_num;

-- 累计分布
SELECT emp_id, salary,
    RANK() OVER (ORDER BY salary) AS rnk,
    PERCENT_RANK() OVER (ORDER BY salary) AS pct,
    NTILE(4) OVER (ORDER BY salary) AS quartile
FROM employee_salaries;
