# StarRocks: 窗口函数实战

> 参考资料:
> - [1] StarRocks Documentation - Window Functions


与 Doris 语法完全兼容(同源)。

移动平均

```sql
SELECT sale_date, amount,
    ROUND(AVG(amount) OVER (ORDER BY sale_date ROWS BETWEEN 6 PRECEDING AND CURRENT ROW), 2) AS ma7
FROM daily_sales;

```

环比

```sql
WITH monthly AS (
    SELECT DATE_FORMAT(sale_date, '%Y-%m-01') AS month, SUM(amount) AS total FROM daily_sales
    GROUP BY DATE_FORMAT(sale_date, '%Y-%m-01')
)
SELECT month, total, LAG(total) OVER (ORDER BY month) AS prev,
    ROUND((total - LAG(total) OVER (ORDER BY month)) / NULLIF(LAG(total) OVER (ORDER BY month), 0) * 100, 2) AS mom
FROM monthly;

```

占比

```sql
SELECT product_id, SUM(amount) AS total,
    ROUND(SUM(amount) / SUM(SUM(amount)) OVER () * 100, 2) AS pct
FROM daily_sales GROUP BY product_id;

```

QUALIFY 简化排名过滤(3.2+):
SELECT *, RANK() OVER (ORDER BY salary DESC) AS rnk
FROM employees QUALIFY rnk <= 10;

Pipeline 引擎优化窗口函数并行度。

