# YugabyteDB: TopN 排名查询

> 参考资料:
> - [YugabyteDB Documentation - Window Functions](https://docs.yugabyte.com/latest/api/ysql/exprs/window_functions/)
> - [YugabyteDB Documentation - LIMIT](https://docs.yugabyte.com/latest/api/ysql/the-sql-language/statements/perf_limit/)

**引擎定位**: 分布式 SQL 数据库，兼容 PostgreSQL 协议。基于 DocDB (RocksDB) 存储，Raft 共识。

## 示例数据上下文

假设表结构（兼容 PostgreSQL 语法）:
  orders(order_id SERIAL, customer_id INT, amount DECIMAL(10,2), order_date DATE)

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

## DISTINCT ON（兼容 PostgreSQL）


```sql
SELECT DISTINCT ON (customer_id)
       order_id, customer_id, amount, order_date
FROM orders
ORDER BY customer_id, amount DESC;

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

YugabyteDB 兼容 PostgreSQL 语法（YSQL API）
支持 DISTINCT ON（PostgreSQL 特有功能）
分布式架构，数据自动分片
**注意:** LATERAL 子查询支持有限
