# Flink SQL: 复合类型

> 参考资料:
> - [Flink Documentation - Data Types (ARRAY)](https://nightlies.apache.org/flink/flink-docs-stable/docs/dev/table/types/#array)
> - [Flink Documentation - Data Types (MAP)](https://nightlies.apache.org/flink/flink-docs-stable/docs/dev/table/types/#map)
> - [Flink Documentation - Data Types (ROW)](https://nightlies.apache.org/flink/flink-docs-stable/docs/dev/table/types/#row)
> - [Flink Documentation - Built-in Functions](https://nightlies.apache.org/flink/flink-docs-stable/docs/dev/table/functions/systemFunctions/)

**引擎定位**: 流批一体计算引擎。表是外部系统的映射，支持 Changelog 语义和 Watermark 机制。

## ARRAY 类型


```sql
CREATE TABLE users (
    id     BIGINT,
    name   STRING,
    tags   ARRAY<STRING>,
    scores ARRAY<INT>
) WITH (
    'connector' = 'kafka',
    'topic' = 'users',
    'format' = 'json'
);

```

数组构造
```sql
SELECT ARRAY['admin', 'dev', 'ops'];

```

数组索引（从 1 开始）
```sql
SELECT tags[1] FROM users;

```

ARRAY 函数
```sql
SELECT CARDINALITY(tags) FROM users;               -- 长度
SELECT ELEMENT(ARRAY['only_one']) FROM users;       -- 单元素数组取值
SELECT ARRAY_CONTAINS(tags, 'admin') FROM users;    -- Flink 1.15+
SELECT ARRAY_DISTINCT(tags) FROM users;             -- Flink 1.16+
SELECT ARRAY_UNION(ARRAY[1,2], ARRAY[2,3]);        -- Flink 1.16+
SELECT ARRAY_CONCAT(ARRAY[1,2], ARRAY[3,4]);       -- Flink 1.16+
SELECT ARRAY_POSITION(tags, 'admin') FROM users;    -- Flink 1.16+
SELECT ARRAY_REMOVE(tags, 'admin') FROM users;      -- Flink 1.16+
SELECT ARRAY_REVERSE(tags) FROM users;              -- Flink 1.16+
SELECT ARRAY_SLICE(tags, 1, 2) FROM users;          -- Flink 1.17+
SELECT ARRAY_SORT(tags) FROM users;                 -- Flink 1.17+
SELECT ARRAY_APPEND(tags, 'new') FROM users;        -- Flink 1.17+
SELECT ARRAY_PREPEND('first', tags) FROM users;     -- Flink 1.17+

```

UNNEST: 展开数组
```sql
SELECT u.name, t.tag
FROM users u
CROSS JOIN UNNEST(u.tags) AS t(tag);

```

COLLECT: 聚合为数组（Flink 的 ARRAY_AGG）
```sql
SELECT department, COLLECT(name) AS members
FROM employees
GROUP BY department;

```

## MAP 类型


```sql
CREATE TABLE products (
    id         BIGINT,
    name       STRING,
    attributes MAP<STRING, STRING>,
    metrics    MAP<STRING, DOUBLE>
) WITH (
    'connector' = 'kafka',
    'topic' = 'products',
    'format' = 'json'
);

```

Map 构造
```sql
SELECT MAP['brand', 'Dell', 'ram', '16GB'];

```

Map 访问
```sql
SELECT attributes['brand'] FROM products;

```

Map 函数
```sql
SELECT CARDINALITY(attributes) FROM products;       -- 大小
SELECT MAP_KEYS(attributes) FROM products;          -- Flink 1.15+
SELECT MAP_VALUES(attributes) FROM products;        -- Flink 1.15+
SELECT MAP_ENTRIES(attributes) FROM products;       -- Flink 1.17+
SELECT MAP_UNION(MAP['a', 1], MAP['b', 2]);        -- Flink 1.17+

```

Map 展开
```sql
SELECT p.name, t.key, t.value
FROM products p
CROSS JOIN UNNEST(p.attributes) AS t(key, value);

```

## ROW 类型（= STRUCT）


```sql
CREATE TABLE orders (
    id       BIGINT,
    customer ROW<name STRING, email STRING>,
    address  ROW<street STRING, city STRING, state STRING, zip STRING>
) WITH (
    'connector' = 'kafka',
    'topic' = 'orders',
    'format' = 'json'
);

```

ROW 构造
```sql
SELECT ROW('Alice', 'alice@example.com');
SELECT (name, email) FROM source_table;

```

访问 ROW 字段
```sql
SELECT customer.name, customer.email FROM orders;
SELECT address.city FROM orders;

```

## 嵌套类型


ARRAY of ROW
```sql
CREATE TABLE events (
    id    BIGINT,
    items ARRAY<ROW<name STRING, qty INT, price DOUBLE>>
) WITH (
    'connector' = 'kafka',
    'topic' = 'events',
    'format' = 'json'
);

```

展开嵌套
```sql
SELECT e.id, t.name, t.qty, t.price
FROM events e
CROSS JOIN UNNEST(e.items) AS t(name, qty, price);

```

MAP of ARRAY
```sql
CREATE TABLE configs (
    id       BIGINT,
    settings MAP<STRING, ARRAY<STRING>>
) WITH (
    'connector' = 'kafka',
    'topic' = 'configs',
    'format' = 'json'
);

```

## 注意事项


## Flink SQL 原生支持 ARRAY、MAP、ROW

## 数组下标从 1 开始

## 许多数组/Map 函数从 Flink 1.15+ 开始添加

## COLLECT 是 Flink 的 ARRAY_AGG

## ROW 类型等价于 STRUCT

## 支持任意深度的嵌套

## JSON 格式自动映射复杂类型
