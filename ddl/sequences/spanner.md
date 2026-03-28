# Spanner: 序列与自增

> 参考资料:
> - [Spanner Documentation - CREATE SEQUENCE](https://cloud.google.com/spanner/docs/reference/standard-sql/data-definition-language#create_sequence)
> - [Spanner Documentation - Primary Keys & Unique IDs](https://cloud.google.com/spanner/docs/schema-design#primary-key-prevent-hotspots)
> - [Spanner Documentation - Bit-reversed Sequences](https://cloud.google.com/spanner/docs/reference/standard-sql/data-definition-language#bit_reversed_positive)

**引擎定位**: Google 全球分布式数据库，TrueTime 外部一致性。基于 Colossus 存储，支持跨洲强一致事务。

## SEQUENCE（Spanner 使用位反转序列）

避免分布式写热点
```sql
    OPTIONS (sequence_kind = 'bit_reversed_positive');

```

带参数的序列
```sql
CREATE SEQUENCE order_id_seq
    OPTIONS (
        sequence_kind = 'bit_reversed_positive',
        start_with_counter = 1000,
        skip_range_min = 1,
        skip_range_max = 1000
    );

```

使用序列
```sql
CREATE TABLE users (
    id       INT64 DEFAULT (GET_NEXT_SEQUENCE_VALUE(SEQUENCE user_id_seq)),
    username STRING(64) NOT NULL,
    email    STRING(255) NOT NULL
) PRIMARY KEY (id);

```

修改序列
```sql
ALTER SEQUENCE user_id_seq SET OPTIONS (
    skip_range_min = 1,
    skip_range_max = 5000
);

```

删除序列
```sql
DROP SEQUENCE user_id_seq;

```

## Spanner 不支持 AUTO_INCREMENT / IDENTITY

**原因:** 自增值会导致写热点（所有新行写入同一分片）
UUID 生成（推荐的主键策略）
```sql
    id         STRING(36) DEFAULT (GENERATE_UUID()),
    user_id    INT64,
    created_at TIMESTAMP DEFAULT (CURRENT_TIMESTAMP())
) PRIMARY KEY (id);

SELECT GENERATE_UUID();

```

## 主键设计最佳实践

方法 1：UUID（推荐）
```sql
CREATE TABLE orders (
    id     STRING(36) DEFAULT (GENERATE_UUID()),
    amount NUMERIC
) PRIMARY KEY (id);

```

方法 2：位反转序列（需要数值型主键时）
```sql
CREATE TABLE products (
    id   INT64 DEFAULT (GET_NEXT_SEQUENCE_VALUE(SEQUENCE user_id_seq)),
    name STRING(64)
) PRIMARY KEY (id);

```

方法 3：复合主键（业务键）
```sql
CREATE TABLE events (
    user_id    INT64,
    event_time TIMESTAMP,
    event_type STRING(32)
) PRIMARY KEY (user_id, event_time DESC);

```

错误做法：单调递增主键（会导致热点！）
CREATE TABLE bad_table (id INT64) PRIMARY KEY (id);
INSERT ... VALUES (1), (2), (3) ...  -- 所有写入集中在一个分片

## 序列 vs 自增 权衡

## UUID（推荐）：分布均匀，无热点

## 位反转序列：数值型但分布均匀，适合需要整数 ID 的场景

## 严禁使用单调递增 ID 作为主键（性能灾难）

## Spanner 的核心约束：主键分布必须均匀


**限制:**
不支持 AUTO_INCREMENT / IDENTITY / SERIAL
不支持 GENERATED AS IDENTITY
只支持 bit_reversed_positive 类型的序列
位反转序列的值不连续、不可预测
