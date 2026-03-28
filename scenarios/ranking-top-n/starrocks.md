# StarRocks: Top-N 查询

> 参考资料:
> - [1] StarRocks Documentation - Window Functions
>   https://docs.starrocks.io/docs/sql-reference/sql-functions/


全局 Top-N

```sql
SELECT order_id, customer_id, amount FROM orders ORDER BY amount DESC LIMIT 10;

```

分组 Top-N (子查询方式)

```sql
SELECT * FROM (
    SELECT *, ROW_NUMBER() OVER (PARTITION BY customer_id ORDER BY amount DESC) AS rn
    FROM orders
) ranked WHERE rn <= 3;

```

QUALIFY (3.2+，StarRocks 优势):
SELECT *, ROW_NUMBER() OVER (PARTITION BY customer_id ORDER BY amount DESC) AS rn
FROM orders QUALIFY rn <= 3;
无需子查询，更简洁。Doris 不支持。

Pipeline 引擎优化: Local Top-N → Exchange → Global Top-N。

