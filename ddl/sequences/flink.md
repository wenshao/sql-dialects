# Flink SQL: 序列与自增

> 参考资料:
> - [Flink Documentation - CREATE TABLE](https://nightlies.apache.org/flink/flink-docs-stable/docs/dev/table/sql/create/#create-table)
> - [Flink Documentation - Built-in Functions](https://nightlies.apache.org/flink/flink-docs-stable/docs/dev/table/functions/systemfunctions/)

**引擎定位**: 流批一体计算引擎。表是外部系统的映射，支持 Changelog 语义和 Watermark 机制。

## Flink SQL 是流处理引擎，不支持传统的序列和自增

不支持 CREATE SEQUENCE
不支持 AUTO_INCREMENT / IDENTITY / SERIAL

## 替代方案


方法 1：使用 UUID() 生成唯一标识符
```sql
CREATE TABLE events (
    id         STRING,
    event_type STRING,
    event_time TIMESTAMP(3),
    WATERMARK FOR event_time AS event_time - INTERVAL '5' SECOND
) WITH (
    'connector' = 'kafka',
    'topic' = 'events',
    'format' = 'json'
);

```

在查询时使用 UUID()
```sql
INSERT INTO events
SELECT UUID(), event_type, event_time
FROM source_events;

```

方法 2：使用 ROW_NUMBER() 窗口函数
```sql
SELECT
    ROW_NUMBER() OVER (ORDER BY event_time) AS row_id,
    event_type,
    event_time
FROM events;

```

方法 3：使用源系统的 ID（Kafka offset、数据库主键等）
Flink 通常从外部系统读取数据，ID 由源系统生成

方法 4：使用计算列（Computed Column）
```sql
CREATE TABLE orders (
    order_data STRING,
    order_time TIMESTAMP(3),
    order_id AS UUID(),                      -- 计算列
    WATERMARK FOR order_time AS order_time - INTERVAL '5' SECOND
) WITH (
    'connector' = 'kafka',
    'topic' = 'orders',
    'format' = 'json'
);

```

## UUID 生成

```sql
SELECT UUID();
```

返回 UUID 字符串

## 序列 vs 自增 权衡

Flink 是流处理引擎，设计理念不同于 OLTP：
## 数据通常从外部源（Kafka、数据库 CDC）流入，已有 ID

## UUID() 是最常用的唯一标识方案

## 不需要严格递增的序列号

## 如需递增 ID，建议在源系统或 sink 系统中生成


**限制:**
不支持 CREATE SEQUENCE
不支持 AUTO_INCREMENT / IDENTITY / SERIAL
不支持 GENERATED AS IDENTITY
UUID() 是唯一的内置 ID 生成函数
