# SAP HANA: 表分区策略

> 参考资料:
> - [SAP HANA Documentation - Table Partitioning](https://help.sap.com/docs/SAP_HANA_PLATFORM/4fe29514fd584807ac9f2a04f6754767/)
> - ============================================================
> - RANGE 分区
> - ============================================================

```sql
CREATE COLUMN TABLE orders (
    id BIGINT, user_id BIGINT, amount DECIMAL(10,2), order_date DATE
) PARTITION BY RANGE (order_date) (
    PARTITION '2023-01-01' <= VALUES < '2024-01-01',
    PARTITION '2024-01-01' <= VALUES < '2025-01-01',
    PARTITION '2025-01-01' <= VALUES < '2026-01-01',
    PARTITION OTHERS
);
```

## HASH 分区


```sql
CREATE COLUMN TABLE sessions (
    id BIGINT, user_id BIGINT, data NVARCHAR(5000)
) PARTITION BY HASH (user_id) PARTITIONS 8;
```

## ROUNDROBIN 分区


```sql
CREATE COLUMN TABLE logs (
    id BIGINT, message NVARCHAR(5000)
) PARTITION BY ROUNDROBIN PARTITIONS 4;
```

## 多级分区


```sql
CREATE COLUMN TABLE sales (
    id BIGINT, sale_date DATE, region NVARCHAR(20), amount DECIMAL(10,2)
) PARTITION BY RANGE (sale_date) (
    (PARTITION '2024-01-01' <= VALUES < '2025-01-01',
     PARTITION '2025-01-01' <= VALUES < '2026-01-01')
    SUBPARTITION BY HASH (region) PARTITIONS 4
);
```

## 分区管理


## 添加分区

```sql
ALTER TABLE orders ADD PARTITION
    '2026-01-01' <= VALUES < '2027-01-01';
```

## 删除分区

```sql
ALTER TABLE orders DROP PARTITION 1;
```

## 合并分区

```sql
ALTER TABLE orders MERGE PARTITIONS 2, 3;
```

## 移动分区

```sql
ALTER TABLE orders MOVE PARTITION 1 TO 'host:port';
```

## 动态范围分区（HANA 2.0+）


```sql
CREATE COLUMN TABLE auto_partitioned (
    id BIGINT, created_date DATE, data NVARCHAR(5000)
) PARTITION BY RANGE (created_date) (
    PARTITION VALUE = '2024-01-01',
    PARTITION OTHERS DYNAMIC THRESHOLD 1000000
);
```

注意：SAP HANA 支持 RANGE, HASH, ROUNDROBIN 分区
注意：列存储表和行存储表都支持分区
注意：动态范围分区自动根据阈值创建新分区
注意：多级分区结合了 RANGE 和 HASH 策略
注意：分区可以在不同节点间移动（Scale-out）
