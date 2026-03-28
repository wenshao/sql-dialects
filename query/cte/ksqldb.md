# ksqlDB: CTE（公共表表达式）

> 参考资料:
> - [ksqlDB Reference](https://docs.ksqldb.io/en/latest/developer-guide/ksqldb-reference/)
> - [ksqlDB API Reference](https://docs.ksqldb.io/en/latest/developer-guide/api/)


## ksqlDB 不支持传统的 CTE（WITH 子句）

通过创建中间 STREAM/TABLE 实现类似功能

## 中间 STREAM/TABLE 替代 CTE


CTE 方式（不支持）：
WITH filtered AS (SELECT * FROM events WHERE type = 'click')
SELECT user_id, COUNT(*) FROM filtered GROUP BY user_id;
替代方案：创建中间 STREAM + 聚合 TABLE

```sql
CREATE STREAM click_events AS
SELECT * FROM events WHERE event_type = 'click'
EMIT CHANGES;

CREATE TABLE click_counts AS
SELECT user_id, COUNT(*) AS click_count
FROM click_events
GROUP BY user_id
EMIT CHANGES;
```

## 多步数据管道（替代 CTE 链）


## 步骤 1：过滤和转换

```sql
CREATE STREAM cleaned_orders AS
SELECT order_id, user_id,
       CAST(amount AS DOUBLE) AS amount,
       product
FROM orders
WHERE amount > 0
EMIT CHANGES;
```

## 步骤 2：丰富数据

```sql
CREATE STREAM enriched_orders AS
SELECT o.order_id, o.amount, o.product,
       u.username, u.region
FROM cleaned_orders o
LEFT JOIN users u ON o.user_id = u.user_id
EMIT CHANGES;
```

## 步骤 3：聚合

```sql
CREATE TABLE region_totals AS
SELECT region,
       COUNT(*) AS order_count,
       SUM(amount) AS total_amount
FROM enriched_orders
GROUP BY region
EMIT CHANGES;
```

## 内联查询（Pull Query 中的简单替代）


## Pull Query 不支持 CTE，只能直接查询物化 TABLE

```sql
SELECT * FROM region_totals WHERE region = 'US';
```

## 递归查询（不支持）


ksqlDB 不支持递归 CTE
流式系统通常不需要递归查询
注意：ksqlDB 不支持 CTE（WITH 子句）
注意：通过创建中间 STREAM/TABLE 链实现管道
注意：每个中间对象都是持久运行的查询
注意：这种模式比 CTE 更灵活（可独立监控、调试）
注意：但也更消耗资源（每个中间对象都占用资源）
