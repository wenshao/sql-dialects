# ksqlDB: 触发器

ksqlDB 不支持触发器
持久查询本身就是"触发器"——当数据到达时自动处理
============================================================
持久查询（类似 AFTER INSERT 触发器）
============================================================
当 orders 有新数据时自动过滤高价值订单

```sql
CREATE STREAM high_value_orders AS
SELECT * FROM orders WHERE amount > 1000
EMIT CHANGES;
```

## 当有新订单时自动更新统计

```sql
CREATE TABLE user_totals AS
SELECT user_id, COUNT(*) AS cnt, SUM(amount) AS total
FROM orders
GROUP BY user_id
EMIT CHANGES;
```

## 当有新数据时自动丰富（JOIN）

```sql
CREATE STREAM enriched_orders AS
SELECT o.order_id, o.amount, u.username, u.email
FROM orders o
LEFT JOIN users u ON o.user_id = u.user_id
EMIT CHANGES;
```

## 事件驱动（类似触发器回调）


## 创建告警 STREAM

```sql
CREATE STREAM alerts AS
SELECT order_id, user_id, amount,
       'high_value_alert' AS alert_type,
       TIMESTAMPTOSTRING(ROWTIME, 'yyyy-MM-dd HH:mm:ss') AS alert_time
FROM orders
WHERE amount > 10000
EMIT CHANGES;
```

## alerts 的数据会写入 Kafka topic

下游消费者（邮件服务、短信服务等）消费告警

## 管理持久查询


```sql
SHOW QUERIES;
EXPLAIN <query_id>;
TERMINATE <query_id>;
```

注意：ksqlDB 不支持触发器
注意：持久查询 = 数据到达时自动执行 = 类似触发器
注意：每个持久查询都是独立运行的
注意：通过 Kafka topic 传递事件到下游消费者
