# Spanner: 复合类型

> 参考资料:
> - [Spanner Documentation - Data Types (ARRAY)](https://cloud.google.com/spanner/docs/reference/standard-sql/data-types#array_type)
> - [Spanner Documentation - Data Types (STRUCT)](https://cloud.google.com/spanner/docs/reference/standard-sql/data-types#struct_type)
> - [Spanner Documentation - Array Functions](https://cloud.google.com/spanner/docs/reference/standard-sql/array_functions)
> - [Spanner Documentation - JSON Type](https://cloud.google.com/spanner/docs/reference/standard-sql/data-types#json_type)

**引擎定位**: Google 全球分布式数据库，TrueTime 外部一致性。基于 Colossus 存储，支持跨洲强一致事务。

## ARRAY 类型


```sql
CREATE TABLE users (
    id     INT64 NOT NULL,
    name   STRING(100) NOT NULL,
    tags   ARRAY<STRING(50)>,
    scores ARRAY<INT64>
) PRIMARY KEY (id);

```

插入数组
```sql
INSERT INTO users (id, name, tags, scores) VALUES
    (1, 'Alice', ['admin', 'dev'], [90, 85, 95]),
    (2, 'Bob',   ['user', 'tester'], [70, 80, 75]);

```

数组访问（使用 OFFSET 从 0 或 ORDINAL 从 1）
```sql
SELECT tags[OFFSET(0)] FROM users;
SELECT tags[ORDINAL(1)] FROM users;
SELECT tags[SAFE_OFFSET(10)] FROM users;     -- 越界返回 NULL

```

ARRAY 函数
```sql
SELECT ARRAY_LENGTH(tags) FROM users;
SELECT ARRAY_CONCAT(['a'], ['b','c']);
SELECT ARRAY_REVERSE([1,2,3]);
SELECT ARRAY_TO_STRING(['a','b','c'], ', ');
SELECT GENERATE_ARRAY(1, 10);

```

包含检查
```sql
SELECT * FROM users WHERE 'admin' IN UNNEST(tags);

```

UNNEST
```sql
SELECT u.name, tag
FROM users u, UNNEST(u.tags) AS tag;

SELECT u.name, tag, offset
FROM users u, UNNEST(u.tags) AS tag WITH OFFSET;

```

ARRAY_AGG
```sql
SELECT department, ARRAY_AGG(name ORDER BY name)
FROM employees GROUP BY department;

```

## STRUCT 类型（仅在查询中使用，不能作为表列）


STRUCT 构造
```sql
SELECT STRUCT('Alice' AS name, 30 AS age);
SELECT STRUCT<name STRING, age INT64>('Alice', 30);

```

STRUCT 在子查询中
```sql
SELECT s.name, s.age
FROM UNNEST([
    STRUCT('Alice' AS name, 30 AS age),
    STRUCT('Bob', 25)
]) AS s;

```

**注意:** STRUCT 不能作为表列类型！
Spanner 表列只支持标量类型和 ARRAY<标量类型>

## JSON 类型（Spanner）


```sql
CREATE TABLE events (
    id   INT64 NOT NULL,
    data JSON
) PRIMARY KEY (id);

INSERT INTO events (id, data) VALUES
    (1, JSON '{"type": "click", "tags": ["mobile"], "info": {"ip": "1.2.3.4"}}');

```

JSON 函数
```sql
SELECT JSON_VALUE(data, '$.type') FROM events;
SELECT JSON_QUERY(data, '$.tags') FROM events;
SELECT JSON_QUERY_ARRAY(data, '$.tags') FROM events;

```

## MAP 替代方案


Spanner 没有 MAP 类型
替代方案: 使用 JSON 或关联表

## 注意事项


## 支持 ARRAY 类型（表列）

## STRUCT 只能在查询中使用，不能作为表列

## 不支持 ARRAY<ARRAY<...>>（嵌套数组）

## 不支持 MAP 类型

## JSON 类型提供灵活的复杂数据存储

## 数组索引: OFFSET(0-based) 或 ORDINAL(1-based)
