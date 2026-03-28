# TimescaleDB: Top-N 查询（排名与分组取前 N 条）

> 参考资料:
> - [TimescaleDB Documentation - Window Functions](https://docs.timescale.com/)
> - [PostgreSQL Documentation - Window Functions](https://www.postgresql.org/docs/current/tutorial-window.html)


## 示例数据上下文

假设表结构（基于 PostgreSQL + 超表）:
orders(order_id SERIAL, customer_id INT, amount NUMERIC(10,2), order_date TIMESTAMPTZ)
SELECT create_hypertable('orders', 'order_date');

## Top-N 整体


```sql
SELECT order_id, customer_id, amount
FROM orders
ORDER BY amount DESC
LIMIT 10;
```

## FETCH FIRST WITH TIES（PostgreSQL 13+）

```sql
SELECT order_id, customer_id, amount
FROM orders
ORDER BY amount DESC
FETCH FIRST 10 ROWS WITH TIES;
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
```

## DISTINCT ON（继承 PostgreSQL）


```sql
SELECT DISTINCT ON (customer_id)
       order_id, customer_id, amount, order_date
FROM orders
ORDER BY customer_id, amount DESC;
```

## LATERAL 子查询（继承 PostgreSQL）


```sql
SELECT c.customer_id, t.order_id, t.amount
FROM (SELECT DISTINCT customer_id FROM orders) c
CROSS JOIN LATERAL (
    SELECT order_id, amount
    FROM orders o
    WHERE o.customer_id = c.customer_id
    ORDER BY amount DESC
    LIMIT 3
) t;
```

## TimescaleDB 特色：按时间分桶的 Top-N


## 每小时内金额最大的前 3 笔订单

```sql
SELECT *
FROM (
    SELECT order_id, customer_id, amount, order_date,
           time_bucket('1 hour', order_date) AS bucket,
           ROW_NUMBER() OVER (
               PARTITION BY time_bucket('1 hour', order_date)
               ORDER BY amount DESC
           ) AS rn
    FROM orders
) ranked
WHERE rn <= 3;
```

## 性能考量


```sql
CREATE INDEX idx_orders_customer_amount ON orders (customer_id, amount DESC);
```

TimescaleDB 完全兼容 PostgreSQL，支持所有 PostgreSQL 特性
超表按时间分区，时间范围查询自动修剪
支持 DISTINCT ON, LATERAL, CTE 等 PostgreSQL 特性
time_bucket 配合窗口函数实现时序 Top-N
