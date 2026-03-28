# TDengine: 窗口函数

> 参考资料:
> - [TDengine SQL Reference](https://docs.taosdata.com/taos-sql/)
> - [TDengine Function Reference](https://docs.taosdata.com/taos-sql/function/)
> - TDengine 不支持传统的 SQL 窗口函数（ROW_NUMBER, RANK 等）
> - 但提供时序特有的窗口查询：INTERVAL, SESSION, STATE_WINDOW
> - ============================================================
> - INTERVAL 窗口（时间降采样，最重要的功能）
> - ============================================================
> - 每小时平均值

```sql
SELECT _WSTART, AVG(current), MAX(voltage)
FROM meters
WHERE ts >= '2024-01-01' AND ts < '2024-02-01'
INTERVAL(1h);
```

## 每 10 分钟聚合

```sql
SELECT _WSTART, _WEND, AVG(current), COUNT(*)
FROM d1001
INTERVAL(10m);
```

## 每天聚合

```sql
SELECT _WSTART, AVG(current), SUM(current)
FROM meters
WHERE location = 'Beijing.Chaoyang'
INTERVAL(1d);
```

## 支持的时间单位：a(毫秒), s(秒), m(分), h(时), d(天), w(周), n(月), y(年)

## SLIDING 滑动窗口（与 INTERVAL 配合）


## 每 5 分钟滑动，窗口大小 10 分钟

```sql
SELECT _WSTART, AVG(current)
FROM d1001
INTERVAL(10m) SLIDING(5m);
```

## 每 1 小时滑动，窗口大小 24 小时

```sql
SELECT _WSTART, AVG(current), MAX(current), MIN(current)
FROM meters
INTERVAL(24h) SLIDING(1h);
```

## FILL 填充缺失值


## FILL(NULL) - 用 NULL 填充

```sql
SELECT _WSTART, AVG(current)
FROM d1001
WHERE ts >= '2024-01-01' AND ts < '2024-01-02'
INTERVAL(1h) FILL(NULL);
```

## FILL(VALUE, 0) - 用指定值填充

```sql
SELECT _WSTART, AVG(current)
FROM d1001
INTERVAL(1h) FILL(VALUE, 0);
```

## FILL(PREV) - 用前一个值填充

```sql
SELECT _WSTART, AVG(current)
FROM d1001
INTERVAL(1h) FILL(PREV);
```

## FILL(NEXT) - 用后一个值填充

```sql
SELECT _WSTART, AVG(current)
FROM d1001
INTERVAL(1h) FILL(NEXT);
```

## FILL(LINEAR) - 线性插值

```sql
SELECT _WSTART, AVG(current)
FROM d1001
INTERVAL(1h) FILL(LINEAR);
```

## SESSION 窗口（基于会话间隔）


## 超过 10 分钟无数据则视为新会话

```sql
SELECT _WSTART, _WEND, COUNT(*), AVG(current)
FROM d1001
SESSION(ts, 10m);
```

## STATE_WINDOW（状态窗口）


## 按状态值分组连续相同值

```sql
SELECT _WSTART, _WEND, COUNT(*), AVG(voltage)
FROM d1001
STATE_WINDOW(voltage);
```

## 内置伪列


_WSTART: 窗口开始时间
_WEND: 窗口结束时间
_WDURATION: 窗口持续时间
_QSTART: 查询起始时间
_QEND: 查询结束时间

```sql
SELECT _WSTART, _WEND, _WDURATION, AVG(current)
FROM d1001
INTERVAL(1h);
```

注意：TDengine 不支持 ROW_NUMBER, RANK, LAG, LEAD 等标准窗口函数
注意：INTERVAL/SLIDING/FILL 是 TDengine 时序分析的核心
注意：FILL 只在 INTERVAL 查询中可用
注意：SESSION 窗口适合 IoT 设备的会话分析
注意：STATE_WINDOW 适合设备状态变化分析
