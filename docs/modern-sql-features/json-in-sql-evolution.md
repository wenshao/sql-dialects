# JSON in SQL: 语法设计的演进与分裂

JSON 支持是过去 10 年 SQL 引擎变化最大的领域之一。各引擎的设计选择差异巨大，本文从引擎开发者角度分析这些选择的 trade-off。

## 演进时间线

```
2009  PostgreSQL 9.2: JSON 类型（文本存储，每次解析）
2012  Oracle 12c R1: JSON 存在 VARCHAR2/CLOB 中 + IS JSON 校验
2014  PostgreSQL 9.4: JSONB（二进制存储，支持索引）—— 里程碑
2015  MySQL 5.7.8: JSON 类型（二进制存储）
2016  SQL Server 2016: JSON 支持（无原生类型，存在 NVARCHAR 中）
2016  SQL:2016 标准: 正式定义 JSON 函数（JSON_VALUE/JSON_QUERY/JSON_TABLE 等）
2018  SQLite 3.9.0: json1 扩展
2020  ClickHouse: JSON 作为 String + 函数
2021  Oracle 21c: 原生 JSON 类型
2022  BigQuery: JSON 类型
2023  PostgreSQL 17: SQL 标准 JSON_TABLE
2024  ClickHouse: 半结构化 JSON 类型（实验性）
```

## 核心设计决策 1: 存储格式

### 方案 A: 文本存储（SQL Server, 早期 PostgreSQL, Hive）

```sql
-- SQL Server: JSON 存在 NVARCHAR 中
CREATE TABLE events (
    id BIGINT IDENTITY PRIMARY KEY,
    data NVARCHAR(MAX) CHECK (ISJSON(data) = 1)
);
```

- **优点**: 实现最简单，不需要新的存储格式
- **缺点**: 每次访问都要解析（O(n)），无法高效索引
- **适用**: 只写入和整体读取，极少做字段级查询

### 方案 B: 二进制存储（PostgreSQL JSONB, MySQL JSON, Oracle 21c）

```sql
-- PostgreSQL JSONB: 写入时解析并存储为二进制
CREATE TABLE events (
    id BIGSERIAL PRIMARY KEY,
    data JSONB
);
-- 字段访问是 O(1)（哈希查找）
SELECT data->>'name' FROM events;
```

- **优点**: 读取快（已解析），支持索引，支持局部更新
- **缺点**: 写入时有解析开销，存储空间略大（需要存储结构信息）
- **PostgreSQL JSONB 细节**: 键排序去重，支持 GIN 索引
- **MySQL JSON 细节**: 键排序 + 偏移表（offset table），支持 partial update (8.0+)

### 方案 C: 半结构化原生类型（Snowflake VARIANT, BigQuery STRUCT）

```sql
-- Snowflake: VARIANT 统一所有半结构化数据
CREATE TABLE events (
    id NUMBER AUTOINCREMENT,
    data VARIANT  -- 可以是 JSON/XML/Avro/Parquet
);
-- : 运算符（Snowflake 独有）
SELECT data:user:name::STRING FROM events;

-- BigQuery: STRUCT + ARRAY（Schema 内嵌，类型已知）
CREATE TABLE events (
    id INT64,
    data STRUCT<user STRUCT<name STRING, age INT64>, tags ARRAY<STRING>>
);
SELECT data.user.name FROM events;
```

- **Snowflake VARIANT**: 自描述格式，列式存储的每列可以有不同类型
- **BigQuery STRUCT**: 编译时类型已知，本质是嵌套列式存储
- **ClickHouse**: 传统上用 String + JSONExtract 函数，新版实验性 JSON 类型

**对引擎开发者的建议**:
- OLTP 引擎: 二进制 JSON（PostgreSQL JSONB 模式）是最佳选择
- OLAP 引擎: STRUCT/ARRAY 原生嵌套类型（BigQuery 模式）性能最好
- 通用引擎: 同时支持 JSON（灵活）和 STRUCT（高性能）

## 核心设计决策 2: 路径表达式语法

这是各引擎分裂最严重的地方：

| 引擎 | 获取 JSON 值 | 获取文本值 | 数组索引 |
|------|------------|-----------|---------|
| PostgreSQL | `data->'key'` | `data->>'key'` | `data->0` |
| MySQL | `data->'$.key'` | `data->>'$.key'` | `data->'$.arr[0]'` |
| SQL Server | `JSON_VALUE(data, '$.key')` | 同左（总是文本） | `JSON_VALUE(data, '$.arr[0]')` |
| Oracle | `data.key` (点表示法) | `JSON_VALUE(data, '$.key')` | `data.arr[0]` |
| BigQuery | `data.key` | `data.key` | `data.arr[0]` |
| Snowflake | `data:key` | `data:key::STRING` | `data:arr[0]` |
| ClickHouse | `JSONExtractString(data, 'key')` | 同左 | `JSONExtractString(data, 'arr', 1)` |
| SQLite | `json_extract(data, '$.key')` | `data->>'$.key'` (3.38+) | `json_extract(data, '$.arr[0]')` |
| DuckDB | `data->>'key'` 或 `data.key` | 同左 | `data[0]` |

**分裂原因分析**:
- `->` vs `:`  vs `.`: 运算符选择取决于 parser 的保留符号
- `$.key` (JSONPath) vs `key` (简化路径): JSONPath 更标准但更冗长
- SQL:2016 标准定义了 `JSON_VALUE(expr, path)`，但几乎没有引擎完全遵循

**对引擎开发者的建议**:
- 如果走标准路线: 实现 `JSON_VALUE` + `JSON_QUERY` (SQL:2016)
- 如果走 PG 兼容路线: 实现 `->` 和 `->>`
- 如果走便捷路线: 实现点表示法 `data.key`（最自然，BigQuery/Oracle 做法）
- 推荐同时支持函数形式和运算符形式

## 核心设计决策 3: JSON 索引

| 引擎 | 索引方式 | 说明 |
|------|---------|------|
| PostgreSQL | GIN 索引 (JSONB) | 支持 @> 包含查询、? 键存在查询 |
| PostgreSQL | 函数索引 | `CREATE INDEX ON t ((data->>'name'))` |
| MySQL | 多值索引 (8.0.17+) | `CREATE INDEX ON t ((CAST(data->'$.tags' AS CHAR(64) ARRAY)))` |
| MySQL | 虚拟列 + 索引 | 先创建 GENERATED 列，再建索引 |
| Oracle | 函数索引 | `CREATE INDEX ON t (JSON_VALUE(data, '$.name'))` |
| Oracle | JSON 搜索索引 | `CREATE SEARCH INDEX ON t (data) FOR JSON` |
| Oracle | 多值索引 (21c) | `CREATE MULTIVALUE INDEX ON t e (e.data.tags.string())` |
| SQL Server | 计算列 + 索引 | 先 ADD col AS JSON_VALUE(data, '$.name')，再建索引 |
| BigQuery | 无（STRUCT 天然列式） | 不需要额外索引 |
| Snowflake | 无（微分区自动优化） | 不需要额外索引 |

**设计分析**:
- **GIN 索引**（PostgreSQL）: 最灵活，支持任意键查询，但写入开销大
- **函数索引**: 只加速特定路径的查询，但通用性好
- **多值索引**: 专为 JSON 数组设计，MySQL 8.0 和 Oracle 21c 的新能力
- **无索引**（BigQuery/Snowflake）: 依赖列式存储的天然优势

## 核心设计决策 4: JSON 修改

| 操作 | PostgreSQL | MySQL | SQL Server | Oracle |
|------|-----------|-------|-----------|--------|
| 设置值 | `jsonb_set(data, '{key}', '"val"')` | `JSON_SET(data, '$.key', 'val')` | `JSON_MODIFY(data, '$.key', 'val')` | `JSON_TRANSFORM(data, SET '$.key' = 'val')` |
| 删除键 | `data - 'key'` | `JSON_REMOVE(data, '$.key')` | `JSON_MODIFY(data, '$.key', NULL)` | `JSON_TRANSFORM(data, REMOVE '$.key')` |
| 合并 | `data \|\| '{"a":1}'` | 无原生（多次 JSON_SET） | 无原生 | `JSON_MERGEPATCH(data, '{"a":1}')` |
| 数组追加 | `data \|\| '["new"]'` | `JSON_ARRAY_APPEND(data, '$', 'new')` | `JSON_MODIFY(data, 'append $.arr', 'new')` | `JSON_TRANSFORM(data, APPEND '$.arr' = 'new')` |

**PostgreSQL 的优势**: 运算符 `||`（合并）、`-`（删除）、`#-`（路径删除）— 简洁且组合性好
**MySQL 的优势**: `JSON_SET`/`JSON_INSERT`/`JSON_REPLACE` 三种语义明确区分
**Oracle 的优势**: `JSON_TRANSFORM` 可以在一个调用中做多种修改

**partial update 优化**:
- MySQL 8.0+: 如果 JSON_SET 只修改值（不改变结构），可以原地更新而非重写整个文档
- PostgreSQL: JSONB 的 TOAST 压缩 + 行版本化，无原地更新
- **对引擎开发者**: partial update 对大 JSON 文档性能影响巨大，建议实现

## 核心设计决策 5: JSON 到关系表的转换

这是 JSON 在 SQL 中最重要的能力——将嵌套 JSON 展开为关系表：

```sql
-- SQL:2016 标准: JSON_TABLE
SELECT jt.*
FROM events,
JSON_TABLE(data, '$' COLUMNS (
    name VARCHAR(64) PATH '$.user.name',
    age INT PATH '$.user.age',
    NESTED PATH '$.items[*]' COLUMNS (
        product VARCHAR(100) PATH '$.product',
        qty INT PATH '$.qty'
    )
)) AS jt;
```

各引擎的实现:

| 引擎 | 方式 | 说明 |
|------|------|------|
| Oracle 12c+ | `JSON_TABLE` | 最早实现，功能最全 |
| MySQL 8.0+ | `JSON_TABLE` | 兼容 SQL 标准 |
| PostgreSQL 17+ | `JSON_TABLE` | 最晚支持标准语法 |
| PostgreSQL | `jsonb_to_recordset`, `jsonb_array_elements` | 传统方式 |
| SQL Server | `OPENJSON` | 独有语法，非标准 |
| Snowflake | `FLATTEN` | 独有语法，WITH 子句定义输出列 |
| BigQuery | `UNNEST` + STRUCT 字段访问 | 利用原生嵌套类型 |
| ClickHouse | `JSONExtract` + `arrayJoin` | 函数组合 |
| Hive/Spark | `LATERAL VIEW json_tuple` | Hive 生态方式 |
| DuckDB | `UNNEST` 或结构体访问 | 类 PostgreSQL |

**对引擎开发者的建议**:
- 优先实现 SQL:2016 `JSON_TABLE`（标准化程度最高，Oracle/MySQL 已采用）
- 同时支持简化的 `UNNEST` 或 `FLATTEN`（日常使用更便捷）
- `JSON_TABLE` 的实现本质是一个"表生成函数"（Table Function），在执行计划中产生行

## 支持矩阵总览

| 特性 | PG | MySQL | Oracle | SQL Server | BigQuery | Snowflake | ClickHouse | DuckDB |
|------|-----|-------|--------|-----------|---------|-----------|-----------|--------|
| 原生 JSON 类型 | JSONB 9.4+ | JSON 5.7+ | JSON 21c+ | ❌ (NVARCHAR) | JSON | VARIANT | String | JSON |
| 路径提取 | `->` `->>'` | `->` `->>'` `$.path` | `.` 点表示法 | `JSON_VALUE()` | `.` 点表示法 | `:` | 函数 | `->` `.` |
| GIN/倒排索引 | ✅ | ❌ | ✅ 搜索索引 | ❌ | ❌ | ❌ | ❌ | ❌ |
| 函数索引 | ✅ | ✅ 虚拟列 | ✅ | ✅ 计算列 | ❌ | ❌ | ❌ | ❌ |
| 多值索引 | ❌ | ✅ 8.0.17+ | ✅ 21c+ | ❌ | ❌ | ❌ | ❌ | ❌ |
| JSON_TABLE | ✅ 17+ | ✅ 8.0+ | ✅ 12c+ | OPENJSON | UNNEST | FLATTEN | arrayJoin | UNNEST |
| Partial Update | ❌ | ✅ 8.0+ | ✅ | N/A | N/A | N/A | N/A | ❌ |
| JSON 聚合 | ✅ json_agg | ✅ JSON_ARRAYAGG | ✅ JSON_ARRAYAGG | FOR JSON | TO_JSON_STRING | ARRAY_AGG | groupArray | json_group_array |

## 对引擎开发者的总结

1. **存储**: OLTP 用二进制 JSON (JSONB)，OLAP 用原生嵌套类型 (STRUCT/ARRAY)
2. **路径语法**: 同时支持标准函数 (JSON_VALUE) 和便捷运算符 (-> 或 .)
3. **索引**: 至少支持函数索引（表达式索引），GIN 索引是进阶
4. **展开**: 实现 JSON_TABLE (SQL:2016 标准)
5. **修改**: 实现 partial update（大文档场景性能关键）
6. **不要发明新语法**: JSON 语法已经够碎片化了，尽量用已有方案
