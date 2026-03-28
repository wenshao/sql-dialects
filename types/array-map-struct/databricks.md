# Databricks: 复合/复杂类型 (Array, Map, Struct)

> 参考资料:
> - [Databricks Documentation - Complex Types](https://docs.databricks.com/en/sql/language-manual/data-types/complex-types.html)
> - [Databricks Documentation - Array Functions](https://docs.databricks.com/en/sql/language-manual/functions/array-functions.html)
> - [Databricks Documentation - Map Functions](https://docs.databricks.com/en/sql/language-manual/functions/map-functions.html)


## Databricks 基于 Spark SQL，完全支持 ARRAY、MAP、STRUCT

参见 spark.sql 获取完整的 Spark SQL 复杂类型功能
本文件重点展示 Databricks 特有的增强功能

## ARRAY 类型


```sql
CREATE TABLE users (
    id     BIGINT,
    name   STRING,
    tags   ARRAY<STRING>,
    scores ARRAY<INT>
) USING DELTA;

INSERT INTO users VALUES
    (1, 'Alice', ARRAY('admin', 'dev'), ARRAY(90, 85, 95)),
    (2, 'Bob',   ARRAY('user'), ARRAY(70, 80));
```


数组索引（从 0 开始）
```sql
SELECT tags[0] FROM users;
SELECT element_at(tags, 1) FROM users;        -- 从 1 开始
```


ARRAY 函数
```sql
SELECT SIZE(tags), ARRAY_CONTAINS(tags, 'admin') FROM users;
SELECT SORT_ARRAY(scores), ARRAY_DISTINCT(tags) FROM users;
SELECT TRANSFORM(scores, x -> x * 2) FROM users;
SELECT FILTER(scores, x -> x > 80) FROM users;
SELECT AGGREGATE(scores, 0, (acc, x) -> acc + x) FROM users;
```


EXPLODE / LATERAL VIEW
```sql
SELECT id, EXPLODE(tags) AS tag FROM users;
```


COLLECT_LIST / COLLECT_SET
```sql
SELECT COLLECT_LIST(name) FROM users;
```


## MAP 类型


```sql
CREATE TABLE products (
    id         BIGINT,
    attributes MAP<STRING, STRING>,
    metrics    MAP<STRING, DOUBLE>
) USING DELTA;

INSERT INTO products VALUES
    (1, MAP('brand', 'Dell', 'ram', '16GB'), MAP('price', 999.99));

SELECT attributes['brand'] FROM products;
SELECT MAP_KEYS(attributes), MAP_VALUES(attributes) FROM products;
SELECT MAP_FILTER(attributes, (k, v) -> k = 'brand') FROM products;
```


## STRUCT 类型


```sql
CREATE TABLE orders (
    id       BIGINT,
    customer STRUCT<name: STRING, email: STRING>,
    items    ARRAY<STRUCT<name: STRING, qty: INT, price: DOUBLE>>
) USING DELTA;

INSERT INTO orders VALUES (
    1,
    STRUCT('Alice', 'alice@example.com'),
    ARRAY(STRUCT('Widget', 2, 9.99), STRUCT('Gadget', 1, 29.99))
);

SELECT customer.name, customer.email FROM orders;
SELECT INLINE(items) FROM orders;
```


## Databricks 特有增强


Photon 引擎对复杂类型的优化
Databricks Runtime 自动优化嵌套列的读取

Delta Lake Schema Evolution（自动适应复杂类型变化）
```sql
ALTER TABLE users SET TBLPROPERTIES ('delta.columnMapping.mode' = 'name');
```


液体聚簇 (Liquid Clustering, DBR 13.3+)
复杂类型列可以参与液体聚簇
```sql
ALTER TABLE users CLUSTER BY (name);
```


## 注意事项


1. 完全兼容 Spark SQL 的 ARRAY、MAP、STRUCT
2. Photon 引擎提供复杂类型加速
3. Delta Lake 支持复杂类型的 Schema Evolution
4. 参见 spark.sql 获取完整的函数列表
