# TDengine: Sequences & Auto-Increment

> 参考资料:
> - [TDengine Documentation - Data Types](https://docs.tdengine.com/reference/sql/data-type/)
> - [TDengine Documentation - CREATE TABLE](https://docs.tdengine.com/reference/sql/table/)
> - [TDengine Documentation - SQL Functions](https://docs.tdengine.com/reference/sql/function/)


## TDengine 不支持 SEQUENCE、AUTO_INCREMENT、IDENTITY

## TDengine 是时序数据库，数据以时间戳为主键

每条记录天然以时间戳唯一标识

## 时间戳作为主键

```sql
CREATE STABLE sensor_data (
    ts          TIMESTAMP,                   -- 必须的时间戳列（主键）
    temperature FLOAT,
    humidity    FLOAT
) TAGS (
    device_id   INT,
    location    NCHAR(64)
);
```

## 插入数据（时间戳是天然的"序列"）

```sql
INSERT INTO d1001 USING sensor_data TAGS(1, 'Beijing')
VALUES (NOW, 25.5, 60.0);
```

## 使用纳秒时间戳提高精度

```sql
INSERT INTO d1001 VALUES ('2024-01-15 10:30:00.000000001', 25.5, 60.0);
```

## 替代方案


方法 1：使用时间戳作为唯一标识
TDengine 中每个设备（子表）的时间戳是唯一的
时间戳 + 设备标签 = 全局唯一标识
方法 2：使用 NOW 函数

```sql
INSERT INTO d1001 VALUES (NOW, 25.5, 60.0);
INSERT INTO d1001 VALUES (NOW + 1a, 26.0, 61.0);  -- 1a = 1 毫秒偏移
```

## 方法 3：在应用层生成 UUID 作为额外列

```sql
CREATE STABLE events (
    ts       TIMESTAMP,
    event_id BINARY(36),                    -- UUID 存储
    data     NCHAR(1000)
) TAGS (
    source   NCHAR(64)
);
```

## 序列 vs 自增 权衡

TDengine 是时序数据库，设计理念完全不同：
1. 时间戳是天然的主键和"序列"
2. 每个子表内的时间戳唯一
3. 不需要传统的自增 ID
4. 如需额外唯一标识，在应用层生成
限制：
不支持 CREATE SEQUENCE
不支持 AUTO_INCREMENT / IDENTITY / SERIAL
不支持 GENERATED AS IDENTITY
不支持 UUID 生成函数
时间戳列是必须的且是第一列
