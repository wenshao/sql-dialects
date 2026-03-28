# Firebird: 表分区策略

> 参考资料:
> - [Firebird Documentation](https://firebirdsql.org/file/documentation/)


## Firebird 不支持表分区

替代方案：

## 手动分表


```sql
CREATE TABLE orders_2023 (
    id BIGINT NOT NULL, user_id BIGINT, amount DECIMAL(10,2), order_date DATE
);
CREATE TABLE orders_2024 (
    id BIGINT NOT NULL, user_id BIGINT, amount DECIMAL(10,2), order_date DATE
);
```

## 使用视图统一查询

```sql
CREATE VIEW orders AS
SELECT * FROM orders_2023
UNION ALL
SELECT * FROM orders_2024;
```

## 索引优化（替代分区裁剪）


```sql
CREATE INDEX idx_orders_date ON orders_2024(order_date);
```

注意：Firebird 不支持表分区
注意：手动分表 + 视图是常用替代方案
注意：索引可以部分替代分区裁剪的效果
