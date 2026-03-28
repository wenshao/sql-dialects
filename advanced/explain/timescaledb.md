# TimescaleDB: 执行计划与查询分析

> 参考资料:
> - [TimescaleDB Documentation - Query performance](https://docs.timescale.com/timescaledb/latest/how-to-guides/query-data/)
> - [PostgreSQL Documentation - EXPLAIN (TimescaleDB 基于 PostgreSQL)](https://www.postgresql.org/docs/current/sql-explain.html)
> - ============================================================
> - EXPLAIN 基本用法（继承自 PostgreSQL）
> - ============================================================

```sql
EXPLAIN SELECT * FROM sensor_data WHERE time > NOW() - INTERVAL '1 hour';
```

## EXPLAIN ANALYZE


```sql
EXPLAIN ANALYZE SELECT * FROM sensor_data
WHERE time > NOW() - INTERVAL '1 hour';
```

## 完整选项


```sql
EXPLAIN (ANALYZE, BUFFERS, COSTS, TIMING, VERBOSE)
SELECT device_id, AVG(temperature)
FROM sensor_data
WHERE time > NOW() - INTERVAL '1 day'
GROUP BY device_id;
```

## 超表（Hypertable）特有的计划操作


## Chunk 裁剪（基于时间维度）

```sql
EXPLAIN SELECT * FROM sensor_data
WHERE time >= '2024-01-01' AND time < '2024-02-01';
```

输出示例：
Append
> Seq Scan on _hyper_1_10_chunk  (time range chunk)
> Seq Scan on _hyper_1_11_chunk  (time range chunk)
注意：只扫描匹配时间范围的 chunk

## 连续聚合的执行计划


## 查看连续聚合的查询计划

```sql
EXPLAIN SELECT * FROM hourly_sensor_avg
WHERE bucket >= NOW() - INTERVAL '7 days';
```

## 连续聚合使用物化数据 + 实时计算

输出可能包含 UNION ALL（物化部分 + 实时部分）

## 压缩 chunk 的查询


## 压缩 chunk 使用特殊的扫描方式

```sql
EXPLAIN ANALYZE SELECT * FROM sensor_data
WHERE time >= '2023-01-01' AND time < '2023-02-01';
```

压缩的 chunk 可能显示：
Custom Scan (DecompressChunk)
> Seq Scan on compress_hyper_1_20_chunk

## 分布式超表（多节点）


## 分布式查询计划

```sql
EXPLAIN VERBOSE SELECT device_id, AVG(temperature)
FROM distributed_sensor_data
WHERE time > NOW() - INTERVAL '1 day'
GROUP BY device_id;
```

## 可能显示：

Custom Scan (DataNodeScan)  -- 在数据节点执行

## TimescaleDB 特有的诊断


## 查看 chunk 信息

```sql
SELECT chunk_name, range_start, range_end, is_compressed
FROM timescaledb_information.chunks
WHERE hypertable_name = 'sensor_data'
ORDER BY range_start DESC;
```

## 查看超表的维度信息

```sql
SELECT * FROM timescaledb_information.dimensions
WHERE hypertable_name = 'sensor_data';
```

## 查看压缩统计

```sql
SELECT * FROM timescaledb_information.compression_settings
WHERE hypertable_name = 'sensor_data';
```

## 统计信息


## 标准 PostgreSQL ANALYZE

```sql
ANALYZE sensor_data;
```

注意：TimescaleDB 基于 PostgreSQL，EXPLAIN 语法完全相同
注意：超表（Hypertable）的 Chunk 裁剪是关键优化
注意：压缩 chunk 显示 DecompressChunk 自定义扫描
注意：连续聚合可能使用 UNION ALL（物化 + 实时）
注意：分布式超表显示 DataNodeScan 操作
注意：时间维度索引对时序查询性能至关重要
