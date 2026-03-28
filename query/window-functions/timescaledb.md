# TimescaleDB: 窗口函数

> 参考资料:
> - [TimescaleDB API Reference](https://docs.timescale.com/api/latest/)
> - [TimescaleDB Hyperfunctions](https://docs.timescale.com/api/latest/hyperfunctions/)


TimescaleDB 继承 PostgreSQL 全部窗口函数
额外提供 time_bucket 等时序窗口功能
ROW_NUMBER / RANK / DENSE_RANK

```sql
SELECT sensor_id, time, temperature,
    ROW_NUMBER() OVER (ORDER BY time) AS rn,
    RANK()       OVER (ORDER BY temperature DESC) AS rnk,
    DENSE_RANK() OVER (ORDER BY temperature DESC) AS dense_rnk
FROM sensor_data;
```

## 分区

```sql
SELECT sensor_id, time, temperature,
    ROW_NUMBER() OVER (PARTITION BY sensor_id ORDER BY time DESC) AS rn
FROM sensor_data;
```

## 聚合窗口函数

```sql
SELECT sensor_id, time, temperature,
    AVG(temperature) OVER (PARTITION BY sensor_id) AS avg_temp,
    MIN(temperature) OVER (PARTITION BY sensor_id) AS min_temp,
    MAX(temperature) OVER (PARTITION BY sensor_id) AS max_temp,
    COUNT(*)         OVER (PARTITION BY sensor_id) AS cnt
FROM sensor_data;
```

## 偏移函数（前后值比较，时序分析核心）

```sql
SELECT sensor_id, time, temperature,
    LAG(temperature, 1)  OVER (PARTITION BY sensor_id ORDER BY time) AS prev_temp,
    LEAD(temperature, 1) OVER (PARTITION BY sensor_id ORDER BY time) AS next_temp,
    temperature - LAG(temperature) OVER (PARTITION BY sensor_id ORDER BY time) AS temp_change
FROM sensor_data;
```

## FIRST_VALUE / LAST_VALUE

```sql
SELECT sensor_id, time, temperature,
    FIRST_VALUE(temperature) OVER w AS first_temp,
    LAST_VALUE(temperature)  OVER w AS last_temp
FROM sensor_data
WINDOW w AS (PARTITION BY sensor_id ORDER BY time
    ROWS BETWEEN UNBOUNDED PRECEDING AND UNBOUNDED FOLLOWING);
```

## NTH_VALUE / NTILE

```sql
SELECT sensor_id, time, temperature,
    NTH_VALUE(temperature, 2) OVER (PARTITION BY sensor_id ORDER BY time) AS second_reading,
    NTILE(4) OVER (ORDER BY temperature) AS quartile
FROM sensor_data;
```

## 滑动窗口（移动平均）

```sql
SELECT sensor_id, time, temperature,
    AVG(temperature) OVER (PARTITION BY sensor_id ORDER BY time
        ROWS BETWEEN 4 PRECEDING AND CURRENT ROW) AS moving_avg_5,
    SUM(temperature) OVER (PARTITION BY sensor_id ORDER BY time
        ROWS BETWEEN 2 PRECEDING AND 2 FOLLOWING) AS centered_sum
FROM sensor_data;
```

## 命名窗口

```sql
SELECT sensor_id, time, temperature,
    ROW_NUMBER() OVER w AS rn,
    LAG(temperature) OVER w AS prev,
    LEAD(temperature) OVER w AS next
FROM sensor_data
WINDOW w AS (PARTITION BY sensor_id ORDER BY time);
```

## PERCENT_RANK / CUME_DIST

```sql
SELECT sensor_id, temperature,
    PERCENT_RANK() OVER (ORDER BY temperature) AS pct_rank,
    CUME_DIST()    OVER (ORDER BY temperature) AS cume_dist
FROM sensor_data;
```

## 时序特有：time_bucket + 窗口函数


## 每小时平均温度的移动平均

```sql
SELECT sensor_id, bucket,
    avg_temp,
    AVG(avg_temp) OVER (PARTITION BY sensor_id ORDER BY bucket
        ROWS BETWEEN 3 PRECEDING AND CURRENT ROW) AS moving_avg_4h
FROM (
    SELECT sensor_id,
           time_bucket('1 hour', time) AS bucket,
           AVG(temperature) AS avg_temp
    FROM sensor_data
    GROUP BY sensor_id, bucket
) hourly;
```

## 获取每个传感器的最新读数

```sql
SELECT * FROM (
    SELECT *, ROW_NUMBER() OVER (PARTITION BY sensor_id ORDER BY time DESC) AS rn
    FROM sensor_data
) WHERE rn = 1;
```

注意：完全兼容 PostgreSQL 的窗口函数
注意：LAG/LEAD 在时序分析中极其重要（变化检测）
注意：time_bucket + 窗口函数是时序分析的核心模式
注意：支持 FILTER 子句
