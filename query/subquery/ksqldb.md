# ksqlDB: 子查询

> 参考资料:
> - [ksqlDB Reference](https://docs.ksqldb.io/en/latest/developer-guide/ksqldb-reference/)
> - [ksqlDB API Reference](https://docs.ksqldb.io/en/latest/developer-guide/api/)
> - ksqlDB 不支持传统的子查询
> - 通过创建中间 STREAM/TABLE 实现类似功能
> - ============================================================
> - 不支持内联子查询
> - ============================================================
> - 以下都不支持：
> - SELECT * FROM orders WHERE user_id IN (SELECT ...);
> - SELECT *, (SELECT ...) FROM orders;
> - SELECT * FROM (SELECT ... FROM orders);
> - SELECT * FROM orders WHERE EXISTS (SELECT ...);
> - ============================================================
> - 替代方案：创建中间 STREAM/TABLE
> - ============================================================
> - 场景：过滤高价值用户的订单
> - 步骤 1：创建中间 TABLE

```sql
CREATE TABLE high_value_users AS
SELECT user_id, SUM(amount) AS total
FROM orders
GROUP BY user_id
HAVING SUM(amount) > 10000
EMIT CHANGES;
```

## 步骤 2：使用中间 TABLE JOIN

```sql
CREATE STREAM high_value_orders AS
SELECT o.order_id, o.amount, o.user_id, h.total
FROM orders o
INNER JOIN high_value_users h ON o.user_id = h.user_id
EMIT CHANGES;
```

## 替代方案：链式 STREAM


## 第一步：过滤

```sql
CREATE STREAM filtered_events AS
SELECT * FROM events WHERE event_type = 'purchase'
EMIT CHANGES;
```

## 第二步：转换

```sql
CREATE STREAM enriched_events AS
SELECT event_id, user_id,
       CAST(EXTRACTJSONFIELD(payload, '$.amount') AS DOUBLE) AS amount
FROM filtered_events
EMIT CHANGES;
```

## 第三步：聚合

```sql
CREATE TABLE purchase_totals AS
SELECT user_id, SUM(amount) AS total_purchases
FROM enriched_events
GROUP BY user_id
EMIT CHANGES;
```

## Pull Query 中的简单过滤（类似子查询效果）


## Pull Query 支持 WHERE 过滤但不支持子查询

```sql
SELECT * FROM user_order_totals WHERE user_id = 'user_123';
```

注意：ksqlDB 不支持任何形式的子查询
注意：通过创建中间 STREAM/TABLE 实现类似功能
注意：每个中间对象都是持久运行的查询
注意：这种模式实际上创建了一个数据管道
