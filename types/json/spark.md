# Spark SQL: JSON 类型与处理 (JSON Type)

> 参考资料:
> - [1] Spark SQL - JSON Functions
>   https://spark.apache.org/docs/latest/sql-ref-functions-builtin.html
> - [2] Spark SQL - JSON Data Source
>   https://spark.apache.org/docs/latest/sql-data-sources-json.html


## 1. 核心设计: Spark 没有原生 JSON 列类型


Spark 将 JSON 存储为 STRING，通过函数解析和操作。
这与 PostgreSQL/MySQL 的原生 JSON 类型有本质区别:
PostgreSQL JSONB: 二进制存储，支持 GIN 索引，查询 O(1) 字段访问
MySQL JSON:       二进制存储，支持虚拟列索引
Spark STRING:     每次查询都重新解析 JSON 字符串

Spark 4.0 引入 Variant 类型:
VARIANT 是二进制半结构化类型，类似 Snowflake VARIANT
解析一次，多次访问字段，性能远优于 STRING + get_json_object


```sql
CREATE TABLE events (
    id   BIGINT,
    data STRING                                  -- JSON 存为 STRING
) USING PARQUET;

INSERT INTO events VALUES (1, '{"name":"alice","age":25,"tags":["vip","new"]}');

```

## 2. get_json_object: 路径提取

```sql
SELECT get_json_object(data, '$.name') FROM events;      -- 'alice' (STRING)
SELECT get_json_object(data, '$.age') FROM events;       -- '25' (STRING!)
SELECT get_json_object(data, '$.tags[0]') FROM events;   -- 'vip'
SELECT get_json_object(data, '$.tags') FROM events;      -- '["vip","new"]'

```

总是返回 STRING，需要 CAST 转换:

```sql
SELECT CAST(get_json_object(data, '$.age') AS INT) FROM events;

```

## 3. from_json: 结构化解析（推荐）

```sql
SELECT from_json(data, 'STRUCT<name:STRING, age:INT, tags:ARRAY<STRING>>') AS parsed
FROM events;

```

访问解析后的字段

```sql
SELECT parsed.name, parsed.age, parsed.tags FROM (
    SELECT from_json(data, 'STRUCT<name:STRING, age:INT, tags:ARRAY<STRING>>') AS parsed
    FROM events
);

```

使用 schema_of_json 推断 Schema

```sql
SELECT schema_of_json('{"name":"","age":0,"tags":[""]}');

SELECT from_json(data,
    schema_of_json('{"name":"","age":0,"tags":[""]}')
) AS parsed
FROM events;

```

 from_json vs get_json_object:
   from_json:          一次解析，返回类型化 STRUCT，可多次访问字段
   get_json_object:    每次调用重新解析 JSON（多字段提取时低效）

## 4. json_tuple: 多字段提取（Hive 兼容）

```sql
SELECT id, j.name, j.age
FROM events
LATERAL VIEW json_tuple(data, 'name', 'age') j AS name, age;

```

 json_tuple 一次解析提取多个顶级字段——比多次 get_json_object 更高效
 但不支持嵌套路径（$.a.b.c）

## 5. to_json: 生成 JSON

```sql
SELECT to_json(STRUCT('alice' AS name, 25 AS age));
SELECT to_json(MAP('key1', 'value1', 'key2', 'value2'));
SELECT to_json(ARRAY('a', 'b', 'c'));

```

JSON_OBJECT / JSON_ARRAY（Spark 3.5+）

```sql
SELECT JSON_OBJECT('name', 'alice', 'age', 25);
SELECT JSON_ARRAY('a', 'b', 'c');

```

## 6. JSON 数组展开

```sql
SELECT id, tag
FROM events
LATERAL VIEW EXPLODE(
    from_json(get_json_object(data, '$.tags'), 'ARRAY<STRING>')
) t AS tag;

```

## 7. JSON 聚合

```sql
SELECT to_json(COLLECT_LIST(username)) FROM users;
SELECT to_json(MAP_FROM_ENTRIES(COLLECT_LIST(STRUCT(username, age)))) FROM users;

```

## 8. JSON 文件读取

 CREATE TABLE json_data USING JSON OPTIONS (path '/data/events.json');
 CREATE TABLE json_data (name STRING, age INT, tags ARRAY<STRING>)
 USING JSON OPTIONS (path '/data/events.json', multiLine 'true');

## 9. 嵌套 JSON 处理

```sql
SELECT get_json_object(data, '$.address.city') AS city FROM events;

SELECT parsed.* FROM (
    SELECT from_json(data,
        'STRUCT<name:STRING, age:INT, address:STRUCT<city:STRING, zip:STRING>>'
    ) AS parsed
    FROM events
);

```

WHERE 子句中使用 JSON

```sql
SELECT * FROM events WHERE get_json_object(data, '$.name') = 'alice';
SELECT * FROM events WHERE CAST(get_json_object(data, '$.age') AS INT) > 20;

```

## 10. 版本演进

Spark 2.0: get_json_object, json_tuple
Spark 2.1: from_json, to_json
Spark 2.4: schema_of_json
Spark 3.5: JSON_OBJECT, JSON_ARRAY
Spark 4.0: Variant 类型（原生半结构化支持）

限制:
无原生 JSON 列类型（存为 STRING，每次查询重新解析）
无 JSON 路径操作符（-> / ->>），使用 get_json_object 函数
get_json_object 总是返回 STRING（需要 CAST）
from_json 需要提供完整 Schema（不支持部分 Schema）
无 JSON 索引（无法加速 JSON 字段查询）
Spark 4.0 的 Variant 类型将大幅改善 JSON 处理性能

