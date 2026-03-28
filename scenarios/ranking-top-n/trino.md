# Trino: TopN 排名查询

> 参考资料:
> - [Trino Documentation - Window Functions](https://trino.io/docs/current/functions/window.html)
> - [Trino Documentation - SELECT](https://trino.io/docs/current/sql/select.html)

**引擎定位**: 分布式查询引擎（前身 Presto），不存储数据。通过 Connector 查询异构数据源（Hive/Iceberg/RDBMS）。

## 示例数据上下文

假设表结构:
  orders(order_id INTEGER, customer_id INTEGER, amount DECIMAL(10,2), order_date DATE)

## Top-N 整体


```sql
SELECT order_id, customer_id, amount
FROM orders
ORDER BY amount DESC
LIMIT 10;

SELECT order_id, customer_id, amount
FROM orders
ORDER BY amount DESC
OFFSET 20 LIMIT 10;

```

FETCH FIRST（SQL 标准语法）
```sql
SELECT order_id, customer_id, amount
FROM orders
ORDER BY amount DESC
FETCH FIRST 10 ROWS ONLY;

```

FETCH FIRST WITH TIES
```sql
SELECT order_id, customer_id, amount
FROM orders
ORDER BY amount DESC
FETCH FIRST 10 ROWS WITH TIES;

```

## Top-N 分组


ROW_NUMBER() 方式
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

## 关联子查询方式


```sql
SELECT o.*
FROM orders o
WHERE (
    SELECT COUNT(*)
    FROM orders o2
    WHERE o2.customer_id = o.customer_id
      AND o2.amount > o.amount
) < 3
ORDER BY o.customer_id, o.amount DESC;

```

## CTE 方式


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


Trino 是 MPP 查询引擎，窗口函数自动分布式执行
FETCH FIRST WITH TIES 在 Trino 中可用
使用分区表和桶化优化分组 Top-N 查询
Trino 支持多种连接器（Hive, Iceberg, Delta Lake 等）
**注意:** Trino 不支持 LATERAL / CROSS APPLY / QUALIFY
