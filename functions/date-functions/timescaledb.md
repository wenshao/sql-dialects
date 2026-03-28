# TimescaleDB: 日期函数

TimescaleDB 继承 PostgreSQL 日期函数 + 时序扩展
当前时间

```sql
SELECT NOW();
SELECT CURRENT_TIMESTAMP;
SELECT CURRENT_DATE;
SELECT CLOCK_TIMESTAMP();                    -- 实际调用时间
```

## 日期加减

```sql
SELECT NOW() + INTERVAL '1 day';
SELECT NOW() - INTERVAL '3 hours';
SELECT DATE '2024-01-15' + 7;
```

## 日期差

```sql
SELECT AGE(NOW(), '2024-01-01'::TIMESTAMPTZ);
SELECT AGE('2024-12-31'::DATE, '2024-01-01'::DATE);
SELECT EXTRACT(EPOCH FROM NOW() - '2024-01-01'::TIMESTAMPTZ);
```

## 提取

```sql
SELECT EXTRACT(YEAR FROM NOW());
SELECT EXTRACT(MONTH FROM NOW());
SELECT EXTRACT(DOW FROM NOW());              -- 0=周日
SELECT DATE_PART('hour', NOW());
```

## 截断

```sql
SELECT DATE_TRUNC('hour', NOW());
SELECT DATE_TRUNC('day', NOW());
SELECT DATE_TRUNC('month', NOW());
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

## 时区

```sql
SELECT NOW() AT TIME ZONE 'Asia/Shanghai';
SELECT TIMEZONE('UTC', NOW());
```

## 生成时间序列

```sql
SELECT generate_series(
    '2024-01-01'::TIMESTAMPTZ,
    '2024-01-31'::TIMESTAMPTZ,
    INTERVAL '1 day'
);
```

## TimescaleDB 特有函数


## time_bucket（按时间分桶）

```sql
SELECT time_bucket('1 hour', time) AS bucket, AVG(temperature)
FROM sensor_data GROUP BY bucket;
```

## time_bucket 带偏移

```sql
SELECT time_bucket('1 day', time, INTERVAL '8 hours') AS bucket
FROM sensor_data GROUP BY bucket;
```

## time_bucket_gapfill（填充缺失桶）

```sql
SELECT time_bucket_gapfill('1 hour', time) AS bucket,
       interpolate(AVG(temperature)),
       locf(AVG(humidity))
FROM sensor_data
WHERE time > NOW() - INTERVAL '24 hours' AND time < NOW()
GROUP BY bucket;
```

注意：time_bucket 是 TimescaleDB 核心函数
注意：gapfill + interpolate/locf 处理时序数据缺失
注意：完全兼容 PostgreSQL 日期函数
