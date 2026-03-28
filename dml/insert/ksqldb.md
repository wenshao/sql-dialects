# ksqlDB: INSERT

> 参考资料:
> - [ksqlDB Reference](https://docs.ksqldb.io/en/latest/developer-guide/ksqldb-reference/)
> - [ksqlDB API Reference](https://docs.ksqldb.io/en/latest/developer-guide/api/)
> - ksqlDB 中向 STREAM 或 TABLE 插入数据
> - ============================================================
> - INSERT INTO STREAM
> - ============================================================
> - 向 STREAM 插入单条记录

```sql
INSERT INTO pageviews (user_id, page_url, view_time)
VALUES ('user_123', '/home', 1705286400000);
```

## 插入多条（每条单独的 INSERT）

```sql
INSERT INTO pageviews (user_id, page_url, view_time)
VALUES ('user_123', '/products', 1705286460000);
INSERT INTO pageviews (user_id, page_url, view_time)
VALUES ('user_456', '/home', 1705286520000);
```

## 插入复杂类型

```sql
INSERT INTO events (event_id, event_type, payload)
VALUES ('evt_001', 'click', '{"button": "submit", "page": "/form"}');
```

## 插入 STRUCT 类型

```sql
INSERT INTO typed_events (id, v_struct)
VALUES ('evt_002', STRUCT(name := 'alice', age := 25));
```

## 插入 ARRAY 类型

```sql
INSERT INTO typed_events (id, v_array)
VALUES ('evt_003', ARRAY['tag1', 'tag2', 'tag3']);
```

## 插入 MAP 类型

```sql
INSERT INTO typed_events (id, v_map)
VALUES ('evt_004', MAP('key1' := 1, 'key2' := 2));
```

## INSERT INTO TABLE


## 向 TABLE 插入（相同 PRIMARY KEY 覆盖旧值）

```sql
INSERT INTO users (user_id, username, email, region)
VALUES ('user_123', 'alice', 'alice@example.com', 'US');
```

## 更新（本质是插入新记录覆盖旧值）

```sql
INSERT INTO users (user_id, username, email, region)
VALUES ('user_123', 'alice', 'alice_new@example.com', 'US');
```

## CREATE ... AS SELECT（持久查询，持续"插入"）


## 从一个 STREAM 持续插入到另一个 STREAM

```sql
CREATE STREAM filtered_events AS
SELECT * FROM events WHERE event_type = 'click'
EMIT CHANGES;
```

## INSERT INTO ... SELECT（向已存在的 STREAM 追加数据）

```sql
INSERT INTO filtered_events
SELECT * FROM events WHERE event_type = 'impression'
EMIT CHANGES;
```

注意：ksqlDB 不支持批量 INSERT（多 VALUES）
注意：STREAM 的 INSERT 是追加，TABLE 的 INSERT 是 upsert
注意：INSERT INTO ... SELECT 创建持久查询
注意：实际生产中数据通常由 Kafka Producer 写入，而非 INSERT
注意：INSERT 的数据会写入底层 Kafka Topic
