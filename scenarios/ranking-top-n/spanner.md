# Spanner: TopN 排名查询

> 参考资料:
> - [Spanner Documentation - Analytic Functions](https://cloud.google.com/spanner/docs/reference/standard-sql/analytic-function-concepts)
> - [Spanner Documentation - LIMIT](https://cloud.google.com/spanner/docs/reference/standard-sql/query-syntax#limit_and_offset_clause)

**引擎定位**: Google 全球分布式数据库，TrueTime 外部一致性。基于 Colossus 存储，支持跨洲强一致事务。

## 示例数据上下文

假设表结构:
  orders(order_id INT64, customer_id INT64, amount NUMERIC, order_date DATE)

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


Spanner 的交错表（Interleaved Table）优化父子关系查询
使用二级索引优化排序：
  CREATE INDEX idx_orders_by_amount ON orders(customer_id, amount DESC);
Spanner 全球分布式，自动分片
**注意:** Spanner 不支持 LATERAL / CROSS APPLY / QUALIFY
