# StarRocks: PIVOT / UNPIVOT

> 参考资料:
> - [1] StarRocks Documentation - SELECT
>   https://docs.starrocks.io/docs/sql-reference/sql-statements/


与 Doris 完全相同: 没有原生 PIVOT/UNPIVOT 语法。

PIVOT: CASE WHEN + GROUP BY

```sql
SELECT product,
    SUM(CASE WHEN quarter = 'Q1' THEN amount ELSE 0 END) AS Q1,
    SUM(CASE WHEN quarter = 'Q2' THEN amount ELSE 0 END) AS Q2,
    SUM(CASE WHEN quarter = 'Q3' THEN amount ELSE 0 END) AS Q3,
    SUM(CASE WHEN quarter = 'Q4' THEN amount ELSE 0 END) AS Q4
FROM sales GROUP BY product;

```

UNPIVOT: UNION ALL

```sql
SELECT product, 'Q1' AS quarter, Q1 AS amount FROM quarterly_sales
UNION ALL SELECT product, 'Q2', Q2 FROM quarterly_sales
UNION ALL SELECT product, 'Q3', Q3 FROM quarterly_sales
UNION ALL SELECT product, 'Q4', Q4 FROM quarterly_sales;

```
