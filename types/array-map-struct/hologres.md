# Hologres: 复合/复杂类型 (Array, Map, Struct)

> 参考资料:
> - [Hologres 文档 - 数据类型](https://help.aliyun.com/document_detail/130660.html)
> - [Hologres 文档 - JSON 和 JSONB](https://help.aliyun.com/document_detail/401513.html)


## Hologres 兼容 PostgreSQL，支持 ARRAY 和 JSON/JSONB


## ARRAY 类型

```sql
CREATE TABLE users (
    id     SERIAL PRIMARY KEY,
    name   TEXT NOT NULL,
    tags   TEXT[],
    scores INTEGER[]
);

INSERT INTO users (name, tags, scores) VALUES
    ('Alice', ARRAY['admin', 'dev'], ARRAY[90, 85, 95]);

SELECT tags[1] FROM users;
SELECT ARRAY_LENGTH(tags, 1) FROM users;
SELECT * FROM users WHERE tags @> ARRAY['admin'];
SELECT * FROM users WHERE 'admin' = ANY(tags);
SELECT UNNEST(tags) FROM users;
```

## ARRAY_AGG

```sql
SELECT ARRAY_AGG(name) FROM users;
```

## JSONB

```sql
CREATE TABLE events (id SERIAL, data JSONB);
INSERT INTO events (data) VALUES ('{"tags": ["a", "b"], "info": {"x": 1}}');
SELECT data->'tags' FROM events;
SELECT data->>'info' FROM events;
```

## JSON 数组/对象操作

```sql
SELECT jsonb_array_length(data->'tags') FROM events;
SELECT jsonb_array_elements(data->'tags') FROM events;
SELECT jsonb_each(data->'info') FROM events;
```

## 注意事项


## 兼容 PostgreSQL 的 ARRAY 类型

## 支持 JSONB 类型

## 不支持 PostgreSQL 复合类型（CREATE TYPE AS）

## 不支持 hstore

## 数组下标从 1 开始
