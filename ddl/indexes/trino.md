# Trino: 索引

> 参考资料:
> - [Trino - Connectors](https://trino.io/docs/current/connector.html)
> - [Trino - SQL Statement List](https://trino.io/docs/current/sql.html)

**引擎定位**: 分布式查询引擎（前身 Presto），不存储数据。通过 Connector 查询异构数据源（Hive/Iceberg/RDBMS）。

## Hive Connector: 分区和文件格式优化


分区表（最主要的优化手段）
```sql
CREATE TABLE hive.mydb.orders (
    id         BIGINT,
    user_id    BIGINT,
    amount     DECIMAL(10,2)
)
WITH (
    format = 'ORC',
    partitioned_by = ARRAY['dt']
);

```

ORC 和 Parquet 文件内置列统计信息（min/max/count）
Trino 自动利用这些信息进行谓词下推
选择合适的文件格式就是最好的"索引"

收集统计信息
```sql
ANALYZE hive.mydb.orders;

```

## Iceberg Connector: 分区和排序优化


Iceberg 分区演进（不需要重写数据）
```sql
CREATE TABLE iceberg.mydb.orders (
    id         BIGINT,
    user_id    BIGINT,
    amount     DECIMAL(10,2),
    order_date DATE
)
WITH (
    format = 'PARQUET',
    partitioning = ARRAY['month(order_date)'],
    sorted_by = ARRAY['user_id']
);

```

Iceberg 分区转换：
year(col), month(col), day(col), hour(col)
bucket(N, col)
truncate(N, col)

## Delta Lake Connector: Z-Order 优化


Delta Lake 支持 Z-Order 优化（通过 Spark 执行）
Trino 读取时自动利用 Delta 的统计信息

## 表统计信息（通用）


查看表统计信息
```sql
SHOW STATS FOR orders;

```

收集统计信息（取决于 Connector）
```sql
ANALYZE orders;

```

## 查询优化替代方案


## 选择合适的文件格式（ORC/Parquet 的列裁剪和谓词下推）

## 合理分区（避免过多小分区）

## 排序（Iceberg sorted_by 或 ORC/Parquet 内的排序）

## 分桶（Hive bucketed_by）

## 物化视图（部分 Connector 支持）


**注意:** Trino 本身不存储数据，没有索引概念
**注意:** 性能优化依赖底层数据格式的特性
**注意:** 谓词下推（Predicate Pushdown）是 Trino 最重要的优化
**注意:** 选择 ORC/Parquet 格式比 CSV/JSON 有数量级的性能提升
