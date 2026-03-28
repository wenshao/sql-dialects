# ksqlDB: JSON 类型

ksqlDB 原生支持 JSON 作为数据序列化格式
没有独立的 JSON 列类型，JSON 结构映射为 ksqlDB 类型
============================================================
JSON 格式的 STREAM/TABLE
============================================================

```sql
CREATE STREAM events (
    event_id   VARCHAR KEY,
    event_type VARCHAR,
    payload    VARCHAR,                      -- JSON 存为 VARCHAR
    metadata   STRUCT<source VARCHAR, version INT>,  -- 结构化 JSON
    tags       ARRAY<VARCHAR>,               -- JSON 数组
    properties MAP<VARCHAR, VARCHAR>         -- JSON 对象
) WITH (
    KAFKA_TOPIC = 'events_topic',
    VALUE_FORMAT = 'JSON'
);
```

## JSON 字段提取


## EXTRACTJSONFIELD（从 VARCHAR 中提取 JSON 字段）

```sql
SELECT EXTRACTJSONFIELD(payload, '$.name') AS name FROM events EMIT CHANGES;
SELECT EXTRACTJSONFIELD(payload, '$.items[0].id') AS first_id FROM events EMIT CHANGES;
SELECT EXTRACTJSONFIELD(payload, '$.nested.deep.value') AS deep FROM events EMIT CHANGES;
```

## STRUCT 字段访问（直接用 -> 访问）

```sql
SELECT metadata->source AS event_source FROM events EMIT CHANGES;
SELECT metadata->version AS ver FROM events EMIT CHANGES;
```

## ARRAY 访问

```sql
SELECT tags[1] AS first_tag FROM events EMIT CHANGES;
```

## MAP 访问

```sql
SELECT properties['key1'] AS val FROM events EMIT CHANGES;
```

## 复杂类型构造


## 构造 STRUCT

```sql
SELECT STRUCT(name := 'alice', age := 25) FROM events EMIT CHANGES;
```

## 构造 ARRAY

```sql
SELECT ARRAY['a', 'b', 'c'] FROM events EMIT CHANGES;
```

## 构造 MAP

```sql
SELECT MAP('k1' := 'v1', 'k2' := 'v2') FROM events EMIT CHANGES;
```

## AS_VALUE（将 KEY 放入 VALUE）

```sql
SELECT AS_VALUE(event_id) AS id FROM events EMIT CHANGES;
```

## ARRAY 和 MAP 函数


```sql
SELECT ARRAY_LENGTH(tags) FROM events EMIT CHANGES;
SELECT ARRAY_CONTAINS(tags, 'vip') FROM events EMIT CHANGES;
SELECT EXPLODE(tags) FROM events EMIT CHANGES;       -- 展开数组
```

## JSON Schema Registry


## 使用 AVRO/PROTOBUF 格式时，schema 自动管理

```sql
CREATE STREAM avro_events (
    event_id VARCHAR KEY,
    name VARCHAR,
    amount DOUBLE
) WITH (
    KAFKA_TOPIC = 'avro_events',
    VALUE_FORMAT = 'AVRO'
);
```

注意：JSON 是最常用的数据格式（VALUE_FORMAT = 'JSON'）
注意：没有独立的 JSON 列类型
注意：EXTRACTJSONFIELD 从 VARCHAR 提取 JSON 字段
注意：STRUCT/ARRAY/MAP 映射 JSON 结构
注意：也支持 AVRO 和 PROTOBUF 格式
