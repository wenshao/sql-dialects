# TimescaleDB: JOIN

> 参考资料:
> - [TimescaleDB API Reference](https://docs.timescale.com/api/latest/)
> - [TimescaleDB Hyperfunctions](https://docs.timescale.com/api/latest/hyperfunctions/)


TimescaleDB 继承 PostgreSQL 全部 JOIN 语法
时序表与维度表的 JOIN 是常见模式
INNER JOIN

```sql
SELECT s.time, s.temperature, d.name AS device_name
FROM sensor_data s
INNER JOIN devices d ON s.sensor_id = d.id;
```

## LEFT JOIN

```sql
SELECT s.time, s.temperature, d.name
FROM sensor_data s
LEFT JOIN devices d ON s.sensor_id = d.id;
```

## RIGHT JOIN

```sql
SELECT s.time, s.temperature, d.name
FROM sensor_data s
RIGHT JOIN devices d ON s.sensor_id = d.id;
```

## FULL OUTER JOIN

```sql
SELECT s.time, s.temperature, d.name
FROM sensor_data s
FULL OUTER JOIN devices d ON s.sensor_id = d.id;
```

## CROSS JOIN

```sql
SELECT s.time, c.config_name
FROM sensor_data s
CROSS JOIN configs c;
```

## 自连接（比较前后时间点）

```sql
SELECT a.time, a.temperature AS current_temp,
       b.temperature AS prev_temp,
       a.temperature - b.temperature AS diff
FROM sensor_data a
JOIN sensor_data b ON a.sensor_id = b.sensor_id
    AND b.time = a.time - INTERVAL '1 minute';
```

## USING

```sql
SELECT * FROM sensor_data JOIN devices USING (sensor_id);
```

## LATERAL JOIN

```sql
SELECT d.name, latest.*
FROM devices d
CROSS JOIN LATERAL (
    SELECT time, temperature, humidity
    FROM sensor_data s
    WHERE s.sensor_id = d.id
    ORDER BY time DESC
    LIMIT 5
) latest;
```

## NATURAL JOIN

```sql
SELECT * FROM sensor_data NATURAL JOIN devices;
```

## 多表 JOIN

```sql
SELECT s.time, s.temperature, d.name, l.city
FROM sensor_data s
JOIN devices d ON s.sensor_id = d.id
JOIN locations l ON d.location_id = l.id;
```

## 时序特有：time_bucket JOIN


## 按时间桶聚合后 JOIN

```sql
SELECT tb.bucket, tb.avg_temp, d.name
FROM (
    SELECT time_bucket('1 hour', time) AS bucket,
           sensor_id,
           AVG(temperature) AS avg_temp
    FROM sensor_data
    GROUP BY bucket, sensor_id
) tb
JOIN devices d ON tb.sensor_id = d.id;
```

## 连续聚合 JOIN

```sql
SELECT ca.bucket, ca.avg_temp, d.name
FROM hourly_temps ca
JOIN devices d ON ca.sensor_id = d.id
WHERE ca.bucket > NOW() - INTERVAL '24 hours';
```

注意：完全兼容 PostgreSQL 的 JOIN 语法
注意：时序表与维度表的 JOIN 是最常见的模式
注意：LATERAL JOIN 适合获取每个设备的最新 N 条数据
注意：time_bucket + JOIN 是时序分析的核心模式
