# TimescaleDB: DELETE

> 参考资料:
> - [TimescaleDB API Reference](https://docs.timescale.com/api/latest/)
> - [TimescaleDB Hyperfunctions](https://docs.timescale.com/api/latest/hyperfunctions/)


TimescaleDB 继承 PostgreSQL 全部 DELETE 语法
额外提供 drop_chunks 高效删除整个时间范围
基本删除

```sql
DELETE FROM sensor_data WHERE sensor_id = 1 AND time = '2024-01-15 10:00:00+08';
```

## 按时间范围删除

```sql
DELETE FROM sensor_data WHERE time < '2024-01-01';
DELETE FROM sensor_data WHERE time BETWEEN '2024-01-01' AND '2024-01-31';
```

## 条件删除

```sql
DELETE FROM sensor_data WHERE temperature > 100 AND sensor_id = 1;
```

## 子查询删除

```sql
DELETE FROM sensor_data WHERE sensor_id IN (
    SELECT id FROM devices WHERE status = 'decommissioned'
);
```

## EXISTS 删除

```sql
DELETE FROM sensor_data s
WHERE EXISTS (SELECT 1 FROM blacklist b WHERE b.sensor_id = s.sensor_id);
```

## CTE + DELETE

```sql
WITH old_data AS (
    SELECT DISTINCT sensor_id FROM sensor_data WHERE time < NOW() - INTERVAL '1 year'
)
DELETE FROM sensor_data WHERE sensor_id IN (SELECT sensor_id FROM old_data);
```

## USING 子句（多表删除）

```sql
DELETE FROM sensor_data s
USING devices d
WHERE s.sensor_id = d.id AND d.status = 'removed';
```

## RETURNING

```sql
DELETE FROM sensor_data WHERE sensor_id = 1 AND time < '2024-01-01'
RETURNING *;
```

## drop_chunks（高效删除整个 chunk，推荐）


## 删除指定时间之前的所有 chunk（最高效的方式）

```sql
SELECT drop_chunks('sensor_data', INTERVAL '90 days');
```

## 删除指定时间范围的 chunk

```sql
SELECT drop_chunks('sensor_data',
    older_than => INTERVAL '90 days',
    newer_than => INTERVAL '180 days'
);
```

## 数据保留策略（自动删除）


## 添加自动保留策略（定期删除旧数据）

```sql
SELECT add_retention_policy('sensor_data', INTERVAL '90 days');
```

## 查看保留策略

```sql
SELECT * FROM timescaledb_information.jobs
WHERE proc_name = 'policy_retention';
```

## 移除保留策略

```sql
SELECT remove_retention_policy('sensor_data');
```

## TRUNCATE（清空表）

```sql
TRUNCATE TABLE sensor_data;
```

注意：drop_chunks 比 DELETE 高效得多（直接删除文件）
注意：add_retention_policy 是自动化数据保留的推荐方式
注意：压缩的 chunk 可以直接 drop（无需解压）
注意：DELETE 完全兼容 PostgreSQL 语法
