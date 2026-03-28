# StarRocks: 复合类型 (Array, Map, Struct)

> 参考资料:
> - [1] StarRocks Documentation - Complex Types
>   https://docs.starrocks.io/docs/sql-reference/data-types/


## 1. ARRAY (2.0+)

```sql
CREATE TABLE users (
    id BIGINT, name VARCHAR(100), tags ARRAY<VARCHAR(50)>, scores ARRAY<INT>
) DUPLICATE KEY(id) DISTRIBUTED BY HASH(id) BUCKETS 8;

INSERT INTO users VALUES (1, 'Alice', ['admin', 'dev'], [90, 85, 95]);

SELECT tags[0] FROM users;  -- 从 0 开始(与 Doris 一致)
SELECT ARRAY_LENGTH(tags), ARRAY_CONTAINS(tags, 'admin') FROM users;
SELECT ARRAY_SORT(tags), ARRAY_DISTINCT(tags) FROM users;

```

UNNEST (SQL 标准风格，不同于 Doris 的 LATERAL VIEW EXPLODE)

```sql
SELECT u.name, tag FROM users u, UNNEST(u.tags) AS t(tag);

```

ARRAY_AGG

```sql
SELECT department, ARRAY_AGG(name) FROM employees GROUP BY department;

```

## 2. MAP (2.5+)

```sql
CREATE TABLE products (
    id BIGINT, name VARCHAR(100), attrs MAP<VARCHAR(50), VARCHAR(200)>
) DUPLICATE KEY(id) DISTRIBUTED BY HASH(id) BUCKETS 8;

SELECT attrs['brand'] FROM products;
SELECT MAP_KEYS(attrs), MAP_VALUES(attrs), MAP_SIZE(attrs) FROM products;

```

## 3. STRUCT (2.5+)

```sql
CREATE TABLE orders (
    id BIGINT, customer STRUCT<name VARCHAR(100), email VARCHAR(200)>
) DUPLICATE KEY(id) DISTRIBUTED BY HASH(id) BUCKETS 8;

SELECT customer.name FROM orders;

```

## 4. StarRocks vs Doris 差异

展开语法(核心差异):
- **Doris**: LATERAL VIEW EXPLODE(arr) t AS col    (Hive 风格)
- **StarRocks**: UNNEST(arr) AS t(col)                  (SQL 标准风格)

版本:
- **Doris**: ARRAY 1.2+, MAP/STRUCT 2.0+
- **StarRocks**: ARRAY 2.0+, MAP/STRUCT 2.5+

对引擎开发者的启示:
复合类型的列存实现需要嵌套编码(Nested Column Encoding):

```
ARRAY: repetition level + definition level(类似 Parquet)
MAP:   key array + value array
STRUCT: 展平为多列(每个字段一列)
```
