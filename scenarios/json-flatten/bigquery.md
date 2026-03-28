# BigQuery: JSON 展平为关系行 (JSON Flatten)

> 参考资料:
> - [1] BigQuery - JSON Functions
>   https://cloud.google.com/bigquery/docs/reference/standard-sql/json_functions
> - [2] BigQuery - UNNEST
>   https://cloud.google.com/bigquery/docs/reference/standard-sql/query-syntax#unnest


## 1. STRUCT 数组展平（原生嵌套类型）


BigQuery 推荐用 STRUCT/ARRAY 存储嵌套数据（而非 JSON 字符串）:
CREATE TABLE events (
user_name STRING,
actions ARRAY<STRUCT<type STRING, target STRING>>
);

展平 ARRAY<STRUCT>:

```sql
SELECT user_name, action.type, action.target
FROM events, UNNEST(actions) AS action;

```

保留没有 actions 的行（LEFT JOIN UNNEST）:

```sql
SELECT user_name, action.type, action.target
FROM events LEFT JOIN UNNEST(actions) AS action ON TRUE;

```

带位置索引:

```sql
SELECT user_name, action.type, pos
FROM events, UNNEST(actions) AS action WITH OFFSET AS pos;

```

## 2. JSON 类型展平


从 JSON 类型列提取数组并展平:

```sql
SELECT
    JSON_VALUE(payload, '$.user') AS user_name,
    JSON_VALUE(action, '$.type') AS action_type,
    JSON_VALUE(action, '$.target') AS target
FROM events,
UNNEST(JSON_QUERY_ARRAY(payload, '$.actions')) AS action;

```

展平 JSON 对象的所有键:

```sql
SELECT key, value
FROM events,
UNNEST(
    ARRAY(
        SELECT AS STRUCT key, JSON_QUERY(payload, CONCAT('$.', key)) AS value
        FROM UNNEST(
            SPLIT(REGEXP_REPLACE(TO_JSON_STRING(payload), r'[{}" ]', ''), ',')
        ) AS kv,
        UNNEST([SPLIT(kv, ':')[OFFSET(0)]]) AS key
    )
);
```

 注: BigQuery 没有内置的 JSON 键枚举函数，需要字符串操作

## 3. STRUCT 点号访问（最简洁的展平）


BigQuery 的 STRUCT 支持点号访问:

```sql
SELECT payload.user AS user_name FROM events;
SELECT payload.address.city AS city FROM events;
```

 这是最简洁的 JSON/嵌套数据访问方式

## 4. 多层嵌套展平


展平两层嵌套:
events → actions (ARRAY) → tags (ARRAY)

```sql
SELECT user_name, action.type, tag
FROM events,
UNNEST(actions) AS action,
UNNEST(action.tags) AS tag;

```

## 5. JSON 展平 + 聚合（常见的 ETL 模式）


展平后聚合

```sql
SELECT
    JSON_VALUE(payload, '$.user') AS user_name,
    COUNT(*) AS action_count,
    COUNTIF(JSON_VALUE(action, '$.type') = 'click') AS click_count
FROM events,
UNNEST(JSON_QUERY_ARRAY(payload, '$.actions')) AS action
GROUP BY user_name;

```

## 6. 对比与引擎开发者启示

BigQuery JSON 展平的核心:
(1) UNNEST → ARRAY 展开为行（核心操作）
(2) STRUCT 点号访问 → 最简洁的嵌套访问
(3) JSON_QUERY_ARRAY → JSON 数组提取
(4) ARRAY<STRUCT> → 比 JSON 更高效（列式存储）

对比:
ClickHouse: ARRAY JOIN（更简洁的语法）
PostgreSQL: jsonb_array_elements / LATERAL JOIN
SQLite:     json_each（虚拟表函数）
MySQL:      JSON_TABLE（8.0+）

对引擎开发者的启示:
UNNEST 是嵌套类型引擎的基础操作。
STRUCT 点号访问 比 JSON_EXTRACT 更直观。
原生嵌套类型（ARRAY<STRUCT>）比 JSON 字符串更高效。

