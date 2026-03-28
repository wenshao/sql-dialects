# YugabyteDB: 复合类型

> 参考资料:
> - [YugabyteDB Documentation - Data Types](https://docs.yugabyte.com/latest/api/ysql/datatypes/)
> - [YugabyteDB Documentation - Array Functions](https://docs.yugabyte.com/latest/api/ysql/exprs/func_array/)
> - [YugabyteDB Documentation - JSON Functions](https://docs.yugabyte.com/latest/api/ysql/datatypes/type_json/)

**引擎定位**: 分布式 SQL 数据库，兼容 PostgreSQL 协议。基于 DocDB (RocksDB) 存储，Raft 共识。

## YugabyteDB 兼容 PostgreSQL，支持 ARRAY 和复合类型


ARRAY
```sql
CREATE TABLE users (
    id     SERIAL PRIMARY KEY,
    name   TEXT NOT NULL,
    tags   TEXT[],
    scores INTEGER[]
);

INSERT INTO users (name, tags, scores) VALUES
    ('Alice', ARRAY['admin', 'dev'], ARRAY[90, 85, 95]),
    ('Bob',   ARRAY['user'], ARRAY[70, 80]);

SELECT tags[1] FROM users;
SELECT ARRAY_LENGTH(tags, 1) FROM users;
SELECT * FROM users WHERE tags @> ARRAY['admin'];
SELECT * FROM users WHERE 'admin' = ANY(tags);
SELECT u.name, UNNEST(u.tags) AS tag FROM users u;
SELECT ARRAY_AGG(name) FROM users;

```

ARRAY 操作
```sql
SELECT ARRAY_APPEND(tags, 'new') FROM users;
SELECT ARRAY_CAT(tags, ARRAY['extra']) FROM users;
SELECT ARRAY_REMOVE(tags, 'admin') FROM users;
SELECT ARRAY_POSITION(tags, 'admin') FROM users;

```

复合类型
```sql
CREATE TYPE address AS (street TEXT, city TEXT, zip VARCHAR(10));
CREATE TABLE customers (id SERIAL PRIMARY KEY, addr address);
INSERT INTO customers (addr) VALUES (ROW('123 Main', 'NYC', '10001'));
SELECT (addr).city FROM customers;

```

JSONB
```sql
CREATE TABLE events (id SERIAL PRIMARY KEY, data JSONB);
INSERT INTO events (data) VALUES ('{"tags": ["a","b"], "info": {"x": 1}}');
SELECT data->'tags' FROM events;
SELECT data->'info'->>'x' FROM events;

```

GIN 索引
```sql
CREATE INDEX idx_data ON events USING GIN (data);
CREATE INDEX idx_tags ON users USING GIN (tags);

```

## 注意事项


## 完全兼容 PostgreSQL 的 ARRAY 和复合类型

## 支持 JSONB 和 GIN 索引

## 数组下标从 1 开始

## 分布式架构下 ARRAY/JSONB 完全支持
