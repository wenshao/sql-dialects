# TiDB: TopN 排名查询

> 参考资料:
> - [TiDB Documentation - Window Functions](https://docs.pingcap.com/tidb/stable/window-functions)
> - [TiDB Documentation - LIMIT](https://docs.pingcap.com/tidb/stable/sql-statement-select)

**引擎定位**: 分布式 HTAP 数据库，兼容 MySQL 协议。基于 TiKV 行存 + TiFlash 列存，Raft 共识。

## 示例数据上下文

假设表结构（兼容 MySQL 语法）:
  orders(order_id INT AUTO_INCREMENT, customer_id INT, amount DECIMAL(10,2), order_date DATE)

## Top-N 整体


```sql
SELECT order_id, customer_id, amount
FROM orders
ORDER BY amount DESC
LIMIT 10;

SELECT order_id, customer_id, amount
FROM orders
ORDER BY amount DESC
LIMIT 10 OFFSET 20;

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

TiDB 兼容 MySQL 语法，支持窗口函数
TiDB 分布式架构自动下推窗口计算到 TiKV/TiFlash
TiFlash 列式副本对 Top-N 查询更高效
**注意:** TiDB 不支持 LATERAL / CROSS APPLY / QUALIFY
