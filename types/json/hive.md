# Hive: JSON 处理 (无原生 JSON 类型)

> 参考资料:
> - [1] Apache Hive - get_json_object
>   https://cwiki.apache.org/confluence/display/Hive/LanguageManual+UDF
> - [2] Apache Hive - JsonSerDe
>   https://cwiki.apache.org/confluence/display/Hive/LanguageManual+DDL


## 1. Hive 没有原生 JSON 类型

JSON 数据存储为 STRING，通过函数在查询时解析。
替代方案: 使用 ARRAY/MAP/STRUCT 原生复合类型代替 JSON。
或使用 JsonSerDe 在建表时将 JSON 映射为 Hive 列。


```sql
CREATE TABLE events (id BIGINT, data STRING) STORED AS ORC;

```

## 2. get_json_object: JSONPath 查询

```sql
SELECT
    GET_JSON_OBJECT(data, '$.name')     AS name,      -- 顶层字段
    GET_JSON_OBJECT(data, '$.age')      AS age,       -- 返回 STRING
    GET_JSON_OBJECT(data, '$.tags[0]')  AS first_tag,  -- 数组元素
    GET_JSON_OBJECT(data, '$.addr.city') AS city       -- 嵌套字段
FROM events;

```

WHERE 条件中使用

```sql
SELECT * FROM events WHERE GET_JSON_OBJECT(data, '$.name') = 'alice';

```

 限制: 每次调用只提取一个字段，多字段需要多次解析 JSON 字符串

## 3. json_tuple: 一次提取多个顶层字段 (推荐)

```sql
SELECT e.id, j.name, j.age
FROM events e
LATERAL VIEW JSON_TUPLE(e.data, 'name', 'age') j AS name, age;

```

 json_tuple 比多次 get_json_object 高效: 只解析一次 JSON
 限制: 只支持顶层字段，不支持嵌套路径

## 4. JsonSerDe: 建表时映射 JSON (推荐方案)

```sql
CREATE TABLE json_events (
    name   STRING,
    age    INT,
    tags   ARRAY<STRING>,
    addr   STRUCT<city:STRING, zip:STRING>
)
ROW FORMAT SERDE 'org.apache.hive.hcatalog.data.JsonSerDe'
STORED AS TEXTFILE;

```

直接用列名访问（不需要 get_json_object）

```sql
SELECT name, addr.city, tags[0] FROM json_events;

```

 SerDe 的优势:
1. 查询简单: 像普通列一样访问

2. 类型安全: JSON 字段映射为 Hive 类型

3. 嵌套支持: ARRAY/STRUCT 自动映射


## 5. 复合类型替代 JSON (推荐)

```sql
CREATE TABLE users (
    name     STRING,
    address  STRUCT<street:STRING, city:STRING, zip:STRING>,
    tags     ARRAY<STRING>,
    settings MAP<STRING, STRING>
) STORED AS ORC;

```

访问

```sql
SELECT address.city, tags[0], settings['theme'] FROM users;

```

 设计分析: 为什么 Hive 推荐用复合类型而非 JSON?
1. 类型检查: 复合类型在编译时检查，JSON 在运行时解析

2. 列存优化: ORC/Parquet 可以对 STRUCT 字段做列级裁剪（只读需要的字段）

3. 性能: 不需要每次查询时解析 JSON 字符串

4. 索引统计: ORC 的 min/max 统计可以应用于 STRUCT 内部字段


## 6. 跨引擎对比: JSON 支持

 引擎          JSON 类型    路径查询          JSON 索引
 MySQL(5.7+)   JSON         JSON_EXTRACT/->   函数索引(8.0+)
 PostgreSQL    JSON/JSONB   ->>/->             GIN 索引(JSONB)
 Hive          STRING       GET_JSON_OBJECT    无
 Spark SQL     STRING       GET_JSON_OBJECT    无
 BigQuery      JSON(预览)   JSON_EXTRACT       无
 ClickHouse    String       JSONExtract        无
 Trino         JSON         JSON_EXTRACT       无

 PostgreSQL 的 JSONB 是最强的 JSON 实现:
 预解析 + GIN 索引 + 丰富的操作符（@>、?、#>）

## 7. 已知限制

1. 无原生 JSON 类型: JSON 作为 STRING 存储，性能差

2. get_json_object 每次重新解析: 多字段提取效率低

3. json_tuple 只支持顶层字段: 嵌套字段需要 get_json_object

4. 无 JSON 构建函数: 不能在 SQL 中构建 JSON（无 JSON_OBJECT/JSON_ARRAY）

5. 无 JSON 修改函数: 不能在 SQL 中修改 JSON 字段


## 8. 对引擎开发者的启示

1. JSON 类型 vs 函数处理: Hive 选择了函数处理（不引入新类型），

    PostgreSQL 选择了原生类型（JSONB）。原生类型性能更好但实现复杂。
2. SerDe 模式是 JSON 处理的好方案: 在建表时解析一次，查询时直接用列访问

3. 复合类型(ARRAY/MAP/STRUCT)比 JSON 更适合分析:

    列式存储可以对复合类型做精确的列裁剪和统计
4. JSON 处理是大数据引擎的必备能力: 半结构化数据越来越多

