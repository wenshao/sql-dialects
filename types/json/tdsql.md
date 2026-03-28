# TDSQL: JSON 类型

TDSQL distributed MySQL-compatible JSON support.

> 参考资料:
> - [TDSQL-C MySQL Documentation](https://cloud.tencent.com/document/product/1003)
> - [TDSQL MySQL Documentation](https://cloud.tencent.com/document/product/557)
> - [MySQL 8.0 Reference Manual - JSON Data Type](https://dev.mysql.com/doc/refman/8.0/en/json.html)
> - ============================================================
> - 1. JSON 列类型
> - ============================================================
> - TDSQL 兼容 MySQL 的原生 JSON 类型
> - JSON 数据在存储时自动验证格式，非法 JSON 插入报错
> - 内部使用二进制格式存储（与 MySQL 一致），查询时无需重新解析

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

## 分布式环境下的 JSON 注意事项


2.1 JSON 列不能作为 shardkey
JSON 类型的数据不适合作为分片键（大小不确定，hash 不均匀）
如果需要按 JSON 内字段分片，应将该字段提取为独立列

```sql
CREATE TABLE events_distributed (
    id       BIGINT NOT NULL AUTO_INCREMENT,
    user_id  BIGINT NOT NULL,                -- 提取为独立列，作为 shardkey
    data     JSON,
    PRIMARY KEY (id),
    SHARDKEY (user_id)
);
```

2.2 JSON 查询的分布式执行
WHERE 条件中的 JSON 函数在各分片独立执行
跨分片的 JSON 聚合（JSON_ARRAYAGG 等）由代理层合并
JSON 函数无法利用索引（除非使用虚拟列 + 函数索引）
2.3 JSON 列的网络传输
JSON 数据在分片间传输时完整传递
大 JSON 文档会增加分布式查询的网络开销
建议: JSON 文档控制在合理大小（建议 < 1KB ~ 10KB）

## JSON 字段读取


## MySQL 风格的 JSON 路径语法（使用 $. 前缀）

```sql
SELECT data->'$.name' FROM events;                              -- JSON 值: "alice"
SELECT data->>'$.name' FROM events;                             -- TEXT 值: alice
SELECT JSON_EXTRACT(data, '$.name') FROM events;                -- 等价于 ->
SELECT JSON_UNQUOTE(JSON_EXTRACT(data, '$.name')) FROM events;  -- 等价于 ->>
```

## 嵌套访问

```sql
SELECT data->'$.tags[0]' FROM events;              -- 数组索引: "vip"
SELECT data->'$.address.city' FROM events;          -- 嵌套路径
```

## 通配符

```sql
SELECT data->'$.tags[*]' FROM events;               -- 所有数组元素
SELECT data->'$.*' FROM events;                      -- 所有顶层值
```

## JSON 查询条件


## 等值比较

```sql
SELECT * FROM events WHERE data->>'$.name' = 'alice';
```

## JSON_CONTAINS: 检查是否包含指定值

```sql
SELECT * FROM events WHERE JSON_CONTAINS(data, '"vip"', '$.tags');
SELECT * FROM events WHERE JSON_CONTAINS(data, '{"name": "alice"}');
```

## JSON_CONTAINS_PATH: 检查路径是否存在

```sql
SELECT * FROM events WHERE JSON_CONTAINS_PATH(data, 'one', '$.name');
SELECT * WHERE JSON_CONTAINS_PATH(data, 'all', '$.name', '$.age');
```

## JSON_SEARCH: 搜索字符串值

```sql
SELECT JSON_SEARCH(data, 'one', 'alice');          -- '$.name'
SELECT JSON_SEARCH(data, 'all', 'vip');             -- '$.tags[0]'
```

## JSON 修改操作


## JSON_SET: 设置值（存在则更新，不存在则插入）

```sql
SELECT JSON_SET(data, '$.age', 26) FROM events;
SELECT JSON_SET(data, '$.email', 'a@e.com') FROM events;
```

## JSON_INSERT: 仅插入（不更新已有值）

```sql
SELECT JSON_INSERT(data, '$.email', 'a@e.com') FROM events;
```

## JSON_REPLACE: 仅替换（不插入新值）

```sql
SELECT JSON_REPLACE(data, '$.age', 26) FROM events;
```

## JSON_REMOVE: 删除指定路径

```sql
SELECT JSON_REMOVE(data, '$.tags') FROM events;
SELECT JSON_REMOVE(data, '$.tags[0]') FROM events;
```

## JSON 函数


## 类型检查

```sql
SELECT JSON_TYPE(data->'$.name') FROM events;       -- 'STRING'
SELECT JSON_TYPE(data->'$.age') FROM events;        -- 'INTEGER'
SELECT JSON_VALID('{"a":1}');                        -- 1（合法 JSON）
```

## 键操作

```sql
SELECT JSON_KEYS(data) FROM events;                  -- ['name', 'age', 'tags']
```

## 长度

```sql
SELECT JSON_LENGTH(data) FROM events;                -- 3（顶层键数量）
SELECT JSON_LENGTH(data->'$.tags') FROM events;      -- 2（数组长度）
```

## 深度

```sql
SELECT JSON_DEPTH(data) FROM events;                 -- 3（最大嵌套深度）
```

## JSON 聚合


## 聚合为 JSON 数组

```sql
SELECT JSON_ARRAYAGG(username) FROM users;            -- ["alice", "bob"]
```

## 聚合为 JSON 对象

```sql
SELECT JSON_OBJECTAGG(username, age) FROM users;      -- {"alice": 25, "bob": 30}
```

分布式聚合注意:
JSON_ARRAYAGG / JSON_OBJECTAGG 在各分片独立执行
代理层合并各分片的 JSON 结果
大结果集的 JSON 聚合可能消耗大量内存

## JSON 构造函数


## 构造对象

```sql
SELECT JSON_OBJECT('name', 'alice', 'age', 25);
SELECT JSON_OBJECT('name', 'bob', 'tags', JSON_ARRAY(1, 2, 3));
```

## 构造数组

```sql
SELECT JSON_ARRAY(1, 'hello', NULL, TRUE);
```

## 合并

```sql
SELECT JSON_MERGE_PRESERVE('{"a": 1}', '{"b": 2}');    -- {"a": 1, "b": 2}
SELECT JSON_MERGE_PATCH('{"a": 1, "b": 2}', '{"b": 3}'); -- {"a": 1, "b": 3}
```

## JSON 表函数（MySQL 8.0+ 兼容）


## JSON_TABLE: 将 JSON 数组展开为关系表

```sql
SELECT jt.*
FROM events e,
JSON_TABLE(e.data, '$.tags[*]' COLUMNS (
    tag VARCHAR(64) PATH '$'
)) jt;
```

## JSON_TABLE 带嵌套列

```sql
SELECT jt.*
FROM events e,
JSON_TABLE(e.data, '$' COLUMNS (
    name VARCHAR(64) PATH '$.name',
    age  INT PATH '$.age',
    NESTED PATH '$.tags[*]' COLUMNS (
        tag VARCHAR(64) PATH '$'
    )
)) jt;
```

## JSON 索引与性能


## JSON 列本身不能直接创建索引（与 MySQL 一致）

解决方案: 使用虚拟生成列 + 索引

```sql
CREATE TABLE events_indexed (
    id   BIGINT AUTO_INCREMENT PRIMARY KEY,
    data JSON,
    name VARCHAR(64) GENERATED ALWAYS AS (JSON_UNQUOTE(JSON_EXTRACT(data, '$.name'))) STORED,
    INDEX idx_name (name)
);
```

分布式 JSON 性能建议:
1. 高频查询的 JSON 字段提取为虚拟列并建索引
2. JSON 文档控制在合理大小（< 10KB）
3. 避免 JSON 列参与跨分片 JOIN
4. JSON_CONTAINS 比手动解析字符串更高效
5. JSON_TABLE 适合一次性展开 JSON 结构

## 注意事项与最佳实践


## JSON 类型与 MySQL 完全兼容，使用 $. 路径语法

## JSON 列不能作为 shardkey，需提取为独立列

## JSON 函数在各分片独立执行，跨分片聚合由代理层合并

## 高频查询的 JSON 字段建议使用虚拟列 + 索引加速

## JSON 文档建议控制在合理大小，避免大 JSON 的分布式传输开销

## JSON_SET / JSON_INSERT / JSON_REPLACE 语义不同，注意区分

## JSON_TABLE 功能强大，适合 JSON 数据的关系化查询

## 所有分片的 JSON 函数行为一致，无需担心分布式差异
