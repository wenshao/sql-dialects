# KingbaseES: Top-N 查询（排名与分组取前 N 条）

> 参考资料:
> - [KingbaseES Documentation](https://help.kingbase.com.cn/v8/index.html)
> - [KingbaseES SQL Reference](https://help.kingbase.com.cn/v8/development/sql/index.html)
> - ============================================================
> - 示例数据上下文
> - ============================================================
> - 假设表结构（兼容 PostgreSQL/Oracle 语法）:
> - orders(order_id SERIAL, customer_id INT, amount NUMERIC(10,2), order_date DATE)
> - ============================================================
> - 1. Top-N 整体
> - ============================================================

```sql
SELECT order_id, customer_id, amount
FROM orders
ORDER BY amount DESC
LIMIT 10;

SELECT order_id, customer_id, amount
FROM orders
ORDER BY amount DESC
FETCH FIRST 10 ROWS ONLY;
```

## Top-N 分组


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


```sql
CREATE INDEX idx_orders_customer_amount ON orders (customer_id, amount DESC);
```

KingbaseES 是国产数据库，兼容 PostgreSQL 和 Oracle 语法
支持窗口函数、CTE
注意：具体特性取决于兼容模式（PostgreSQL 或 Oracle）
