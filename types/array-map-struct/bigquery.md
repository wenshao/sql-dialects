# BigQuery: 复合/复杂类型 (Array, Map, Struct)

> 参考资料:
> - [1] BigQuery Documentation - Data Types (ARRAY)
>   https://cloud.google.com/bigquery/docs/reference/standard-sql/data-types#array_type
> - [2] BigQuery Documentation - Data Types (STRUCT)
>   https://cloud.google.com/bigquery/docs/reference/standard-sql/data-types#struct_type
> - [3] BigQuery Documentation - Array Functions
>   https://cloud.google.com/bigquery/docs/reference/standard-sql/array_functions
> - [4] BigQuery Documentation - UNNEST
>   https://cloud.google.com/bigquery/docs/reference/standard-sql/query-syntax#unnest_operator


## ARRAY 类型


定义数组列

```sql
CREATE TABLE users (
    id      INT64 NOT NULL,
    name    STRING NOT NULL,
    tags    ARRAY<STRING>,                     -- 字符串数组
    scores  ARRAY<INT64>,                      -- 整数数组
    emails  ARRAY<STRING>
);

```

插入数组数据

```sql
INSERT INTO users VALUES
    (1, 'Alice', ['admin', 'dev'], [90, 85, 95], ['alice@a.com']),
    (2, 'Bob',   ['user', 'tester'], [70, 80, 75], ['bob@b.com', 'bob2@b.com']);

```

数组构造

```sql
SELECT ['a', 'b', 'c'] AS arr;
SELECT ARRAY<INT64>[1, 2, 3] AS typed_arr;

```

数组索引（从 0 开始，使用 OFFSET；从 1 开始，使用 ORDINAL）

```sql
SELECT tags[OFFSET(0)] FROM users;           -- 第一个元素（从 0）
SELECT tags[ORDINAL(1)] FROM users;          -- 第一个元素（从 1）
SELECT tags[SAFE_OFFSET(10)] FROM users;     -- 越界返回 NULL

```

## ARRAY 函数


ARRAY_LENGTH: 长度

```sql
SELECT ARRAY_LENGTH(tags) FROM users;

```

ARRAY_CONCAT: 连接数组

```sql
SELECT ARRAY_CONCAT(['a','b'], ['c','d']);    -- ['a','b','c','d']

```

ARRAY_REVERSE: 反转

```sql
SELECT ARRAY_REVERSE([1,2,3]);               -- [3,2,1]

```

ARRAY_TO_STRING: 转为字符串

```sql
SELECT ARRAY_TO_STRING(['a','b','c'], ', '); -- 'a, b, c'

```

GENERATE_ARRAY: 生成数字数组

```sql
SELECT GENERATE_ARRAY(1, 10);                -- [1,2,...,10]
SELECT GENERATE_ARRAY(0, 10, 2);             -- [0,2,4,6,8,10]

```

GENERATE_DATE_ARRAY: 生成日期数组

```sql
SELECT GENERATE_DATE_ARRAY('2024-01-01', '2024-01-07');

```

ARRAY_INCLUDES (= 包含检查)

```sql
SELECT 'admin' IN UNNEST(tags) FROM users;

```

## UNNEST: 展开数组为行


基本 UNNEST

```sql
SELECT id, name, tag
FROM users, UNNEST(tags) AS tag;

```

WITH OFFSET（带索引展开）

```sql
SELECT id, name, tag, offset
FROM users, UNNEST(tags) AS tag WITH OFFSET;

```

UNNEST 在 WHERE 中

```sql
SELECT * FROM users WHERE 'admin' IN UNNEST(tags);

```

UNNEST 多个数组

```sql
SELECT id, tag, score
FROM users,
     UNNEST(tags) AS tag WITH OFFSET AS tag_off,
     UNNEST(scores) AS score WITH OFFSET AS score_off
WHERE tag_off = score_off;

```

## ARRAY_AGG: 聚合为数组


```sql
SELECT department, ARRAY_AGG(name ORDER BY name) AS members
FROM employees
GROUP BY department;

```

去重

```sql
SELECT ARRAY_AGG(DISTINCT tag) AS unique_tags
FROM users, UNNEST(tags) AS tag;

```

限制数量

```sql
SELECT ARRAY_AGG(name ORDER BY salary DESC LIMIT 5) AS top5
FROM employees;

```

忽略 NULL

```sql
SELECT ARRAY_AGG(val IGNORE NULLS) FROM t;

```

## STRUCT 类型


定义 STRUCT 列

```sql
CREATE TABLE orders (
    id          INT64 NOT NULL,
    customer    STRUCT<name STRING, email STRING>,
    address     STRUCT<street STRING, city STRING, state STRING, zip STRING>,
    created_at  TIMESTAMP
);

```

插入 STRUCT 数据

```sql
INSERT INTO orders VALUES (
    1,
    STRUCT('Alice', 'alice@example.com'),
    STRUCT('123 Main St', 'Springfield', 'IL', '62701'),
    CURRENT_TIMESTAMP()
);

```

构造 STRUCT

```sql
SELECT STRUCT('Alice' AS name, 30 AS age);
SELECT STRUCT<name STRING, age INT64>('Alice', 30);

```

访问 STRUCT 字段

```sql
SELECT customer.name, customer.email FROM orders;
SELECT address.city, address.zip FROM orders;

```

## 嵌套类型


ARRAY of STRUCT（最常用的嵌套模式）

```sql
CREATE TABLE events (
    id       INT64 NOT NULL,
    user_id  INT64,
    items    ARRAY<STRUCT<
        product_id INT64,
        name       STRING,
        quantity   INT64,
        price      FLOAT64
    >>
);

INSERT INTO events VALUES (
    1, 100,
    [
        STRUCT(1, 'Widget', 2, 9.99),
        STRUCT(2, 'Gadget', 1, 29.99)
    ]
);

```

查询嵌套结构

```sql
SELECT id, item.name, item.quantity, item.price
FROM events, UNNEST(items) AS item;

```

嵌套聚合

```sql
SELECT user_id,
    ARRAY_AGG(STRUCT(item.name, item.quantity)) AS order_summary
FROM events, UNNEST(items) AS item
GROUP BY user_id;

```

STRUCT 嵌套 STRUCT

```sql
CREATE TABLE profiles (
    id      INT64,
    info    STRUCT<
        personal STRUCT<name STRING, age INT64>,
        contact  STRUCT<email STRING, phone STRING>
    >
);

SELECT info.personal.name, info.contact.email FROM profiles;

```

 ARRAY of ARRAY（BigQuery 不支持！）
 BigQuery 不允许 ARRAY<ARRAY<...>>
 替代方案: 使用 ARRAY<STRUCT<items ARRAY<...>>>

## MAP 替代方案


BigQuery 没有原生 MAP 类型
方案 1: ARRAY<STRUCT<key, value>>

```sql
CREATE TABLE config (
    id       INT64,
    settings ARRAY<STRUCT<key STRING, value STRING>>
);

INSERT INTO config VALUES (1, [
    STRUCT('theme', 'dark'),
    STRUCT('lang', 'en'),
    STRUCT('timezone', 'UTC')
]);

```

查找特定键

```sql
SELECT s.value
FROM config, UNNEST(settings) AS s
WHERE s.key = 'theme';

```

方案 2: JSON 类型（BigQuery GA）

```sql
CREATE TABLE config_v2 (
    id       INT64,
    settings JSON
);

INSERT INTO config_v2 VALUES (1, JSON '{"theme": "dark", "lang": "en"}');

SELECT JSON_VALUE(settings, '$.theme') FROM config_v2;

```

## JSON 类型


JSON 列

```sql
CREATE TABLE logs (
    id   INT64,
    data JSON
);

INSERT INTO logs VALUES (1, JSON '{"level": "info", "tags": ["web", "api"]}');

```

JSON 函数

```sql
SELECT JSON_VALUE(data, '$.level') FROM logs;         -- 标量值
SELECT JSON_QUERY(data, '$.tags') FROM logs;          -- JSON 片段
SELECT JSON_QUERY_ARRAY(data, '$.tags') FROM logs;    -- 转为 ARRAY
SELECT JSON_VALUE_ARRAY(data, '$.tags') FROM logs;    -- 转为 STRING ARRAY

```

## 注意事项


### 1. BigQuery 原生支持 ARRAY 和 STRUCT

### 2. 不支持原生 MAP 类型（用 ARRAY<STRUCT<key,value>> 替代）

### 3. 不支持 ARRAY<ARRAY<...>>（嵌套数组）

### 4. ARRAY 下标从 0 开始 (OFFSET) 或从 1 开始 (ORDINAL)

### 5. UNNEST 是处理数组的核心操作

### 6. JSON 类型提供额外的灵活性

