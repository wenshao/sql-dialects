# TDengine: Top-N 查询（排名与分组取前 N 条）

> 参考资料:
> - [TDengine SQL Reference](https://docs.taosdata.com/taos-sql/)
> - [TDengine Function Reference](https://docs.taosdata.com/taos-sql/function/)


## 示例数据上下文

假设超级表结构:
CREATE STABLE meters (ts TIMESTAMP, current FLOAT, voltage INT, phase FLOAT)
TAGS (location NCHAR(64), group_id INT);

## 注意：TDengine 是时序数据库，SQL 功能有限


## Top-N 整体（简单 LIMIT）


## 按值排序取前 N

```sql
SELECT ts, current, voltage
FROM meters
ORDER BY current DESC
LIMIT 10;
```

## LIMIT + OFFSET

```sql
SELECT ts, current, voltage
FROM meters
ORDER BY current DESC
LIMIT 10 OFFSET 20;
```

## 按标签分组 Top（使用聚合函数）


## 每个 location 的最大电流值

```sql
SELECT location, MAX(current) AS max_current
FROM meters
GROUP BY location
ORDER BY max_current DESC;
```

## 使用 TOP 函数（TDengine 特有）

```sql
SELECT TOP(current, 3) FROM meters;
```

## 每个子表取最大值

```sql
SELECT location, LAST(ts) AS last_ts, MAX(current) AS max_current
FROM meters
GROUP BY location;
```

## 窗口查询（时间窗口内的 Top-N）


## 每 10 分钟窗口内的最大值

```sql
SELECT _wstart, MAX(current) AS max_current, MAX(voltage) AS max_voltage
FROM meters
WHERE ts >= '2024-01-01' AND ts < '2024-01-02'
INTERVAL(10m);
```

## 按标签分组的时间窗口

```sql
SELECT _wstart, location, MAX(current) AS max_current
FROM meters
WHERE ts >= '2024-01-01' AND ts < '2024-01-02'
PARTITION BY location
INTERVAL(10m);
```

## 性能考量


TDengine 不支持窗口函数（ROW_NUMBER / RANK / DENSE_RANK）
TDengine 不支持关联子查询
TDengine 不支持 LATERAL / CROSS APPLY / QUALIFY / CTE
使用 TOP() 函数取列的前 N 个值
时序数据的 Top-N 通常结合 INTERVAL 窗口使用
超级表 + 标签分组是 TDengine 的核心查询模式
