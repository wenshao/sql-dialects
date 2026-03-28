# TDengine: 聚合函数

## 基本聚合

```sql
SELECT COUNT(*) FROM meters;
SELECT COUNT(current) FROM d1001;
SELECT SUM(current) FROM d1001;
SELECT AVG(current) FROM d1001;
SELECT MIN(current) FROM d1001;
SELECT MAX(current) FROM d1001;
```

## GROUP BY 标签

```sql
SELECT location, COUNT(*), AVG(current) FROM meters GROUP BY location;
SELECT location, group_id, AVG(current) FROM meters GROUP BY location, group_id;
```

## HAVING

```sql
SELECT location, AVG(current) AS avg_val
FROM meters GROUP BY location HAVING AVG(current) > 10;
```

## TDengine 特有聚合函数


## FIRST（第一个非 NULL 值，按时间顺序）

```sql
SELECT FIRST(current) FROM d1001;
```

## LAST（最后一个非 NULL 值，按时间顺序）

```sql
SELECT LAST(current) FROM d1001;
```

## LAST_ROW（最后一行的值，性能极高）

```sql
SELECT LAST_ROW(current) FROM d1001;
```

## SPREAD（最大值 - 最小值）

```sql
SELECT SPREAD(current) FROM d1001;
```

## PERCENTILE（百分位数，仅普通表）

```sql
SELECT PERCENTILE(current, 50) FROM d1001;    -- 中位数
SELECT PERCENTILE(current, 95) FROM d1001;    -- P95
```

## APERCENTILE（近似百分位数，超级表可用）

```sql
SELECT APERCENTILE(current, 50) FROM meters;
SELECT APERCENTILE(current, 95, 't-digest') FROM meters;
```

## LEASTSQUARES（最小二乘法线性拟合）

```sql
SELECT LEASTSQUARES(current, ts) FROM d1001;
```

## HISTOGRAM（直方图）

```sql
SELECT HISTOGRAM(current, 'linear_bin', '{"start": 0, "width": 5, "count": 10, "infinity": true}')
FROM d1001;
```

## MODE（众数）

```sql
SELECT MODE(voltage) FROM d1001;
```

## HYPERLOGLOG（近似去重计数）

```sql
SELECT HYPERLOGLOG(location) FROM meters;
```

## TWA（时间加权平均）

```sql
SELECT TWA(current) FROM d1001
WHERE ts >= '2024-01-01' AND ts < '2024-02-01';
```

## IRATE（即时速率）

```sql
SELECT IRATE(current) FROM d1001;
```

## 降采样聚合（INTERVAL）


```sql
SELECT _WSTART, AVG(current), MAX(voltage), MIN(voltage)
FROM meters
WHERE ts >= '2024-01-01'
INTERVAL(1h)
GROUP BY location;
```

注意：FIRST/LAST/LAST_ROW 是时序分析核心函数
注意：SPREAD 是 MAX - MIN 的快捷方式
注意：TWA 是时间加权平均，适合非均匀采样
注意：APERCENTILE 支持超级表，PERCENTILE 仅普通表
注意：不支持 GROUPING SETS / ROLLUP / CUBE
