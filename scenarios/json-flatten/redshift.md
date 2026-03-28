# Redshift: JSON 展平为关系行 (JSON Flatten)

> 参考资料:
> - [Amazon Redshift - JSON Functions](https://docs.aws.amazon.com/redshift/latest/dg/json-functions.html)
> - [Amazon Redshift - SUPER Data Type](https://docs.aws.amazon.com/redshift/latest/dg/r_SUPER_type.html)
> - [Amazon Redshift - PartiQL](https://docs.aws.amazon.com/redshift/latest/dg/super-overview.html)


## 示例数据

```sql
CREATE TABLE orders_json (
    id   INT IDENTITY(1,1),
    data SUPER                    -- Redshift SUPER 类型（推荐）
);
```


用 JSON_PARSE 插入
```sql
INSERT INTO orders_json (data)
VALUES (JSON_PARSE('{"customer":"Alice","total":150.0,"items":[{"product":"Widget","qty":2,"price":25.0},{"product":"Gadget","qty":1,"price":100.0}],"address":{"city":"Beijing","zip":"100000"}}'));
```


## 1. 提取 JSON 字段（PartiQL 点语法）

```sql
SELECT id,
       data.customer::VARCHAR           AS customer,
       data.total::DECIMAL(10,2)        AS total,
       data.address.city::VARCHAR       AS city
FROM   orders_json;
```


## 2. UNNEST 展开数组（推荐, Redshift SUPER 类型）

```sql
SELECT o.id,
       o.data.customer::VARCHAR       AS customer,
       item.product::VARCHAR          AS product,
       item.qty::INT                  AS qty,
       item.price::DECIMAL(10,2)      AS price
FROM   orders_json o,
       o.data.items AS item;
```


## 3. JSON_EXTRACT_PATH_TEXT（旧版 VARCHAR 列存储 JSON）

CREATE TABLE orders_json_text (id INT, data VARCHAR(MAX));
SELECT id,
JSON_EXTRACT_PATH_TEXT(data, 'customer')     AS customer,
JSON_EXTRACT_PATH_TEXT(data, 'address','city') AS city
FROM orders_json_text;
