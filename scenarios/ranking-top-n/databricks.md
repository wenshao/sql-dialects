# Databricks (Spark SQL): Top-N 查询（排名与分组取前 N 条）

> 参考资料:
> - [Databricks SQL Reference - Window Functions](https://docs.databricks.com/sql/language-manual/sql-ref-functions-builtin.html)
> - [Databricks SQL Reference - QUALIFY](https://docs.databricks.com/sql/language-manual/sql-ref-syntax-qry-select-qualify.html)


## 示例数据上下文

假设表结构:
orders(order_id INT, customer_id INT, amount DECIMAL(10,2), order_date DATE)

## 1. Top-N 整体


```sql
SELECT order_id, customer_id, amount
FROM orders
ORDER BY amount DESC
LIMIT 10;
```


## 2. Top-N 分组 + QUALIFY（Databricks 支持）


QUALIFY 直接过滤（Databricks Runtime 12.2+）
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


## 4. LATERAL VIEW（Databricks/Spark 独有）


使用 collect_list + slice 取每组前 N
```sql
SELECT customer_id, top_order.*
FROM (
    SELECT customer_id,
           slice(
               sort_array(collect_list(struct(amount, order_id, order_date)), false),
               1, 3
           ) AS top_orders
    FROM orders
    GROUP BY customer_id
)
LATERAL VIEW explode(top_orders) AS top_order;
```


## 5. 关联子查询方式


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


## 6. 性能考量


QUALIFY 是 Databricks 推荐方式（12.2+）
Delta 表的 Z-ORDER 可优化分组查询
```sql
OPTIMIZE orders ZORDER BY (customer_id);
```

Photon 引擎自动优化窗口函数执行
大表建议使用分区 + Z-ORDER
注意：Databricks 不支持传统 LATERAL 子查询语法
