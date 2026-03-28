# TDengine: 分页

> 参考资料:
> - [TDengine SQL Reference](https://docs.taosdata.com/taos-sql/)
> - [TDengine Function Reference](https://docs.taosdata.com/taos-sql/function/)
> - LIMIT / OFFSET

```sql
SELECT * FROM d1001 ORDER BY ts DESC LIMIT 10 OFFSET 20;
```

## 仅 LIMIT

```sql
SELECT * FROM d1001 ORDER BY ts DESC LIMIT 10;
```

## 按时间范围分页（推荐，利用时间索引）

```sql
SELECT * FROM d1001
WHERE ts >= '2024-01-15' AND ts < '2024-01-16'
LIMIT 100;
```

## 按时间和标签过滤后分页

```sql
SELECT * FROM meters
WHERE location = 'Beijing.Chaoyang'
    AND ts >= '2024-01-01' AND ts < '2024-02-01'
LIMIT 100 OFFSET 200;
```

## 降采样分页（INTERVAL + LIMIT）


## 小时聚合后分页

```sql
SELECT _WSTART, AVG(current), MAX(voltage)
FROM d1001
WHERE ts >= '2024-01-01' AND ts < '2024-02-01'
INTERVAL(1h)
LIMIT 24 OFFSET 0;
```

## SLIMIT / SOFFSET（子表分页，TDengine 特有）


SLIMIT: 限制返回的子表数量
SOFFSET: 跳过的子表数量
前 5 个子表

```sql
SELECT * FROM meters
WHERE ts >= '2024-01-01'
SLIMIT 5;
```

## 跳过前 5 个子表，取接下来 5 个

```sql
SELECT * FROM meters
WHERE ts >= '2024-01-01'
SLIMIT 5 SOFFSET 5;
```

## SLIMIT + LIMIT 组合

```sql
SELECT * FROM meters
WHERE ts >= '2024-01-01'
LIMIT 100        -- 每个子表最多 100 行
SLIMIT 10;       -- 最多 10 个子表
```

## 游标分页（基于时间戳）


## 使用上一页最后一条的时间戳作为游标

第一页

```sql
SELECT * FROM d1001 ORDER BY ts LIMIT 100;
```

## 下一页（使用上一页最后的时间戳）

```sql
SELECT * FROM d1001 WHERE ts > '2024-01-15 10:00:00.000' ORDER BY ts LIMIT 100;
```

注意：SLIMIT/SOFFSET 是 TDengine 特有的子表级分页
注意：时间范围 + LIMIT 是最高效的分页方式
注意：基于时间戳的游标分页适合大数据量
注意：OFFSET 值较大时性能会下降
