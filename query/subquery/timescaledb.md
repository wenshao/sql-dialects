# TimescaleDB: 子查询

> 参考资料:
> - [TimescaleDB API Reference](https://docs.timescale.com/api/latest/)
> - [TimescaleDB Hyperfunctions](https://docs.timescale.com/api/latest/hyperfunctions/)


## TimescaleDB 继承 PostgreSQL 全部子查询功能

标量子查询

```sql
SELECT sensor_id,
    (SELECT name FROM devices WHERE id = sensor_data.sensor_id) AS device_name
FROM sensor_data;
```

## WHERE 子查询

```sql
SELECT * FROM sensor_data WHERE sensor_id IN (
    SELECT id FROM devices WHERE status = 'active'
);
```

## EXISTS

```sql
SELECT * FROM devices d
WHERE EXISTS (
    SELECT 1 FROM sensor_data s
    WHERE s.sensor_id = d.id AND s.time > NOW() - INTERVAL '1 hour'
);
```

## NOT EXISTS（查找无数据的设备）

```sql
SELECT * FROM devices d
WHERE NOT EXISTS (
    SELECT 1 FROM sensor_data s WHERE s.sensor_id = d.id
);
```

## 比较运算符 + 子查询

```sql
SELECT * FROM sensor_data
WHERE temperature > (SELECT AVG(temperature) FROM sensor_data);
```

## FROM 子查询

```sql
SELECT t.sensor_id, t.avg_temp FROM (
    SELECT sensor_id, AVG(temperature) AS avg_temp
    FROM sensor_data
    WHERE time > NOW() - INTERVAL '24 hours'
    GROUP BY sensor_id
) t WHERE t.avg_temp > 30;
```

## 关联子查询

```sql
SELECT s.sensor_id, s.time, s.temperature,
    (SELECT MAX(temperature) FROM sensor_data
     WHERE sensor_id = s.sensor_id AND time > NOW() - INTERVAL '1 day') AS daily_max
FROM sensor_data s;
```

## LATERAL 子查询

```sql
SELECT d.name, latest.*
FROM devices d
CROSS JOIN LATERAL (
    SELECT time, temperature
    FROM sensor_data s
    WHERE s.sensor_id = d.id
    ORDER BY time DESC
    LIMIT 1
) latest;
```

## ANY / ALL

```sql
SELECT * FROM sensor_data
WHERE temperature > ALL (
    SELECT AVG(temperature) FROM sensor_data GROUP BY sensor_id
);
```

## 时序特有子查询


## time_bucket 子查询

```sql
SELECT * FROM sensor_data
WHERE (sensor_id, time_bucket('1 hour', time)) IN (
    SELECT sensor_id, time_bucket('1 hour', time)
    FROM sensor_data
    GROUP BY sensor_id, time_bucket('1 hour', time)
    HAVING AVG(temperature) > 50
);
```

注意：完全兼容 PostgreSQL 的子查询功能
注意：LATERAL 子查询在时序分析中非常有用
注意：关联子查询可能在大数据量下性能较差
