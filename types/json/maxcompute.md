# MaxCompute (ODPS): JSON 类型

> 参考资料:
> - [1] MaxCompute - JSON Functions
>   https://help.aliyun.com/zh/maxcompute/user-guide/json-functions
> - [2] MaxCompute SQL - Data Types
>   https://help.aliyun.com/zh/maxcompute/user-guide/data-types-1


## 1. JSON 在 MaxCompute 中的演进


阶段 1（传统方式）: STRING 存储 JSON + GET_JSON_OBJECT 查询

```sql
CREATE TABLE events_v1 (
    id   BIGINT,
    data STRING                             -- JSON 字符串存储在 STRING 列中
);

```

阶段 2（复合类型，2.0+）: MAP/ARRAY/STRUCT 替代 JSON

```sql
CREATE TABLE events_v2 (
    id       BIGINT,
    tags     ARRAY<STRING>,
    props    MAP<STRING, STRING>,
    address  STRUCT<city: STRING, zip: STRING>
);

```

阶段 3（原生 JSON 类型，2024+）: 真正的 JSON 列类型

```sql
CREATE TABLE events_v3 (
    id   BIGINT,
    data JSON                               -- 原生 JSON 类型
);

```

 设计演进分析:
   STRING 存 JSON: 无类型检查，每次查询都要解析 JSON 字符串
   MAP/ARRAY/STRUCT: 列式存储原生支持，性能好但 schema 必须预定义
   原生 JSON: 半结构化数据的最佳方案，存储和查询都有优化

   对比:
     PostgreSQL: JSON(文本) + JSONB(二进制，推荐) — 两种 JSON 类型
     MySQL 5.7+: JSON 类型（二进制存储，自动验证）
     BigQuery:   JSON 类型（2022+）
     Snowflake:  VARIANT 类型（比 JSON 更通用，支持任意半结构化数据）
     ClickHouse: JSON 类型（实验性）+ Nested 类型

## 2. GET_JSON_OBJECT —— 核心 JSON 查询函数


插入 JSON 数据

```sql
INSERT INTO events_v1 VALUES (1, '{"name": "alice", "age": 25, "tags": ["admin", "dev"]}');

```

提取字段（返回 STRING）

```sql
SELECT GET_JSON_OBJECT(data, '$.name') FROM events_v1;       -- 'alice'
SELECT GET_JSON_OBJECT(data, '$.age') FROM events_v1;        -- '25'（STRING!）
SELECT GET_JSON_OBJECT(data, '$.tags[0]') FROM events_v1;    -- 'admin'

```

嵌套路径

```sql
SELECT GET_JSON_OBJECT(data, '$.address.city') FROM events_v1;

```

JSON 路径语法（jQuery 风格）:
$.key:         顶层键
$.key1.key2:   嵌套键
$.array[0]:    数组元素（从 0 开始）
$.array[*]:    所有数组元素

设计分析: GET_JSON_OBJECT 总是返回 STRING
即使 JSON 值是数字，返回的也是 STRING
需要手动 CAST: CAST(GET_JSON_OBJECT(data, '$.age') AS INT)
对比 PostgreSQL: data->>'age' 返回 text, data->'age' 返回 json
对比 BigQuery: JSON_VALUE 返回 STRING，JSON_QUERY 返回 JSON

查询条件中使用 JSON

```sql
SELECT * FROM events_v1
WHERE GET_JSON_OBJECT(data, '$.name') = 'alice';

```

 性能问题: GET_JSON_OBJECT 每次调用都解析整个 JSON 字符串
   解决: 使用 JSON_TUPLE 一次提取多个键

## 3. JSON_TUPLE —— 批量提取


```sql
SELECT o.id, j.name, j.age
FROM events_v1 o
LATERAL VIEW JSON_TUPLE(o.data, 'name', 'age') j AS name, age;

```

 JSON_TUPLE 只解析一次 JSON 字符串，比多次 GET_JSON_OBJECT 快
 但仍然返回 STRING（需要 CAST 转换类型）

## 4. 复合类型: MAP/ARRAY/STRUCT（JSON 的列式替代）


当 JSON 的 schema 是固定的时，推荐使用复合类型:

```sql
CREATE TABLE users (
    name     STRING,
    address  STRUCT<street: STRING, city: STRING, zip: STRING>,
    tags     ARRAY<STRING>,
    props    MAP<STRING, STRING>
);

```

访问复合类型（列式存储原生支持，性能远优于 GET_JSON_OBJECT）

```sql
SELECT address.city FROM users;             -- 点号访问 STRUCT 字段
SELECT tags[0] FROM users;                  -- 下标访问 ARRAY 元素
SELECT props['key1'] FROM users;            -- 键值访问 MAP

```

构造复合类型

```sql
SELECT MAP('k1', 'v1', 'k2', 'v2');
SELECT ARRAY('a', 'b', 'c');
SELECT NAMED_STRUCT('name', 'alice', 'age', 25);

```

MAP/ARRAY 函数

```sql
SELECT MAP_KEYS(props) FROM users;
SELECT MAP_VALUES(props) FROM users;
SELECT SIZE(tags) FROM users;
SELECT ARRAY_CONTAINS(tags, 'vip') FROM users;

```

 设计选择: 何时用 JSON vs 复合类型?
   JSON:        schema 不固定、字段变化频繁、数据来自外部系统
   MAP:         key-value 对，key 类型统一
   ARRAY:       有序列表，元素类型统一
   STRUCT:      schema 固定，字段名和类型预定义
   复合类型的优势: 列式存储原生编码、谓词下推、更好的压缩

## 5. EXPLODE —— JSON 数组展开为多行


展开 ARRAY

```sql
SELECT u.name, t.tag
FROM users u
LATERAL VIEW EXPLODE(u.tags) t AS tag;

```

展开 MAP

```sql
SELECT u.name, t.key, t.value
FROM users u
LATERAL VIEW EXPLODE(u.props) t AS key, value;

```

 JSON 字符串数组的展开（需要先解析）:
   GET_JSON_OBJECT 提取 JSON 数组 → STRING
   需要先转为 ARRAY 再 EXPLODE
   这是 STRING 存 JSON 的麻烦之处

## 6. 横向对比: JSON 支持


 JSON 类型:
   MaxCompute: JSON(2024+), STRING+GET_JSON_OBJECT(传统)
   PostgreSQL: JSON + JSONB（最成熟，支持索引）
   MySQL 5.7+: JSON（二进制存储）
   BigQuery:   JSON（2022+）
   Snowflake:  VARIANT（比 JSON 更通用）
   ClickHouse: JSON（实验性）

 JSON 路径语法:
   MaxCompute: GET_JSON_OBJECT(data, '$.path')
   PostgreSQL: data->'key' / data->>'key' / data #>> '{path}'
   MySQL:      JSON_EXTRACT(data, '$.path') / data->'$.path'
   BigQuery:   JSON_VALUE(data, '$.path') / JSON_QUERY
   Snowflake:  data:path::type（冒号语法，最简洁）

 JSON 索引:
   MaxCompute: 不支持（全量扫描 + 解析）
   PostgreSQL: GIN 索引 on JSONB（支持 @> 包含查询）
   MySQL:      虚拟列 + B-tree 索引
   BigQuery:   搜索索引（有限支持）
   ClickHouse: 不支持（全量扫描）

## 7. 对引擎开发者的启示


1. JSON 在大数据场景中很常见（日志、事件、API 数据）— 必须支持

2. 原生 JSON 类型 > STRING + 解析函数（性能和类型安全）

3. Snowflake 的 VARIANT 是有趣的设计: 比 JSON 更通用的半结构化类型

4. 固定 schema 的 JSON 应转为复合类型（STRUCT）— 列式存储更高效

5. JSON 索引（如 PostgreSQL 的 GIN on JSONB）在 OLTP 中价值大

    但在 OLAP 中价值有限（反正都是全表扫描）
6. GET_JSON_OBJECT 返回 STRING 的设计导致大量 CAST — 应支持类型推断

