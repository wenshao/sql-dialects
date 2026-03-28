# Azure Synapse Analytics: Top-N 查询（排名与分组取前 N 条）

> 参考资料:
> - [Synapse Documentation - Ranking Functions](https://learn.microsoft.com/en-us/azure/synapse-analytics/sql/query-ranking-functions)
> - [Synapse Documentation - TOP](https://learn.microsoft.com/en-us/sql/t-sql/queries/top-transact-sql)


## 示例数据上下文

假设表结构:
orders(order_id INT, customer_id INT, amount DECIMAL(10,2), order_date DATE)
WITH (DISTRIBUTION = HASH(customer_id))

## 1. Top-N 整体


```sql
SELECT TOP 10 order_id, customer_id, amount
FROM orders
ORDER BY amount DESC;

SELECT TOP 10 WITH TIES order_id, customer_id, amount
FROM orders
ORDER BY amount DESC;
```


OFFSET-FETCH（SQL 标准语法）
```sql
SELECT order_id, customer_id, amount
FROM orders
ORDER BY amount DESC
OFFSET 0 ROWS FETCH NEXT 10 ROWS ONLY;
```


## 2. Top-N 分组


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


## 3. CROSS APPLY（兼容 T-SQL）


```sql
SELECT c.customer_id, t.order_id, t.amount
FROM (SELECT DISTINCT customer_id FROM orders) c
CROSS APPLY (
    SELECT TOP 3 order_id, amount
    FROM orders o
    WHERE o.customer_id = c.customer_id
    ORDER BY amount DESC
) t;
```


## 4. 性能考量


DISTRIBUTION = HASH(customer_id) 使分组 Top-N 本地执行
Synapse 兼容 T-SQL 语法
MPP 架构自动并行
注意：Synapse 不支持 QUALIFY / LATERAL
