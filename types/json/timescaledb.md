# TimescaleDB: JSON 类型

> 参考资料:
> - [TimescaleDB API Reference](https://docs.timescale.com/api/latest/)
> - [TimescaleDB Hyperfunctions](https://docs.timescale.com/api/latest/hyperfunctions/)
> - TimescaleDB 继承 PostgreSQL 的 JSON 和 JSONB 类型
> - JSON: 存储原始文本（保留空格、键顺序）
> - JSONB: 二进制格式（更高效，支持索引，推荐）

```sql
CREATE TABLE events (
    time    TIMESTAMPTZ NOT NULL,
    type    TEXT,
    payload JSONB
);
SELECT create_hypertable('events', 'time');
```

## 插入 JSON

```sql
INSERT INTO events VALUES (NOW(), 'login', '{"user": "alice", "ip": "192.168.1.1"}');
INSERT INTO events VALUES (NOW(), 'click', '{"page": "/home", "button": "submit"}'::JSONB);
```

## 读取 JSON 字段

```sql
SELECT payload->'user' FROM events;              -- JSON 值
SELECT payload->>'user' FROM events;             -- TEXT 值
SELECT payload->'nested'->'key' FROM events;     -- 嵌套访问
SELECT payload#>>'{nested,key}' FROM events;     -- 路径访问
```

## 查询条件

```sql
SELECT * FROM events WHERE payload->>'user' = 'alice';
SELECT * FROM events WHERE payload @> '{"user": "alice"}'::JSONB;  -- 包含
SELECT * FROM events WHERE payload ? 'user';     -- 键存在
```

## GIN 索引加速

```sql
CREATE INDEX idx_payload ON events USING GIN (payload);
CREATE INDEX idx_payload_path ON events USING GIN (payload jsonb_path_ops);
```

## JSON 构造

```sql
SELECT jsonb_build_object('name', 'alice', 'age', 25);
SELECT jsonb_build_array(1, 2, 3);
SELECT to_jsonb(ROW('alice', 25));
```

## JSON 修改

```sql
SELECT payload || '{"role": "admin"}'::JSONB FROM events;       -- 合并
SELECT payload - 'ip' FROM events;                               -- 删除键
SELECT jsonb_set(payload, '{role}', '"admin"') FROM events;     -- 设置值
```

## JSON 展开

```sql
SELECT * FROM jsonb_each(payload) FROM events;
SELECT * FROM jsonb_array_elements('[1,2,3]'::JSONB);
SELECT jsonb_object_keys(payload) FROM events;
```

## JSONPath（PostgreSQL 12+）

```sql
SELECT jsonb_path_query(payload, '$.user') FROM events;
```

注意：JSONB 是推荐类型（支持索引和操作符）
注意：GIN 索引可加速 JSONB 查询
注意：完全兼容 PostgreSQL 的 JSON 功能
