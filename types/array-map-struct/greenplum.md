# Greenplum: 复合/复杂类型 (Array, Map, Struct)

> 参考资料:
> - [Greenplum Documentation - Array Types](https://docs.vmware.com/en/VMware-Greenplum/7/greenplum-database/ref_guide-data_types.html)
> - [Greenplum Documentation - Composite Types](https://docs.vmware.com/en/VMware-Greenplum/7/greenplum-database/admin_guide-ddl-ddl-type.html)
> - [PostgreSQL Documentation - Arrays (Greenplum 兼容)](https://www.postgresql.org/docs/current/arrays.html)


## Greenplum 基于 PostgreSQL，继承 ARRAY 和复合类型


ARRAY 类型
```sql
CREATE TABLE users (
    id     SERIAL PRIMARY KEY,
    name   TEXT NOT NULL,
    tags   TEXT[],
    scores INTEGER[]
) DISTRIBUTED BY (id);

INSERT INTO users (name, tags, scores) VALUES
    ('Alice', ARRAY['admin', 'dev'], ARRAY[90, 85, 95]),
    ('Bob',   '{user,tester}', '{70,80,75}');
```


数组索引（从 1 开始）
```sql
SELECT tags[1] FROM users;
```


数组操作
```sql
SELECT ARRAY_LENGTH(tags, 1) FROM users;
SELECT ARRAY_CAT(tags, ARRAY['new']) FROM users;
SELECT ARRAY_APPEND(tags, 'extra') FROM users;
SELECT * FROM users WHERE tags @> ARRAY['admin'];
SELECT * FROM users WHERE 'admin' = ANY(tags);
```


UNNEST
```sql
SELECT u.name, UNNEST(u.tags) AS tag FROM users u;
```


ARRAY_AGG
```sql
SELECT department, ARRAY_AGG(name) FROM employees GROUP BY department;
```


## 复合类型


```sql
CREATE TYPE address AS (
    street TEXT, city TEXT, state TEXT, zip VARCHAR(10)
);

CREATE TABLE customers (
    id        SERIAL PRIMARY KEY,
    name      TEXT,
    home_addr address
) DISTRIBUTED BY (id);

INSERT INTO customers (name, home_addr) VALUES
    ('Alice', ROW('123 Main St', 'Springfield', 'IL', '62701'));

SELECT (home_addr).city FROM customers;
```


## JSON / JSONB


```sql
CREATE TABLE events (id SERIAL, data JSONB) DISTRIBUTED BY (id);
INSERT INTO events (data) VALUES ('{"tags": ["a", "b"], "info": {"x": 1}}');
SELECT data->>'tags' FROM events;
SELECT data->'info'->>'x' FROM events;
```


## 注意事项


1. 继承 PostgreSQL 的 ARRAY 和复合类型
2. 支持 hstore 扩展（需要安装）
3. 支持 JSONB 类型
4. 分布键不能使用复杂类型
5. 数组下标从 1 开始
