# JSON 类型 (JSON Types) — 方言对比

## 语法支持对比

### 传统 RDBMS

| 特性 | MySQL | PostgreSQL | SQLite | Oracle | SQL Server | MariaDB | Firebird | Db2 | SAP HANA |
|---|---|---|---|---|---|---|---|---|---|
| JSON 列类型 | ✅ 5.7+ | ✅ JSON/JSONB | ❌ TEXT | ✅ 21c+ | ❌ NVARCHAR | ✅ 10.2+ | ❌ | ✅ 11.1+ | ❌ NCLOB |
| 二进制 JSON | ❌ | ✅ JSONB | ❌ | ✅ OSON | ❌ | ❌ | ❌ | ✅ BSON | ❌ |
| 路径提取 | ✅ ->/->> | ✅ ->/->>/#> | ✅ json_extract | ✅ json_value | ✅ JSON_VALUE | ✅ ->/->> | ❌ | ✅ JSON_VALUE | ✅ JSON_VALUE |
| 路径查询 | ✅ JSON_EXTRACT | ✅ jsonb_path_query | ✅ json_each | ✅ JSON_QUERY | ✅ JSON_QUERY | ✅ JSON_EXTRACT | ❌ | ✅ JSON_QUERY | ✅ JSON_QUERY |
| JSON 索引 | ✅ 生成列 | ✅ GIN on JSONB | ❌ | ✅ | ❌ | ✅ | ❌ | ❌ | ❌ |
| JSON 聚合 | ✅ JSON_ARRAYAGG | ✅ json_agg | ✅ json_group_array | ✅ JSON_ARRAYAGG | ✅ FOR JSON | ✅ JSON_ARRAYAGG | ❌ | ✅ JSON_ARRAYAGG | ✅ |
| JSON 修改 | ✅ JSON_SET | ✅ jsonb_set | ✅ json_set | ✅ JSON_TRANSFORM | ✅ JSON_MODIFY | ✅ JSON_SET | ❌ | ❌ | ❌ |
| JSON_TABLE | ✅ 8.0+ | ✅ 12+ | ❌ | ✅ 12c+ | ✅ OPENJSON | ❌ | ❌ | ❌ | ❌ |

### 大数据 / 分析引擎

| 特性 | BigQuery | Snowflake | MaxCompute | Hive | ClickHouse | StarRocks | Trino | Hologres | Doris | DuckDB | Spark | Flink |
|---|---|---|---|---|---|---|---|---|---|---|---|---|
| JSON 类型 | ✅ JSON | ✅ VARIANT | ❌ STRING | ❌ STRING | ✅ JSON | ✅ JSON | ✅ JSON | ✅ JSON/JSONB | ✅ JSON | ✅ JSON | ❌ STRING | ❌ STRING |
| 路径提取 | ✅ JSON_VALUE | ✅ : 语法 | ✅ GET_JSON_OBJECT | ✅ GET_JSON_OBJECT | ✅ JSONExtract | ✅ ->/->> | ✅ json_extract | ✅ ->/->> | ✅ JSON_EXTRACT | ✅ ->/->> | ✅ get_json_object | ✅ JSON_VALUE |
| 半结构化 | ✅ STRUCT | ✅ VARIANT/OBJECT | ✅ | ✅ MAP/STRUCT | ✅ Tuple/Map | ❌ | ✅ ROW/MAP | ❌ | ❌ | ✅ STRUCT/MAP | ✅ MAP/STRUCT | ✅ ROW/MAP |
| JSON 索引 | ❌ | ❌ | ❌ | ❌ | ❌ | ❌ | ❌ | ✅ GIN | ❌ | ❌ | ❌ | ❌ |

### 分布式 / NewSQL

| 特性 | TiDB | OceanBase | CockroachDB | Spanner | YugabyteDB | PolarDB | openGauss | TDSQL | DamengDB | KingbaseES |
|---|---|---|---|---|---|---|---|---|---|---|
| JSON 类型 | ✅ | ✅ | ✅ JSONB | ✅ JSON | ✅ JSONB | ✅ | ✅ | ✅ | ✅ | ✅ JSON/JSONB |
| 路径提取 | ✅ ->/->> | ✅ ->/->> | ✅ ->/->> | ✅ JSON_VALUE | ✅ ->/->> | ✅ ->/->> | ✅ ->/->> | ✅ ->/->> | ✅ | ✅ ->/->> |

## 关键差异

- **PostgreSQL JSONB** 是最成熟的 JSON 实现，支持 GIN 索引和丰富的操作符
- **Snowflake VARIANT** 是半结构化数据的独特类型，支持 : 路径语法
- **SQL Server** 无原生 JSON 类型，用 NVARCHAR 存储，用 OPENJSON 解析
- **SAP HANA/Firebird** JSON 支持最弱
- **BigQuery** 同时支持 JSON 类型和原生 STRUCT/ARRAY
- **Hive/Spark/Flink** 无 JSON 类型，用 STRING 存储配合解析函数
- **CockroachDB/YugabyteDB/KingbaseES** 继承 PostgreSQL JSONB 全套功能
- **MySQL** -> 返回 JSON，->> 返回文本，PostgreSQL -> 返回 JSON，->> 返回文本
