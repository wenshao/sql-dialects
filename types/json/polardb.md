# PolarDB: JSON 类型

PolarDB-X (distributed, MySQL 8.0 compatible).

> 参考资料:
> - [PolarDB-X SQL Reference](https://help.aliyun.com/zh/polardb/polardb-for-xscale/sql-reference/)
> - [PolarDB MySQL Documentation](https://help.aliyun.com/zh/polardb/polardb-for-mysql/)


## JSON 列

```sql
CREATE TABLE events (
    id   BIGINT NOT NULL AUTO_INCREMENT PRIMARY KEY,
    data JSON
);
```

## 插入 JSON

```sql
INSERT INTO events (data) VALUES ('{"name": "alice", "age": 25, "tags": ["vip", "new"]}');
INSERT INTO events (data) VALUES (JSON_OBJECT('name', 'bob', 'age', 30));
INSERT INTO events (data) VALUES (JSON_ARRAY(1, 2, 3));
```

## 读取 JSON 字段

```sql
SELECT data->'$.name' FROM events;                   -- JSON 值: "alice"
SELECT data->>'$.name' FROM events;                  -- 文本: alice
SELECT JSON_EXTRACT(data, '$.name') FROM events;
SELECT JSON_UNQUOTE(JSON_EXTRACT(data, '$.name')) FROM events;
```

## 嵌套访问

```sql
SELECT data->'$.tags[0]' FROM events;
SELECT data->>'$.address.city' FROM events;
```

## 查询条件

```sql
SELECT * FROM events WHERE data->>'$.name' = 'alice';
SELECT * FROM events WHERE JSON_CONTAINS(data, '"vip"', '$.tags');
SELECT * FROM events WHERE JSON_CONTAINS_PATH(data, 'one', '$.name', '$.email');
```

## 修改 JSON

```sql
SELECT JSON_SET(data, '$.age', 26) FROM events;
SELECT JSON_INSERT(data, '$.email', 'a@e.com') FROM events;
SELECT JSON_REPLACE(data, '$.age', 26) FROM events;
SELECT JSON_REMOVE(data, '$.tags') FROM events;
```

## JSON 函数

```sql
SELECT JSON_TYPE(data->'$.name') FROM events;
SELECT JSON_VALID('{"a":1}');
SELECT JSON_KEYS(data) FROM events;
SELECT JSON_LENGTH(data->'$.tags') FROM events;
```

## JSON 聚合

```sql
SELECT JSON_ARRAYAGG(username) FROM users;
SELECT JSON_OBJECTAGG(username, age) FROM users;
```

## JSON 表

```sql
SELECT * FROM events,
JSON_TABLE(data, '$' COLUMNS (
    name VARCHAR(64) PATH '$.name',
    age INT PATH '$.age'
)) AS jt;
```

## 多值索引

```sql
CREATE INDEX idx_tags ON events ((CAST(data->'$.tags' AS CHAR(64) ARRAY)));
```

注意事项：
JSON 类型与 MySQL 8.0 完全兼容
JSON 列不能作为分区键
JSON 索引在各分片上独立维护
