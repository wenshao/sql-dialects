# SQLite: 排名与 Top-N

> 参考资料:
> - [SQLite Documentation - Window Functions](https://www.sqlite.org/windowfunctions.html)
> - [SQLite Documentation - SELECT with LIMIT](https://www.sqlite.org/lang_select.html)

## 示例数据上下文

假设表结构:
  orders(order_id INTEGER PRIMARY KEY, customer_id INTEGER, amount REAL, order_date TEXT)

## Top-N 整体

LIMIT 语法
```sql
SELECT order_id, customer_id, amount
FROM orders
ORDER BY amount DESC
LIMIT 10;
```

LIMIT + OFFSET
```sql
SELECT order_id, customer_id, amount
FROM orders
ORDER BY amount DESC
LIMIT 10 OFFSET 20;
```

## Top-N 分组（SQLite 3.25.0+ 窗口函数）

ROW_NUMBER() 方式（SQLite 3.25.0+, 2018-09-15）
```sql
SELECT *
FROM (
    SELECT order_id, customer_id, amount, order_date,
           ROW_NUMBER() OVER (
               PARTITION BY customer_id
               ORDER BY amount DESC
           ) AS rn
    FROM orders
) ranked
WHERE rn <= 3;
```

RANK() 方式
```sql
SELECT *
FROM (
    SELECT order_id, customer_id, amount, order_date,
           RANK() OVER (
               PARTITION BY customer_id
               ORDER BY amount DESC
           ) AS rnk
    FROM orders
) ranked
WHERE rnk <= 3;
```

DENSE_RANK() 方式
```sql
SELECT *
FROM (
    SELECT order_id, customer_id, amount, order_date,
           DENSE_RANK() OVER (
               PARTITION BY customer_id
               ORDER BY amount DESC
           ) AS drnk
    FROM orders
) ranked
WHERE drnk <= 3;
```

## 无窗口函数的替代方案（SQLite 3.24 及以下）

关联子查询方式
```sql
SELECT o.*
FROM orders o
WHERE (
    SELECT COUNT(*)
    FROM orders o2
    WHERE o2.customer_id = o.customer_id
      AND (o2.amount > o.amount
           OR (o2.amount = o.amount AND o2.order_id < o.order_id))
) < 3
ORDER BY o.customer_id, o.amount DESC;
```

GROUP BY + GROUP_CONCAT 取每组最大值的 ID
```sql
SELECT customer_id,
       MAX(amount) AS max_amount
FROM orders
GROUP BY customer_id
ORDER BY max_amount DESC
LIMIT 10;
```

## CTE + 窗口函数（SQLite 3.8.3+）

```sql
WITH ranked_orders AS (
    SELECT order_id, customer_id, amount, order_date,
           ROW_NUMBER() OVER (
               PARTITION BY customer_id
               ORDER BY amount DESC
           ) AS rn
    FROM orders
)
SELECT order_id, customer_id, amount, order_date
FROM ranked_orders
WHERE rn <= 3;
```

## 性能考量

推荐索引
```sql
CREATE INDEX idx_orders_customer_amount ON orders (customer_id, amount DESC);
```

窗口函数需要 SQLite 3.25.0+（2018-09-15）
CTE 需要 SQLite 3.8.3+（2014-02-03）
关联子查询在 SQLite 中性能尚可（小数据集）
SQLite 不支持 LATERAL / CROSS APPLY / QUALIFY
SQLite 不支持 FETCH FIRST WITH TIES
