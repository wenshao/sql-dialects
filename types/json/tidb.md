# TiDB: JSON 类型

> 参考资料:
> - [TiDB SQL Reference](https://docs.pingcap.com/tidb/stable/sql-statement-overview)
> - [TiDB - MySQL Compatibility](https://docs.pingcap.com/tidb/stable/mysql-compatibility)
> - [TiDB - Functions and Operators](https://docs.pingcap.com/tidb/stable/functions-and-operators-overview)

**引擎定位**: 分布式 HTAP 数据库，兼容 MySQL 协议。基于 TiKV 行存 + TiFlash 列存，Raft 共识。

```sql
CREATE TABLE events (
    id   BIGINT NOT NULL AUTO_RANDOM PRIMARY KEY,
    data JSON
);

```

Insert JSON (same as MySQL)
```sql
INSERT INTO events (data) VALUES ('{"name": "alice", "age": 25, "tags": ["vip", "new"]}');
INSERT INTO events (data) VALUES (JSON_OBJECT('name', 'bob', 'age', 30));
INSERT INTO events (data) VALUES (JSON_ARRAY(1, 2, 3));

```

Read JSON fields (same as MySQL)
```sql
SELECT data->'$.name' FROM events;
SELECT data->>'$.name' FROM events;
SELECT JSON_EXTRACT(data, '$.name') FROM events;
SELECT JSON_UNQUOTE(JSON_EXTRACT(data, '$.name')) FROM events;

```

Nested access (same as MySQL)
```sql
SELECT data->'$.tags[0]' FROM events;
SELECT data->>'$.address.city' FROM events;

```

Query conditions (same as MySQL)
```sql
SELECT * FROM events WHERE data->>'$.name' = 'alice';
SELECT * FROM events WHERE JSON_CONTAINS(data, '"vip"', '$.tags');
SELECT * FROM events WHERE JSON_CONTAINS_PATH(data, 'one', '$.name', '$.email');

```

Modify JSON (same as MySQL)
```sql
SELECT JSON_SET(data, '$.age', 26) FROM events;
SELECT JSON_INSERT(data, '$.email', 'a@e.com') FROM events;
SELECT JSON_REPLACE(data, '$.age', 26) FROM events;
SELECT JSON_REMOVE(data, '$.tags') FROM events;

```

JSON functions (same as MySQL)
```sql
SELECT JSON_TYPE(data->'$.name') FROM events;
SELECT JSON_VALID('{"a":1}');
SELECT JSON_KEYS(data) FROM events;
SELECT JSON_LENGTH(data->'$.tags') FROM events;

```

JSON aggregation (same as MySQL 5.7.22+)
```sql
SELECT JSON_ARRAYAGG(username) FROM users;
SELECT JSON_OBJECTAGG(username, age) FROM users;

```

JSON_TABLE (same as MySQL 8.0)
```sql
SELECT * FROM events,
JSON_TABLE(data, '$' COLUMNS (
    name VARCHAR(64) PATH '$.name',
    age INT PATH '$.age'
)) AS jt;

```

Multi-valued index on JSON arrays (6.6+)
```sql
CREATE INDEX idx_tags ON events ((CAST(data->'$.tags' AS CHAR(64) ARRAY)));
SELECT * FROM events WHERE 'vip' MEMBER OF (data->'$.tags');

```

Expression index on JSON fields (5.0+)
```sql
CREATE INDEX idx_json_name ON events ((CAST(data->>'$.name' AS CHAR(64))));

```

JSON binary format:
TiDB stores JSON in binary format (same as MySQL)
JSON values in TiKV are encoded as key-value pairs
Large JSON documents affect TiKV transaction size

Limitations:
Same JSON functions as MySQL 8.0
Large JSON values may hit txn-entry-size-limit (default 6MB)
JSON column cannot be used as primary key or in partition expression
Partial JSON update (in-place) not supported (full rewrite on update)
JSON path expressions follow MySQL syntax
JSON comparison follows MySQL binary comparison rules
