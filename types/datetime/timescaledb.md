# TimescaleDB: 日期时间类型

> 参考资料:
> - [TimescaleDB API Reference](https://docs.timescale.com/api/latest/)
> - [TimescaleDB Hyperfunctions](https://docs.timescale.com/api/latest/hyperfunctions/)


TimescaleDB 继承 PostgreSQL 日期时间类型 + 时序扩展函数
DATE: 日期
TIME: 时间（无时区）
TIMESTAMP: 日期时间（无时区）
TIMESTAMPTZ: 日期时间（带时区，推荐）
INTERVAL: 时间间隔

```sql
CREATE TABLE sensor_data (
    time        TIMESTAMPTZ NOT NULL,        -- 推荐使用带时区
    sensor_id   INT NOT NULL,
    temperature DOUBLE PRECISION
);
SELECT create_hypertable('sensor_data', 'time');
```

## 获取当前时间

```sql
SELECT NOW();                                 -- TIMESTAMPTZ
SELECT CURRENT_TIMESTAMP;                     -- TIMESTAMPTZ
SELECT CURRENT_DATE;                          -- DATE
SELECT CURRENT_TIME;                          -- TIME
```

## 日期运算

```sql
SELECT NOW() + INTERVAL '1 day';
SELECT NOW() - INTERVAL '3 hours';
SELECT '2024-01-15'::DATE + 7;               -- 加 7 天
```

## 日期差

```sql
SELECT AGE(NOW(), '2024-01-01'::TIMESTAMPTZ);
SELECT EXTRACT(EPOCH FROM NOW() - '2024-01-01'::TIMESTAMPTZ);
```

## 提取

```sql
SELECT EXTRACT(YEAR FROM NOW());
SELECT EXTRACT(MONTH FROM NOW());
SELECT DATE_PART('hour', NOW());
```

## 截断

```sql
SELECT DATE_TRUNC('hour', NOW());
SELECT DATE_TRUNC('day', NOW());
```

## 格式化

```sql
SELECT TO_CHAR(NOW(), 'YYYY-MM-DD HH24:MI:SS');
SELECT TO_CHAR(NOW(), 'Day, DD Month YYYY');
```

## 解析

```sql
SELECT TO_TIMESTAMP('2024-01-15 10:30:00', 'YYYY-MM-DD HH24:MI:SS');
SELECT TO_DATE('2024-01-15', 'YYYY-MM-DD');
```

## 时区转换

```sql
SELECT NOW() AT TIME ZONE 'Asia/Shanghai';
SELECT NOW() AT TIME ZONE 'UTC';
```

## TimescaleDB 特有：time_bucket


## 按固定时间间隔分桶（时序分析核心函数）

```sql
SELECT time_bucket('1 hour', time) AS bucket,
       AVG(temperature) AS avg_temp
FROM sensor_data
GROUP BY bucket ORDER BY bucket;
```

## 自定义偏移的 time_bucket

```sql
SELECT time_bucket('1 day', time, '2024-01-01'::TIMESTAMPTZ) AS bucket,
       COUNT(*)
FROM sensor_data
GROUP BY bucket;
```

## time_bucket_gapfill（填充缺失的时间桶）

```sql
SELECT time_bucket_gapfill('1 hour', time) AS bucket,
       AVG(temperature) AS avg_temp
FROM sensor_data
WHERE time > NOW() - INTERVAL '24 hours' AND time < NOW()
GROUP BY bucket;
```

## interpolate（在 gapfill 中插值）

```sql
SELECT time_bucket_gapfill('1 hour', time) AS bucket,
       interpolate(AVG(temperature)) AS avg_temp
FROM sensor_data
WHERE time > NOW() - INTERVAL '24 hours' AND time < NOW()
GROUP BY bucket;
```

## locf（Last Observation Carried Forward）

```sql
SELECT time_bucket_gapfill('1 hour', time) AS bucket,
       locf(AVG(temperature)) AS avg_temp
FROM sensor_data
WHERE time > NOW() - INTERVAL '24 hours' AND time < NOW()
GROUP BY bucket;
```

注意：TIMESTAMPTZ 是推荐的时间类型
注意：time_bucket 是 TimescaleDB 最核心的函数
注意：time_bucket_gapfill + interpolate/locf 处理缺失数据
注意：完全兼容 PostgreSQL 的日期时间功能
