# TimescaleDB: UPDATE

> 参考资料:
> - [TimescaleDB API Reference](https://docs.timescale.com/api/latest/)
> - [TimescaleDB Hyperfunctions](https://docs.timescale.com/api/latest/hyperfunctions/)
> - TimescaleDB 继承 PostgreSQL 全部 UPDATE 语法
> - 注意：压缩的 chunk 不能直接 UPDATE
> - 基本更新

```sql
UPDATE sensor_data SET temperature = 25.0 WHERE sensor_id = 1 AND time = '2024-01-15 10:00:00+08';
```

## 多列更新

```sql
UPDATE sensor_data SET temperature = 25.0, humidity = 60.0
WHERE sensor_id = 1 AND time = '2024-01-15 10:00:00+08';
```

## 条件更新

```sql
UPDATE sensor_data SET temperature = temperature * 1.1
WHERE sensor_id = 1 AND temperature < 0;
```

## 带时间范围的更新

```sql
UPDATE sensor_data SET humidity = 50.0
WHERE time BETWEEN '2024-01-01' AND '2024-01-31'
    AND sensor_id = 1;
```

## 子查询更新

```sql
UPDATE sensor_data SET temperature = (
    SELECT AVG(temperature) FROM sensor_data WHERE sensor_id = 1
)
WHERE temperature IS NULL AND sensor_id = 1;
```

## FROM 子句（多表更新）

```sql
UPDATE sensor_data s
SET location = d.site_name
FROM devices d
WHERE s.sensor_id = d.id;
```

## CTE + UPDATE

```sql
WITH avg_readings AS (
    SELECT sensor_id, AVG(temperature) AS avg_temp
    FROM sensor_data
    GROUP BY sensor_id
)
UPDATE sensor_data s
SET temperature = a.avg_temp
FROM avg_readings a
WHERE s.sensor_id = a.sensor_id AND s.temperature IS NULL;
```

## RETURNING

```sql
UPDATE sensor_data SET temperature = 25.0
WHERE sensor_id = 1 AND time = '2024-01-15 10:00:00+08'
RETURNING *;
```

## CASE 表达式

```sql
UPDATE sensor_data SET status = CASE
    WHEN temperature > 100 THEN 'critical'
    WHEN temperature > 50 THEN 'warning'
    ELSE 'normal'
END
WHERE time > NOW() - INTERVAL '1 day';
```

## 压缩 chunk 的更新（需先解压）


## 查看压缩状态

```sql
SELECT * FROM timescaledb_information.compressed_chunk_stats;
```

## 解压后才能更新

```sql
SELECT decompress_chunk(c) FROM show_chunks('sensor_data',
    older_than => INTERVAL '7 days') c;
```

## 更新解压后的数据

```sql
UPDATE sensor_data SET temperature = 25.0
WHERE time < NOW() - INTERVAL '7 days' AND sensor_id = 1;
```

## 重新压缩

```sql
SELECT compress_chunk(c) FROM show_chunks('sensor_data',
    older_than => INTERVAL '7 days') c;
```

注意：完全兼容 PostgreSQL 的 UPDATE 语法
注意：压缩的 chunk 不能直接 UPDATE，需先解压
注意：时序数据通常追加为主，UPDATE 操作较少
注意：大范围 UPDATE 可能跨多个 chunk，影响性能
