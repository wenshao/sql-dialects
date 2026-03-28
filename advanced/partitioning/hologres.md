# Hologres: 表分区策略

> 参考资料:
> - [Hologres Documentation - Partitioned Tables](https://help.aliyun.com/document_detail/200792.html)
> - ============================================================
> - 分区表（兼容 PostgreSQL）
> - ============================================================
> - 创建分区父表

```sql
CREATE TABLE orders (
    id BIGINT, user_id BIGINT, amount NUMERIC, order_date DATE NOT NULL
) PARTITION BY LIST (order_date);
```

## 创建子分区

```sql
CREATE TABLE orders_20240601 PARTITION OF orders
    FOR VALUES IN ('2024-06-01');
CREATE TABLE orders_20240602 PARTITION OF orders
    FOR VALUES IN ('2024-06-02');
```

## Hologres 推荐使用 LIST 分区（按天）

## 设置表属性


## 行存表分区

```sql
BEGIN;
CREATE TABLE row_orders (
    id BIGINT, data TEXT, dt DATE NOT NULL
) PARTITION BY LIST (dt);
CALL set_table_property('row_orders', 'orientation', 'row');
COMMIT;
```

## 列存表分区

```sql
BEGIN;
CREATE TABLE col_orders (
    id BIGINT, amount NUMERIC, dt DATE NOT NULL
) PARTITION BY LIST (dt);
CALL set_table_property('col_orders', 'orientation', 'column');
COMMIT;
```

## 分区管理


## 添加分区

```sql
CREATE TABLE orders_20240603 PARTITION OF orders
    FOR VALUES IN ('2024-06-03');
```

## 删除分区

```sql
DROP TABLE orders_20240601;
```

注意：Hologres 主要使用 LIST 分区（按天/日期值）
注意：行存表和列存表都支持分区
注意：分区裁剪在查询时自动进行
注意：建议使用 DATE 类型作为分区键
