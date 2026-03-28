# ksqlDB: JOIN

> 参考资料:
> - [ksqlDB Reference](https://docs.ksqldb.io/en/latest/developer-guide/ksqldb-reference/)
> - [ksqlDB API Reference](https://docs.ksqldb.io/en/latest/developer-guide/api/)


## ksqlDB 支持特定类型的 JOIN

不同组合（Stream-Table, Table-Table, Stream-Stream）有不同规则

## Stream-Table JOIN（最常用）


## STREAM LEFT JOIN TABLE（丰富流数据）

```sql
CREATE STREAM enriched_orders AS
SELECT o.order_id, o.amount, o.product,
       u.username, u.email, u.region
FROM orders o
LEFT JOIN users u ON o.user_id = u.user_id
EMIT CHANGES;
```

## STREAM INNER JOIN TABLE

```sql
CREATE STREAM valid_orders AS
SELECT o.order_id, o.amount, u.username
FROM orders o
INNER JOIN users u ON o.user_id = u.user_id
EMIT CHANGES;
```

## Table-Table JOIN


## TABLE JOIN TABLE

```sql
CREATE TABLE user_product_info AS
SELECT u.user_id, u.username, p.name AS product_name, p.price
FROM user_preferences u
JOIN products p ON u.product_id = p.product_id
EMIT CHANGES;
```

## Stream-Stream JOIN（需要窗口）


## 两个 STREAM JOIN 必须指定 WITHIN 窗口

```sql
CREATE STREAM order_payments AS
SELECT o.order_id, o.amount, p.payment_method, p.payment_time
FROM orders o
INNER JOIN payments p
    WITHIN 1 HOUR
    ON o.order_id = p.order_id
EMIT CHANGES;
```

## WITHIN + GRACE PERIOD

```sql
CREATE STREAM matched_events AS
SELECT a.event_id, b.event_id, a.user_id
FROM clicks a
INNER JOIN impressions b
    WITHIN 30 MINUTES GRACE PERIOD 10 MINUTES
    ON a.user_id = b.user_id
EMIT CHANGES;
```

## LEFT JOIN（Stream-Stream）

```sql
CREATE STREAM unmatched_orders AS
SELECT o.order_id, o.amount, p.payment_method
FROM orders o
LEFT JOIN payments p
    WITHIN 24 HOURS
    ON o.order_id = p.order_id
EMIT CHANGES;
```

## 多表 JOIN


## Stream JOIN Table JOIN Table

```sql
CREATE STREAM fully_enriched AS
SELECT o.order_id, o.amount,
       u.username, u.region,
       p.name AS product_name
FROM orders o
LEFT JOIN users u ON o.user_id = u.user_id
LEFT JOIN products p ON o.product_id = p.product_id
EMIT CHANGES;
```

## 不支持的 JOIN


不支持 RIGHT JOIN
不支持 FULL OUTER JOIN
不支持 CROSS JOIN
不支持非等值 JOIN
Stream-Stream JOIN 必须有 WITHIN 窗口
注意：Stream-Table JOIN 最常用，用于丰富流数据
注意：Stream-Stream JOIN 必须指定 WITHIN 时间窗口
注意：JOIN 条件必须基于 KEY/PRIMARY KEY
注意：所有 JOIN 都创建持久查询
注意：不支持 RIGHT JOIN 和 FULL OUTER JOIN
