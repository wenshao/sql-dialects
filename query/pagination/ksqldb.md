# ksqlDB: 分页

> 参考资料:
> - [ksqlDB Reference](https://docs.ksqldb.io/en/latest/developer-guide/ksqldb-reference/)
> - [ksqlDB API Reference](https://docs.ksqldb.io/en/latest/developer-guide/api/)


## ksqlDB 的分页能力非常有限

Push Query 是流式的，Pull Query 支持有限的 LIMIT

## Pull Query（LIMIT 支持）


## LIMIT

```sql
SELECT * FROM user_order_totals LIMIT 10;
```

## Pull Query 按 KEY 查询

```sql
SELECT * FROM users WHERE user_id = 'user_123';
```

## 范围查询（有限支持）

```sql
SELECT * FROM windowed_counts
WHERE user_id = 'user_123'
    AND WINDOWSTART >= '2024-01-15T00:00:00'
    AND WINDOWEND <= '2024-01-16T00:00:00'
LIMIT 24;
```

## Push Query（流式，无分页概念）


## Push Query 持续推送所有结果，没有分页

```sql
SELECT * FROM orders EMIT CHANGES;
```

## LIMIT 在 Push Query 中限制返回的消息总数

```sql
SELECT * FROM orders EMIT CHANGES LIMIT 100;
```

## 不支持的分页操作


不支持 OFFSET
SELECT * FROM users LIMIT 10 OFFSET 20;  -- 不支持
不支持 FETCH FIRST
不支持 ROW_NUMBER（无窗口函数）
不支持游标分页

## 替代方案


方案 1：在应用层实现分页
拉取所有数据后在客户端分页
方案 2：使用窗口限制数据量

```sql
CREATE TABLE recent_orders AS
SELECT user_id, COUNT(*) AS cnt
FROM orders
WINDOW TUMBLING (SIZE 1 HOUR)
GROUP BY user_id
EMIT CHANGES;
```

方案 3：使用 Kafka Consumer 直接消费特定 offset
通过 Kafka Consumer API 实现更精确的分页
注意：ksqlDB 不是为分页查询设计的
注意：Pull Query 支持 LIMIT 但不支持 OFFSET
注意：Push Query 是流式的，LIMIT 限制消息总数
注意：精确分页建议在应用层实现
