# JSON 路径与查询语法：各 SQL 方言全对比

> 参考资料:
> - [MySQL 8.0 - JSON Functions](https://dev.mysql.com/doc/refman/8.0/en/json-functions.html)
> - [PostgreSQL - JSON Functions](https://www.postgresql.org/docs/current/functions-json.html)
> - [SQL Server - JSON Data](https://learn.microsoft.com/en-us/sql/relational-databases/json/json-data-sql-server)
> - [BigQuery - JSON Functions](https://cloud.google.com/bigquery/docs/reference/standard-sql/json_functions)
> - [Snowflake - Semi-structured Data](https://docs.snowflake.com/en/sql-reference/data-types-semistructured)

JSON 路径表达式是 SQL 引擎中分裂最严重的语法领域。同一个查询——"取出 JSON 对象中 `user.name` 的值"——在 17 种引擎中可能有 10 种完全不同的写法。本文系统梳理各引擎的 JSON 路径语法、提取函数、索引策略、修改操作与聚合能力。

## JSON 类型支持矩阵

| 引擎 | 原生 JSON 类型 | 存储格式 | 版本 | 备注 |
|------|--------------|---------|------|------|
| PostgreSQL | `JSON` / `JSONB` | 文本 / 二进制 | 9.2+ / 9.4+ | JSONB 是主力，写入解析、键排序去重 |
| MySQL | `JSON` | 二进制 | 5.7.8+ | 内部使用偏移表（offset table）实现 O(1) 键查找 |
| MariaDB | `JSON` (LONGTEXT 别名) | 文本 | 10.2+ | 底层仍是 LONGTEXT，无二进制优化 |
| Oracle | `JSON` | 原生二进制 (OSON) | 21c+ | 21c 前存于 VARCHAR2/CLOB + IS JSON 约束 |
| SQL Server | 无原生类型 | 文本 (NVARCHAR) | 2016+ | `ISJSON()` 检查约束，无二进制存储 |
| SQLite | 无原生类型 | 文本 | 3.9+ (json1) | JSON1 扩展；3.38+ 支持 `->` / `->>` 运算符 |
| BigQuery | `JSON` | 列式内部格式 | 2022+ | 也支持 STRUCT/ARRAY 嵌套类型 |
| Snowflake | `VARIANT` | 自有二进制 | GA | 统一 JSON/XML/Avro/Parquet |
| ClickHouse | `JSON` (实验性) | 列式 | 24.1+ | 传统上用 String + JSONExtract 函数 |
| DuckDB | `JSON` | 二进制 | GA | 同时支持 STRUCT/LIST/MAP 原生嵌套 |
| Trino | `JSON` | 文本 | GA | 内部 Slice 表示 |
| Spark SQL | `STRING` | 文本 | - | 无原生类型，依赖 `from_json()` / `get_json_object()` |
| Hive | `STRING` | 文本 | - | `get_json_object()` 函数 |
| Doris | `JSON` | 二进制 | 1.2+ | 二进制 JSON 格式 |
| StarRocks | `JSON` | 二进制 | 2.2+ | 二进制存储，支持 Flat JSON 优化 |
| Hologres | `JSON` / `JSONB` | 二进制 | 1.1+ | V1.3+ 列存优化 |
| MaxCompute | `JSON` | 列式内部格式 | GA | 列存优化，支持 JSON 路径索引 |

## 路径语法对比

### 核心对照表

以 JSON `{"user": {"name": "张三", "scores": [90, 85, 92]}}` 为例：

| 引擎 | 取对象/JSON 值 | 取标量/文本值 | 取数组元素 |
|------|--------------|-------------|-----------|
| PostgreSQL | `data->'user'` | `data->'user'->>'name'` | `data->'scores'->0` |
| PostgreSQL (路径) | `data#>'{user}'` | `data#>>'{user,name}'` | `data#>'{scores,0}'` |
| MySQL | `data->'$.user'` | `data->>'$.user.name'` | `data->'$.scores[0]'` |
| MariaDB | `data->'$.user'` | `JSON_UNQUOTE(data->'$.user.name')` | `data->'$.scores[0]'` |
| Oracle (点表示法) | `t.data.user` | `t.data.user.string()` | `t.data.scores[0]` |
| Oracle (函数) | `JSON_QUERY(data, '$.user')` | `JSON_VALUE(data, '$.user.name')` | `JSON_VALUE(data, '$.scores[0]')` |
| SQL Server | `JSON_QUERY(data, '$.user')` | `JSON_VALUE(data, '$.user.name')` | `JSON_VALUE(data, '$.scores[0]')` |
| SQLite (3.38+) | `data->'$.user'` | `data->>'$.user.name'` | `data->>'$.scores[0]'` |
| SQLite (函数) | `json_extract(data, '$.user')` | `json_extract(data, '$.user.name')` | `json_extract(data, '$.scores[0]')` |
| BigQuery | `JSON_QUERY(data, '$.user')` | `JSON_VALUE(data, '$.user.name')` | `JSON_VALUE(data, '$.scores[0]')` |
| BigQuery (下标, *仅 STRUCT 类型*) | `data.user` | `data.user.name` | `data.scores[0]` |
| Snowflake | `data:user` | `data:user:name::STRING` | `data:scores[0]` |
| ClickHouse | `JSON_QUERY(data, '$.user')` | `JSON_VALUE(data, '$.user.name')` | `JSON_VALUE(data, '$.scores[0]')` |
| ClickHouse (传统) | `JSONExtract(data, 'user', 'String')` | `JSONExtractString(data, 'user', 'name')` | `JSONExtractInt(data, 'scores', 1)` |
| DuckDB | `data->'user'` | `data->'user'->>'name'` | `data->'scores'->0` |
| DuckDB (点表示法) | `data.user` | `data.user.name` | `data.scores[0]` |
| Trino | `json_query(data, 'lax $.user')` | `json_value(data, 'lax $.user.name')` | `json_value(data, 'lax $.scores[0]')` |
| Spark SQL | — | `get_json_object(data, '$.user.name')` | `get_json_object(data, '$.scores[0]')` |
| Hive | — | `get_json_object(data, '$.user.name')` | `get_json_object(data, '$.scores[0]')` |
| Doris | `data->'user'` | `json_extract_string(data, '$.user.name')` | `json_extract(data, '$.scores[0]')` |
| StarRocks | `data->'user'` | `json_query(data, '$.user.name')` | `json_query(data, '$.scores[0]')` |

### `->` / `->>` 运算符家族

PostgreSQL 在 9.2 引入，已成为事实标准之一。`->` 返回 JSON 类型，`->>` 返回文本类型：

```sql
-- PostgreSQL: 键名取值
SELECT data->'user'->>'name' FROM events;        -- 返回 text '张三'

-- PostgreSQL: 路径取值（#> 和 #>>）
SELECT data#>>'{user,name}' FROM events;          -- 深层路径

-- MySQL: 必须使用 JSONPath 语法（$.前缀）
SELECT data->>'$.user.name' FROM events;          -- MySQL 的 ->> 等价于 JSON_UNQUOTE(JSON_EXTRACT(...))

-- SQLite 3.38+: 与 MySQL 相同，使用 $.前缀
SELECT data->>'$.user.name' FROM events;

-- DuckDB: 语法与 PostgreSQL 一致
SELECT data->'user'->>'name' FROM events;
```

**关键差异**: PostgreSQL/DuckDB 的 `->` 接受键名字符串或数组索引整数；MySQL/SQLite 的 `->` 接受 JSONPath 表达式（以 `$` 开头）。看起来相似，实际不可互换。

### `:` 路径运算符（Snowflake 独有）

```sql
-- Snowflake VARIANT 专用冒号语法
SELECT
    data:user:name::STRING,               -- 嵌套路径 + 类型转换
    data:scores[0]::INT,                  -- 数组索引
    data:user:name::STRING IS NOT NULL    -- NULL 判断
FROM events;

-- 大小写敏感: 键名保留原始大小写
SELECT data:User:Name FROM events;        -- 与 data:user:name 不同
```

### `JSON_VALUE()` / `JSON_QUERY()` (SQL:2016 标准)

SQL:2016 定义的标准函数，区分标量提取（`JSON_VALUE`）和对象/数组提取（`JSON_QUERY`）：

```sql
-- SQL:2016 标准语法（Oracle, SQL Server, BigQuery, Trino, ClickHouse）
SELECT
    JSON_VALUE(data, '$.user.name')                    AS name,       -- 标量值 → 文本
    JSON_QUERY(data, '$.user')                         AS user_obj,   -- 对象/数组 → JSON
    JSON_VALUE(data, '$.scores[0]' RETURNING INT)      AS first_score -- 带类型转换
FROM events;

-- 错误处理子句（SQL:2016 标准）
SELECT
    JSON_VALUE(data, '$.missing'  NULL     ON ERROR)   AS safe_null,
    JSON_VALUE(data, '$.missing'  DEFAULT  'N/A' ON EMPTY) AS with_default,
    JSON_VALUE(data, '$.bad_path' ERROR    ON ERROR)   AS strict_mode
FROM events;
```

各引擎 `JSON_VALUE` / `JSON_QUERY` 支持状态：

| 引擎 | JSON_VALUE | JSON_QUERY | RETURNING 子句 | ON ERROR/EMPTY |
|------|-----------|-----------|---------------|---------------|
| Oracle 12c+ | 完整 | 完整 | 完整 | 完整 |
| SQL Server 2016+ | 完整 | 完整 | 不支持 | 不支持 |
| BigQuery | 完整 | 完整 | 不支持 | 不支持 |
| PostgreSQL 17+ | 完整 | 完整 | 完整 | 完整 |
| MySQL 8.0.4+ | 部分 | 不支持 | 不支持 | 部分 |
| Trino 419+ | 完整 | 完整 | 完整 | 完整 |
| ClickHouse | 完整 | 完整 | 不支持 | 不支持 |
| MariaDB 10.2+ | 不支持 | 不支持 | — | — |
| SQLite | 不支持 | 不支持 | — | — |
| DuckDB | 不支持 | 不支持 | — | — |

### `JSON_EXTRACT()` 系列（MySQL / BigQuery / SQLite）

```sql
-- MySQL
SELECT
    JSON_EXTRACT(data, '$.user.name'),                       -- 返回 JSON
    JSON_UNQUOTE(JSON_EXTRACT(data, '$.user.name')),        -- 返回 text（去掉引号）
    JSON_EXTRACT(data, '$.scores[0]', '$.scores[2]')        -- 多路径提取
FROM events;

-- BigQuery
SELECT
    JSON_EXTRACT(data, '$.user.name'),           -- 返回 JSON
    JSON_EXTRACT_SCALAR(data, '$.user.name')     -- 返回 STRING
FROM events;

-- SQLite
SELECT json_extract(data, '$.user.name') FROM events;    -- 返回 SQL 值（自动类型推断）
```

### `$.path` JSONPath 语法差异

虽然各引擎都声称支持 JSONPath，但语法细节差异显著：

| 语法特性 | MySQL | Oracle | SQL Server | BigQuery | PostgreSQL 17+ |
|---------|-------|--------|-----------|---------|---------------|
| 基本路径 `$.key` | 支持 | 支持 | 支持 | 支持 | 支持 |
| 数组下标 `$[0]` | 支持 | 支持 | 支持 | 支持 | 支持 |
| 通配符 `$.store.*` | 支持 | 支持 | 不支持 | 支持 | 支持 |
| 递归 `$..name` | 不支持 | 支持 | 不支持 | 不支持 | 支持 (`.**`) |
| 数组切片 `$[0 to 2]` | 不支持 | 支持 | 不支持 | 不支持 | 支持 |
| 过滤 `$[?(@.price>10)]` | 不支持 | 支持 | 不支持 | 不支持 | 支持 (`?()`) |
| lax/strict 模式 | 不支持 | 不支持 | 支持 (lax 默认) | 不支持 | 支持 |

```sql
-- Oracle: 完整 JSONPath 支持
SELECT JSON_QUERY(data, '$.store.book[?(@.price < 10)]' WITH WRAPPER)
FROM bookstore;

-- PostgreSQL 17+: SQL/JSON Path 表达式
SELECT jsonb_path_query(data, '$.store.book[*] ? (@.price < 10)')
FROM bookstore;

-- SQL Server: lax/strict 模式
SELECT JSON_VALUE(data, 'lax $.missing_key')         -- 返回 NULL（宽松模式）
SELECT JSON_VALUE(data, 'strict $.missing_key')      -- 报错（严格模式）
```

## JSON_TABLE: 将 JSON 展开为关系表

### SQL:2016 标准语法

```sql
-- 标准 JSON_TABLE（Oracle 12c+, MySQL 8.0+, PostgreSQL 17+, Trino 419+, MariaDB 10.6+）
SELECT jt.*
FROM orders o,
JSON_TABLE(
    o.data,
    '$.items[*]'
    COLUMNS (
        item_idx   FOR ORDINALITY,
        product    VARCHAR(100)  PATH '$.product',
        qty        INT           PATH '$.qty',
        price      DECIMAL(10,2) PATH '$.price'  DEFAULT 0 ON EMPTY,
        NESTED PATH '$.tags[*]' COLUMNS (
            tag VARCHAR(50) PATH '$'
        )
    )
) AS jt;
```

### 各引擎等价语法

```sql
-- SQL Server: OPENJSON（非标准，但功能等价）
SELECT j.*
FROM orders o
CROSS APPLY OPENJSON(o.data, '$.items')
WITH (
    product  VARCHAR(100)  '$.product',
    qty      INT           '$.qty',
    price    DECIMAL(10,2) '$.price'
) j;

-- Snowflake: FLATTEN
SELECT
    f.value:product::STRING  AS product,
    f.value:qty::INT         AS qty,
    f.value:price::NUMBER    AS price
FROM orders o,
LATERAL FLATTEN(input => PARSE_JSON(o.data):items) f;

-- BigQuery: UNNEST + JSON_QUERY_ARRAY
SELECT
    JSON_VALUE(item, '$.product')              AS product,
    CAST(JSON_VALUE(item, '$.qty') AS INT64)   AS qty,
    CAST(JSON_VALUE(item, '$.price') AS FLOAT64) AS price
FROM orders o,
UNNEST(JSON_QUERY_ARRAY(o.data, '$.items')) AS item;

-- ClickHouse: JSONExtract + arrayJoin
SELECT
    JSONExtractString(item, 'product')    AS product,
    JSONExtractInt(item, 'qty')           AS qty,
    JSONExtractFloat(item, 'price')       AS price
FROM orders
ARRAY JOIN JSONExtractArrayRaw(data, 'items') AS item;

-- DuckDB: unnest + from_json
SELECT unnest(from_json(data, '["json"]'), recursive := true)
FROM orders;

-- Spark SQL: from_json + explode
SELECT e.*
FROM orders
LATERAL VIEW explode(from_json(data, 'array<struct<product:string,qty:int,price:double>>')) t AS e;

-- Hive: json_tuple + LATERAL VIEW
SELECT j.product, j.qty, j.price
FROM orders
LATERAL VIEW json_tuple(data, 'product', 'qty', 'price') j
AS product, qty, price;
```

### JSON_TABLE 支持矩阵

| 引擎 | 函数 | NESTED PATH | FOR ORDINALITY | ON EMPTY/ERROR | 版本 |
|------|------|-----------|---------------|---------------|------|
| Oracle | `JSON_TABLE` | 支持 | 支持 | 支持 | 12c+ |
| MySQL | `JSON_TABLE` | 支持 | 支持 | 支持 | 8.0+ |
| PostgreSQL | `JSON_TABLE` | 支持 | 支持 | 支持 | 17+ |
| MariaDB | `JSON_TABLE` | 支持 | 支持 | 支持 | 10.6+ |
| Trino | `JSON_TABLE` | 支持 | 支持 | 支持 | 419+ |
| Db2 | `JSON_TABLE` | 支持 | 支持 | 支持 | 11.1+ |
| SQL Server | `OPENJSON` | 不支持 (需嵌套 APPLY) | 不支持 | 不支持 | 2016+ |
| Snowflake | `FLATTEN` | 不支持 (需嵌套 FLATTEN) | `INDEX` 列 | 不支持 | GA |
| BigQuery | `UNNEST` | 不支持 (需嵌套 UNNEST) | `WITH OFFSET` | 不支持 | GA |
| ClickHouse | `arrayJoin` | 不支持 | 不支持 | 不支持 | GA |
| DuckDB | `unnest` | 不支持 | 不支持 | 不支持 | GA |
| Spark SQL | `explode` | 不支持 | `posexplode` | 不支持 | GA |
| Hive | `json_tuple` | 不支持 | 不支持 | 不支持 | GA |

## JSON 索引

| 引擎 | 索引方式 | 语法 | 备注 |
|------|---------|------|------|
| PostgreSQL | **GIN 索引** | `CREATE INDEX ON t USING GIN (data)` | 支持 `@>` 包含、`?` 键存在、`?&` / `?\|` 多键查询 |
| PostgreSQL | 函数索引 | `CREATE INDEX ON t ((data->>'name'))` | 只加速特定路径 |
| MySQL | 虚拟列 + B-Tree | `ALTER TABLE t ADD name VARCHAR(50) GENERATED ALWAYS AS (data->>'$.name'), ADD INDEX (name)` | 传统方式 |
| MySQL | **多值索引** | `CREATE INDEX ON t ((CAST(data->'$.tags' AS CHAR(64) ARRAY)))` | 8.0.17+，专为 JSON 数组设计 |
| Oracle | 函数索引 | `CREATE INDEX ON t (JSON_VALUE(data, '$.name'))` | 标准函数索引 |
| Oracle | JSON 搜索索引 | `CREATE SEARCH INDEX ON t (data) FOR JSON` | 全 JSON 文档索引 |
| Oracle | 多值索引 | `CREATE MULTIVALUE INDEX ON t e (e.data.tags.string())` | 21c+，数组索引 |
| SQL Server | 计算列 + 索引 | `ALTER TABLE t ADD name AS JSON_VALUE(data, '$.name'); CREATE INDEX ON t (name)` | 需要两步 |
| BigQuery | **搜索索引** | `CREATE SEARCH INDEX ON t (data)` | 自动倒排索引，支持 `SEARCH()` 函数 |
| Snowflake | 无传统索引 | — | 依赖微分区自动裁剪和搜索优化 |
| ClickHouse | 物化列 | `ALTER TABLE t ADD COLUMN name String MATERIALIZED JSONExtractString(data, 'name')` | 读取时自动填充 |
| DuckDB | 无 | — | 列式存储，内存引擎，无传统索引 |
| Doris | 倒排索引 | `CREATE INDEX ON t (data) USING INVERTED` | 2.0+，JSON 字段倒排索引 |
| StarRocks | Flat JSON | 自动优化 | 自动将高频访问的 JSON 路径展平为列式存储 |

### GIN 索引详解 (PostgreSQL)

```sql
-- 两种 GIN 运算符类
-- jsonb_ops（默认）: 支持 @>, ?, ?|, ?& 运算符
CREATE INDEX idx_data ON events USING GIN (data);

-- jsonb_path_ops: 只支持 @>，但索引更小、更快
CREATE INDEX idx_data ON events USING GIN (data jsonb_path_ops);

-- 查询示例
SELECT * FROM events WHERE data @> '{"user": {"role": "admin"}}';    -- 包含查询
SELECT * FROM events WHERE data ? 'email';                            -- 键存在
SELECT * FROM events WHERE data ?| array['email', 'phone'];          -- 任一键存在
```

### 多值索引详解 (MySQL 8.0.17+)

```sql
-- 为 JSON 数组创建多值索引
CREATE TABLE products (
    id INT PRIMARY KEY,
    data JSON,
    INDEX idx_tags ((CAST(data->'$.tags' AS CHAR(64) ARRAY)))
);

-- 利用多值索引的查询
SELECT * FROM products WHERE JSON_CONTAINS(data->'$.tags', '"electronics"');
SELECT * FROM products WHERE JSON_OVERLAPS(data->'$.tags', '["electronics", "books"]');
SELECT * FROM products WHERE 'electronics' MEMBER OF (data->'$.tags');
```

## JSON 修改操作

### 修改函数支持矩阵

| 操作 | PostgreSQL | MySQL | Oracle | SQL Server | SQLite | BigQuery |
|------|-----------|-------|--------|-----------|--------|---------|
| 设置/更新值 | `jsonb_set()` | `JSON_SET()` | `JSON_TRANSFORM(SET)` | `JSON_MODIFY()` | `json_set()` | 不支持原地修改 |
| 仅插入 | `jsonb_set(..., false)` | `JSON_INSERT()` | `JSON_TRANSFORM(INSERT)` | — | `json_insert()` | — |
| 仅替换 | `jsonb_set(..., true)` | `JSON_REPLACE()` | `JSON_TRANSFORM(REPLACE)` | — | `json_replace()` | — |
| 删除键 | `data - 'key'` | `JSON_REMOVE()` | `JSON_TRANSFORM(REMOVE)` | `JSON_MODIFY(... NULL)` | `json_remove()` | — |
| 合并/拼接 | `data \|\| '{...}'` | `JSON_MERGE_PATCH()` | `JSON_MERGEPATCH()` | — | `json_patch()` | — |
| 数组追加 | `data \|\| '["x"]'` | `JSON_ARRAY_APPEND()` | `JSON_TRANSFORM(APPEND)` | `JSON_MODIFY(append)` | `json_insert()` | — |
| 数组插入 | `jsonb_insert()` | `JSON_ARRAY_INSERT()` | `JSON_TRANSFORM(INSERT)` | — | — | — |

```sql
-- PostgreSQL: 运算符风格，简洁
UPDATE events SET data = data || '{"status": "active"}'        -- 合并
    WHERE data->>'user' = '张三';
UPDATE events SET data = data - 'temp_field';                   -- 删除键
UPDATE events SET data = jsonb_set(data, '{user,name}', '"李四"');  -- 设置嵌套值

-- MySQL: 函数风格，语义明确
UPDATE events SET data = JSON_SET(data, '$.status', 'active')   -- 存在则更新，否则插入
    WHERE data->>'$.user' = '张三';
UPDATE events SET data = JSON_INSERT(data, '$.status', 'active') -- 仅不存在时插入
UPDATE events SET data = JSON_REPLACE(data, '$.status', 'active') -- 仅存在时替换
UPDATE events SET data = JSON_REMOVE(data, '$.temp_field');      -- 删除键

-- Oracle: JSON_TRANSFORM 可在一次调用中完成多个操作
UPDATE events SET data = JSON_TRANSFORM(data,
    SET '$.status' = 'active',
    REMOVE '$.temp_field',
    RENAME '$.user.name' = 'full_name'
);

-- SQL Server: JSON_MODIFY 统一处理
UPDATE events SET data = JSON_MODIFY(data, '$.status', 'active');
UPDATE events SET data = JSON_MODIFY(data, '$.temp_field', NULL);      -- 删除
UPDATE events SET data = JSON_MODIFY(data, 'append $.tags', 'new_tag'); -- 数组追加
```

### Partial Update 优化

| 引擎 | 支持 | 机制 | 条件 |
|------|------|------|------|
| MySQL 8.0+ | 支持 | binlog partial update | 仅 `JSON_SET` / `JSON_REPLACE` / `JSON_REMOVE`，且不改变 JSON 文档结构 |
| Oracle 21c+ | 支持 | OSON 格式原地更新 | JSON_TRANSFORM 操作 |
| PostgreSQL | 不支持 | 整行重写 (MVCC) | JSONB 始终产生新版本 |
| SQL Server | 不支持 | 整个 NVARCHAR 重写 | 无二进制格式可优化 |

## JSON 聚合函数

### 支持矩阵

| 函数 | SQL:2016 标准 | PostgreSQL | MySQL | Oracle | SQL Server | BigQuery | Snowflake | ClickHouse | DuckDB |
|------|-------------|-----------|-------|--------|-----------|---------|-----------|-----------|--------|
| 行 → JSON 数组 | `JSON_ARRAYAGG` | `json_agg` / `jsonb_agg` | `JSON_ARRAYAGG` (8.0+) | `JSON_ARRAYAGG` | `FOR JSON` | `JSON_AGG` (未排序) | `ARRAY_AGG` + `TO_JSON` | `groupArray` | `json_group_array` |
| 行 → JSON 对象 | `JSON_OBJECTAGG` | `json_object_agg` / `jsonb_object_agg` | `JSON_OBJECTAGG` (8.0+) | `JSON_OBJECTAGG` | `FOR JSON` | — | `OBJECT_AGG` | `groupObject` (实验性) | `json_group_object` |
| 值 → JSON 数组 | `JSON_ARRAY` | `json_build_array` | `JSON_ARRAY` (8.0.17+) | `JSON_ARRAY` | `JSON_ARRAY` (2022+) | `JSON_ARRAY` | `ARRAY_CONSTRUCT` | `JSONExtractArrayRaw` | `json_array` |
| 值 → JSON 对象 | `JSON_OBJECT` | `json_build_object` | `JSON_OBJECT` (8.0.11+) | `JSON_OBJECT` | `JSON_OBJECT` (2022+) | `JSON_OBJECT` | `OBJECT_CONSTRUCT` | — | `json_object` |

```sql
-- PostgreSQL
SELECT json_agg(row_to_json(t)) FROM (SELECT id, name FROM users) t;
SELECT jsonb_object_agg(key, value) FROM user_settings;

-- MySQL 8.0+
SELECT JSON_ARRAYAGG(JSON_OBJECT('id', id, 'name', name)) FROM users;
SELECT JSON_OBJECTAGG(setting_key, setting_value) FROM user_settings;

-- Oracle
SELECT JSON_ARRAYAGG(JSON_OBJECT('id' VALUE id, 'name' VALUE name) RETURNING CLOB)
FROM users;

-- SQL Server: FOR JSON 子句（非标准但强大）
SELECT id, name FROM users FOR JSON PATH;                -- [{...}, {...}]
SELECT id, name FROM users FOR JSON PATH, ROOT('users'); -- {"users":[{...}]}

-- BigQuery
SELECT JSON_AGG(t) FROM (SELECT id, name FROM users) t;

-- Snowflake
SELECT ARRAY_AGG(OBJECT_CONSTRUCT('id', id, 'name', name)) FROM users;
```

### 排序控制

```sql
-- MySQL 8.0+: JSON_ARRAYAGG 支持 ORDER BY
SELECT JSON_ARRAYAGG(name ORDER BY id) FROM users;

-- PostgreSQL: json_agg 支持 ORDER BY
SELECT json_agg(name ORDER BY id) FROM users;

-- Oracle: JSON_ARRAYAGG 支持 ORDER BY
SELECT JSON_ARRAYAGG(name ORDER BY id RETURNING CLOB) FROM users;

-- SQL Server: FOR JSON 需要外层 ORDER BY
SELECT name FROM users ORDER BY id FOR JSON PATH;
```

## JSON 列存优化

### Hologres V1.3+

Hologres 在 V1.3 版本引入 JSON 列存优化：

```sql
-- 创建列存表，JSON 列自动优化
CREATE TABLE events (
    id BIGINT,
    data JSON
)
WITH (orientation = 'column');

-- Hologres 自动将高频访问的 JSON 路径展平为独立列
-- 查询时自动路由到列式存储
SELECT data->>'user_name', data->>'action'
FROM events
WHERE data->>'action' = 'purchase';

-- V1.3+ 优化: JSON 列存引擎自动识别 schema
-- 热路径 O(1) 列式读取，冷路径回退到 JSON 解析
```

### MaxCompute JSON 列存

```sql
-- MaxCompute: JSON 类型支持列式存储优化
CREATE TABLE events (
    id BIGINT,
    data JSON
) STORED AS ALIORC;

-- 路径提取
SELECT json_extract(data, '$.user.name') FROM events;
SELECT json_extract_scalar(data, '$.user.age') FROM events;

-- MaxCompute 优化:
-- 1. JSON 列以列式格式存储，避免全文档扫描
-- 2. 支持谓词下推到 JSON 路径
-- 3. 与 STRUCT/ARRAY 类型互操作
```

### StarRocks Flat JSON

```sql
-- StarRocks: Flat JSON 自动优化
-- 引擎自动检测 JSON 中高频访问的路径，展平为列式存储
CREATE TABLE events (
    id BIGINT,
    data JSON
)
PROPERTIES ("enable_flat_json" = "true");

-- 查询自动利用 Flat JSON 加速
SELECT get_json_string(data, '$.user.name')
FROM events
WHERE get_json_string(data, '$.action') = 'click';
```

## 跨引擎迁移速查

从 PostgreSQL 迁移到其他引擎时的路径语法转换：

| PostgreSQL 语法 | MySQL | Oracle | SQL Server | Snowflake | BigQuery |
|----------------|-------|--------|-----------|-----------|---------|
| `data->>'key'` | `data->>'$.key'` | `JSON_VALUE(data, '$.key')` | `JSON_VALUE(data, '$.key')` | `data:key::STRING` | `JSON_VALUE(data, '$.key')` |
| `data->'obj'->'key'` | `data->'$.obj.key'` | `JSON_QUERY(data, '$.obj')` | `JSON_QUERY(data, '$.obj')` | `data:obj:key` | `JSON_QUERY(data, '$.obj')` |
| `data->0` | `data->'$[0]'` | `JSON_VALUE(data, '$[0]')` | `JSON_VALUE(data, '$[0]')` | `data[0]` | `JSON_VALUE(data, '$[0]')` |
| `data @> '{"k":"v"}'` | `JSON_CONTAINS(data, '"v"', '$.k')` | `JSON_EXISTS(data, '$.k?(@ == "v")')` | 无等价 | `data:k::STRING = 'v'` | `JSON_VALUE(data, '$.k') = 'v'` |
| `data ? 'key'` | `JSON_CONTAINS_PATH(data, 'one', '$.key')` | `JSON_EXISTS(data, '$.key')` | `JSON_VALUE(data, '$.key') IS NOT NULL` | `data:key IS NOT NULL` | `JSON_QUERY(data, '$.key') IS NOT NULL` |

## 设计建议

**对引擎开发者**:
- 至少实现 `JSON_VALUE` + `JSON_QUERY`（SQL:2016 标准），确保标准合规
- 同时提供运算符快捷方式（`->` / `->>` 或 `.` 点表示法），提升开发者体验
- `JSON_TABLE` 是 JSON-关系桥梁的最重要函数，优先级高于其他 JSON 函数
- 二进制存储格式是性能基础——文本存储的 JSON 在路径查询场景下性能差 10-100 倍

**对应用开发者**:
- 跨引擎项目优先使用 `JSON_VALUE()` / `JSON_QUERY()` 函数——覆盖面最广
- 避免依赖 `@>` / `?` 等 PostgreSQL 专有运算符，除非确定不需要迁移
- JSON 文档超过 1KB 时必须考虑索引策略——全表扫描 + JSON 解析的成本是双重的
- 频繁修改的 JSON 字段考虑使用 MySQL（partial update）或 Oracle（JSON_TRANSFORM 批量操作）
