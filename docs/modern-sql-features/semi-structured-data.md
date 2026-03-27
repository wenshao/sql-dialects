# 半结构化数据处理演进

从 TEXT 列存 JSON 到原生嵌套类型——SQL 引擎处理半结构化数据的二十年演进。

## 支持矩阵

| 引擎 | 类型 | 存储格式 | 版本 | 索引支持 | 备注 |
|------|------|---------|------|---------|------|
| PostgreSQL | JSONB | 二进制 JSON | 9.4+ | GIN 索引 | **开创者**，也支持 JSON（文本） |
| MySQL | JSON | 二进制 JSON | 5.7+ | 多值索引 (8.0.17+) | 不支持 GIN |
| Snowflake | VARIANT | 自有二进制 | GA | 无传统索引 | **最灵活**，统一 JSON/XML/Avro |
| BigQuery | STRUCT / ARRAY / JSON | 列式嵌套 | GA | 自动优化 | Schema 内嵌 |
| Redshift | SUPER | PartiQL 查询 | 2021+ | 无 | 半结构化超级类型 |
| ClickHouse | Nested / Tuple / Map / JSON | 列式存储 | 各版本 | 有 | JSON 类型实验中 |
| Oracle | JSON | 原生 JSON 类型 | 21c+ | 函数索引 / JSON 搜索索引 | 之前用 VARCHAR2/CLOB |
| SQL Server | NVARCHAR + OPENJSON | 文本存储 | 2016+ | 计算列索引 | 无原生 JSON 类型 |
| DuckDB | STRUCT / LIST / MAP / JSON | 列式嵌套 | GA | 无传统索引 | 原生嵌套类型 |
| SQLite | JSON 函数 | 文本存储 | 3.38+ | 无 | 基于 JSON1 扩展 |

## 设计演进的三个阶段

```
阶段 1 (2000s): TEXT/VARCHAR 存 JSON 字符串
├── 数据库不理解 JSON 结构
├── 解析在应用层完成
├── 无法索引、无法查询 JSON 内部字段
└── 代表: 所有早期数据库

阶段 2 (2012-2018): 二进制 JSON 类型
├── 数据库解析并以二进制格式存储 JSON
├── 支持 JSON 路径查询
├── 可以建索引（GIN、函数索引）
├── 代表: PostgreSQL JSONB, MySQL JSON
└── 本质: 仍是"文档嵌在关系型中"

阶段 3 (2018+): 原生嵌套类型
├── STRUCT/ARRAY/MAP 是一等类型
├── 列式存储引擎原生支持嵌套列
├── 无需 JSON 序列化/反序列化
├── 代表: BigQuery, DuckDB, ClickHouse
└── 本质: "关系模型扩展为支持嵌套"
```

## 各引擎语法对比

### PostgreSQL JSONB（开创者）

```sql
-- 两种 JSON 类型: JSON（文本）和 JSONB（二进制）
-- 几乎总是应该用 JSONB

CREATE TABLE events (
    id SERIAL PRIMARY KEY,
    data JSONB NOT NULL
);

INSERT INTO events (data) VALUES
('{"user": "alice", "action": "click", "meta": {"page": "/home", "duration": 3.5}}');

-- 路径查询运算符
SELECT data->'user' AS user_json,            -- → "alice" (JSON 类型)
       data->>'user' AS user_text,           -- → alice   (TEXT 类型)
       data->'meta'->>'page' AS page,        -- → /home
       data#>'{meta,page}' AS page_json,     -- → "/home" (路径访问)
       data#>>'{meta,page}' AS page_text     -- → /home
FROM events;

-- 包含查询（高效，可用 GIN 索引）
SELECT * FROM events WHERE data @> '{"user": "alice"}';

-- 存在查询
SELECT * FROM events WHERE data ? 'action';            -- key 存在
SELECT * FROM events WHERE data ?| array['action', 'type'];  -- 任一 key 存在
SELECT * FROM events WHERE data ?& array['user', 'action'];  -- 所有 key 存在

-- JSON 路径查询（PostgreSQL 12+, SQL:2016 标准）
SELECT * FROM events WHERE data @@ '$.meta.duration > 2';
SELECT jsonb_path_query(data, '$.meta.*') FROM events;

-- 聚合构造 JSON
SELECT jsonb_agg(name) FROM employees;                        -- ["Alice","Bob"]
SELECT jsonb_object_agg(name, salary) FROM employees;         -- {"Alice":80000}

-- 更新 JSON 字段
UPDATE events SET data = data || '{"status": "processed"}';          -- 合并
UPDATE events SET data = data - 'meta';                              -- 删除 key
UPDATE events SET data = jsonb_set(data, '{meta,page}', '"/new"');   -- 设置路径

-- JSONB 展开
SELECT * FROM jsonb_each('{"a":1,"b":2}');         -- key-value 行
SELECT * FROM jsonb_array_elements('[1,2,3]');      -- 数组元素行
```

### MySQL JSON (5.7+)

```sql
CREATE TABLE events (
    id INT AUTO_INCREMENT PRIMARY KEY,
    data JSON NOT NULL
);

INSERT INTO events (data) VALUES
('{"user": "alice", "action": "click", "tags": ["web", "mobile"]}');

-- 路径查询（JSON Path 语法）
SELECT JSON_EXTRACT(data, '$.user') AS user,                  -- "alice"
       data->'$.user' AS user_shorthand,                       -- "alice"
       JSON_UNQUOTE(JSON_EXTRACT(data, '$.user')) AS user_text, -- alice
       data->>'$.user' AS user_unquoted                        -- alice (8.0.21+)
FROM events;

-- JSON 搜索
SELECT * FROM events
WHERE JSON_CONTAINS(data, '"click"', '$.action');

SELECT * FROM events
WHERE JSON_CONTAINS(data, '"web"', '$.tags');

-- JSON 修改
UPDATE events SET data = JSON_SET(data, '$.status', 'done');
UPDATE events SET data = JSON_REMOVE(data, '$.tags');
UPDATE events SET data = JSON_ARRAY_APPEND(data, '$.tags', 'new');

-- JSON 表函数（MySQL 8.0+）: JSON 转关系表
SELECT jt.*
FROM events,
JSON_TABLE(data, '$' COLUMNS (
    user_name VARCHAR(50) PATH '$.user',
    action VARCHAR(50) PATH '$.action',
    NESTED PATH '$.tags[*]' COLUMNS (tag VARCHAR(20) PATH '$')
)) AS jt;

-- ⚠️ MySQL 的限制:
-- 1. 无类似 PostgreSQL 的 @> 包含运算符
-- 2. JSON 列不能直接做 WHERE data = '...'（需用函数）
-- 3. 部分更新优化从 8.0.3 开始
```

### Snowflake VARIANT（最灵活）

```sql
-- VARIANT 类型: 可以存储 JSON, XML, Avro, Parquet 等任何半结构化数据
CREATE TABLE raw_events (
    id NUMBER AUTOINCREMENT,
    raw_data VARIANT
);

-- 从 JSON 字符串解析
INSERT INTO raw_events (raw_data)
SELECT PARSE_JSON('{"user": "alice", "action": "click", "scores": [90, 85, 95]}');

-- 路径查询（冒号语法，简洁优雅）
SELECT raw_data:user::STRING AS user,            -- 类型转换
       raw_data:action::STRING AS action,
       raw_data:scores[0]::NUMBER AS first_score  -- 数组索引
FROM raw_events;

-- 嵌套路径
SELECT raw_data:meta.page::STRING AS page
FROM raw_events;

-- FLATTEN: 展开嵌套结构（核心函数）
SELECT e.raw_data:user::STRING AS user, f.value::NUMBER AS score
FROM raw_events e,
LATERAL FLATTEN(input => e.raw_data:scores) f;

-- OBJECT_CONSTRUCT / ARRAY_CONSTRUCT: 构造半结构化数据
SELECT OBJECT_CONSTRUCT('name', name, 'salary', salary) AS emp_json
FROM employees;

-- Schema on Read: 从 VARIANT 列查询时才确定 schema
-- 无需预定义字段，新字段自动可查
-- 这是 Snowflake 处理 JSON 数据的核心优势
```

### BigQuery STRUCT / ARRAY（Schema 内嵌）

```sql
-- BigQuery 的哲学: 不用 JSON 类型，用 STRUCT + ARRAY 表达嵌套

-- 定义嵌套 schema
CREATE TABLE events (
    event_id INT64,
    user STRUCT<name STRING, age INT64, email STRING>,
    tags ARRAY<STRING>,
    metadata STRUCT<
        source STRING,
        scores ARRAY<INT64>,
        location STRUCT<lat FLOAT64, lng FLOAT64>
    >
);

-- 查询嵌套字段（点号访问）
SELECT event_id,
       user.name,
       user.age,
       metadata.location.lat
FROM events;

-- 展开数组
SELECT event_id, tag
FROM events, UNNEST(tags) AS tag;

-- 多层展开
SELECT event_id, score
FROM events, UNNEST(metadata.scores) AS score;

-- JSON 类型（BigQuery 也支持, 2022+）
CREATE TABLE json_events (
    id INT64,
    data JSON
);

SELECT JSON_VALUE(data, '$.user') AS user FROM json_events;

-- BigQuery 的 STRUCT/ARRAY 在列式存储中非常高效
-- Dremel 论文定义的 repetition/definition level 原生支持嵌套
```

### Redshift SUPER（PartiQL 查询）

```sql
-- SUPER 类型: 半结构化超级类型
CREATE TABLE events (
    id INT,
    data SUPER
);

-- 从 JSON 加载
INSERT INTO events VALUES (1, JSON_PARSE('{"user": "alice", "tags": ["a", "b"]}'));

-- PartiQL 查询语法
SELECT data.user, data.tags[0]
FROM events;

-- 展开数组
SELECT e.id, t AS tag
FROM events e, e.data.tags t;

-- SUPER 类型支持无 schema 的动态查询
-- 不存在的路径返回 NULL 而不是报错
SELECT data.nonexistent_field FROM events;  -- NULL
```

### ClickHouse（列式嵌套）

```sql
-- Nested 类型: 列式存储的嵌套结构
CREATE TABLE events (
    id UInt64,
    user_name String,
    tags Nested(
        name String,
        value String
    )
) ENGINE = MergeTree() ORDER BY id;

-- Nested 实际上存储为并行数组
-- tags.name: Array(String)
-- tags.value: Array(String)

INSERT INTO events VALUES (1, 'alice', ['env', 'version'], ['prod', '2.0']);

SELECT id, tags.name, tags.value FROM events;

-- Tuple 类型: 固定结构的嵌套
CREATE TABLE events2 (
    id UInt64,
    metadata Tuple(source String, version UInt32)
) ENGINE = MergeTree() ORDER BY id;

SELECT id, metadata.1 AS source, metadata.2 AS version FROM events2;

-- Map 类型: 动态键值对
CREATE TABLE events3 (
    id UInt64,
    properties Map(String, String)
) ENGINE = MergeTree() ORDER BY id;

SELECT id, properties['browser'] FROM events3;

-- JSON 类型（实验中）: 自动推断 schema 的半结构化类型
-- ClickHouse 的方向: 将 JSON 解析为列式存储，而非二进制 blob
```

### SQL Server OPENJSON + FOR JSON

```sql
-- SQL Server 没有原生 JSON 类型，用 NVARCHAR 存储
CREATE TABLE events (
    id INT IDENTITY PRIMARY KEY,
    data NVARCHAR(MAX)   -- JSON 存在 NVARCHAR 中
);

-- JSON 查询函数
SELECT JSON_VALUE(data, '$.user') AS user,       -- 标量值
       JSON_QUERY(data, '$.meta') AS meta_obj    -- 对象/数组
FROM events;

-- OPENJSON: JSON 转关系表
SELECT *
FROM events
CROSS APPLY OPENJSON(data)
WITH (
    user_name VARCHAR(50) '$.user',
    action VARCHAR(50) '$.action',
    page VARCHAR(100) '$.meta.page'
);

-- FOR JSON: 关系表转 JSON
SELECT id, name, salary
FROM employees
FOR JSON PATH;
-- [{"id":1,"name":"Alice","salary":80000}, ...]

-- 计算列 + 索引: 对 JSON 字段建索引的方式
ALTER TABLE events
ADD user_name AS JSON_VALUE(data, '$.user');
CREATE INDEX idx_user ON events (user_name);

-- ISJSON: 验证 JSON 格式
ALTER TABLE events ADD CONSTRAINT chk_json CHECK (ISJSON(data) = 1);
```

## 索引策略对比

| 索引类型 | 引擎 | 适用场景 | 原理 |
|---------|------|---------|------|
| GIN 索引 | PostgreSQL | `@>` 包含查询、`?` 存在查询 | 倒排索引，索引所有 key 和 value |
| 函数索引 | Oracle, PostgreSQL | 特定路径的精确查询 | 对 JSON 路径表达式建 B-tree |
| 多值索引 | MySQL 8.0.17+ | JSON 数组中的值查询 | 对数组元素建倒排索引 |
| 计算列索引 | SQL Server | 特定字段的查询 | 先提取为计算列，再建 B-tree |
| JSON 搜索索引 | Oracle 21c | 全文搜索 JSON | 基于 Oracle Text |
| 无传统索引 | Snowflake, BigQuery | 大规模扫描 | 依赖微分区裁剪 / 列式存储 |

```sql
-- PostgreSQL GIN 索引
CREATE INDEX idx_data_gin ON events USING gin (data);
-- 加速: data @> '{"user": "alice"}'
-- 加速: data ? 'user'
-- GIN 索引适合写少读多的场景（写入时维护成本高）

-- PostgreSQL jsonb_path_ops GIN（更紧凑）
CREATE INDEX idx_data_pathops ON events USING gin (data jsonb_path_ops);
-- 只加速 @> 查询，不加速 ? 查询，但索引更小

-- MySQL 多值索引 (8.0.17+)
ALTER TABLE events ADD INDEX idx_tags (
    (CAST(data->'$.tags' AS CHAR(50) ARRAY))
);
-- 加速: JSON_CONTAINS(data->'$.tags', '"web"')
-- 加速: 'web' MEMBER OF (data->'$.tags')

-- Oracle 函数索引
CREATE INDEX idx_user ON events (JSON_VALUE(data, '$.user'));
```

## 对引擎开发者的实现建议

### 1. 存储格式选择

```
选项 A: 二进制 JSON (PostgreSQL JSONB 方式)
├── 优点: 灵活，无需 schema
├── 缺点: 访问单个字段需要遍历
└── 适合: OLTP，JSON 整体读写

选项 B: 列式展开 (BigQuery / ClickHouse 方式)
├── 优点: 列裁剪、向量化处理
├── 缺点: schema 变更时需要调整列
└── 适合: OLAP，分析查询

选项 C: 混合 (Snowflake VARIANT 方式)
├── 优点: 灵活 + 自动优化
├── 缺点: 实现复杂
└── 适合: 需要同时支持 ETL 和分析的场景
```

### 2. 类型系统集成

半结构化类型需要与现有类型系统深度集成：

- 隐式类型转换规则（JSON 中的 number 如何与 SQL INT 比较）
- NULL 语义（JSON null vs SQL NULL 是不同概念）
- 比较语义（两个 JSON 对象如何比较大小？key 顺序是否影响相等性？）

### 3. 查询优化

```
-- 关键优化: JSON 路径下推
SELECT data->'user' FROM events WHERE data->>'status' = 'active'
→ 优化器应该识别出只需读取 data 中的 user 和 status 两个字段
→ 在列式存储中，这可以转化为列裁剪
→ 在行式存储中，可以避免完整反序列化
```

## 参考资料

- PostgreSQL: [JSON Types](https://www.postgresql.org/docs/current/datatype-json.html)
- MySQL: [JSON Data Type](https://dev.mysql.com/doc/refman/8.0/en/json.html)
- Snowflake: [VARIANT](https://docs.snowflake.com/en/sql-reference/data-types-semistructured)
- BigQuery: [STRUCT / ARRAY](https://cloud.google.com/bigquery/docs/nested-repeated)
- ClickHouse: [Nested / Map / Tuple](https://clickhouse.com/docs/en/sql-reference/data-types/nested-data-structures)
- SQL Server: [JSON in SQL Server](https://learn.microsoft.com/en-us/sql/relational-databases/json/json-data-sql-server)
- Oracle: [JSON in Oracle](https://docs.oracle.com/en/database/oracle/oracle-database/21/adjsn/)
