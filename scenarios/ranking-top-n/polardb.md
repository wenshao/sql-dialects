# PolarDB: Top-N 查询（排名与分组取前 N 条）

> 参考资料:
> - [PolarDB-MySQL Documentation](https://help.aliyun.com/product/172538.html)
> - [PolarDB-PostgreSQL Documentation](https://help.aliyun.com/product/173613.html)


## 示例数据上下文

假设表结构（MySQL 兼容模式）:
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

PolarDB 是阿里云的云原生数据库
兼容 MySQL/PostgreSQL（取决于版本）
共享存储架构，读写分离
并行查询优化窗口函数执行
