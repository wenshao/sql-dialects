# TimescaleDB: 聚合函数

## TimescaleDB 继承 PostgreSQL 聚合函数 + 时序扩展

基本聚合

```sql
SELECT COUNT(*), COUNT(DISTINCT sensor_id), SUM(temperature),
       AVG(temperature), MIN(temperature), MAX(temperature)
FROM sensor_data;
```

## GROUP BY

```sql
SELECT sensor_id, COUNT(*), AVG(temperature)
FROM sensor_data GROUP BY sensor_id;
```

## GROUP BY + HAVING

```sql
SELECT sensor_id, AVG(temperature) AS avg_temp
FROM sensor_data GROUP BY sensor_id HAVING AVG(temperature) > 25;
```

## 字符串聚合

```sql
SELECT STRING_AGG(DISTINCT name, ', ' ORDER BY name) FROM devices;
```

## JSON 聚合

```sql
SELECT jsonb_agg(name) FROM devices;
SELECT jsonb_object_agg(id, name) FROM devices;
```

## 数组聚合

```sql
SELECT ARRAY_AGG(name ORDER BY id) FROM devices;
```

## 统计函数

```sql
SELECT STDDEV(temperature), VARIANCE(temperature),
       STDDEV_POP(temperature), VAR_POP(temperature)
FROM sensor_data;
```

## PERCENTILE

```sql
SELECT PERCENTILE_CONT(0.5) WITHIN GROUP (ORDER BY temperature) AS median,
       PERCENTILE_DISC(0.95) WITHIN GROUP (ORDER BY temperature) AS p95
FROM sensor_data;
```

## GROUPING SETS / CUBE / ROLLUP

```sql
SELECT sensor_id, DATE_TRUNC('day', time) AS day, AVG(temperature)
FROM sensor_data GROUP BY GROUPING SETS ((sensor_id), (day), ());

SELECT sensor_id, DATE_TRUNC('day', time) AS day, AVG(temperature)
FROM sensor_data GROUP BY ROLLUP (sensor_id, day);
```

## FILTER

```sql
SELECT COUNT(*) FILTER (WHERE temperature > 30) AS hot_count,
       COUNT(*) FILTER (WHERE temperature < 10) AS cold_count
FROM sensor_data;
```

## BOOL_AND / BOOL_OR

```sql
SELECT sensor_id, BOOL_AND(active), BOOL_OR(alert)
FROM sensor_data GROUP BY sensor_id;
```

## TimescaleDB 特有聚合


## time_bucket + 聚合

```sql
SELECT time_bucket('1 hour', time) AS bucket, sensor_id,
       AVG(temperature), MIN(temperature), MAX(temperature)
FROM sensor_data
GROUP BY bucket, sensor_id;
```

## 连续聚合（物化视图，自动维护）

```sql
CREATE MATERIALIZED VIEW hourly_temps
WITH (timescaledb.continuous) AS
SELECT time_bucket('1 hour', time) AS bucket,
       sensor_id,
       AVG(temperature) AS avg_temp,
       MIN(temperature) AS min_temp,
       MAX(temperature) AS max_temp
FROM sensor_data
GROUP BY bucket, sensor_id;
```

## 刷新策略

```sql
SELECT add_continuous_aggregate_policy('hourly_temps',
    start_offset => INTERVAL '3 hours',
    end_offset => INTERVAL '1 hour',
    schedule_interval => INTERVAL '1 hour');
```

注意：完全兼容 PostgreSQL 聚合函数
注意：连续聚合是 TimescaleDB 核心特性
注意：time_bucket + 聚合是时序分析标准模式
注意：支持 FILTER、GROUPING SETS 等高级功能
