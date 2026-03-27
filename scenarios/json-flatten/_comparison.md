# JSON 展平为关系行 (JSON Flatten) — 方言对比

## 语法支持对比

### 传统 RDBMS

| 特性 | MySQL | PostgreSQL | SQLite | Oracle | SQL Server | MariaDB | Firebird | Db2 | SAP HANA |
|---|---|---|---|---|---|---|---|---|---|
| 原生 JSON 类型 | ✅ 5.7+ | ✅ JSON / JSONB 9.4+ | ⚠️ TEXT + json1 | ✅ 21c+ | ✅ NVARCHAR + JSON 函数 | ✅ 10.2+ | ❌ | ✅ 11.1+ | ✅ |
| JSON_TABLE | ✅ 8.0.4+ | ❌ | ❌ | ✅ 12c+ | ❌ | ✅ 10.6+ | ❌ | ✅ 11.1+ | ✅ |
| jsonb_array_elements | ❌ | ✅ 9.4+ | ❌ | ❌ | ❌ | ❌ | ❌ | ❌ | ❌ |
| json_each / json_tree | ❌ | ✅ | ✅ json1 扩展 | ❌ | ❌ | ❌ | ❌ | ❌ | ❌ |
| OPENJSON | ❌ | ❌ | ❌ | ❌ | ✅ 2016+ | ❌ | ❌ | ❌ | ❌ |
| JSON 路径提取 | ✅ ->/->> | ✅ ->/->>/#> | ✅ json_extract | ✅ JSON_VALUE | ✅ JSON_VALUE | ✅ ->/->> | ❌ | ✅ JSON_VALUE | ✅ JSON_VALUE |
| 嵌套 JSON 展开 | ✅ NESTED PATH | ✅ jsonb_each 递归 | ✅ json_tree 递归 | ✅ NESTED PATH | ✅ 嵌套 OPENJSON | ✅ NESTED PATH | ❌ | ✅ NESTED | ⚠️ |
| JSON 聚合（行转 JSON） | ✅ JSON_ARRAYAGG | ✅ json_agg | ✅ json_group_array | ✅ JSON_ARRAYAGG 12c+ | ✅ FOR JSON | ✅ JSON_ARRAYAGG | ❌ | ✅ JSON_ARRAYAGG | ✅ |
| JSONB 索引 | ❌ | ✅ GIN | ❌ | ⚠️ | ❌ | ❌ | ❌ | ❌ | ❌ |
| JSON_KEYS / JSON_OBJECT_KEYS | ✅ JSON_KEYS | ✅ jsonb_object_keys | ✅ json_each | ✅ JSON_KEYS 21c+ | ❌ | ✅ JSON_KEYS | ❌ | ❌ | ❌ |

### 大数据 / 分析引擎

| 特性 | BigQuery | Snowflake | MaxCompute | Hive | ClickHouse | StarRocks | Trino | Hologres | Doris | DuckDB | Spark | Flink |
|---|---|---|---|---|---|---|---|---|---|---|---|---|
| 原生 JSON 类型 | ✅ JSON | ✅ VARIANT | ⚠️ STRING | ⚠️ STRING | ✅ JSON 22.3+ | ✅ JSON | ✅ JSON | ✅ JSON | ✅ JSON | ✅ JSON | ⚠️ STRING | ⚠️ STRING |
| JSON_TABLE 或等价 | ❌ | ❌ | ❌ | ❌ | ❌ | ❌ | ❌ | ❌ | ❌ | ❌ | ❌ | ❌ |
| UNNEST + JSON 解析 | ✅ JSON_EXTRACT_ARRAY + UNNEST | ✅ FLATTEN | ❌ | ✅ LATERAL VIEW EXPLODE | ✅ JSONExtractArrayRaw + arrayJoin | ✅ json_each | ✅ UNNEST + json_parse | ❌ | ✅ EXPLODE | ✅ UNNEST + json | ✅ FROM_JSON + EXPLODE | ✅ UNNEST |
| JSON 路径提取 | ✅ JSON_EXTRACT | ✅ : 语法 | ✅ GET_JSON_OBJECT | ✅ GET_JSON_OBJECT | ✅ JSONExtract | ✅ -> | ✅ JSON_EXTRACT | ✅ -> | ✅ JSON_EXTRACT | ✅ ->/->> | ✅ GET_JSON_OBJECT | ✅ JSON_VALUE |
| FLATTEN 通用展开 | ❌ | ✅ | ❌ | ❌ | ❌ | ❌ | ❌ | ❌ | ❌ | ❌ | ❌ | ❌ |
| JSON 聚合 | ✅ TO_JSON_STRING | ✅ ARRAY_AGG + OBJECT_CONSTRUCT | ⚠️ | ⚠️ | ✅ JSONExtract | ✅ JSON_ARRAY | ✅ | ⚠️ | ⚠️ | ✅ | ✅ TO_JSON | ✅ |

### 云数据仓库

| 特性 | Redshift | Synapse | Databricks | Greenplum | Impala | Vertica | Teradata |
|---|---|---|---|---|---|---|---|
| 原生 JSON 类型 | ✅ SUPER | ⚠️ NVARCHAR | ⚠️ STRING | ⚠️ JSON 扩展 | ⚠️ STRING | ⚠️ FLEX | ⚠️ JSON 15+ |
| JSON 展开方式 | ✅ PartiQL 语法 | ✅ OPENJSON | ✅ FROM_JSON + EXPLODE | ⚠️ json_array_elements | ❌ | ✅ MAPJSONEXTRACTOR | ⚠️ JSON_SHRED |
| JSON 路径提取 | ✅ . 语法 | ✅ JSON_VALUE | ✅ : 语法 | ✅ json_extract | ⚠️ GET_JSON_OBJECT | ✅ | ✅ JSON_EXTRACT |
| FLATTEN | ❌ | ❌ | ✅ EXPLODE | ❌ | ❌ | ❌ | ❌ |

### 分布式 / NewSQL

| 特性 | TiDB | OceanBase | CockroachDB | Spanner | YugabyteDB | PolarDB | openGauss | TDSQL | DamengDB | KingbaseES |
|---|---|---|---|---|---|---|---|---|---|---|
| 原生 JSON 类型 | ✅ | ✅ | ✅ JSONB | ✅ JSON | ✅ JSONB | ✅ | ✅ | ✅ | ⚠️ | ✅ |
| JSON_TABLE | ✅ | ✅ | ❌ | ❌ | ❌ | ✅ | ❌ | ✅ | ❌ | ❌ |
| json_array_elements | ❌ | ❌ | ✅ | ❌ | ✅ | ❌ | ✅ | ❌ | ❌ | ✅ |
| JSON 路径提取 | ✅ ->/->> | ✅ | ✅ ->/->> | ✅ JSON_VALUE | ✅ ->/->> | ✅ ->/->> | ✅ ->/->> | ✅ | ⚠️ | ✅ ->/->> |

### 特殊用途

| 特性 | TimescaleDB | TDengine | ksqlDB | Materialize | H2 | Derby |
|---|---|---|---|---|---|---|
| 原生 JSON 类型 | ✅ JSONB | ⚠️ JSON TAG | ⚠️ JSON 格式 | ✅ JSONB | ⚠️ JSON 函数 | ❌ |
| JSON 展开 | ✅ jsonb_array_elements | ❌ | ⚠️ EXTRACTJSONFIELD | ✅ jsonb_array_elements | ❌ | ❌ |
| JSON 路径提取 | ✅ ->/->> | ✅ -> | ✅ EXTRACTJSONFIELD | ✅ ->/->> | ✅ JSON 函数 | ❌ |
| JSON TAG 查询 | ❌ | ✅ | ❌ | ❌ | ❌ | ❌ |

## 关键差异

- **MySQL** 的 `JSON_TABLE`（8.0.4+）是最强大的 JSON 展平工具，支持 `NESTED PATH` 嵌套展开和 `FOR ORDINALITY` 序号
- **PostgreSQL** 使用 `jsonb_array_elements` / `jsonb_each` / `jsonb_to_record` 系列函数，配合 `LATERAL` 使用；JSONB 支持 GIN 索引
- **SQL Server** 的 `OPENJSON`（2016+）类似 `JSON_TABLE`，支持嵌套展开
- **SQLite** 的 `json_each` / `json_tree` 提供递归 JSON 遍历能力
- **Snowflake** 的 `FLATTEN` 是通用展开函数，可处理 VARIANT / ARRAY / OBJECT 类型
- **BigQuery** 使用 `JSON_EXTRACT_ARRAY` + `UNNEST` 模式展开 JSON 数组
- **ClickHouse** 使用 `JSONExtractArrayRaw` + `arrayJoin` 组合
- **Hive / Spark / Doris** 使用 `GET_JSON_OBJECT` 提取 + `LATERAL VIEW EXPLODE` 展开
- **TDengine** 仅在标签（TAG）中支持 JSON 类型，无法对数据列做 JSON 展平
- **Derby / Firebird** 无 JSON 支持
- **大数据引擎**普遍不支持 SQL 标准的 `JSON_TABLE`，各有独特的展开语法
