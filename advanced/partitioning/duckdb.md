# DuckDB: 分区

> 参考资料:
> - [DuckDB Documentation - Hive Partitioning](https://duckdb.org/docs/data/partitioning/hive_partitioning)
> - [DuckDB Documentation - Partitioned Writes](https://duckdb.org/docs/data/partitioning/partitioned_writes)

**引擎定位**: 嵌入式 OLAP 分析引擎，类似 SQLite 的定位。列式存储 + 向量化执行，PostgreSQL 兼容语法。

## 读取 Hive 分区数据


读取 Hive 风格分区的 Parquet 文件
```sql
SELECT * FROM read_parquet('data/orders/year=*/month=*/*.parquet',
    hive_partitioning = true);

```

分区裁剪
```sql
SELECT * FROM read_parquet('data/orders/year=*/month=*/*.parquet',
    hive_partitioning = true)
WHERE year = 2024 AND month = 6;

```

## 写入分区数据


按分区写入 Parquet
```sql
COPY (SELECT *, YEAR(order_date) AS year, MONTH(order_date) AS month
      FROM orders)
TO 'output/orders' (FORMAT PARQUET, PARTITION_BY (year, month));

```

使用 COPY 语句写入分区 CSV
```sql
COPY orders TO 'output/orders' (FORMAT CSV, PARTITION_BY (region));

```

## 视图组织（替代分区）


```sql
CREATE VIEW partitioned_orders AS
SELECT *, YEAR(order_date) AS year FROM orders;

SELECT * FROM partitioned_orders WHERE year = 2024;

```

**注意:** DuckDB 不支持表级分区
**注意:** 通过 Hive 分区格式读写外部文件实现分区
**注意:** hive_partitioning = true 启用分区裁剪
**注意:** PARTITION_BY 参数控制输出文件的分区方式
**注意:** DuckDB 主要用于分析，通过文件分区管理大数据集
