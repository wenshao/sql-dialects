# Spark SQL: JSON 展平为关系行 (JSON Flatten)

> 参考资料:
> - [1] Spark SQL - from_json / get_json_object
>   https://spark.apache.org/docs/latest/api/sql/index.html#from_json
> - [2] Spark SQL - JSON Data Source
>   https://spark.apache.org/docs/latest/sql-data-sources-json.html


## 示例数据

```sql
CREATE OR REPLACE TEMPORARY VIEW orders_json AS
SELECT 1 AS id, '{"customer":"Alice","total":150.0,"items":[{"product":"Widget","qty":2,"price":25.0},{"product":"Gadget","qty":1,"price":100.0}],"address":{"city":"Beijing","zip":"100000"}}' AS data;

```

## 1. get_json_object: 路径提取（最简单）

```sql
SELECT id,
       get_json_object(data, '$.customer')      AS customer,
       get_json_object(data, '$.total')          AS total,
       get_json_object(data, '$.address.city')   AS city,
       get_json_object(data, '$.items[0].product') AS first_item
FROM orders_json;

```

 get_json_object 总是返回 STRING，需要 CAST 转换类型
 对比: PostgreSQL 的 json_extract_path_text 类似
       MySQL 的 JSON_EXTRACT / ->> 操作符

## 2. from_json + Schema: 结构化解析（推荐）

```sql
SELECT id, parsed.customer, parsed.total, parsed.address.city AS city
FROM (
    SELECT id,
           from_json(data,
               'customer STRING, total DOUBLE, items ARRAY<STRUCT<product:STRING,qty:INT,price:DOUBLE>>, address STRUCT<city:STRING,zip:STRING>'
           ) AS parsed
    FROM orders_json
);

```

 from_json 的优势:
1. 一次解析，多次使用字段（get_json_object 每次调用都重新解析 JSON）

2. 返回类型化的 STRUCT——可以直接用 dot notation 访问嵌套字段

3. 数组字段返回 ARRAY 类型——可以直接 EXPLODE


## 3. from_json + EXPLODE: 展开 JSON 数组

```sql
SELECT id, parsed.customer, item.product, item.qty, item.price
FROM (
    SELECT id,
           from_json(data,
               'customer STRING, total DOUBLE, items ARRAY<STRUCT<product:STRING,qty:INT,price:DOUBLE>>'
           ) AS parsed
    FROM orders_json
)
LATERAL VIEW EXPLODE(parsed.items) exploded AS item;

```

## 4. json_tuple: 多字段提取（Hive 兼容，高效）

```sql
SELECT o.id, j.customer, j.total
FROM orders_json o
LATERAL VIEW json_tuple(o.data, 'customer', 'total') j AS customer, total;

```

 json_tuple vs get_json_object:
   json_tuple: 一次解析提取多个字段（更高效），但不支持嵌套路径
   get_json_object: 支持 $.a.b.c 路径，但每次调用都重新解析

## 5. schema_of_json: Schema 推断

```sql
SELECT schema_of_json('{"name":"","age":0,"tags":[""]}');
```

返回: STRUCT<age: BIGINT, name: STRING, tags: ARRAY<STRING>>

可以用推断的 Schema 动态解析:

```sql
SELECT from_json(data,
    schema_of_json('{"customer":"","total":0.0,"items":[{"product":"","qty":0,"price":0.0}]}')
) AS parsed
FROM orders_json;

```

## 6. inline: 展开 STRUCT 数组

```sql
SELECT id, customer, product, qty, price
FROM (
    SELECT id,
           from_json(data, 'customer STRING, items ARRAY<STRUCT<product:STRING,qty:INT,price:DOUBLE>>') AS parsed
    FROM orders_json
)
LATERAL VIEW inline(parsed.items) AS product, qty, price;

```

 inline vs EXPLODE:
   EXPLODE: 返回一列（STRUCT 类型），需要 item.product 访问字段
   inline:  直接展开 STRUCT 的所有字段为独立列

## 7. 对引擎开发者的设计分析


 Spark 的 JSON 处理策略: "STRING + 函数" 而非"原生 JSON 类型"
   优点: 与 Parquet/ORC 列式存储无缝对接（JSON 存为 STRING 列）
   缺点: 每次查询都重新解析 JSON（无 JSON 索引）

 对比:
   PostgreSQL: 原生 JSON/JSONB 类型 + GIN 索引（最强大的内建 JSON 支持）
   MySQL:      JSON 类型 + 虚拟列索引（5.7+）
   BigQuery:   JSON 类型（2022+）+ JSON_QUERY/JSON_VALUE 函数
   Spark:      STRING + from_json/get_json_object（无原生类型）
   Spark 4.0:  Variant 类型（半结构化数据原生支持，类似 Snowflake VARIANT）

 Spark 4.0 的 Variant 类型将改变这一局面:
   VARIANT 是二进制格式，解析一次即可多次访问字段
   类似 Snowflake 的 VARIANT 和 BigQuery 的 JSON 类型

## 8. 版本演进

Spark 2.0: get_json_object, json_tuple
Spark 2.1: from_json, to_json
Spark 2.4: schema_of_json
Spark 3.5: JSON_OBJECT, JSON_ARRAY
Spark 4.0: Variant 类型（原生半结构化支持）

