# Hive: JSON 展平为关系行 (JSON Flatten)

> 参考资料:
> - [1] Apache Hive - get_json_object / json_tuple
>   https://cwiki.apache.org/confluence/display/Hive/LanguageManual+UDF
> - [2] Apache Hive - JsonSerDe
>   https://cwiki.apache.org/confluence/display/Hive/LanguageManual+DDL


## 1. get_json_object: 路径查询

```sql
SELECT id,
    GET_JSON_OBJECT(data, '$.customer')     AS customer,
    GET_JSON_OBJECT(data, '$.total')        AS total,
    GET_JSON_OBJECT(data, '$.address.city') AS city
FROM orders_json;

```

 get_json_object 使用 JSONPath 语法:
 $.key:      顶层字段
 $.key.sub:  嵌套字段
 $.array[0]: 数组元素

 限制: 每次调用只提取一个字段，多字段需要多次调用（多次解析 JSON 字符串）

## 2. json_tuple: 一次提取多个字段 (推荐)

```sql
SELECT o.id, j.customer, j.total
FROM orders_json o
LATERAL VIEW JSON_TUPLE(o.data, 'customer', 'total') j AS customer, total;

```

 json_tuple 比多次 get_json_object 高效: 只解析一次 JSON 字符串
 限制: 只能提取顶层字段，不支持嵌套路径

 设计对比: get_json_object vs json_tuple
 get_json_object: 灵活（支持嵌套路径），但多字段时重复解析
 json_tuple:      高效（一次解析多字段），但只支持顶层字段
 推荐: 顶层字段用 json_tuple，嵌套字段用 get_json_object

## 3. JSON 数组展开

JSON 数组字符串 → Hive ARRAY → EXPLODE

```sql
SELECT o.id,
    GET_JSON_OBJECT(o.data, '$.customer') AS customer,
    GET_JSON_OBJECT(item, '$.product')    AS product,
    GET_JSON_OBJECT(item, '$.qty')        AS qty,
    GET_JSON_OBJECT(item, '$.price')      AS price
FROM orders_json o
LATERAL VIEW EXPLODE(
    SPLIT(REGEXP_REPLACE(REGEXP_REPLACE(
        GET_JSON_OBJECT(o.data, '$.items'),
        '^\\[|\\]$', ''), '\\},\\s*\\{', '},,{'), ',,')
) exploded AS item;

```

 这个方法很 hack: 手动拆分 JSON 数组字符串
 更好的方案: 使用 JsonSerDe 建表（见第 4 节）

## 4. JsonSerDe 建表: 推荐方案

直接用表结构映射 JSON 字段

```sql
CREATE TABLE orders_serde (
    customer STRING,
    total    DOUBLE,
    items    ARRAY<STRUCT<product:STRING, qty:INT, price:DOUBLE>>,
    address  STRUCT<city:STRING, zip:STRING>
)
ROW FORMAT SERDE 'org.apache.hive.hcatalog.data.JsonSerDe'
STORED AS TEXTFILE;

```

使用 LATERAL VIEW EXPLODE 展开嵌套数组

```sql
SELECT o.customer, o.address.city, item.product, item.qty, item.price
FROM orders_serde o
LATERAL VIEW EXPLODE(o.items) exploded AS item;

```

 JsonSerDe 的优势:
### 1. Schema-on-Read: JSON 字段自动映射到 Hive 列

### 2. 嵌套类型: ARRAY<STRUCT<...>> 直接映射 JSON 数组

### 3. 不需要 get_json_object: 直接用列名和点号访问


## 5. 跨引擎对比: JSON 处理

 引擎          JSON 类型   路径查询             数组展开
 MySQL(5.7+)   JSON        JSON_EXTRACT/->      JSON_TABLE(8.0+)
 PostgreSQL    JSON/JSONB  ->>/->               jsonb_array_elements
 Hive          STRING      GET_JSON_OBJECT      LATERAL VIEW EXPLODE
 Spark SQL     STRING      GET_JSON_OBJECT      from_json + explode
 BigQuery      JSON(预览)  JSON_EXTRACT         UNNEST
 Trino         JSON        JSON_EXTRACT         UNNEST(CAST)

## 6. 对引擎开发者的启示

### 1. SerDe 模式是处理半结构化数据的好方案:

    将 JSON 解析推到建表阶段，查询时直接用列式访问
### 2. JSON 路径查询 vs 原生类型: 路径查询灵活但性能差（每次运行时解析）

    原生 JSON 类型（PostgreSQL JSONB）预解析 + 索引是更好的方案
### 3. JSON 数组展开应该有一等语法: Hive 的 SPLIT/REGEXP 拆分 JSON 数组很脆弱

