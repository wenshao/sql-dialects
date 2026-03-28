# ksqlDB: 约束

> 参考资料:
> - [ksqlDB Reference](https://docs.ksqldb.io/en/latest/developer-guide/ksqldb-reference/)
> - [ksqlDB API Reference](https://docs.ksqldb.io/en/latest/developer-guide/api/)


## ksqlDB 约束支持非常有限

只有 KEY（STREAM）和 PRIMARY KEY（TABLE）

## KEY（STREAM 的分区键）


## STREAM 使用 KEY 关键字指定分区键

```sql
CREATE STREAM pageviews (
    user_id    VARCHAR KEY,          -- 分区键，不强制唯一
    page_url   VARCHAR,
    view_time  BIGINT
) WITH (
    KAFKA_TOPIC = 'pageviews_topic',
    VALUE_FORMAT = 'JSON'
);
```

## KEY 用于确定消息写入 Kafka 的哪个分区

不强制唯一性，同一 KEY 可以有多条记录（追加语义）

## PRIMARY KEY（TABLE 的主键）


## TABLE 使用 PRIMARY KEY 指定主键

```sql
CREATE TABLE users (
    user_id    VARCHAR PRIMARY KEY,  -- 主键，基于 key 保留最新值
    username   VARCHAR,
    email      VARCHAR
) WITH (
    KAFKA_TOPIC = 'users_topic',
    VALUE_FORMAT = 'JSON'
);
```

## PRIMARY KEY 决定 TABLE 中的"最新值"语义

相同 PRIMARY KEY 的新消息会替换旧消息（changelog 语义）

## NOT NULL（隐式）


## KEY 和 PRIMARY KEY 列隐式 NOT NULL

其他列没有 NOT NULL 约束

## 数据类型约束


## ksqlDB 支持的数据类型

```sql
CREATE STREAM typed_events (
    id         VARCHAR KEY,
    v_boolean  BOOLEAN,
    v_int      INT,
    v_bigint   BIGINT,
    v_double   DOUBLE,
    v_string   VARCHAR,
    v_array    ARRAY<VARCHAR>,
    v_map      MAP<VARCHAR, INT>,
    v_struct   STRUCT<name VARCHAR, age INT>,
    v_decimal  DECIMAL(10,2)
) WITH (
    KAFKA_TOPIC = 'typed_events',
    VALUE_FORMAT = 'JSON'
);
```

## 不支持的约束


不支持 UNIQUE（KEY/PRIMARY KEY 的唯一性由 Kafka 语义决定）
不支持 FOREIGN KEY
不支持 CHECK
不支持 DEFAULT
不支持 NOT NULL（除 KEY 列外）
注意：ksqlDB 的约束模型极其简单
注意：KEY 决定 Kafka 分区，PRIMARY KEY 决定 changelog 语义
注意：数据完整性由上游生产者保证
注意：TABLE 的 PRIMARY KEY 实现了幂等性（相同 key 覆盖）
