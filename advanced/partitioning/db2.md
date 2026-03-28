# DB2: 表分区策略

> 参考资料:
> - [IBM Documentation - Range-Partitioned Tables](https://www.ibm.com/docs/en/db2/11.5?topic=tables-range-partitioned)
> - [IBM Documentation - Multidimensional Clustering](https://www.ibm.com/docs/en/db2/11.5?topic=tables-multidimensional-clustering)


## RANGE 分区


```sql
CREATE TABLE orders (
    id BIGINT NOT NULL, user_id BIGINT, amount DECIMAL(10,2),
    order_date DATE NOT NULL
) PARTITION BY RANGE(order_date) (
    PARTITION p2023 STARTING ('2023-01-01') ENDING ('2023-12-31'),
    PARTITION p2024 STARTING ('2024-01-01') ENDING ('2024-12-31'),
    PARTITION p2025 STARTING ('2025-01-01') ENDING ('2025-12-31')
);
```

## 自动生成分区（EVERY 子句）

```sql
CREATE TABLE logs (
    id BIGINT, log_date DATE, message VARCHAR(4000)
) PARTITION BY RANGE(log_date) (
    STARTING ('2024-01-01') ENDING ('2026-01-01') EVERY 1 MONTH
);
```

## 分区管理


```sql
ALTER TABLE orders ADD PARTITION p2026
    STARTING ('2026-01-01') ENDING ('2026-12-31');
ALTER TABLE orders DETACH PARTITION p2023 INTO orders_2023;
ALTER TABLE orders ATTACH PARTITION p_reattach
    STARTING ('2023-01-01') ENDING ('2023-12-31')
    FROM orders_2023;
```

## MDC（多维聚簇）


```sql
CREATE TABLE sales (
    id BIGINT, sale_date DATE, region VARCHAR(20), amount DECIMAL(10,2)
) ORGANIZE BY DIMENSIONS (sale_date, region);
```

## MDC 自动按维度组织数据块，查询时跳过不匹配的块

## 分布键（DPF 环境）


```sql
CREATE TABLE distributed_data (
    id BIGINT, data VARCHAR(1000)
) DISTRIBUTE BY HASH(id);
```

注意：DB2 使用 STARTING/ENDING 语法定义分区范围
注意：EVERY 子句自动生成等间隔分区
注意：MDC（多维聚簇）是 DB2 特有的数据组织方式
注意：DETACH/ATTACH 可以快速移入移出分区数据
注意：DPF 环境中 DISTRIBUTE BY HASH 控制跨节点分布
