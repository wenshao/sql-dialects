# Apache Doris: JSON 类型

 Apache Doris: JSON 类型

 参考资料:
   [1] Doris Documentation - JSON Type
       https://doris.apache.org/docs/sql-manual/data-types/

## 1. JSON / JSONB 类型

```sql
CREATE TABLE events (
    id BIGINT NOT NULL, data JSON
) DUPLICATE KEY(id) DISTRIBUTED BY HASH(id) BUCKETS 16;

INSERT INTO events VALUES
    (1, '{"name": "alice", "age": 25, "tags": ["vip", "new"]}'),
    (2, '{"name": "bob", "address": {"city": "Beijing"}}');

```

构造

```sql
INSERT INTO events VALUES (3, JSON_OBJECT('name', 'charlie', 'age', 35));

```

## 2. 路径访问

```sql
SELECT json_extract(data, '$.name') FROM events;          -- JSON 值
SELECT json_extract_string(data, '$.name') FROM events;   -- 字符串
SELECT data->'name', data->>'name' FROM events;           -- 箭头(2.1+)
SELECT data->'address'->'city' FROM events;

```

## 3. 查询

```sql
SELECT * FROM events WHERE json_extract_string(data, '$.name') = 'alice';
SELECT * FROM events WHERE CAST(json_extract(data, '$.age') AS INT) > 25;
SELECT * FROM events WHERE json_contains(data, '"vip"', '$.tags');

```

## 4. JSON 函数

```sql
SELECT json_type(data, '$.name'), json_length(data, '$.tags'), json_keys(data) FROM events;
SELECT json_insert(data, '$.email', 'a@e.com') FROM events;
SELECT json_replace(data, '$.age', 26) FROM events;

```

## 5. JSONB (2.1+，二进制存储)

```sql
CREATE TABLE events_b (id BIGINT NOT NULL, data JSONB)
DUPLICATE KEY(id) DISTRIBUTED BY HASH(id) BUCKETS 16;
```

 JSONB 查询更快(预解析)，但写入稍慢。

## 6. Variant 类型 (2.1+，Doris 独有)

Variant 是 Doris 的半结构化类型——自动推断 JSON 字段类型并列化存储。
查询性能接近原生列(比 JSON 快 5-10 倍)。
对比: StarRocks 没有 Variant 类型。ClickHouse 有 JSON Object(类似)。

限制: JSON 列不能作为 Key/分区/分桶列。

