# StarRocks: 日期序列填充

> 参考资料:
> - [1] StarRocks Documentation
>   https://docs.starrocks.io/docs/sql-reference/sql-functions/


与 Doris 方案相同: 使用辅助表或递归 CTE 生成序列。

递归 CTE 方式:

```sql
WITH RECURSIVE dates AS (
    SELECT CAST('2024-01-01' AS DATE) AS d
    UNION ALL
    SELECT DATE_ADD(d, INTERVAL 1 DAY) FROM dates WHERE d < '2024-01-10'
)
SELECT d AS date, COALESCE(ds.amount, 0) AS amount
FROM dates LEFT JOIN daily_sales ds ON ds.sale_date = dates.d
ORDER BY date;

```

对比 Doris: Doris 2.1+ 有 numbers() 表函数(更简洁)。
StarRocks 推荐递归 CTE 或预建辅助表。

