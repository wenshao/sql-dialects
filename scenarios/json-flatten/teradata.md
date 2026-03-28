# Teradata: JSON 展平为关系行 (JSON Flatten)

> 参考资料:
> - [Teradata Documentation - JSON Data Type](https://docs.teradata.com/r/Teradata-VantageTM-JSON-Data-Type)
> - [Teradata Documentation - JSON Shredding](https://docs.teradata.com/r/Teradata-VantageTM-SQL-Functions-Expressions-and-Predicates)


## 示例数据

```sql
CREATE TABLE orders_json (
    id   INTEGER GENERATED ALWAYS AS IDENTITY,
    data JSON(32000)
);
```


## 1. JSONExtract 提取字段（Teradata 15.0+）

```sql
SELECT id,
       data.JSONExtractValue('$.customer')      AS customer,
       data.JSONExtractValue('$.total')         AS total,
       data.JSONExtractValue('$.address.city')  AS city
FROM   orders_json;
```


## 2. JSON_TABLE 展开数组（Teradata 16.20+）

```sql
SELECT o.id, j.*
FROM   orders_json o,
       JSON_TABLE(o.data, '$.items[*]'
           COLUMNS (
               product VARCHAR(100) PATH '$.product',
               qty     INTEGER      PATH '$.qty',
               price   DECIMAL(10,2) PATH '$.price'
           )
       ) AS j;
```


## 3. JSON Shredding（将 JSON 打散到关系列）

```sql
SELECT id,
       data.JSONExtractValue('$.items[0].product') AS first_product,
       data.JSONExtractValue('$.items[1].product') AS second_product
FROM   orders_json;
```
