# TDengine: 累计/滚动合计（Running Total）

> 参考资料:
> - [TDengine SQL Reference](https://docs.taosdata.com/taos-sql/)
> - ============================================================
> - 示例数据上下文
> - ============================================================
> - 假设表结构:
> - transactions(ts TIMESTAMP, current FLOAT, voltage INT)
> - ============================================================
> - 注意：TDengine 不支持传统窗口函数
> - ============================================================
> - TDengine 使用 INTERVAL 实现时间窗口累计
> - ============================================================
> - 1. 时间窗口聚合（非传统累计）
> - ============================================================
> - 每 10 分钟窗口的累计

```sql
SELECT _wstart, SUM(current) AS total_current, AVG(current) AS avg_current
FROM meters
WHERE ts >= '2024-01-01' AND ts < '2024-01-02'
INTERVAL(10m);
```

## 按标签分组的时间窗口聚合

```sql
SELECT _wstart, location, SUM(current) AS total_current
FROM meters
WHERE ts >= '2024-01-01' AND ts < '2024-01-02'
PARTITION BY location
INTERVAL(10m);
```

## 差值计算（DIFF 函数）


## 相邻行差值

```sql
SELECT ts, current, DIFF(current) AS current_diff
FROM meters
WHERE ts >= '2024-01-01' AND ts < '2024-01-02';
```

## 累计聚合（CSUM - TDengine 3.0+）


## 累计求和

```sql
SELECT ts, current, CSUM(current) AS cumulative_sum
FROM meters
WHERE ts >= '2024-01-01' AND ts < '2024-01-02';
```

## 性能考量


TDengine 不支持 SUM OVER / ROW_NUMBER 等窗口函数
使用 INTERVAL 时间窗口和 CSUM 函数
CSUM 从 TDengine 3.0 开始支持
时序数据的累计通常基于时间窗口
