# OceanBase: JSON 类型

> 参考资料:
> - [OceanBase SQL Reference (MySQL Mode)](https://www.oceanbase.com/docs/common-oceanbase-database-cn)
> - [OceanBase SQL Reference (Oracle Mode)](https://www.oceanbase.com/docs/common-oceanbase-database-cn)

**引擎定位**: 分布式关系型数据库，兼容 MySQL/Oracle 双模式。基于 LSM-Tree 存储，Paxos 共识。

## MySQL Mode (same as MySQL 5.7/8.0)


JSON column
```sql
CREATE TABLE events (
    id   BIGINT NOT NULL AUTO_INCREMENT PRIMARY KEY,
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

```

Nested access
```sql
SELECT data->'$.tags[0]' FROM events;
SELECT data->>'$.address.city' FROM events;

```

Query conditions
```sql
SELECT * FROM events WHERE data->>'$.name' = 'alice';
SELECT * FROM events WHERE JSON_CONTAINS(data, '"vip"', '$.tags');

```

Modify JSON
```sql
SELECT JSON_SET(data, '$.age', 26) FROM events;
SELECT JSON_INSERT(data, '$.email', 'a@e.com') FROM events;
SELECT JSON_REPLACE(data, '$.age', 26) FROM events;
SELECT JSON_REMOVE(data, '$.tags') FROM events;

```

JSON aggregation (same as MySQL)
```sql
SELECT JSON_ARRAYAGG(username) FROM users;
SELECT JSON_OBJECTAGG(username, age) FROM users;

```

JSON_TABLE (4.0+)
```sql
SELECT * FROM events,
JSON_TABLE(data, '$' COLUMNS (
    name VARCHAR(64) PATH '$.name',
    age INT PATH '$.age'
)) AS jt;

```

## Oracle Mode (4.0+)


JSON in Oracle mode uses different syntax
JSON data stored in CLOB or VARCHAR2 columns with IS JSON check constraint
```sql
CREATE TABLE events (
    id   NUMBER NOT NULL,
    data CLOB,
    CONSTRAINT chk_json CHECK (data IS JSON)
);

```

Insert JSON (Oracle mode)
```sql
INSERT INTO events (id, data) VALUES (1, '{"name": "alice", "age": 25}');

```

Query JSON (Oracle mode, dot notation, 4.0+)
```sql
SELECT e.data.name FROM events e;
SELECT e.data.age FROM events e;

```

JSON_VALUE (Oracle mode, extract scalar value)
```sql
SELECT JSON_VALUE(data, '$.name') FROM events;
SELECT JSON_VALUE(data, '$.age' RETURNING NUMBER) FROM events;

```

JSON_QUERY (Oracle mode, extract JSON object/array)
```sql
SELECT JSON_QUERY(data, '$.tags') FROM events;
SELECT JSON_QUERY(data, '$.tags' WITH WRAPPER) FROM events;

```

JSON_EXISTS (Oracle mode, check path existence)
```sql
SELECT * FROM events WHERE JSON_EXISTS(data, '$.name');
SELECT * FROM events WHERE JSON_EXISTS(data, '$.tags[0]');

```

JSON_TABLE (Oracle mode)
```sql
SELECT jt.* FROM events e,
JSON_TABLE(e.data, '$' COLUMNS (
    name VARCHAR2(64) PATH '$.name',
    age  NUMBER PATH '$.age'
)) jt;

```

JSON_MERGEPATCH (Oracle mode, update JSON)
```sql
UPDATE events SET data = JSON_MERGEPATCH(data, '{"age": 26}') WHERE id = 1;

```

JSON generation (Oracle mode)
```sql
SELECT JSON_OBJECT('name' VALUE username, 'age' VALUE age) FROM users;
SELECT JSON_ARRAY(username, age) FROM users;
SELECT JSON_ARRAYAGG(JSON_OBJECT('name' VALUE username)) FROM users;

```

Limitations:
MySQL mode: standard MySQL JSON functions
Oracle mode: IS JSON constraint, JSON_VALUE, JSON_QUERY, JSON_EXISTS
Oracle mode: dot notation for JSON access (4.0+)
Oracle mode: JSON stored in CLOB (not a separate JSON type)
Some advanced JSON functions may differ between modes
