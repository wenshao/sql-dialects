# Greenplum: JSON 类型

> 参考资料:
> - [Greenplum SQL Reference](https://docs.vmware.com/en/VMware-Greenplum/7/greenplum-database/ref_guide-sql_commands-sql_ref.html)
> - [Greenplum Admin Guide](https://docs.vmware.com/en/VMware-Greenplum/7/greenplum-database/admin_guide-intro-about_greenplum.html)


Greenplum 基于 PostgreSQL，支持 JSON 和 JSONB 两种类型

JSON: 文本存储，保留格式
JSONB: 二进制存储，支持索引（推荐）

```sql
CREATE TABLE events (
    id   BIGSERIAL PRIMARY KEY,
    data JSONB
)
DISTRIBUTED BY (id);
```


插入 JSON
```sql
INSERT INTO events (data) VALUES ('{"name": "alice", "age": 25, "tags": ["vip", "new"]}');
INSERT INTO events (data) VALUES (jsonb_build_object('name', 'bob', 'age', 30));
INSERT INTO events (data) VALUES (jsonb_build_array(1, 2, 3));
```


## JSON 路径访问


```sql
SELECT data->'name' FROM events;                   -- "alice"（JSON 值）
SELECT data->>'name' FROM events;                  -- alice（文本值）
SELECT data->'tags'->0 FROM events;                -- "vip"
SELECT data->'tags'->>0 FROM events;               -- vip
SELECT data#>'{address,city}' FROM events;         -- 路径提取
SELECT data#>>'{address,city}' FROM events;        -- 路径提取（文本）
```


## JSON 查询


```sql
SELECT * FROM events WHERE data->>'name' = 'alice';
SELECT * FROM events WHERE (data->>'age')::INT > 25;
SELECT * FROM events WHERE data @> '{"name": "alice"}';      -- 包含
SELECT * FROM events WHERE data ? 'email';                    -- 存在键
SELECT * FROM events WHERE data ?| ARRAY['email', 'phone'];   -- 存在任一键
SELECT * FROM events WHERE data ?& ARRAY['name', 'age'];      -- 存在所有键
```


jsonpath（PostgreSQL 12+）
```sql
SELECT * FROM events WHERE data @@ '$.age > 25';
SELECT jsonb_path_query(data, '$.tags[*]') FROM events;
SELECT jsonb_path_query_first(data, '$.tags[0]') FROM events;
```


## JSON 修改


```sql
SELECT data || '{"email": "a@e.com"}'::JSONB FROM events;     -- 合并
SELECT data - 'age' FROM events;                               -- 删除键
SELECT data - ARRAY['age', 'tags'] FROM events;                -- 删除多键
SELECT data #- '{address,city}' FROM events;                   -- 删除嵌套键
SELECT jsonb_set(data, '{age}', '26') FROM events;            -- 设置值
```


## JSON 聚合


```sql
SELECT jsonb_agg(username) FROM users;
SELECT jsonb_object_agg(username, age) FROM users;
```


JSON 展开
```sql
SELECT * FROM events, jsonb_each(data);
SELECT * FROM events, jsonb_each_text(data);
SELECT * FROM events, jsonb_array_elements(data->'tags');
```


## JSONB 索引


```sql
CREATE INDEX idx_data ON events USING GIN (data);
CREATE INDEX idx_data_path ON events USING GIN (data jsonb_path_ops);
```


注意：Greenplum 兼容 PostgreSQL JSON/JSONB
注意：推荐使用 JSONB（支持索引，查询更快）
注意：GIN 索引加速 @>, ?, ?|, ?& 运算符
注意：jsonb_path_ops 索引仅加速 @> 运算符，但更小
