# Apache Doris: Top-N 查询

Apache Doris: Top-N 查询

参考资料:
[1] Doris Documentation - Window Functions
https://doris.apache.org/docs/sql-manual/sql-functions/window-functions/

全局 Top-N

```sql
SELECT order_id, customer_id, amount FROM orders ORDER BY amount DESC LIMIT 10;

```

分组 Top-N (ROW_NUMBER)

```sql
SELECT * FROM (
    SELECT *, ROW_NUMBER() OVER (PARTITION BY customer_id ORDER BY amount DESC) AS rn
    FROM orders
) ranked WHERE rn <= 3;

```

RANK (允许并列)

```sql
SELECT * FROM (
    SELECT *, RANK() OVER (PARTITION BY customer_id ORDER BY amount DESC) AS rnk
    FROM orders
) ranked WHERE rnk <= 3;

```

CTE 方式

```sql
WITH ranked AS (
    SELECT *, ROW_NUMBER() OVER (PARTITION BY customer_id ORDER BY amount DESC) AS rn
    FROM orders
)
SELECT * FROM ranked WHERE rn <= 3;

```

性能: Doris 自动优化 ORDER BY + LIMIT 为 Top-N(堆排序)。
不支持 QUALIFY(需子查询)。不支持 LATERAL / CROSS APPLY。

