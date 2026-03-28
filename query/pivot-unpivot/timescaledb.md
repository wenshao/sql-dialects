# TimescaleDB: PIVOT / UNPIVOT

> 参考资料:
> - [TimescaleDB Documentation](https://docs.timescale.com/)
> - [PostgreSQL Documentation - tablefunc](https://www.postgresql.org/docs/current/tablefunc.html)
> - [PostgreSQL Documentation - FILTER Clause](https://www.postgresql.org/docs/current/sql-expressions.html#SYNTAX-AGGREGATES)


## PIVOT: CASE WHEN + GROUP BY（继承 PostgreSQL）

```sql
SELECT
    time_bucket('1 day', time) AS day,
    SUM(CASE WHEN sensor_type = 'temperature' THEN value ELSE 0 END) AS temperature,
    SUM(CASE WHEN sensor_type = 'humidity' THEN value ELSE 0 END) AS humidity,
    SUM(CASE WHEN sensor_type = 'pressure' THEN value ELSE 0 END) AS pressure
FROM sensor_data
GROUP BY day
ORDER BY day;
```

## FILTER 子句

```sql
SELECT
    time_bucket('1 hour', time) AS hour,
    AVG(value) FILTER (WHERE sensor_type = 'temperature') AS avg_temp,
    AVG(value) FILTER (WHERE sensor_type = 'humidity') AS avg_humidity,
    MAX(value) FILTER (WHERE sensor_type = 'pressure') AS max_pressure
FROM sensor_data
GROUP BY hour
ORDER BY hour;
```

## PIVOT: crosstab（需要 tablefunc 扩展）

```sql
CREATE EXTENSION IF NOT EXISTS tablefunc;

SELECT * FROM crosstab(
    $$SELECT time_bucket('1 day', time)::date, sensor_type, AVG(value)
      FROM sensor_data
      GROUP BY 1, 2
      ORDER BY 1, 2$$,
    $$SELECT DISTINCT sensor_type FROM sensor_data ORDER BY 1$$
) AS ct(day date, temperature numeric, humidity numeric, pressure numeric);
```

## UNPIVOT: LATERAL + VALUES

```sql
SELECT s.day, v.metric_name, v.metric_value
FROM daily_metrics s
CROSS JOIN LATERAL (
    VALUES
        ('temperature', s.temperature),
        ('humidity', s.humidity),
        ('pressure', s.pressure)
) AS v(metric_name, metric_value);
```

## UNPIVOT: UNION ALL

```sql
SELECT day, 'temperature' AS metric, temperature AS value FROM daily_metrics
UNION ALL
SELECT day, 'humidity' AS metric, humidity AS value FROM daily_metrics
UNION ALL
SELECT day, 'pressure' AS metric, pressure AS value FROM daily_metrics
ORDER BY day, metric;
```

## 时序场景的典型 PIVOT 用例

## 多设备数据按时间对齐

```sql
SELECT
    time_bucket('5 minutes', time) AS period,
    AVG(value) FILTER (WHERE device_id = 'device_001') AS device_001,
    AVG(value) FILTER (WHERE device_id = 'device_002') AS device_002,
    AVG(value) FILTER (WHERE device_id = 'device_003') AS device_003
FROM readings
GROUP BY period
ORDER BY period;
```

## 注意事项

TimescaleDB 继承 PostgreSQL 的所有 PIVOT/UNPIVOT 能力
FILTER 子句配合 time_bucket 非常适合时序数据 PIVOT
crosstab 需要 tablefunc 扩展
PIVOT 查询可用于连续聚合（Continuous Aggregates）
时序数据通常有宽表需求，PIVOT 是常见操作
