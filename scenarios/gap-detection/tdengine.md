# TDengine: 间隙检测与岛屿问题 (Gap Detection & Islands)

> 参考资料:
> - [TDengine Documentation - SQL Functions](https://docs.taosdata.com/taos-sql/function/)
> - [TDengine Documentation - INTERVAL/FILL](https://docs.taosdata.com/taos-sql/interval/)
> - ============================================================
> - TDengine 是时序数据库，间隙检测主要针对时间序列
> - ============================================================
> - 创建超级表

```sql
CREATE STABLE IF NOT EXISTS sensors (
    ts          TIMESTAMP,
    value       FLOAT
) TAGS (
    device_id   NCHAR(64)
);

CREATE TABLE sensor_001 USING sensors TAGS ('device_001');
INSERT INTO sensor_001 VALUES
    ('2024-01-01 00:00:00', 10.5),
    ('2024-01-02 00:00:00', 11.2),
    ('2024-01-04 00:00:00', 12.1),
    ('2024-01-05 00:00:00', 9.8),
    ('2024-01-08 00:00:00', 13.4),
    ('2024-01-09 00:00:00', 14.0),
    ('2024-01-10 00:00:00', 12.7);
```

## 使用 INTERVAL/FILL 检测时间间隙（TDengine 特有）


## INTERVAL + FILL(NONE) 可以找出有数据的时段

INTERVAL + FILL(NULL) 会在没有数据的时段填 NULL

```sql
SELECT _wstart AS bucket_start,
       COUNT(*) AS cnt,
       AVG(value) AS avg_val
FROM sensor_001
WHERE ts BETWEEN '2024-01-01' AND '2024-01-10 23:59:59'
INTERVAL(1d)
FILL(NULL);
```

## 使用 DIFF 函数检测数值间隙


## DIFF() 计算相邻值的差值

```sql
SELECT ts, value, DIFF(value) AS val_diff
FROM sensor_001;
```

## 使用 ELAPSED 检测时间间隔


## ELAPSED 计算连续记录之间的时间间隔

```sql
SELECT ELAPSED(ts, 1d) AS days_elapsed
FROM sensor_001
WHERE ts BETWEEN '2024-01-01' AND '2024-01-10 23:59:59'
INTERVAL(1d);
```

## 使用 INTERP 函数填充时间间隙


## INTERP 在指定时间点进行插值

```sql
SELECT _irowts AS interp_time,
       INTERP(value) AS interp_value
FROM sensor_001
RANGE('2024-01-01', '2024-01-10')
EVERY(1d)
FILL(NULL);
```

## NULL 结果表示该时间点没有数据（即存在间隙）

## 按时间窗口统计间隙


## 使用 STATE_WINDOW 按值的状态变化分组

找出连续有数据和无数据的时段

```sql
SELECT _wstart, _wend, COUNT(*) AS cnt, FIRST(value) AS first_val
FROM sensor_001
STATE_WINDOW(value > 0);
```

## 跨设备的间隙检测


## 使用 PARTITION BY 按设备分组检测间隙

```sql
SELECT _wstart AS bucket_start,
       device_id,
       COUNT(*) AS cnt,
       AVG(value) AS avg_val
FROM sensors
WHERE ts BETWEEN '2024-01-01' AND '2024-01-10 23:59:59'
PARTITION BY device_id
INTERVAL(1d)
FILL(NULL);
```

注意：TDengine 是专用时序数据库，不支持传统窗口函数 LAG/LEAD
注意：INTERVAL/FILL 是 TDengine 检测时间间隙的核心机制
注意：FILL 支持 NULL, PREV, NEXT, LINEAR, VALUE 等填充策略
注意：INTERP + FILL(NULL) 可以精确定位缺失的时间点
注意：TDengine 3.0 引入了 PARTITION BY 语法
