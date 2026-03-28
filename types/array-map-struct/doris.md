# Apache Doris: 复合类型 (Array, Map, Struct)

 Apache Doris: 复合类型 (Array, Map, Struct)

 参考资料:
   [1] Doris Documentation - Complex Types
       https://doris.apache.org/docs/sql-manual/data-types/

## 1. ARRAY 类型 (1.2+)

```sql
CREATE TABLE users (
    id BIGINT, name VARCHAR(100), tags ARRAY<VARCHAR(50)>, scores ARRAY<INT>
) DUPLICATE KEY(id) DISTRIBUTED BY HASH(id) BUCKETS 8;

INSERT INTO users VALUES (1, 'Alice', ['admin', 'dev'], [90, 85, 95]);

```

数组索引(从 0 开始——不同于 BigQuery/PG 从 1 开始)

```sql
SELECT tags[0] FROM users;

```

数组函数

```sql
SELECT ARRAY_LENGTH(tags), ARRAY_CONTAINS(tags, 'admin') FROM users;
SELECT ARRAY_SORT(tags), ARRAY_DISTINCT(tags) FROM users;
SELECT ARRAY_UNION(ARRAY[1,2], ARRAY[2,3]);
SELECT ARRAY_INTERSECT(ARRAY[1,2,3], ARRAY[2,3,4]);
SELECT ARRAY_JOIN(tags, ', ') FROM users;

```

EXPLODE (Hive 风格展开)

```sql
SELECT u.name, t.tag FROM users u LATERAL VIEW EXPLODE(u.tags) t AS tag;

```

COLLECT_LIST / COLLECT_SET (聚合为数组)

```sql
SELECT COLLECT_LIST(name), COLLECT_SET(name) FROM users;
```

ARRAY_AGG (2.0+)

```sql
SELECT department, ARRAY_AGG(name) FROM employees GROUP BY department;

```

## 2. MAP 类型 (2.0+)

```sql
CREATE TABLE products (
    id BIGINT, name VARCHAR(100), attributes MAP<VARCHAR(50), VARCHAR(200)>
) DUPLICATE KEY(id) DISTRIBUTED BY HASH(id) BUCKETS 8;

SELECT attributes['brand'] FROM products;
SELECT MAP_KEYS(attributes), MAP_VALUES(attributes), MAP_SIZE(attributes) FROM products;

```

Map 展开

```sql
SELECT p.name, t.key, t.value FROM products p LATERAL VIEW EXPLODE(p.attributes) t AS key, value;

```

## 3. STRUCT 类型 (2.0+)

```sql
CREATE TABLE orders (
    id BIGINT,
    customer STRUCT<name: VARCHAR(100), email: VARCHAR(200)>,
    address STRUCT<city: VARCHAR(100), zip: VARCHAR(10)>
) DUPLICATE KEY(id) DISTRIBUTED BY HASH(id) BUCKETS 8;

SELECT customer.name, address.city FROM orders;

```

## 4. 嵌套类型

```sql
CREATE TABLE event_items (
    id BIGINT,
    items ARRAY<STRUCT<name: VARCHAR(100), qty: INT, price: DOUBLE>>
) DUPLICATE KEY(id) DISTRIBUTED BY HASH(id) BUCKETS 8;

```

## 5. 对比其他引擎

数组下标:
Doris/StarRocks: 从 0 开始
BigQuery/PG:     从 1 开始(OFFSET 从 0 开始)
ClickHouse:      从 1 开始

展开语法:
Doris:     LATERAL VIEW EXPLODE (Hive 风格)
StarRocks: UNNEST + LATERAL JOIN (SQL 标准风格)
ClickHouse: arrayJoin
BigQuery:  UNNEST
PostgreSQL: UNNEST

