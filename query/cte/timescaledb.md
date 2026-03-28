# TimescaleDB: CTE（公共表表达式）

> 参考资料:
> - [TimescaleDB API Reference](https://docs.timescale.com/api/latest/)
> - [TimescaleDB Hyperfunctions](https://docs.timescale.com/api/latest/hyperfunctions/)


## TimescaleDB 继承 PostgreSQL 全部 CTE 功能

基本 CTE

```sql
WITH recent_data AS (
    SELECT * FROM sensor_data WHERE time > NOW() - INTERVAL '1 hour'
)
SELECT sensor_id, AVG(temperature) FROM recent_data GROUP BY sensor_id;
```

## 多个 CTE

```sql
WITH
recent AS (
    SELECT * FROM sensor_data WHERE time > NOW() - INTERVAL '24 hours'
),
stats AS (
    SELECT sensor_id, AVG(temperature) AS avg_temp, MAX(temperature) AS max_temp
    FROM recent GROUP BY sensor_id
)
SELECT d.name, s.avg_temp, s.max_temp
FROM stats s JOIN devices d ON s.sensor_id = d.id;
```

## CTE 引用前面的 CTE

```sql
WITH
hourly AS (
    SELECT sensor_id, time_bucket('1 hour', time) AS bucket, AVG(temperature) AS avg_temp
    FROM sensor_data GROUP BY sensor_id, bucket
),
anomalies AS (
    SELECT * FROM hourly WHERE avg_temp > (SELECT AVG(avg_temp) + 2 * STDDEV(avg_temp) FROM hourly)
)
SELECT * FROM anomalies ORDER BY bucket DESC;
```

## 递归 CTE

```sql
WITH RECURSIVE nums AS (
    SELECT 1 AS n
    UNION ALL
    SELECT n + 1 FROM nums WHERE n < 100
)
SELECT n FROM nums;
```

## 递归：层级结构

```sql
WITH RECURSIVE org_tree AS (
    SELECT id, username, manager_id, 0 AS level
    FROM users WHERE manager_id IS NULL
    UNION ALL
    SELECT u.id, u.username, u.manager_id, t.level + 1
    FROM users u JOIN org_tree t ON u.manager_id = t.id
)
SELECT * FROM org_tree;
```

## CTE + DML

```sql
WITH old_data AS (
    SELECT * FROM sensor_data WHERE time < NOW() - INTERVAL '90 days'
)
INSERT INTO sensor_data_archive SELECT * FROM old_data;
```

## 时序特有 CTE


## time_bucket CTE

```sql
WITH hourly_avg AS (
    SELECT sensor_id,
           time_bucket('1 hour', time) AS bucket,
           AVG(temperature) AS avg_temp
    FROM sensor_data
    WHERE time > NOW() - INTERVAL '7 days'
    GROUP BY sensor_id, bucket
)
SELECT sensor_id, bucket, avg_temp,
    LAG(avg_temp) OVER (PARTITION BY sensor_id ORDER BY bucket) AS prev_hour
FROM hourly_avg;
```

## MATERIALIZED CTE（强制物化，阻止内联优化）

```sql
WITH stats AS MATERIALIZED (
    SELECT sensor_id, AVG(temperature) AS avg_temp
    FROM sensor_data
    GROUP BY sensor_id
)
SELECT * FROM stats WHERE avg_temp > 25;
```

## NOT MATERIALIZED CTE（强制内联）

```sql
WITH stats AS NOT MATERIALIZED (
    SELECT sensor_id, AVG(temperature) AS avg_temp
    FROM sensor_data
    GROUP BY sensor_id
)
SELECT * FROM stats WHERE avg_temp > 25;
```

注意：完全兼容 PostgreSQL 的 CTE 功能
注意：支持递归 CTE
注意：支持 MATERIALIZED / NOT MATERIALIZED 提示
注意：CTE + time_bucket 是时序分析的常用模式
