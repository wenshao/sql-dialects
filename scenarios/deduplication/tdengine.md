# TDengine: 数据去重策略（Deduplication）

> 参考资料:
> - [TDengine Documentation](https://docs.taosdata.com/taos-sql/)


## 示例数据上下文

假设超级表:
CREATE STABLE meters (ts TIMESTAMP, current FLOAT, voltage INT)
TAGS (location NCHAR(64), group_id INT);

## 注意：TDengine 是时序数据库，去重方式与传统数据库不同


## 查找重复时间戳


TDengine 中同一子表的同一时间戳只能有一条记录
后写入的数据会自动覆盖之前的（即天然去重）
查看跨子表的相同时间戳数据

```sql
SELECT ts, COUNT(*) AS cnt
FROM meters
GROUP BY ts
HAVING COUNT(*) > 1;
```

## 按时间窗口去重


## 每分钟取最后一条记录

```sql
SELECT LAST(ts) AS last_ts, LAST(current) AS last_current, LAST(voltage) AS last_voltage
FROM meters
WHERE ts >= '2024-01-01' AND ts < '2024-01-02'
INTERVAL(1m);
```

## 每分钟取第一条记录

```sql
SELECT FIRST(ts) AS first_ts, FIRST(current) AS first_current
FROM meters
WHERE ts >= '2024-01-01' AND ts < '2024-01-02'
INTERVAL(1m);
```

## 按标签去重


## 每个 location 的最新记录

```sql
SELECT location, LAST(ts) AS last_ts, LAST(current) AS last_current
FROM meters
GROUP BY location;
```

## 性能考量


TDengine 同一子表的同一时间戳天然唯一（后写覆盖前写）
跨子表的去重通过 GROUP BY + LAST/FIRST 函数实现
不支持 ROW_NUMBER / DISTINCT ON / QUALIFY
不支持 DELETE WHERE ... 复杂条件
