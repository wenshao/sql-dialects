# Flink SQL: JSON 展开

> 参考资料:
> - [Flink Documentation - JSON Functions](https://nightlies.apache.org/flink/flink-docs-stable/docs/dev/table/functions/systemfunctions/#json-functions)
> - [Flink Documentation - JSON Format](https://nightlies.apache.org/flink/flink-docs-stable/docs/connectors/table/formats/json/)

**引擎定位**: 流批一体计算引擎。表是外部系统的映射，支持 Changelog 语义和 Watermark 机制。

## 示例: 使用 JSON 格式的表

```sql
CREATE TABLE orders_json (
    customer STRING,
    total    DOUBLE,
    items    ARRAY<ROW<product STRING, qty INT, price DOUBLE>>,
    address  ROW<city STRING, zip STRING>
) WITH (
    'connector' = 'kafka',
    'format'    = 'json'
);

```

## 提取嵌套字段

```sql
SELECT customer, total, address.city, address.zip
FROM   orders_json;

```

## CROSS JOIN UNNEST 展开数组

```sql
SELECT o.customer, item.product, item.qty, item.price
FROM   orders_json o
CROSS JOIN UNNEST(o.items) AS item;

```

## JSON_VALUE / JSON_QUERY（Flink 1.15+, 字符串 JSON）

CREATE TABLE raw_json (data STRING) WITH (...);
SELECT JSON_VALUE(data, '$.customer') AS customer,
       JSON_VALUE(data, '$.total' RETURNING DOUBLE) AS total
FROM raw_json;

## JSON_ARRAYAGG / JSON_OBJECTAGG（反向）

SELECT JSON_OBJECTAGG(KEY customer VALUE total) FROM orders_json;
