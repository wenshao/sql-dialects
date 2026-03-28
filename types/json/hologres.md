# Hologres: JSON 类型

Hologres 兼容 PostgreSQL JSON 类型

> 参考资料:
> - [Hologres - JSON/JSONB](https://help.aliyun.com/zh/hologres/user-guide/json-and-jsonb)
> - [Hologres - Data Types](https://help.aliyun.com/zh/hologres/user-guide/data-types)
> - JSON:  存储原始文本，每次访问都要解析
> - JSONB: 存储二进制格式，支持索引，更快（推荐）

```sql
CREATE TABLE events (
    id   BIGSERIAL PRIMARY KEY,
    data JSONB                             -- 推荐用 JSONB
);
```

## 插入 JSON

```sql
INSERT INTO events (id, data) VALUES (1, '{"name": "alice", "age": 25, "tags": ["vip"]}');
```

## 读取 JSON 字段（PostgreSQL 语法）

```sql
SELECT data->'name' FROM events;           -- 返回 JSON: "alice"
SELECT data->>'name' FROM events;          -- 返回文本: alice
SELECT data->'tags'->0 FROM events;        -- 数组元素
SELECT data#>'{tags,0}' FROM events;       -- 路径访问
```

## 查询条件

```sql
SELECT * FROM events WHERE data->>'name' = 'alice';
SELECT * FROM events WHERE data @> '{"name": "alice"}';    -- 包含
SELECT * FROM events WHERE data ? 'name';                   -- 键存在
```

## JSONB 修改

```sql
SELECT data || '{"email": "a@e.com"}' FROM events;         -- 合并
SELECT data - 'tags' FROM events;                            -- 删除键
SELECT jsonb_set(data, '{age}', '26') FROM events;          -- 设置值
```

## JSONB 索引（GIN 索引）

```sql
CREATE INDEX idx_data ON events USING gin (data);
```

## JSON 聚合

```sql
SELECT jsonb_agg(name) FROM users;
SELECT jsonb_object_agg(name, age) FROM users;
```

## JSON 展开

```sql
SELECT * FROM jsonb_each(data) FROM events;
SELECT * FROM jsonb_array_elements(data->'tags') FROM events;
```

注意：与 PostgreSQL JSON 语法基本一致
注意：JSONB 推荐用于需要查询的场景
注意：不支持所有 PostgreSQL JSON 函数（如 JSON Path 支持有限）
注意：GIN 索引支持但性能特征与 PostgreSQL 不同（列存引擎）
注意：JSON 列不能作为 Distribution Key
