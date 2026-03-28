# Vertica: Top-N 查询（排名与分组取前 N 条）

> 参考资料:
> - [Vertica Documentation - Analytic Functions](https://www.vertica.com/docs/latest/HTML/Content/Authoring/SQLReferenceManual/Functions/Analytic/AnalyticFunctions.htm)
> - [Vertica Documentation - LIMIT](https://www.vertica.com/docs/latest/HTML/Content/Authoring/SQLReferenceManual/Statements/SELECT/LIMITClause.htm)


## 示例数据上下文

假设表结构:
orders(order_id INT, customer_id INT, amount DECIMAL(10,2), order_date DATE)

## 1. Top-N 整体


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


## 2. Top-N 分组


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


## 3. 关联子查询方式


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


## 4. CTE 方式


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


## 5. 性能考量


Vertica 是列式 MPP 数据库，窗口函数天然高效
投影（Projection）优化排序：
CREATE PROJECTION orders_by_customer AS
SELECT * FROM orders ORDER BY customer_id, amount DESC;
使用 SEGMENTED BY hash(customer_id) ALL NODES 分布数据
Vertica 窗口函数自动利用投影的排序
注意：Vertica 不支持 LATERAL / CROSS APPLY / QUALIFY
