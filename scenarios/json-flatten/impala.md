# Apache Impala: JSON 展平为关系行 (JSON Flatten)

> 参考资料:
> - [Impala Documentation - Complex Types (ARRAY, MAP, STRUCT)](https://impala.apache.org/docs/build/html/topics/impala_complex_types.html)
> - [Impala Documentation - get_json_object](https://impala.apache.org/docs/build/html/topics/impala_misc_functions.html)
> - [Impala Documentation - JSON Functions](https://impala.apache.org/docs/build/html/topics/impala_json_functions.html)


## 1. 示例数据（JSON 字符串存储）


```sql
CREATE TABLE orders_json (
    id   INT,
    data STRING
)
STORED AS TEXTFILE;

INSERT INTO orders_json VALUES
    (1, '{"customer": "Alice", "total": 150.00, "items": [{"product": "Widget", "qty": 2, "price": 25.00}, {"product": "Gadget", "qty": 1, "price": 100.00}], "address": {"city": "Beijing", "zip": "100000"}}'),
    (2, '{"customer": "Bob", "total": 80.00, "items": [{"product": "Widget", "qty": 3, "price": 25.00}, {"product": "Doohickey", "qty": 1, "price": 5.00}], "address": {"city": "Shanghai", "zip": "200000"}}');
```


## 2. get_json_object 提取标量字段


```sql
SELECT id,
       get_json_object(data, '$.customer')       AS customer,
       CAST(get_json_object(data, '$.total') AS DOUBLE) AS total,
       get_json_object(data, '$.address.city')   AS city,
       get_json_object(data, '$.address.zip')    AS zip
FROM   orders_json;
```


get_json_object 使用 JSONPath 语法
$        : 根对象
.key     : 对象字段访问
[*]      : 数组所有元素
[0]      : 数组第一个元素
返回值始终为 STRING 类型，需要 CAST 转换

## 3. 提取 JSON 数组中的单个元素


```sql
SELECT id,
       get_json_object(data, '$.items[0].product') AS first_product,
       get_json_object(data, '$.items[0].qty')     AS first_qty,
       get_json_object(data, '$.items[1].product') AS second_product,
       get_json_object(data, '$.items[1].qty')     AS second_qty
FROM   orders_json;
```


局限: 需要提前知道数组长度，无法动态展开所有元素
这是 Impala JSON 字符串处理的主要短板

## 4. 复杂类型: Parquet/ORC 嵌套结构（推荐方案）


Impala 真正强大的 JSON 处理方式是使用 Parquet/ORC 的复杂类型
将 JSON 数据在 ETL 阶段转为 Parquet 格式

```sql
CREATE TABLE orders_complex (
    id       INT,
    customer STRING,
    total    DOUBLE,
    address  STRUCT<city: STRING, zip: STRING>,
    items    ARRAY<STRUCT<product: STRING, qty: INT, price: DOUBLE>>
)
STORED AS PARQUET;
```


查询嵌套数组（自动展开为多行）
```sql
SELECT o.id, o.customer, item.product, item.qty, item.price
FROM   orders_complex o, o.items item;
```


**设计分析: 直接引用 o.items 实现数组展开**
Impala 对复杂类型的原生支持非常优雅
无需 LATERAL 关键字，直接在 FROM 子句中引用数组列
这是 Impala 与其他数据库最大的不同

## 5. 提取 STRUCT 嵌套字段


```sql
SELECT id, customer, address.city, address.zip
FROM   orders_complex;
```


STRUCT 字段用 . 访问，语法简洁

## 6. MAP 类型展开键值对


CREATE TABLE events_metadata (
id        INT,
event_ts  TIMESTAMP,
meta      MAP<STRING, STRING>
) STORED AS PARQUET;

SELECT id, meta_key, meta_value
FROM   events_metadata, meta;

MAP 类型在 FROM 子句中引用时自动展开为 (key, value) 行

## 7. 聚合 + 数组展开组合


```sql
SELECT o.customer,
       COUNT(*)                    AS item_count,
       SUM(item.qty * item.price)  AS total_amount
FROM   orders_complex o, o.items item
GROUP  BY o.customer;
```


展开后可以直接进行聚合计算

## 8. JSON 字符串 → Parquet 复杂类型（ETL 策略）


使用 Hive/Spark 将 JSON 转为 Parquet:
INSERT OVERWRITE TABLE orders_complex
SELECT id, get_json_object(data, '$.customer'), ...
FROM orders_json;

或者直接使用 Spark 的 JSON 读取器:
spark.read.json(path).write.parquet(output)

## 9. 横向对比与对引擎开发者的启示


1. Impala JSON 处理的两条路径:
路径 A: get_json_object 处理 JSON 字符串（灵活但受限）
路径 B: 复杂类型（ARRAY/MAP/STRUCT）处理嵌套数据（推荐）

2. 与其他数据库对比:
PostgreSQL: LATERAL + jsonb_array_elements（组合式）
Hive:       LATERAL VIEW explode（类似 Impala 复杂类型）
Presto:     CROSS JOIN UNNEST + CAST(JSON_PARSE ...)（JSON + 数组组合）
Spark SQL:  from_json + explode（类型安全的 JSON 解析）

**对引擎开发者:**

Impala 的"数组列直接在 FROM 中引用"设计非常优雅
对于大数据场景，Parquet 复杂类型比运行时 JSON 解析高效得多
JSON 字符串 → Parquet 复杂类型的 ETL 策略是最佳实践
若要增强 JSON 字符串处理能力，可参考 Presto/Trino 的 JSON 函数设计
