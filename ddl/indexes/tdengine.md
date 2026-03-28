# TDengine: 索引

> 参考资料:
> - [TDengine SQL Reference](https://docs.taosdata.com/taos-sql/)
> - [TDengine Function Reference](https://docs.taosdata.com/taos-sql/function/)


## TDengine 不支持传统的 B-tree / Hash 索引

时序数据通过内置优化机制高效查询

## 内置索引机制（自动，无需手动创建）


## 时间戳列自动索引

## 第一列（TIMESTAMP）自动建立索引，按时间范围查询非常高效

```sql
SELECT * FROM meters WHERE ts >= '2024-01-01' AND ts < '2024-02-01';
```

## 标签（TAG）自动索引

## 所有 TAG 列自动建立索引，按标签过滤非常高效

```sql
SELECT * FROM meters WHERE location = 'Beijing.Chaoyang';
SELECT * FROM meters WHERE group_id = 2;
```

## 子表名索引

## 子表名本身就是索引，直接查询子表最快

```sql
SELECT * FROM d1001 WHERE ts >= '2024-01-01';
```

## SMA 索引（预聚合索引，3.0+）


## 创建带 SMA 索引的超级表（在建表时指定）

```sql
CREATE STABLE meters_sma (
    ts          TIMESTAMP,
    current     FLOAT,
    voltage     INT,
    phase       FLOAT
) TAGS (
    location    NCHAR(64),
    group_id    INT
) SMA(current, voltage);           -- 对指定列创建预聚合索引
```

## SMA 索引加速 MIN/MAX/SUM/AVG 等聚合查询

```sql
SELECT AVG(current), MAX(voltage) FROM meters_sma
WHERE ts >= '2024-01-01' AND ts < '2024-02-01';
```

## 标签索引（3.0.3.0+）


## 创建标签索引

```sql
CREATE INDEX idx_location ON meters (location);
```

## 删除标签索引

```sql
DROP INDEX idx_location;
```

## 查询优化


## 按时间过滤（利用时间戳索引）

```sql
SELECT * FROM meters WHERE ts BETWEEN '2024-01-01' AND '2024-01-31';
```

## 按标签过滤（利用标签索引）

```sql
SELECT * FROM meters WHERE location = 'Beijing.Chaoyang' AND group_id > 1;
```

## 组合过滤（时间 + 标签最优）

```sql
SELECT AVG(current) FROM meters
WHERE location = 'Beijing.Chaoyang'
    AND ts >= '2024-01-01' AND ts < '2024-02-01'
INTERVAL(1h);
```

注意：TDengine 不支持传统的 CREATE INDEX（仅标签索引和 SMA 索引）
注意：时间戳列自动索引，无需手动创建
注意：标签列自动索引，用于过滤子表
注意：SMA 索引用于加速预聚合查询
注意：TDengine 的存储引擎针对时序数据优化，无需传统索引
