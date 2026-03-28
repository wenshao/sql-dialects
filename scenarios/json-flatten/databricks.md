# Databricks: JSON 展平为关系行 (JSON Flatten)

> 参考资料:
> - [Databricks SQL Reference - from_json](https://docs.databricks.com/sql/language-manual/functions/from_json.html)
> - [Databricks SQL Reference - explode / inline](https://docs.databricks.com/sql/language-manual/functions/explode.html)
> - [Databricks SQL Reference - schema_of_json](https://docs.databricks.com/sql/language-manual/functions/schema_of_json.html)


## 示例数据

```sql
CREATE OR REPLACE TEMPORARY VIEW orders_json AS
SELECT 1 AS id, '{"customer":"Alice","total":150.0,"items":[{"product":"Widget","qty":2,"price":25.0},{"product":"Gadget","qty":1,"price":100.0}],"address":{"city":"Beijing","zip":"100000"}}' AS data;
```


## 1. get_json_object 提取字段

```sql
SELECT id,
       get_json_object(data, '$.customer')      AS customer,
       get_json_object(data, '$.address.city')  AS city
FROM   orders_json;
```


## 2. from_json + schema_of_json（自动推导 Schema）

```sql
SELECT id, parsed.*
FROM (
    SELECT id, from_json(data, schema_of_json(data)) AS parsed
    FROM   orders_json
);
```


## 3. from_json + explode 展开数组

```sql
SELECT id, parsed.customer, item.*
FROM (
    SELECT id,
           from_json(data,
               'STRUCT<customer:STRING,total:DOUBLE,items:ARRAY<STRUCT<product:STRING,qty:INT,price:DOUBLE>>,address:STRUCT<city:STRING,zip:STRING>>'
           ) AS parsed
    FROM orders_json
)
LATERAL VIEW explode(parsed.items) AS item;
```


## 4. inline 展开（直接将 ARRAY<STRUCT> 展平为列）

```sql
SELECT id, customer, product, qty, price
FROM (
    SELECT id,
           from_json(data, 'STRUCT<customer:STRING,items:ARRAY<STRUCT<product:STRING,qty:INT,price:DOUBLE>>>') AS parsed
    FROM orders_json
)
LATERAL VIEW inline(parsed.items) AS product, qty, price;
```
