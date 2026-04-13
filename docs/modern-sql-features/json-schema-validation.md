# JSON 模式验证 (JSON Schema Validation)

JSON 列以"无模式"自由著称，但生产系统从来不允许真正的无模式：每个 `metadata`、`payload`、`config` 列背后都藏着一份未写下来的契约。把这份契约从应用层下沉到数据库内部，用 `IS JSON`、`CHECK` 约束、JSON Schema 校验函数强制执行，是 JSON 列从"半结构化"走向"可治理的半结构化"的关键一步。本文系统对比 45+ 数据库引擎对 JSON 模式验证的支持。

> 本文聚焦 JSON 模式验证（schema validation）。其他相关主题：
> - 类型存储与函数演进 → `json-in-sql-evolution.md`
> - JSONPath / JSON_VALUE / JSON_QUERY 路径表达式 → `json-path-syntax.md`
> - JSON_TABLE 平铺 → `json-table.md`

## 为什么要把 JSON 模式验证放进数据库

把 JSON 写进 `TEXT` 或 `BLOB` 是最简单的方案，但它把所有问题推向应用层：

1. **写入约束失效**：应用代码可以写入任意字符串，下游服务读到非法 JSON 才会报错，并且无法回滚源头。
2. **多写者灾难**：当 ETL、流任务、人工 SQL、外部系统同时写一张表时，应用层的 Pydantic / Zod / Joi 校验各写各的，最终列里出现五种"看起来正确"的 JSON 形状。
3. **历史污染**：一次错误发布把 `is_active: "true"`（字符串）和 `is_active: true`（布尔）都写入同一列，几个月后才被发现，回填代价巨大。
4. **索引失效**：JSON 函数索引（如 `idx ON (data->>'sku')`）依赖某个键存在；缺键的脏数据让索引部分变 NULL，查询不再走索引而毫无报警。
5. **下游契约**：CDC/同步管道、向量化分析引擎、列存储自动 schema 推断都假设 JSON 形状稳定，schema drift 直接打爆 schema registry。

数据库内的 JSON 模式验证从弱到强可以分成五层：

| 层级 | 能力 | 标准 |
|------|------|------|
| L1 语法校验 | 字符串是合法 JSON | SQL:2016 `IS JSON` |
| L2 类型校验 | 顶层是 OBJECT/ARRAY/SCALAR | SQL:2016 `IS JSON OBJECT` 等 |
| L3 唯一键 | 对象中没有重复键 | SQL:2016 `WITH UNIQUE KEYS` |
| L4 路径存在 | 必填字段存在且类型正确 | SQL:2023 `JSON_EXISTS` + `JSON_VALUE ... RETURNING` |
| L5 完整 schema | 嵌套结构、枚举、正则、数字范围 | JSON Schema Draft 2020-12 / Oracle `DBMS_JSON_SCHEMA` |

SQL 标准目前只覆盖到 L4；L5 仍处在各厂商扩展阶段，Oracle 23ai 是第一个把 IETF JSON Schema 内置到数据库的主流商业引擎。

## SQL 标准定义

### SQL:2016 — IS JSON 谓词

SQL:2016（ISO/IEC 9075-2 第 8.x 节）正式引入 JSON 类型相关的谓词：

```sql
<json_predicate> ::=
    <expression> IS [NOT] JSON
        [ <json_type> ]
        [ <unique_keys_clause> ]

<json_type> ::= VALUE | ARRAY | OBJECT | SCALAR

<unique_keys_clause> ::= WITH UNIQUE KEYS | WITHOUT UNIQUE KEYS
```

语义要点：

1. `expr IS JSON` 等价于 `expr IS JSON VALUE`，只校验"是合法 JSON"。
2. `IS JSON OBJECT` 要求顶层是 `{...}`；`IS JSON ARRAY` 要求顶层是 `[...]`；`IS JSON SCALAR` 要求顶层是数字、字符串、布尔或 `null`。
3. `WITH UNIQUE KEYS` 进一步要求所有对象（含嵌套）都不能出现重复键，这是 ECMA-404 允许、但绝大多数应用禁止的情况。
4. `WITHOUT UNIQUE KEYS` 是默认行为。
5. 该谓词可以用在 `WHERE`、`CHECK`、`CASE`、`HAVING` 中。

### SQL:2023 — 路径语义

SQL:2023（ISO/IEC 9075-2:2023）补充了 `JSON_EXISTS`、`JSON_VALUE`、`JSON_QUERY`、`JSON_TABLE` 等函数，配合 `RETURNING <data type>` 与 `ERROR ON ERROR` 子句，可以做到字段级类型校验：

```sql
CHECK (
  JSON_EXISTS(payload, '$.user_id')
  AND JSON_VALUE(payload, '$.amount' RETURNING DECIMAL(18,2) ERROR ON ERROR) > 0
)
```

这相当于把"必填 + 类型 + 业务规则"用标准 SQL 表达，是 SQL 标准对 schema 验证的最强保证。但它仍然不是完整的 JSON Schema（例如不支持 `oneOf`、`patternProperties`、`$ref`），完整 JSON Schema 仍属于 ISO/IEC TR 19075-6 描述的"实现选项"。

### IETF JSON Schema

数据库厂商提到"JSON Schema"通常指 IETF 草案：

| 草案 | 年份 | 关键特性 |
|------|------|---------|
| Draft-04 | 2013 | `required`、`properties`、`type` |
| Draft-06/07 | 2017–2018 | `const`、`if/then/else`、`contains` |
| 2019-09 | 2019 | `$defs`、`unevaluatedProperties` |
| 2020-12 | 2020 | `prefixItems`、`dependentRequired` |

Oracle 23ai 的 `DBMS_JSON_SCHEMA` 实现的是 Draft 2020-12 子集，PostgreSQL 的 `pg_jsonschema` 扩展底层使用 Rust 库 `jsonschema` 同样支持 2020-12。

## 支持矩阵

### 矩阵 1：`IS JSON` 谓词（SQL:2016）

| 引擎 | `IS JSON` | `IS NOT JSON` | 实现版本 | 备注 |
|------|----------|---------------|---------|------|
| PostgreSQL | 是 | 是 | 16+ | 16 起补齐 SQL:2016 |
| MySQL | 否 (`JSON_VALID()`) | 否 | 5.7+ | 函数式而非谓词 |
| MariaDB | 否 (`JSON_VALID()`) | 否 | 10.0.16+ | 同上 |
| SQLite | 否 (`json_valid()`) | 否 | 3.38+ | json1 扩展 |
| Oracle | 是 | 是 | 12.1.0.2+ | SQL:2016 之前已实现 |
| SQL Server | 否 (`ISJSON()`) | 否 | 2016+ | 函数返回 0/1 |
| DB2 | 是 | 是 | 11.5+ | LUW 与 z/OS |
| Snowflake | 否 (`IS_VALID_JSON`) | 否 | GA | 仅函数 |
| BigQuery | 否 (`SAFE.PARSE_JSON`) | 否 | GA | 通过解析失败判定 |
| Redshift | 否 (`IS_VALID_JSON`) | 否 | GA | SUPER 类型 |
| DuckDB | 否 (`json_valid()`) | 否 | 0.7+ | JSON 扩展 |
| ClickHouse | 否 (`isValidJSON`) | 否 | 早期 | 函数 |
| Trino | 是 | 是 | 351+ | SQL:2016 |
| Presto | 是 | 是 | 0.217+ | 同 Trino |
| Spark SQL | 否 (`get_json_object` 间接) | 否 | -- | 无直接谓词 |
| Hive | 否 | 否 | -- | 无 |
| Flink SQL | 是 | 是 | 1.15+ | SQL:2016 兼容 |
| Databricks | 否 | 否 | -- | 走 SQL Spark |
| Teradata | 否 (`JSON_CHECK`) | 否 | 16+ | 函数式 |
| Greenplum | 是 | 是 | 7.0+ | 继承 PG 16 |
| CockroachDB | 否 | 否 | -- | JSONB 隐含校验 |
| TiDB | 否 (`JSON_VALID`) | 否 | 5.7 兼容 | 函数 |
| OceanBase | 否 (`JSON_VALID`) | 否 | 4.x | 函数 |
| YugabyteDB | 是 | 是 | 2.20+ | 继承 PG |
| SingleStore | 否 (`JSON_EXTRACT_*`) | 否 | -- | JSON 类型 |
| Vertica | 否 (Flex Tables) | 否 | -- | 无谓词 |
| Impala | 否 | 否 | -- | 无 JSON 类型 |
| StarRocks | 否 (`json_valid`) | 否 | 2.5+ | 函数 |
| Doris | 否 (`json_valid`) | 否 | 1.2+ | 函数 |
| MonetDB | 是 | 是 | Jul2021+ | JSON 模块 |
| CrateDB | 否 (OBJECT 类型隐含) | 否 | -- | 自动校验 |
| TimescaleDB | 是 | 是 | 继承 PG 16 | -- |
| QuestDB | 否 | 否 | -- | 无 JSON |
| Exasol | 否 | 否 | -- | 7.1+ JSON 函数 |
| SAP HANA | 否 (`IS_JSON`) | 否 | 2.0 SP05+ | 函数 |
| Informix | 是 | 是 | 12.10+ | BSON 列 |
| Firebird | 否 | 否 | -- | 无 JSON 类型 |
| H2 | 是 | 是 | 2.0+ | SQL:2016 兼容 |
| HSQLDB | 否 | 否 | -- | 无 |
| Derby | 否 | 否 | -- | 无 |
| Amazon Athena | 是 | 是 | 继承 Trino | -- |
| Azure Synapse | 否 (`ISJSON`) | 否 | GA | 同 SQL Server |
| Google Spanner | 否 | 否 | -- | JSON 类型自动校验 |
| Materialize | 否 | 否 | -- | 继承 PG 部分 |
| RisingWave | 否 | 否 | -- | -- |
| InfluxDB SQL | 否 | 否 | -- | -- |
| DatabendDB | 否 (`is_valid_json`) | 否 | GA | VARIANT |
| Yellowbrick | 否 | 否 | -- | -- |
| Firebolt | 否 | 否 | -- | -- |

> 谓词形式（标准 `IS JSON`）只有约 12 个引擎完整支持；其余 30+ 引擎用函数 `JSON_VALID()` / `ISJSON()` / `IS_VALID_JSON()` 提供等价能力。

### 矩阵 2：`IS JSON { VALUE | ARRAY | OBJECT | SCALAR }`

| 引擎 | VALUE | ARRAY | OBJECT | SCALAR | 备注 |
|------|-------|-------|--------|--------|------|
| PostgreSQL 16+ | 是 | 是 | 是 | 是 | 完整 |
| Oracle 12c+ | 是 | 是 | 是 | 是 | 完整 |
| DB2 11.5+ | 是 | 是 | 是 | 是 | 完整 |
| Trino / Presto | 是 | 是 | 是 | 是 | 完整 |
| H2 2.0+ | 是 | 是 | 是 | 是 | 完整 |
| Flink SQL 1.15+ | 是 | 是 | 是 | 是 | 完整 |
| MonetDB | 是 | 是 | 是 | -- | SCALAR 缺失 |
| Greenplum 7+ | 是 | 是 | 是 | 是 | 继承 PG |
| YugabyteDB 2.20+ | 是 | 是 | 是 | 是 | 继承 PG |
| TimescaleDB | 是 | 是 | 是 | 是 | 继承 PG |
| Athena | 是 | 是 | 是 | 是 | 继承 Trino |
| Informix | 是 | 是 | 是 | -- | -- |
| MySQL (`JSON_TYPE`) | 间接 | 间接 | 间接 | 间接 | 比较字符串 |
| MariaDB (`JSON_TYPE`) | 间接 | 间接 | 间接 | 间接 | 同上 |
| SQL Server | -- | -- | -- | -- | 仅 ISJSON |
| Snowflake | 间接 (`TYPEOF`) | 间接 | 间接 | 间接 | -- |
| BigQuery | 间接 (`JSON_TYPE`) | 间接 | 间接 | 间接 | -- |
| DuckDB | 间接 (`json_type`) | 间接 | 间接 | 间接 | -- |
| 其余 | -- | -- | -- | -- | 仅根级别校验 |

### 矩阵 3：`IS JSON WITH UNIQUE KEYS`

重复键虽然合法 JSON 允许，但绝大多数生产系统视其为错误：

| 引擎 | 支持 | 语法 |
|------|------|------|
| PostgreSQL 16+ | 是 | `data IS JSON WITH UNIQUE KEYS` |
| Oracle 12c+ | 是 | `data IS JSON (WITH UNIQUE KEYS)` |
| DB2 11.5+ | 是 | `data IS JSON WITH UNIQUE KEYS` |
| Trino / Presto | 是 | `data IS JSON WITH UNIQUE KEYS` |
| H2 2.0+ | 是 | `data IS JSON WITH UNIQUE KEYS` |
| Flink SQL | 是 | 标准语法 |
| Greenplum 7+ | 是 | 继承 PG |
| YugabyteDB | 是 | 继承 PG |
| MySQL | 否 | 解析时直接覆盖（去重） |
| MariaDB | 否 | 解析时去重 |
| SQL Server | 否 | -- |
| Snowflake | 否 | VARIANT 解析时去重 |
| BigQuery | 否 | `PARSE_JSON` 默认抛错，可选 `wide_number_mode` 但无 unique keys 选项 |
| DuckDB | 否 | -- |
| ClickHouse | 否 | -- |
| 其余 | 否 | -- |

> 真正区分这一能力的是"是否在解析阶段就完整保存原始键序"。MySQL/Snowflake/BigQuery 把 JSON 解析为内部树并自动去重，技术上不可能在事后判断重复键；只有 PG/Oracle/DB2/Trino 类引擎在 `IS JSON` 这一步做了一次额外扫描。

### 矩阵 4：`CHECK (col IS JSON)` 约束

| 引擎 | 直接 `IS JSON` | 用 `JSON_VALID` 等价 | 强制 vs. 信息性 |
|------|---------------|--------------------|----------------|
| PostgreSQL 16+ | 是 | -- | 强制 |
| Oracle 12c+ | 是 | -- | 强制 |
| DB2 11.5+ | 是 | -- | 强制 |
| MySQL 5.7+ | 否 | 是（5.7 起 CHECK 解析、8.0.16 起强制）| 8.0.16+ 强制 |
| MariaDB 10.4.3+ | 否 | 是（隐式 LONGTEXT + CHECK） | 强制 |
| SQL Server 2016+ | 否 | `CHECK (ISJSON(col)=1)` | 强制 |
| Azure Synapse | 否 | `CHECK (ISJSON(col)=1)` | 强制 |
| SQLite 3.38+ | 否 | `CHECK (json_valid(col))` | 强制 |
| H2 2.0+ | 是 | -- | 强制 |
| HSQLDB | 否 | -- | -- |
| Derby | 否 | -- | -- |
| Firebird | 否 | -- | -- |
| ClickHouse | 否 | `CHECK (isValidJSON(col))` 22.3+ | 强制 |
| DuckDB | 否 | `CHECK (json_valid(col))` | 强制 |
| MonetDB | 是 | -- | 强制 |
| Greenplum 7+ | 是 | -- | 强制 |
| TimescaleDB | 是 | -- | 强制 |
| YugabyteDB | 是 | -- | 强制 |
| CockroachDB | 否 | JSONB 类型隐含 | 类型层 |
| TiDB | 否 | JSON 类型隐含 | 类型层 |
| OceanBase | 否 | JSON 类型隐含 | 类型层 |
| SingleStore | 否 | JSON 类型隐含 | 类型层 |
| Snowflake | 否 | `CHECK` 仅信息性 | 信息性 |
| BigQuery | 否 | 不支持 CHECK 约束 | -- |
| Redshift | 否 | 不支持 CHECK 约束 | 信息性 |
| Trino / Presto | 否 | 无 DDL CHECK | -- |
| Spark SQL / Databricks | 否 | Delta 表 `CHECK` 支持 `get_json_object` | 强制 (Delta) |
| Hive | 否 | -- | -- |
| Flink SQL | -- | -- | 流式 DDL 无 CHECK |
| Vertica | 否 | -- | -- |
| Impala | 否 | -- | -- |
| StarRocks | 否 | -- | -- |
| Doris | 否 | -- | -- |
| Teradata | 否 | JSON 类型校验 | 类型层 |
| SAP HANA | 否 | `CHECK (IS_JSON(col)=1)` | 强制 |
| Informix | 是 | -- | 强制 |
| CrateDB | 否 | OBJECT 类型隐含 | 类型层 |
| Exasol | 否 | -- | -- |
| Athena | 否 | 不支持 CHECK | -- |
| Spanner | 否 | JSON 类型隐含 | 类型层 |
| Materialize | 否 | -- | -- |
| RisingWave | 否 | -- | -- |
| Databend | 否 | -- | -- |
| Yellowbrick | 是 | -- | 继承 PG |
| Firebolt | 否 | -- | -- |
| QuestDB | 否 | -- | -- |
| InfluxDB SQL | 否 | -- | -- |

### 矩阵 5：`CHECK (JSON_VALUE(...) IS ...)` 字段级约束

把单个字段当成"投影列"加约束，是 L4 字段级 schema 验证最常用的实现：

| 引擎 | 函数 | 表达式约束 | 生成列 + 约束 |
|------|------|-----------|--------------|
| PostgreSQL 12+ | `jsonb_path_query_first` | 是 | 是 |
| PostgreSQL 17+ | `JSON_VALUE` (SQL:2023) | 是 | 是 |
| Oracle 12c+ | `JSON_VALUE` | 是 | 是（虚拟列） |
| SQL Server 2016+ | `JSON_VALUE` | 是 | 是 |
| MySQL 5.7+ | `JSON_EXTRACT` / `->>` | 是 | 是 |
| MariaDB 10.2+ | `JSON_VALUE` | 是 | 是 |
| SQLite 3.38+ | `json_extract` | 是 | 是 |
| DB2 11.5+ | `JSON_VALUE` | 是 | 是 |
| H2 2.0+ | `JSON_VALUE` | 是 | 是 |
| DuckDB | `json_extract` | 是 | 是 |
| ClickHouse | `JSONExtract*` | 22.3+ | -- |
| Snowflake | `:` + `TRY_CAST` | 仅信息性 | -- |
| BigQuery | `JSON_VALUE` | 不支持 | -- |
| 其余 | 视各自 CHECK 支持 | -- | -- |

### 矩阵 6：JSON Schema Draft 完整校验

这是 L5 能力，跨越"字段级 CHECK"进入"递归 schema 校验"：

| 引擎 | 内置 | 扩展/UDF | 支持的 Draft | 备注 |
|------|------|---------|-------------|------|
| Oracle 23ai | 是 (`DBMS_JSON_SCHEMA`) | -- | 2020-12 子集 | 内置约束 + 函数 |
| PostgreSQL | 否 | `pg_jsonschema` (Supabase) | 2020-12 | Rust 实现 |
| PostgreSQL | 否 | `postgres-json-schema` (PL/pgSQL) | Draft-04 | 纯 SQL 实现 |
| SQL Server | 否 | CLR / 自定义函数 | -- | 通常借 .NET |
| MySQL | 否 | UDF (社区) | -- | 无官方 |
| MariaDB | 否 | -- | -- | -- |
| DuckDB | 否 | -- | -- | -- |
| ClickHouse | 否 | -- | -- | -- |
| Snowflake | 否 | JavaScript UDF | 任意 | 用户自写 |
| BigQuery | 否 | JS UDF | 任意 | 用户自写 |
| Databricks | 否 | Python UDF | 任意 | -- |
| Spark SQL | 否 | `from_json` 用 StructType 间接 | -- | 投射式校验 |
| Trino | 否 | -- | -- | -- |
| Presto | 否 | -- | -- | -- |
| 其他 | 否 | -- | -- | -- |

> Oracle 23ai 是目前唯一一个把 IETF JSON Schema 当成"一等公民"内置进数据库的主流引擎。其他引擎要么靠扩展（PG），要么靠 UDF，要么完全不支持。

### 矩阵 7：外部 JSON Schema 文件验证

这一行的关键能力：用户提供一个 schema 文档（字符串或文件），调用一个函数把待校验值与之比对。

| 引擎 | 函数 | schema 来源 |
|------|------|------------|
| Oracle 23ai | `DBMS_JSON_SCHEMA.IS_VALID(payload, schema)` | CLOB/JSON 列 |
| PostgreSQL + pg_jsonschema | `jsonb_matches_schema(schema, payload)` | JSONB 字面量 |
| Snowflake (UDF) | 自定义 | Stage 文件 |
| BigQuery (UDF) | 自定义 | GCS 文件 |
| Spark (`from_json`) | 不是 schema 校验 | StructType (非 IETF) |
| 其余 | -- | -- |

### 矩阵 8：OSON 二进制 JSON 与类型化校验

Oracle 21c 起 JSON 列默认存储为 OSON 二进制格式（Optimized Schema-less Object Notation），写入时强制做语法校验并保留键序：

| 引擎 | 二进制 JSON 格式 | 写入时校验 | 保留键序 |
|------|----------------|----------|---------|
| Oracle 21c+ | OSON | 是 | 是 |
| PostgreSQL | JSONB | 是 | 否（按二叉堆排序） |
| MySQL 5.7+ | 二进制 JSON | 是 | 否（按键名排序） |
| MariaDB 10.6+ | LONGTEXT (10.5 之前) / JSON binary (10.6 起 mysql 兼容模式) | 是 | 否 |
| SQL Server | NVARCHAR | 是（写入函数判定） | 是（文本保留） |
| DB2 | BSON | 是 | 否 |
| Snowflake | VARIANT | 是 | 否 |
| BigQuery | 内部列存 | 是 | 否 |
| Redshift | SUPER | 是 | 否 |
| DuckDB | JSON 字符串 | 是 | 是 |
| ClickHouse 24.8+ | JSON (列式) | 是 | -- |
| Databricks 15.3+ | VARIANT | 是 | 否 |

### 矩阵 9：MySQL 风格"严格类型 JSON 列"

MySQL/MariaDB/TiDB/OceanBase/SingleStore 均提供 `JSON` 数据类型，写入时强制语法校验但不校验形状：

| 引擎 | JSON 类型 | 语法校验 | 形状校验 | 重复键 |
|------|----------|---------|---------|--------|
| MySQL 5.7+ | JSON | 是 | 否 | 静默去重 |
| MySQL 8.0+ | JSON | 是 | 否（除非 CHECK） | 静默去重 |
| MariaDB 10.2+ | JSON (LONGTEXT) | CHECK | 否 | -- |
| TiDB | JSON | 是 | 否 | 静默去重 |
| OceanBase | JSON | 是 | 否 | 静默去重 |
| SingleStore | JSON | 是 | 否 | 静默去重 |
| CockroachDB | JSONB | 是 | 否 | 静默去重 |
| Spanner | JSON | 是 | 否 | 静默去重 |
| CrateDB | OBJECT (DYNAMIC/STRICT/IGNORED) | 是 | DYNAMIC=形状记录 STRICT=拒绝新键 | -- |

> CrateDB 是少数把"形状策略"做成类型属性的引擎：`OBJECT(STRICT)` 在写入未声明字段时直接报错；`OBJECT(DYNAMIC)` 自动扩展 schema；`OBJECT(IGNORED)` 完全 schemaless。

## 各引擎语法详解

### Oracle（最完整的 JSON 模式验证生态）

Oracle 是最早支持 `IS JSON`（12.1.0.2，2014）的商业引擎，也是当前唯一内置完整 JSON Schema 校验的引擎。

```sql
-- L1: 基本语法校验
ALTER TABLE orders ADD CONSTRAINT chk_payload_json
    CHECK (payload IS JSON);

-- L2: 限定为对象或数组
ALTER TABLE orders ADD CONSTRAINT chk_payload_obj
    CHECK (payload IS JSON (OBJECT));

-- L3: 拒绝重复键
ALTER TABLE orders ADD CONSTRAINT chk_payload_unique
    CHECK (payload IS JSON (WITH UNIQUE KEYS));

-- L4: 字段级类型 + 必填
ALTER TABLE orders ADD CONSTRAINT chk_user_id
    CHECK (
        JSON_EXISTS(payload, '$.user_id?(@ != null)')
        AND JSON_VALUE(payload, '$.amount' RETURNING NUMBER) > 0
    );

-- 12c+: JSON_EQUAL 比较两份 JSON 是否在结构上相等
SELECT JSON_EQUAL(j1, j2) FROM ...;

-- 21c: 自动以 OSON 存储
CREATE TABLE events (
    id   NUMBER PRIMARY KEY,
    body JSON       -- 21c+ 原生 JSON 类型，OSON 二进制
);

-- 19c 之前的兼容写法
CREATE TABLE events_legacy (
    id   NUMBER PRIMARY KEY,
    body CLOB CONSTRAINT chk_body_json CHECK (body IS JSON)
);
```

### Oracle 23ai — DBMS_JSON_SCHEMA 深入

23ai（2024 GA）首次把 IETF JSON Schema Draft 2020-12 作为一等公民引入。新增的能力包括：`IS JSON VALIDATE USING <schema>` 约束、`DBMS_JSON_SCHEMA.IS_VALID()`、`DBMS_JSON_SCHEMA.DESCRIBE()` 反向生成 schema。

```sql
-- 1) 直接在 CHECK 中嵌入 schema
CREATE TABLE customer_profiles (
    id      NUMBER PRIMARY KEY,
    profile JSON
        CONSTRAINT chk_profile_schema CHECK (
            profile IS JSON VALIDATE USING '{
                "type": "object",
                "required": ["email", "age"],
                "properties": {
                    "email": {
                        "type": "string",
                        "format": "email",
                        "maxLength": 320
                    },
                    "age": {
                        "type": "integer",
                        "minimum": 0,
                        "maximum": 150
                    },
                    "preferences": {
                        "type": "object",
                        "properties": {
                            "language": { "enum": ["en", "zh", "es", "fr"] },
                            "newsletter": { "type": "boolean" }
                        },
                        "additionalProperties": false
                    }
                }
            }'
        )
);

-- 2) 把 schema 存到独立的元数据表，引用后校验
CREATE TABLE schema_registry (
    name    VARCHAR2(64) PRIMARY KEY,
    version NUMBER,
    schema  JSON
);

INSERT INTO schema_registry VALUES (
    'order_v3', 3,
    '{ "type":"object", "required":["sku","qty"], "properties":{
         "sku":{"type":"string","pattern":"^[A-Z]{2}-[0-9]{6}$"},
         "qty":{"type":"integer","minimum":1,"maximum":9999}
       }}'
);

-- 3) 函数式校验：对一行进行运行时校验
SELECT id,
       DBMS_JSON_SCHEMA.IS_VALID(payload, sr.schema) AS ok,
       DBMS_JSON_SCHEMA.VALIDATE_REPORT(payload, sr.schema) AS report
FROM   orders o, schema_registry sr
WHERE  sr.name = 'order_v3';

-- 4) 反向：从样本 JSON 推断 schema
SELECT DBMS_JSON_SCHEMA.DESCRIBE(JSON('{"a":1,"b":"x"}')) FROM dual;

-- 5) 23ai 同时新增 JSON 关系型对偶视图（JSON-Relational Duality View）
-- 通过 GraphQL-like 文档定义自动维护底层关系表，schema 校验内置
CREATE JSON RELATIONAL DUALITY VIEW orders_dv AS
    SELECT JSON {
      '_id' IS o.id,
      'customer' IS (SELECT JSON { 'name' IS c.name } FROM customers c WHERE c.id = o.customer_id),
      'items' IS (SELECT JSON_ARRAYAGG(JSON {'sku' IS i.sku, 'qty' IS i.qty})
                  FROM order_items i WHERE i.order_id = o.id)
    } FROM orders o;
```

`DBMS_JSON_SCHEMA` 支持的关键字（截至 23.5）：

- 类型：`type`、`enum`、`const`
- 数值：`minimum`、`maximum`、`exclusiveMinimum/Maximum`、`multipleOf`
- 字符串：`minLength`、`maxLength`、`pattern`、`format`（部分 format 仅做语法标记）
- 数组：`items`、`prefixItems`、`minItems`、`maxItems`、`uniqueItems`、`contains`
- 对象：`properties`、`required`、`additionalProperties`、`patternProperties`、`dependentRequired`
- 组合：`allOf`、`anyOf`、`oneOf`、`not`、`if`/`then`/`else`
- 引用：`$ref`（仅 fragment 内部），`$defs`

不支持：`$dynamicRef`、`unevaluatedProperties` 的部分语义、外部 `$ref` 网络解析。

### SQL Server（ISJSON + JSON_PATH_EXISTS）

```sql
-- L1: SQL Server 2016 起的语法校验
ALTER TABLE orders ADD CONSTRAINT chk_payload_json
    CHECK (ISJSON(payload) = 1);

-- 2022 起 ISJSON 接受第二参数限定类型
-- ISJSON(x, OBJECT|ARRAY|SCALAR|VALUE)
ALTER TABLE orders ADD CONSTRAINT chk_payload_obj
    CHECK (ISJSON(payload, OBJECT) = 1);

-- L4: 字段级 + 必填
ALTER TABLE orders ADD CONSTRAINT chk_amount
    CHECK (
        JSON_PATH_EXISTS(payload, '$.amount') = 1
        AND TRY_CONVERT(decimal(18,2), JSON_VALUE(payload, '$.amount')) > 0
    );

-- 2022+: 完整 JSON Schema 通过正则与多个 ISJSON 组合实现
-- 没有内置 schema 校验，社区惯用 SQL CLR + Newtonsoft.Json.Schema

-- 2024+ JSON 类型预览（Azure SQL DB）
CREATE TABLE events (
    id    INT PRIMARY KEY,
    body  JSON   -- 写入时强制语法校验
);
```

### PostgreSQL（pg_jsonschema 扩展是事实标准）

PostgreSQL 16 之前没有 `IS JSON` 谓词，必须用 `jsonb_typeof` 或函数索引；16 起补齐 SQL:2016。

```sql
-- 16 之前的写法
ALTER TABLE orders ADD CONSTRAINT chk_payload_json
    CHECK (payload::jsonb IS NOT NULL);  -- 解析失败抛错

-- 16+ 标准写法
ALTER TABLE orders ADD CONSTRAINT chk_payload_json
    CHECK (payload IS JSON OBJECT WITH UNIQUE KEYS);

-- 17+: SQL/JSON 完整子集，可用 JSON_VALUE
ALTER TABLE orders ADD CONSTRAINT chk_amount
    CHECK (
        JSON_EXISTS(payload, '$.amount')
        AND JSON_VALUE(payload, '$.amount' RETURNING numeric) > 0
    );

-- pg_jsonschema 扩展（Supabase 维护，Rust + jsonschema crate）
CREATE EXTENSION pg_jsonschema;

ALTER TABLE customer_profiles
    ADD CONSTRAINT chk_profile_schema CHECK (
        json_matches_schema(
            '{
                "type":"object",
                "required":["email"],
                "properties":{
                    "email":{"type":"string","format":"email"}
                }
            }',
            profile
        )
    );

-- jsonb 版本
ALTER TABLE customer_profiles
    ADD CONSTRAINT chk_profile_schema_b CHECK (
        jsonb_matches_schema(
            '{...}'::json,
            profile
        )
    );

-- 备选：postgres-json-schema 是纯 PL/pgSQL，性能差但无依赖
```

### MySQL（JSON 类型只校验语法）

```sql
-- MySQL 5.7+ 内置 JSON 类型，自动语法校验
CREATE TABLE orders (
    id      BIGINT PRIMARY KEY,
    payload JSON NOT NULL
);

-- 8.0.16 起 CHECK 强制
ALTER TABLE orders
    ADD CONSTRAINT chk_payload_obj
    CHECK (JSON_TYPE(payload) = 'OBJECT');

ALTER TABLE orders
    ADD CONSTRAINT chk_amount
    CHECK (
        JSON_CONTAINS_PATH(payload, 'one', '$.amount')
        AND CAST(JSON_EXTRACT(payload, '$.amount') AS DECIMAL(18,2)) > 0
    );

-- 用生成列 + 索引 做形状保证
ALTER TABLE orders
    ADD COLUMN amount DECIMAL(18,2) AS (JSON_VALUE(payload, '$.amount')) STORED NOT NULL,
    ADD INDEX idx_amount (amount);
-- NOT NULL 隐式地保证 $.amount 存在，否则 INSERT 失败
```

### MariaDB（JSON_VALID + 隐式 LONGTEXT）

MariaDB 的 JSON 类型实际上是 `LONGTEXT` 加一个隐式 `CHECK (JSON_VALID(col))`，所以"JSON 列"和"带 CHECK 的文本列"在物理上是同一种东西。

```sql
CREATE TABLE orders (
    id      BIGINT PRIMARY KEY,
    payload JSON      -- 等价 LONGTEXT CHECK (JSON_VALID(payload))
);

ALTER TABLE orders
    ADD CONSTRAINT chk_amount CHECK (
        JSON_VALUE(payload, '$.amount') REGEXP '^[0-9]+(\\.[0-9]+)?$'
    );
```

### ClickHouse（JSON 类型从实验到 GA 的演进）

```sql
-- 22.3 起 isValidJSON / JSONExtract*
SELECT isValidJSON('{"a":1}');     -- 1
SELECT JSONType('{"a":1}', 'a');   -- Int64

-- 22.8 实验 JSON 类型
SET allow_experimental_object_type = 1;
CREATE TABLE events (
    id UInt64,
    body Object('json')
) ENGINE = MergeTree ORDER BY id;

-- 24.8+ 新 JSON 类型 GA，列式动态展开
CREATE TABLE events_v2 (
    id UInt64,
    body JSON
) ENGINE = MergeTree ORDER BY id;
-- 自动推断子列，支持 SELECT body.user.name；写入时强制 JSON 语法校验
```

### DuckDB（JSON 类型 + validate_json）

```sql
INSTALL json; LOAD json;

CREATE TABLE events (
    id  BIGINT,
    body JSON
);

INSERT INTO events VALUES (1, '{"a":1}');
INSERT INTO events VALUES (2, 'not json');  -- 报错: Invalid Input Error

-- json_valid() 函数
SELECT json_valid('{"a":1}'),  -- true
       json_valid('oops');     -- false

-- 字段级类型检查
ALTER TABLE events ADD CONSTRAINT chk
    CHECK (json_type(body, '$.a') = 'NUMBER');
```

### Snowflake（VARIANT 是 schema-on-read）

VARIANT 在写入时只校验语法，所有形状错误延迟到读取时；CHECK 约束仅 informational（不强制）。

```sql
CREATE TABLE events (
    id       NUMBER,
    body     VARIANT
);

-- 语法校验
SELECT IS_VALID_JSON_TEXT('{"a":1}');     -- TRUE
SELECT CHECK_JSON('{"a":1}');             -- NULL = 合法; 否则错误信息

-- 类型探测
SELECT TYPEOF(body:amount) FROM events;   -- INTEGER / VARCHAR / OBJECT ...

-- 用 JS UDF 做完整 JSON Schema 校验
CREATE OR REPLACE FUNCTION validate_schema(payload VARIANT, schema VARIANT)
RETURNS BOOLEAN
LANGUAGE JAVASCRIPT
AS $$
    // 加载 ajv 等校验库需通过 Snowpark / external function
    return true;
$$;
```

### BigQuery（JSON 类型 GA 2022）

```sql
-- 强类型 JSON 列
CREATE TABLE ds.events (
    id   INT64,
    body JSON
);

-- PARSE_JSON 严格模式
SELECT PARSE_JSON('{"a":1}', wide_number_mode=>'exact');
SELECT SAFE.PARSE_JSON('not json');    -- NULL 而非错误

-- 类型检查
SELECT JSON_TYPE(JSON '{"a":1}', '$.a');  -- 'number'

-- BigQuery 不支持 CHECK 约束，schema 校验需要在 DML 前置流程或 dataform 中
```

### Databricks / Spark（VARIANT + from_json）

```sql
-- Databricks Runtime 15.3+ VARIANT 类型
CREATE TABLE events (
    id BIGINT,
    body VARIANT
);

INSERT INTO events VALUES (1, PARSE_JSON('{"a":1}'));
SELECT variant_get(body, '$.a', 'INT') FROM events;

-- from_json 基于 StructType 投影式校验（非 IETF JSON Schema）
SELECT from_json(raw, 'STRUCT<a:INT, b:STRING>') AS parsed FROM raw_events;

-- Delta 表 CHECK
ALTER TABLE events ADD CONSTRAINT amount_positive CHECK (
    get_json_object(cast(body as string), '$.amount') > 0
);
```

### 其他引擎要点

```sql
-- DB2 LUW
ALTER TABLE orders ADD CONSTRAINT chk CHECK (payload IS JSON OBJECT WITH UNIQUE KEYS);

-- Trino / Presto / Athena
SELECT json_parse('{"a":1}') IS JSON;   -- TRUE
SELECT json_extract(j, '$.a') FROM t WHERE j IS JSON OBJECT;

-- Flink SQL (1.15+)
SELECT * FROM events WHERE body IS JSON OBJECT;

-- SAP HANA
ALTER TABLE orders ADD CONSTRAINT chk CHECK (IS_JSON(payload) = 1);

-- Teradata
ALTER TABLE orders ADD CONSTRAINT chk CHECK (JSON_CHECK(payload) = 'OK');

-- SingleStore / TiDB / OceanBase: JSON 类型自动校验, 无 IS JSON 谓词
CREATE TABLE t (id BIGINT, body JSON);

-- CrateDB
CREATE TABLE events (
    id BIGINT,
    body OBJECT(STRICT) AS (
        a INT,
        b TEXT
    )
);
INSERT INTO events VALUES (1, {a=1, b='x'});
INSERT INTO events VALUES (2, {a=1, c='oops'});  -- 报错: STRICT 模式拒绝未声明字段
```

## 实战模式：从 L1 到 L5 的渐进式收紧

真实迁移项目里很少一步到位。下面是常见的"从 schemaless 到 schemaful"路径：

### 阶段 1：只校验语法

```sql
-- 起步：把所有非法 JSON 拒绝在大门外
ALTER TABLE legacy_events ADD CONSTRAINT chk_json CHECK (payload IS JSON);
```

这一步通常会暴露 0.01–1% 的脏数据（截断、双重转义、CRLF 嵌入）。

### 阶段 2：限定顶层类型 + 唯一键

```sql
ALTER TABLE legacy_events
    DROP CONSTRAINT chk_json,
    ADD CONSTRAINT chk_json2
        CHECK (payload IS JSON OBJECT WITH UNIQUE KEYS);
```

唯一键这一步对那些把 `{"id":1,"id":2}` 当成"最后写胜出"的客户端格外致命，但也最值得做。

### 阶段 3：用生成列暴露关键字段

```sql
ALTER TABLE legacy_events
    ADD COLUMN event_type TEXT GENERATED ALWAYS AS (payload->>'type') STORED,
    ADD COLUMN occurred_at TIMESTAMPTZ GENERATED ALWAYS AS
        ((payload->>'occurred_at')::timestamptz) STORED,
    ADD CONSTRAINT chk_event_type CHECK (event_type IN ('view','click','purchase'));
```

把"必填字段"做成生成列后，缺字段或类型错误会直接导致写入失败，比 CHECK + JSON_VALUE 更直观。

### 阶段 4：完整 JSON Schema

```sql
-- Oracle 23ai
ALTER TABLE legacy_events
    ADD CONSTRAINT chk_schema CHECK (payload IS JSON VALIDATE USING '...');

-- PostgreSQL + pg_jsonschema
ALTER TABLE legacy_events
    ADD CONSTRAINT chk_schema CHECK (json_matches_schema('...', payload));
```

### 阶段 5：版本化 schema + 双写

把 schema 存到 `schema_registry` 表，给每条记录打 `schema_version`，新版本生效时同时校验新旧两份 schema：

```sql
ALTER TABLE legacy_events
    ADD COLUMN schema_version SMALLINT NOT NULL DEFAULT 3,
    ADD CONSTRAINT chk_schema_v3 CHECK (
        schema_version <> 3
        OR json_matches_schema(
            (SELECT schema FROM schema_registry WHERE name='event' AND version=3),
            payload
        )
    );
```

这把"schema 演进"变成 SQL 里的可观察对象，比依靠 CI 流水线检查 schema 文件可靠得多。

## 性能与实现机制

### `IS JSON` 的复杂度

`IS JSON` 的最朴素实现是"调用 JSON 解析器，看是否抛错"。对于 1KB JSON 大约消耗 1–5 微秒（PostgreSQL 16 实测在 x86 上约 2.3 µs）。带 `WITH UNIQUE KEYS` 时需要再扫描所有键并放进哈希表，额外 ~30% 开销。

### CHECK 约束的代价

`CHECK (col IS JSON)` 在 INSERT/UPDATE 路径上每行调用一次，写入吞吐通常下降 5–15%。一旦换成 `CHECK (json_matches_schema(...))`，因为递归 schema 比对涉及大量字符串比较与正则匹配，开销可能放大 5–50 倍。生产经验：

- **写多读少**：保持 L1/L2 校验，把 L5 校验放进 ETL 前置或异步审计。
- **写少读多**：可以放 L5 在 CHECK 中，反正写入瓶颈不在数据库。
- **批量回填**：临时 `ALTER TABLE ... DISABLE CONSTRAINT ALL` → 回填 → `ENABLE NOVALIDATE`（Oracle）或 `NOT VALID`（PostgreSQL）。

### 函数索引 vs. 生成列

```sql
-- PostgreSQL: 函数索引（不 enforce 形状，仅加速查询）
CREATE INDEX idx_sku ON orders ((payload->>'sku'));

-- 生成列 + 索引（enforce 类型 + 加速查询）
ALTER TABLE orders
    ADD COLUMN sku TEXT GENERATED ALWAYS AS (payload->>'sku') STORED NOT NULL;
CREATE INDEX idx_sku ON orders (sku);
```

生成列把 schema 校验"埋"进物理列，比 CHECK 表达式更高效；`STORED` 列会占空间但读取零开销，`VIRTUAL` 列零空间但读取重算。

### OSON 的角色

Oracle 的 OSON 是"二进制 JSON + schema 校验"两个功能在物理层的统一：

1. 写入时一次解析 → 立即转 OSON → 顺路校验（语法、可选 schema）。
2. 读取时不再需要解析，直接走 OSON 树。
3. JSON Schema 校验可以在 OSON 上做，因为 OSON 保留了所有键序与原始数值精度。

PostgreSQL 的 JSONB 因为按二叉堆排序键，不支持 `WITH UNIQUE KEYS` 的语义保留——如果同一个键写两次，JSONB 在解析阶段就丢弃后者，事后无从判断。这就是为什么 PG 的 `IS JSON WITH UNIQUE KEYS` 必须作用于尚未转换的 `text`/`json`，而非 `jsonb`。

### 列存引擎的 schema 推断

ClickHouse 24.8+、Databricks VARIANT、BigQuery JSON 都把 JSON 列在写入时就分裂成动态子列存储。这种"自动 schema 推断"既是性能优化也是隐式 schema 验证：

- 同一字段在不同行类型不一致时，列存引擎要么报错、要么按 union 类型保留两份。
- 子列的存在意味着 `payload.user.id` 的访问可以走列存而非 JSON 解析。
- 但代价是字段数膨胀（thousands of dynamic subcolumns）会让元数据失控，因此通常配合 `max_dynamic_paths` 上限。

## 关键发现

1. **SQL 标准的 schema 验证只到字段级**：SQL:2016 的 `IS JSON` 与 SQL:2023 的 `JSON_VALUE RETURNING` 解决了"语法+顶层类型+字段类型"，但完整 JSON Schema 仍然属于厂商扩展。
2. **`IS JSON` 谓词的覆盖率不到 30%**：45+ 引擎里只有约 12 个支持 SQL:2016 谓词形式（PG 16+、Oracle、DB2、Trino/Presto、H2、Flink、MonetDB、Informix、Greenplum、Yugabyte、TimescaleDB、Athena）。其余引擎全部走 `JSON_VALID()` / `ISJSON()` / `IS_VALID_JSON()` 函数。
3. **`WITH UNIQUE KEYS` 是少有真区分**：因为它要求底层格式保留键序，MySQL/Snowflake/BigQuery 这一类"解析时去重"的引擎在物理层就实现不了。
4. **CHECK 约束是 schema 验证的主要落地点**：PG/Oracle/DB2/MySQL/MariaDB/SQL Server/SQLite/H2/HANA 都在 CHECK 里做强约束；BigQuery、Snowflake、Trino、ClickHouse 等 OLAP 引擎要么没有 CHECK 要么 CHECK 仅信息性。
5. **Oracle 23ai 是唯一内置 IETF JSON Schema 的引擎**：`DBMS_JSON_SCHEMA` 支持 Draft 2020-12 的大部分关键字，并且与 `IS JSON VALIDATE USING` 约束语法整合。其他主流商业引擎在 2025 年初仍未跟进。
6. **PostgreSQL 16 是分水岭**：补齐 `IS JSON` 谓词后，PG 终于在标准合规度上追平 Oracle 12c；17 起的 SQL/JSON 子集进一步接近 SQL:2023。
7. **`pg_jsonschema` 是 PG 生态事实标准**：Supabase 维护、Rust 实现、支持 Draft 2020-12，性能比纯 PL/pgSQL 的 `postgres-json-schema` 高一到两个数量级。
8. **MySQL 系（含 TiDB/OceanBase/SingleStore）的 JSON 类型只校验语法**：形状校验必须靠 CHECK + JSON_VALUE 或生成列 NOT NULL。MySQL 8.0.16 之前 CHECK 完全不强制，是踩坑高发区。
9. **CrateDB 是异类**：把"形状策略"做成 OBJECT 类型属性（STRICT/DYNAMIC/IGNORED），是少数把 schema 治理嵌进类型系统而非约束系统的引擎。
10. **OLAP 引擎走 schema-on-read**：Snowflake VARIANT、BigQuery JSON、Redshift SUPER、Databricks VARIANT 都把"形状不一致"延迟到查询时，依赖 `TRY_CAST` 与 `SAFE.` 前缀防御失败。这与 OLTP 引擎的"写时强约束"哲学根本不同。
11. **OSON / JSONB / BSON 等二进制格式天生包含语法校验**：写入这些类型的瞬间 JSON 必须合法，所以"`JSON` 类型 + `IS JSON` CHECK"在二进制存储引擎里是冗余的；但对于把 JSON 存进 `TEXT/CLOB` 的旧表，CHECK 仍是唯一防线。
12. **生成列 NOT NULL 是最被低估的 schema 工具**：它把"必填 + 类型"两件事合并到 DDL 里，比 CHECK 表达式更直观、更易调试，并且天然带索引能力。
13. **schema 版本化是被忽视的话题**：Oracle 23ai 的 JSON-Relational Duality View 提供了一种与版本化 schema 共存的解法，但其他引擎的演进路径仍主要靠应用层（schema registry + protobuf-style 演进规则）。
14. **JSON Schema 的性能开销是 5–50 倍于 `IS JSON`**：所以即便引擎支持 L5 校验，是否把它放到 CHECK 里仍要看写入吞吐预算。
15. **真正"无模式"的列在生产里不存在**：哪怕没有 CHECK，应用层、下游 BI、列存自动推断都会对 JSON 形状形成隐式契约；与其让契约散在四处，不如把它写进 DDL。

## 参考资料

- ISO/IEC 9075-2:2016, Section 6.x JSON predicates
- ISO/IEC 9075-2:2023, SQL/JSON 完整子集
- ISO/IEC TR 19075-6:2017, *SQL Notation for the JSON data interchange format*
- IETF Draft: [JSON Schema 2020-12](https://json-schema.org/specification-links.html#2020-12)
- Oracle: [IS JSON Condition](https://docs.oracle.com/en/database/oracle/oracle-database/23/sqlrf/Conditions.html)
- Oracle: [DBMS_JSON_SCHEMA](https://docs.oracle.com/en/database/oracle/oracle-database/23/arpls/dbms_json_schema.html)
- Oracle: [JSON-Relational Duality Views](https://docs.oracle.com/en/database/oracle/oracle-database/23/jsnvu/index.html)
- PostgreSQL: [SQL/JSON in PostgreSQL 16/17](https://www.postgresql.org/docs/current/functions-json.html)
- Supabase: [pg_jsonschema](https://github.com/supabase/pg_jsonschema)
- gavinwahl: [postgres-json-schema](https://github.com/gavinwahl/postgres-json-schema)
- SQL Server: [ISJSON](https://learn.microsoft.com/en-us/sql/t-sql/functions/isjson-transact-sql)
- SQL Server: [JSON_PATH_EXISTS (2022)](https://learn.microsoft.com/en-us/sql/t-sql/functions/json-path-exists-transact-sql)
- MySQL: [JSON Type](https://dev.mysql.com/doc/refman/8.0/en/json.html)
- MariaDB: [JSON_VALID](https://mariadb.com/kb/en/json_valid/)
- DuckDB: [JSON Extension](https://duckdb.org/docs/extensions/json)
- ClickHouse: [JSON Data Type](https://clickhouse.com/docs/en/sql-reference/data-types/json)
- Snowflake: [Semi-Structured Data](https://docs.snowflake.com/en/sql-reference/data-types-semistructured)
- BigQuery: [JSON Data Type](https://cloud.google.com/bigquery/docs/reference/standard-sql/json-data)
- Databricks: [VARIANT Type](https://docs.databricks.com/en/sql/language-manual/data-types/variant-type.html)
- Trino: [JSON Functions](https://trino.io/docs/current/functions/json.html)
- CrateDB: [Object Data Type](https://crate.io/docs/crate/reference/en/latest/general/ddl/data-types.html#type-object)
- DB2: [IS JSON predicate](https://www.ibm.com/docs/en/db2/11.5?topic=predicates-is-json)
