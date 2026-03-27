# UNNEST / explode / FLATTEN

数组和嵌套结构展开为行——各引擎语法差异最大的领域之一。

## 支持矩阵

| 引擎 | 语法 | 适用类型 | 备注 |
|------|------|---------|------|
| PostgreSQL | `UNNEST(array)` | 数组 | **最接近 SQL 标准** |
| BigQuery | `UNNEST(array)` | ARRAY, STRUCT | 配合 CROSS JOIN 或逗号 JOIN |
| Trino | `UNNEST(array)` / `UNNEST(map)` | ARRAY, MAP | - |
| DuckDB | `UNNEST(list)` / `UNNEST(struct)` | LIST, STRUCT, MAP | 也支持 `generate_series` |
| Spark SQL | `LATERAL VIEW explode(array)` | ARRAY, MAP | Hive 兼容语法 |
| Hive | `LATERAL VIEW explode(array)` | ARRAY, MAP | **原创** |
| Databricks | `LATERAL VIEW explode()` / `EXPLODE()` | ARRAY, MAP, STRUCT | 两种语法都支持 |
| Snowflake | `LATERAL FLATTEN(input)` | ARRAY, OBJECT, VARIANT | 独特的 FLATTEN 语法 |
| ClickHouse | `arrayJoin(array)` | Array | 独特的函数式语法 |
| Flink SQL | `CROSS JOIN UNNEST(array)` | ARRAY, MAP, ROW | - |
| MySQL | `JSON_TABLE(json, path)` | JSON | 8.0+，无数组类型 |
| Oracle | `JSON_TABLE` / `TABLE(collection)` | JSON, 集合 | - |
| SQL Server | `OPENJSON` / `STRING_SPLIT` | JSON, 字符串 | 无数组类型 |

## 设计动机

### 核心需求: 嵌套数据展平

现代数据中，数组和嵌套结构越来越常见（JSON、半结构化数据、日志）：

```json
{"user_id": 1, "tags": ["sql", "python", "go"]}
{"user_id": 2, "tags": ["java", "sql"]}
```

需要将每个 tag 展开为独立的行，以便 JOIN、GROUP BY、过滤：

```
| user_id | tag    |
|---------|--------|
| 1       | sql    |
| 1       | python |
| 1       | go     |
| 2       | java   |
| 2       | sql    |
```

## 语法对比

### SQL 标准 / PostgreSQL

```sql
-- 基本 UNNEST
SELECT u.user_id, t.tag
FROM users u
CROSS JOIN UNNEST(u.tags) AS t(tag);

-- PostgreSQL 简写（FROM 中直接调用）
SELECT user_id, unnest(tags) AS tag
FROM users;
-- 注意: 这种写法在 SELECT 中 unnest 是 set-returning function
-- PostgreSQL 10+ 行为规范化（在 FROM 中展开）

-- 多数组同时展开
SELECT unnest(ARRAY['a','b','c']) AS letter,
       unnest(ARRAY[1, 2, 3]) AS number;
-- 结果: (a,1), (b,2), (c,3) —— 按位置配对

-- UNNEST WITH ORDINALITY（带序号）
SELECT u.user_id, t.tag, t.ord
FROM users u
CROSS JOIN UNNEST(u.tags) WITH ORDINALITY AS t(tag, ord);
-- ord 从 1 开始，表示元素在数组中的位置

-- 配合 LEFT JOIN 保留空数组的行
SELECT u.user_id, t.tag
FROM users u
LEFT JOIN UNNEST(u.tags) AS t(tag) ON true;
-- 如果 tags 为空数组或 NULL，user 行保留，tag 为 NULL
```

### BigQuery

```sql
-- CROSS JOIN UNNEST
SELECT u.user_id, tag
FROM users u
CROSS JOIN UNNEST(u.tags) AS tag;

-- 逗号 JOIN 简写（隐式 LATERAL）
SELECT u.user_id, tag
FROM users u, UNNEST(u.tags) AS tag;

-- UNNEST STRUCT 数组
SELECT u.user_id, addr.city, addr.zip
FROM users u, UNNEST(u.addresses) AS addr;
-- addresses 是 ARRAY<STRUCT<city STRING, zip STRING>>

-- 带 OFFSET（序号）
SELECT u.user_id, tag, offset
FROM users u, UNNEST(u.tags) AS tag WITH OFFSET;
-- offset 从 0 开始

-- 保留空数组行
SELECT u.user_id, tag
FROM users u
LEFT JOIN UNNEST(u.tags) AS tag ON true;

-- 子查询中使用 UNNEST（不需要 FROM）
SELECT ARRAY(SELECT x * 2 FROM UNNEST([1,2,3]) AS x) AS doubled;
```

### Hive / Spark SQL

```sql
-- LATERAL VIEW explode（Hive 原创语法）
SELECT u.user_id, t.tag
FROM users u
LATERAL VIEW explode(u.tags) t AS tag;

-- LATERAL VIEW OUTER（保留空数组行）
SELECT u.user_id, t.tag
FROM users u
LATERAL VIEW OUTER explode(u.tags) t AS tag;

-- explode MAP（键值同时展开）
SELECT u.user_id, t.key, t.value
FROM users u
LATERAL VIEW explode(u.properties) t AS key, value;

-- posexplode（带位置序号）
SELECT u.user_id, t.pos, t.tag
FROM users u
LATERAL VIEW posexplode(u.tags) t AS pos, tag;

-- 多层 LATERAL VIEW（嵌套展开）
SELECT u.user_id, t.tag, s.char
FROM users u
LATERAL VIEW explode(u.tags) t AS tag
LATERAL VIEW explode(split(t.tag, '')) s AS char;

-- Spark SQL 也支持在 SELECT 中直接使用（生成器函数）
SELECT user_id, explode(tags) AS tag FROM users;
-- 但不推荐，LATERAL VIEW 更明确
```

### Snowflake（FLATTEN）

```sql
-- LATERAL FLATTEN 展开数组
SELECT u.user_id, f.value::STRING AS tag
FROM users u,
LATERAL FLATTEN(input => u.tags) f;

-- FLATTEN 的输出列
-- f.seq:   全局序号
-- f.key:   对象的 key（数组时为 NULL）
-- f.path:  JSON 路径
-- f.index: 数组索引（从 0 开始）
-- f.value: 元素值（VARIANT 类型）
-- f.this:  当前层的完整数据

-- 展开嵌套 JSON
SELECT
    f.value:name::STRING AS name,
    f.value:age::INT AS age
FROM raw_data r,
LATERAL FLATTEN(input => r.json_col:people) f;

-- 递归展开（RECURSIVE 参数）
SELECT f.key, f.path, f.value
FROM raw_data r,
LATERAL FLATTEN(input => r.nested_json, RECURSIVE => TRUE) f;

-- OUTER => TRUE 保留空数组行
SELECT u.user_id, f.value::STRING AS tag
FROM users u,
LATERAL FLATTEN(input => u.tags, OUTER => TRUE) f;
```

### ClickHouse（arrayJoin）

```sql
-- arrayJoin: 函数式语法，直接在 SELECT 中使用
SELECT user_id, arrayJoin(tags) AS tag
FROM users;

-- arrayJoin 是 ClickHouse 最独特的设计:
-- 它是一个"行乘法器"——将一行变成多行
-- 可以在 SELECT/WHERE/ORDER BY 中使用

-- 带序号
SELECT user_id, tag, num
FROM users
ARRAY JOIN tags AS tag, arrayEnumerate(tags) AS num;
-- ARRAY JOIN 是另一种语法，出现在 FROM 子句

-- LEFT ARRAY JOIN（保留空数组行）
SELECT user_id, tag
FROM users
LEFT ARRAY JOIN tags AS tag;

-- 嵌套数组展开
SELECT user_id, tag
FROM users
ARRAY JOIN nested_tags AS inner_array
ARRAY JOIN inner_array AS tag;
```

### DuckDB

```sql
-- UNNEST（与 PostgreSQL 兼容）
SELECT u.user_id, t.tag
FROM users u, UNNEST(u.tags) AS t(tag);

-- UNNEST struct
SELECT u.user_id, t.*
FROM users u, UNNEST(u.addresses) AS t;

-- UNNEST MAP
SELECT key, value
FROM (SELECT MAP {'a': 1, 'b': 2} AS m), UNNEST(m);

-- generate_series（生成序列）
SELECT * FROM generate_series(1, 10);
```

### MySQL（JSON_TABLE）

```sql
-- MySQL 没有原生数组类型，用 JSON 模拟
-- JSON_TABLE 将 JSON 数组展开为虚拟表
SELECT u.user_id, j.tag
FROM users u
CROSS JOIN JSON_TABLE(
    u.tags,                          -- JSON 列（如 '["sql","python"]'）
    '$[*]'                           -- JSON Path: 数组的每个元素
    COLUMNS (tag VARCHAR(50) PATH '$')  -- 输出列定义
) j;

-- 嵌套 JSON 展开
SELECT u.user_id, j.name, j.score
FROM users u
CROSS JOIN JSON_TABLE(
    u.scores,
    '$[*]'
    COLUMNS (
        name VARCHAR(50) PATH '$.name',
        score INT PATH '$.score'
    )
) j;
```

### SQL Server（OPENJSON）

```sql
-- OPENJSON 展开 JSON 数组
SELECT u.user_id, j.value AS tag
FROM users u
CROSS APPLY OPENJSON(u.tags) j;
-- j.key: 索引, j.value: 值, j.type: JSON 类型

-- 带 schema 定义
SELECT u.user_id, j.name, j.score
FROM users u
CROSS APPLY OPENJSON(u.scores)
WITH (
    name VARCHAR(50) '$.name',
    score INT '$.score'
) j;

-- STRING_SPLIT（非 JSON 的字符串分割）
SELECT u.user_id, s.value AS tag
FROM users u
CROSS APPLY STRING_SPLIT(u.tags_csv, ',') s;
```

## 为什么语法差异如此之大

### 1. 历史路径不同

| 引擎 | 背景 | 结果 |
|------|------|------|
| PostgreSQL | 从关系代数出发，数组是一等类型 | UNNEST 作为标准函数 |
| Hive | MapReduce 生态，UDTF 机制 | LATERAL VIEW + explode |
| Snowflake | JSON/VARIANT 为核心 | FLATTEN 统一处理半结构化 |
| ClickHouse | 列式存储，数组是原生类型 | arrayJoin 作为行乘法器 |
| MySQL/SQL Server | 传统 RDBMS，没有数组类型 | 依赖 JSON 函数 |

### 2. 语法位置不同

| 语法位置 | 代表 | 特点 |
|---------|------|------|
| FROM 子句 | UNNEST, FLATTEN | 语义清晰: "生成一个虚拟表" |
| SELECT 子句 | arrayJoin, explode | 语法简洁但语义不直观 |
| 专用子句 | LATERAL VIEW | Hive 生态特有，独立于标准 SQL |
| 函数调用 | JSON_TABLE, OPENJSON | 不是真正的数组展开，是 JSON 解析 |

### 3. 类型系统差异

有原生数组类型的引擎（PostgreSQL、ClickHouse、DuckDB）可以直接 UNNEST。没有数组类型的引擎（MySQL、SQL Server）只能通过 JSON 函数间接实现。

## 对引擎开发者的实现建议

### 1. UNNEST 的执行模型

UNNEST 在执行计划中是一个特殊的 table function scan：

```
CrossJoin (or LeftJoin if LEFT JOIN UNNEST)
├── TableScan(users)
└── TableFunctionScan(UNNEST(users.tags))
    -- 对于每一行 users，执行 UNNEST 生成 0~N 行
```

本质上是一个 correlated nested loop，其中内部"查询"是对数组的遍历。

### 2. 空数组 / NULL 处理

| 情况 | CROSS JOIN UNNEST | LEFT JOIN UNNEST |
|------|-------------------|------------------|
| 非空数组 | 展开为多行 | 展开为多行 |
| 空数组 `[]` | 外部行被排除 | 外部行保留，展开列为 NULL |
| NULL 数组 | 外部行被排除 | 外部行保留，展开列为 NULL |

建议同时支持 CROSS JOIN 和 LEFT JOIN 语义——LEFT JOIN UNNEST 是非常常见的需求。

### 3. WITH ORDINALITY 的实现

UNNEST WITH ORDINALITY 需要在展开时生成一个递增的序号列：

```
UNNEST(['a', 'b', 'c']) WITH ORDINALITY
→ ('a', 1), ('b', 2), ('c', 3)
```

实现: 在 UNNEST 的 table function scan 中维护一个计数器，每输出一行递增。

### 4. 多数组同时展开

PostgreSQL 支持多数组同时展开——按位置配对，短数组用 NULL 补齐：

```sql
SELECT * FROM UNNEST(ARRAY[1,2,3], ARRAY['a','b']);
-- (1,'a'), (2,'b'), (3,NULL)
```

实现: zip 语义，取最长数组的长度为行数。

### 5. 嵌套展开优化

多层展开（如 `LATERAL VIEW explode(a) LATERAL VIEW explode(b)`）可能产生笛卡尔积般的行数膨胀。优化器应该：

- 估计展开后的行数（基于数组长度统计信息）
- 如果膨胀过大，考虑在展开前先做过滤
- 谓词下推: 如果有对展开后列的过滤条件，尽量在展开时应用

## 参考资料

- SQL 标准: ISO/IEC 9075-2 Section 7.6 (UNNEST)
- PostgreSQL: [UNNEST](https://www.postgresql.org/docs/current/functions-array.html)
- BigQuery: [UNNEST](https://cloud.google.com/bigquery/docs/reference/standard-sql/query-syntax#unnest_operator)
- Snowflake: [FLATTEN](https://docs.snowflake.com/en/sql-reference/functions/flatten)
- ClickHouse: [arrayJoin](https://clickhouse.com/docs/en/sql-reference/functions/array-join)
- Spark SQL: [LATERAL VIEW](https://spark.apache.org/docs/latest/sql-ref-syntax-qry-select-lateral-view.html)
