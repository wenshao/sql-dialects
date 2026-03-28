# Teradata: Top-N 查询（排名与分组取前 N 条）

> 参考资料:
> - [Teradata Documentation - Ordered Analytical Functions](https://docs.teradata.com/r/Teradata-VantageTM-SQL-Functions-Expressions-and-Predicates)
> - [Teradata Documentation - QUALIFY](https://docs.teradata.com/r/Teradata-VantageTM-SQL-Data-Manipulation-Language)


## 示例数据上下文

假设表结构:
orders(order_id INTEGER, customer_id INTEGER, amount DECIMAL(10,2), order_date DATE)

## 1. Top-N 整体


TOP 语法
```sql
SELECT TOP 10 order_id, customer_id, amount
FROM orders
ORDER BY amount DESC;
```


TOP WITH TIES
```sql
SELECT TOP 10 WITH TIES order_id, customer_id, amount
FROM orders
ORDER BY amount DESC;
```


SAMPLE（取 N 行，不保证排序）
```sql
SELECT * FROM orders SAMPLE 10;
```


## 2. Top-N 分组 + QUALIFY（Teradata 是 QUALIFY 的发明者）


QUALIFY 直接过滤窗口函数结果
```sql
SELECT order_id, customer_id, amount, order_date
FROM orders
QUALIFY ROW_NUMBER() OVER (
    PARTITION BY customer_id
    ORDER BY amount DESC
) <= 3;
```


QUALIFY + RANK
```sql
SELECT order_id, customer_id, amount, order_date
FROM orders
QUALIFY RANK() OVER (
    PARTITION BY customer_id
    ORDER BY amount DESC
) <= 3;
```


QUALIFY + DENSE_RANK
```sql
SELECT order_id, customer_id, amount, order_date
FROM orders
QUALIFY DENSE_RANK() OVER (
    PARTITION BY customer_id
    ORDER BY amount DESC
) <= 3;
```


QUALIFY 与 WHERE 组合
```sql
SELECT order_id, customer_id, amount, order_date
FROM orders
WHERE order_date >= DATE '2024-01-01'
QUALIFY ROW_NUMBER() OVER (
    PARTITION BY customer_id
    ORDER BY amount DESC
) <= 3;
```


## 3. 传统子查询方式


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


## 4. 关联子查询方式


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


## 5. CTE 方式


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


## 6. 性能考量


Teradata 是 QUALIFY 关键字的发明者（最早支持）
QUALIFY 是 Teradata 推荐的分组 Top-N 方式
使用 PI（Primary Index）优化分组查询
Teradata 的 MPP 架构自动并行窗口函数
TOP WITH TIES 对整体 Top-N 很方便
注意：Teradata 不支持 LATERAL / CROSS APPLY / LIMIT
