# Materialize: 表分区策略

> 参考资料:
> - [Materialize Documentation](https://materialize.com/docs/)


## Materialize 不支持传统表分区

使用索引和物化视图优化

## 索引（Arrangement）


```sql
CREATE INDEX idx_orders_date ON orders (order_date);
```

## 物化视图（分区替代）


## 通过物化视图预计算不同时间段的聚合

```sql
CREATE MATERIALIZED VIEW monthly_stats AS
SELECT DATE_TRUNC('month', order_date) AS month,
       SUM(amount) AS total, COUNT(*) AS cnt
FROM orders GROUP BY DATE_TRUNC('month', order_date);
```

注意：Materialize 使用增量计算，不需要传统分区
注意：索引（Arrangement）优化特定查询模式
注意：物化视图自动维护计算结果
