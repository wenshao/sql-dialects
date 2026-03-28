# IBM Db2: Top-N 查询（排名与分组取前 N 条）

> 参考资料:
> - [IBM Db2 Documentation - OLAP Functions](https://www.ibm.com/docs/en/db2/11.5?topic=functions-olap-window)
> - [IBM Db2 Documentation - FETCH FIRST](https://www.ibm.com/docs/en/db2/11.5?topic=clause-fetch-first)
> - ============================================================
> - 示例数据上下文
> - ============================================================
> - 假设表结构:
> - orders(order_id INTEGER, customer_id INTEGER, amount DECIMAL(10,2), order_date DATE)
> - ============================================================
> - 1. Top-N 整体
> - ============================================================
> - FETCH FIRST（Db2 经典语法）

```sql
SELECT order_id, customer_id, amount
FROM orders
ORDER BY amount DESC
FETCH FIRST 10 ROWS ONLY;
```

## 分页（Db2 11.1+）

```sql
SELECT order_id, customer_id, amount
FROM orders
ORDER BY amount DESC
OFFSET 20 ROWS FETCH FIRST 10 ROWS ONLY;
```

## LIMIT 语法（Db2 11.5+）

```sql
SELECT order_id, customer_id, amount
FROM orders
ORDER BY amount DESC
LIMIT 10;
```

## Top-N 分组


## ROW_NUMBER() 方式

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

## RANK() 方式

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

## DENSE_RANK() 方式

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

## LATERAL 子查询


```sql
SELECT c.customer_id, t.order_id, t.amount
FROM (SELECT DISTINCT customer_id FROM orders) c,
LATERAL (
    SELECT order_id, amount
    FROM orders o
    WHERE o.customer_id = c.customer_id
    ORDER BY amount DESC
    FETCH FIRST 3 ROWS ONLY
) t;
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


```sql
CREATE INDEX idx_orders_customer_amount ON orders (customer_id, amount DESC);
```

Db2 的 OLAP 函数（窗口函数）支持非常早（Db2 V7+）
LATERAL 子查询在 Db2 中表现良好
FETCH FIRST 是 Db2 标准分页语法
LIMIT 从 Db2 11.5 开始支持（兼容 MySQL/PostgreSQL 语法）
注意：Db2 不支持 QUALIFY / CROSS APPLY
