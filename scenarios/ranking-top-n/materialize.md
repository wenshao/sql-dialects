# Materialize: Top-N 查询（排名与分组取前 N 条）

> 参考资料:
> - [Materialize Documentation - Window Functions](https://materialize.com/docs/sql/functions/#window-functions)
> - [Materialize Documentation - SELECT](https://materialize.com/docs/sql/select/)
> - ============================================================
> - 示例数据上下文
> - ============================================================
> - 假设表结构（兼容 PostgreSQL 语法）:
> - orders(order_id INT, customer_id INT, amount DECIMAL(10,2), order_date TIMESTAMP)
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

## 物化视图（Materialize 特色：增量维护）


## 创建 Top-N 物化视图（自动增量更新）

```sql
CREATE MATERIALIZED VIEW top_orders_per_customer AS
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

## 查询物化视图（毫秒级响应）

```sql
SELECT * FROM top_orders_per_customer;
```

## DISTINCT ON（兼容 PostgreSQL）


```sql
SELECT DISTINCT ON (customer_id)
       order_id, customer_id, amount, order_date
FROM orders
ORDER BY customer_id, amount DESC;
```

## 性能考量


Materialize 增量维护物化视图，Top-N 查询毫秒级响应
窗口函数在物化视图中自动增量计算
兼容 PostgreSQL 语法（包括 DISTINCT ON）
适合实时 Top-N 排行榜场景
注意：不支持 QUALIFY / CROSS APPLY
