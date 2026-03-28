# Vertica: JSON 展平为关系行 (JSON Flatten)

> 参考资料:
> - [Vertica Documentation - Flex Tables and JSON](https://www.vertica.com/docs/latest/HTML/Content/Authoring/FlexTables/FlexTables.htm)
> - [Vertica Documentation - JSON Functions](https://www.vertica.com/docs/latest/HTML/Content/Authoring/SQLReferenceManual/Functions/JSON/JSONFunctions.htm)


## 示例数据

```sql
CREATE TABLE orders_json (
    id   INT,
    data VARCHAR(10000)
);

INSERT INTO orders_json VALUES
(1, '{"customer":"Alice","total":150.0,"items":[{"product":"Widget","qty":2,"price":25.0},{"product":"Gadget","qty":1,"price":100.0}],"address":{"city":"Beijing","zip":"100000"}}');
INSERT INTO orders_json VALUES
(2, '{"customer":"Bob","total":80.0,"items":[{"product":"Widget","qty":3,"price":25.0},{"product":"Doohickey","qty":1,"price":5.0}],"address":{"city":"Shanghai","zip":"200000"}}');
COMMIT;
```


## 1. JSON 函数提取字段（Vertica 9.x+）

```sql
SELECT id,
       JSON_EXTRACT_PATH_TEXT(data, 'customer')       AS customer,
       JSON_EXTRACT_PATH_TEXT(data, 'total')::NUMERIC  AS total,
       JSON_EXTRACT_PATH_TEXT(data, 'address', 'city') AS city
FROM   orders_json;
```


## 2. Flex Table 方式处理 JSON

```sql
CREATE FLEX TABLE orders_flex();
COPY orders_flex FROM STDIN PARSER fjsonparser();
-- 然后可以直接用 MapItems 等函数
```


## 3. 数字表 + JSON 数组索引

```sql
WITH nums AS (
    SELECT ROW_NUMBER() OVER () - 1 AS n
    FROM (SELECT 1 UNION ALL SELECT 2 UNION ALL SELECT 3
          UNION ALL SELECT 4 UNION ALL SELECT 5) t(x)
)
SELECT o.id,
       JSON_EXTRACT_PATH_TEXT(o.data, 'customer') AS customer,
       JSON_EXTRACT_PATH_TEXT(
           JSON_EXTRACT_ARRAY_ELEMENT_TEXT(
               JSON_EXTRACT_PATH_TEXT(o.data, 'items'), n.n
           ), 'product'
       ) AS product
FROM   orders_json o
JOIN   nums n ON n.n < JSON_ARRAY_LENGTH(JSON_EXTRACT_PATH_TEXT(o.data, 'items'));
```
