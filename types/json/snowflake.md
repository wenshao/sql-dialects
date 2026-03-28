# Snowflake: JSON / VARIANT 类型

> 参考资料:
> - [1] Snowflake SQL Reference - VARIANT Data Type
>   https://docs.snowflake.com/en/sql-reference/data-types-semistructured
> - [2] Snowflake SQL Reference - Semi-Structured Functions
>   https://docs.snowflake.com/en/sql-reference/functions-semistructured


## 1. 核心概念: VARIANT 而非 JSON


Snowflake 没有独立的 JSON 类型，使用 VARIANT 存储所有半结构化数据。
VARIANT 可以存储: JSON, Avro, ORC, Parquet, XML 数据。
最大 16 MB/值。


```sql
CREATE TABLE events (id INTEGER, data VARIANT);

```

## 2. 插入 JSON 数据


```sql
INSERT INTO events VALUES (1, PARSE_JSON('{"name":"alice","age":25,"tags":["vip"]}'));
INSERT INTO events VALUES (2, OBJECT_CONSTRUCT('name', 'bob', 'age', 30));

```

## 3. 语法设计分析: : 路径运算符


冒号(:) 是 Snowflake 独有的 VARIANT 路径运算符:

```sql
SELECT data:name FROM events;              -- VARIANT 第一层（返回 VARIANT）
SELECT data:name::STRING FROM events;      -- 转为 STRING
SELECT data:tags[0]::STRING FROM events;   -- 数组索引
SELECT data:address.city FROM events;      -- 嵌套访问（点号）
SELECT data['name'] FROM events;           -- 方括号访问

```

 语法规则:
   : → 第一层字段访问
   . → 嵌套层级访问
   [n] → 数组索引（从 0 开始）
   ['key'] → 动态键名

 对比:
   PostgreSQL: data->>'name'（-> 返回 JSON，->> 返回文本）
   MySQL:      data->>'$.name'（$.path 语法）
   BigQuery:   JSON_VALUE(data, '$.name')
   Oracle:     JSON_VALUE(data, '$.name')

 对引擎开发者的启示:
   : 运算符比 ->/->> 更简洁，但引入了新的解析复杂度。
   data:field::TYPE 同时完成路径提取和类型转换 → 一步到位。

## 4. 查询与过滤


```sql
SELECT * FROM events WHERE data:name::STRING = 'alice';
SELECT * FROM events WHERE data:age::INT > 20;

```

类型转换

```sql
SELECT TRY_CAST(data:age AS INTEGER) FROM events;  -- 安全转换

```

## 5. 类型检查


```sql
SELECT TYPEOF(data:name) FROM events;       -- 'VARCHAR'
SELECT IS_NULL_VALUE(data:email) FROM events; -- JSON null 判断
SELECT IS_OBJECT(data) FROM events;
SELECT IS_ARRAY(data:tags) FROM events;

```

 IS_NULL_VALUE vs IS NULL:
 JSON null: {"field": null} → IS_NULL_VALUE = TRUE, data:field IS NULL = FALSE
 缺失字段: 无此 field    → IS_NULL_VALUE = FALSE, data:field IS NULL = TRUE

## 6. VARIANT 构造与修改


```sql
SELECT PARSE_JSON('{"name": "alice"}');
SELECT OBJECT_CONSTRUCT('name', 'alice', 'age', 25);
SELECT OBJECT_CONSTRUCT_KEEP_NULL('a', 1, 'b', NULL);
SELECT ARRAY_CONSTRUCT(1, 2, 3);
SELECT TO_VARIANT('hello');

```

修改

```sql
SELECT OBJECT_INSERT(data, 'email', 'a@e.com') FROM events;   -- 添加键
SELECT OBJECT_DELETE(data, 'tags') FROM events;                 -- 删除键
SELECT ARRAY_APPEND(data:tags, 'new_tag') FROM events;         -- 数组追加

```

## 7. FLATTEN 展开


展开数组

```sql
SELECT f.value::STRING AS tag
FROM events, LATERAL FLATTEN(input => data:tags) f;

```

展开对象为 KEY-VALUE

```sql
SELECT f.key, f.value
FROM events, LATERAL FLATTEN(input => data) f;

```

递归展开

```sql
SELECT f.path, f.key, f.value
FROM events, LATERAL FLATTEN(input => data, recursive => true) f;

```

## 8. 聚合


```sql
SELECT OBJECT_AGG(key, value) FROM t;
SELECT ARRAY_AGG(value) FROM t;

```

## 9. 内部优化: Sub-column Pruning

 Snowflake 自动推断 VARIANT 列的子列类型，
 为高频访问的路径创建独立的物理子列。
 查询 data:name 时可能只读取 name 子列而非整个 VARIANT。
 这使 VARIANT 的查询性能接近原生列（在高频路径上）。

## 横向对比: JSON 能力矩阵

| 能力          | Snowflake      | BigQuery     | PostgreSQL  | MySQL |
|------|------|------|------|------|
| 类型名称      | VARIANT        | JSON(STRING) | JSONB       | JSON |
| 路径语法      | : 冒号         | JSON_VALUE   | -> / ->>    | $.path |
| 安全转换      | TRY_CAST       | SAFE_CAST    | 异常块      | 不支持 |
| 展开为行      | FLATTEN        | JSON_EXTRACT | jsonb_array | JSON_TABLE |
| 索引加速      | Sub-column     | 不支持       | GIN 索引    | 不支持 |
| 修改操作      | OBJECT_INSERT  | 不支持       | jsonb_set   | JSON_SET |
| 最大大小      | 16MB           | 无限制       | 1GB         | 1GB |
| 类型检查      | TYPEOF/IS_*    | 不支持       | jsonb_typeof| JSON_TYPE |

