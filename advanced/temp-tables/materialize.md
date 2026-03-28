# Materialize: 临时表与临时存储

> 参考资料:
> - [Materialize Documentation - CREATE VIEW](https://materialize.com/docs/sql/create-view/)
> - [Materialize Documentation - CREATE MATERIALIZED VIEW](https://materialize.com/docs/sql/create-materialized-view/)


## Materialize 不支持传统临时表

使用 VIEW 和 MATERIALIZED VIEW

## 普通视图（虚拟临时数据）


```sql
CREATE VIEW active_users AS
SELECT * FROM users WHERE status = 1;

SELECT * FROM active_users;
DROP VIEW active_users;
```

## 物化视图（持久化临时计算）


```sql
CREATE MATERIALIZED VIEW user_order_stats AS
SELECT u.username, COUNT(o.id) AS order_count, SUM(o.amount) AS total
FROM users u LEFT JOIN orders o ON u.id = o.user_id
GROUP BY u.username;
```

## 自动增量更新

```sql
SELECT * FROM user_order_stats;
```

## CTE


```sql
WITH stats AS (
    SELECT user_id, COUNT(*) AS cnt FROM orders GROUP BY user_id
)
SELECT * FROM stats WHERE cnt > 5;
```

注意：Materialize 使用增量计算模型，没有传统临时表
注意：物化视图自动维护最新结果（增量更新）
注意：普通视图类似临时视图（不存储数据）
注意：CTE 可以组织复杂查询的中间结果
