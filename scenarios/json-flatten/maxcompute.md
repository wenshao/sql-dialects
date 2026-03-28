# MaxCompute (ODPS): JSON 展平为关系行

> 参考资料:
> - [1] MaxCompute SQL - JSON Functions
>   https://help.aliyun.com/zh/maxcompute/user-guide/json-functions
> - [2] MaxCompute SQL - LATERAL VIEW
>   https://help.aliyun.com/zh/maxcompute/user-guide/lateral-view


## 1. GET_JSON_OBJECT 提取字段


假设: orders_json(id BIGINT, data STRING)
data 格式: {"customer":"Alice","total":150,"address":{"city":"NYC","zip":"10001"}}


```sql
SELECT id,
       GET_JSON_OBJECT(data, '$.customer')      AS customer,
       GET_JSON_OBJECT(data, '$.total')          AS total,
       GET_JSON_OBJECT(data, '$.address.city')   AS city,
       GET_JSON_OBJECT(data, '$.address.zip')    AS zip
FROM orders_json;

```

 注意: GET_JSON_OBJECT 总是返回 STRING
 需要 CAST 转换: CAST(GET_JSON_OBJECT(data, '$.total') AS DECIMAL(10,2))

## 2. JSON_TUPLE —— 一次提取多个字段（性能更好）


```sql
SELECT o.id, j.customer, j.total
FROM orders_json o
LATERAL VIEW JSON_TUPLE(o.data, 'customer', 'total') j AS customer, total;

```

 JSON_TUPLE 只解析一次 JSON 字符串
 对比多次 GET_JSON_OBJECT: N 个字段 = N 次解析 vs 1 次解析

## 3. JSON 数组展开


data 格式: {"customer":"Alice","items":[{"product":"A","qty":2},{"product":"B","qty":1}]}

方案 A: 复合类型 + EXPLODE（如果能转为 ARRAY<STRUCT>）
方案 B: 字符串解析（通用但复杂）


```sql
SELECT o.id,
       GET_JSON_OBJECT(o.data, '$.customer') AS customer,
       GET_JSON_OBJECT(item, '$.product')    AS product,
       GET_JSON_OBJECT(item, '$.qty')        AS qty
FROM orders_json o
LATERAL VIEW EXPLODE(
    SPLIT(
        REGEXP_REPLACE(REGEXP_REPLACE(
            GET_JSON_OBJECT(o.data, '$.items'),
        '^\\[', ''), '\\]$', ''),
        '\\},\\s*\\{'
    )
) t AS item;

```

 这个方案的局限:
   假设 JSON 数组元素中不包含 },{
   嵌套 JSON 可能导致错误拆分
   推荐: 使用原生 JSON 类型或在 UDF 中解析

## 4. 使用 ARRAY + STRUCT 替代 JSON（推荐方案）


如果可以控制表设计，推荐使用复合类型:

```sql
CREATE TABLE orders_structured (
    id       BIGINT,
    customer STRING,
    total    DECIMAL(10,2),
    items    ARRAY<STRUCT<product: STRING, qty: INT, price: DOUBLE>>
);

```

展开就非常简洁:

```sql
SELECT o.id, o.customer, t.item.product, t.item.qty, t.item.price
FROM orders_structured o
LATERAL VIEW EXPLODE(o.items) t AS item;

```

 性能对比:
   JSON STRING + GET_JSON_OBJECT: 每次查询解析 JSON → 慢
   ARRAY<STRUCT>: 列式存储原生读取 → 快，且支持谓词下推

## 5. 多层 JSON 嵌套展平


两层嵌套: customer → orders → items

```sql
SELECT
    GET_JSON_OBJECT(data, '$.name') AS customer,
    GET_JSON_OBJECT(order_str, '$.id') AS order_id,
    GET_JSON_OBJECT(item_str, '$.product') AS product
FROM customers_json
LATERAL VIEW EXPLODE(SPLIT(
    REGEXP_REPLACE(REGEXP_REPLACE(
        GET_JSON_OBJECT(data, '$.orders'), '^\\[', ''), '\\]$', ''),
    '\\},\\s*\\{')) orders AS order_str
LATERAL VIEW EXPLODE(SPLIT(
    REGEXP_REPLACE(REGEXP_REPLACE(
        GET_JSON_OBJECT(CONCAT('{', order_str, '}'), '$.items'), '^\\[', ''), '\\]$', ''),
    '\\},\\s*\\{')) items AS item_str;

```

 复杂度说明: 多层 JSON 用字符串操作展开非常脆弱
 推荐: 使用 Python UDF 或 TRANSFORM 处理复杂 JSON

## 6. 横向对比与引擎开发者启示


 JSON 展平方式:
   MaxCompute: GET_JSON_OBJECT + LATERAL VIEW（Hive 兼容，麻烦）
   BigQuery:   JSON_VALUE + UNNEST（简洁）
   PostgreSQL: jsonb_array_elements + ->>/->（最灵活）
   Snowflake:  FLATTEN(input => data:items)（最简洁!）
   ClickHouse: JSONExtract + arrayJoin

 对引擎开发者:
1. Snowflake FLATTEN 是 JSON 展平的最佳 API 设计 — 一个函数解决所有展平

2. JSON 数组展开应有原生支持（不应依赖 SPLIT + REGEXP 字符串黑科技）

3. ARRAY<STRUCT> 比 JSON STRING 性能好得多 — 引擎应鼓励复合类型

4. JSON_TUPLE 的"一次解析多字段"设计减少了重复解析开销

